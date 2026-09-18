#include "sync.h"
#include <QTcpSocket>
#include <QTimer>
#include <QDateTime>
#include <QJsonDocument>
#include <QHostInfo>
#include <QUrl>
#include <QUuid>
#include <QCryptographicHash>
#include <QRegularExpression>
#include <openssl/evp.h>
#include <memory>
#include <stdexcept>

static QByteArray decode(const QJsonValue &value, int size = -1) {
    if (!value.isString()) throw std::runtime_error("Invalid binary field");
    const auto input = value.toString().toLatin1();
    const auto result = QByteArray::fromBase64(input, QByteArray::AbortOnBase64DecodingErrors);
    if (result.toBase64() != input) throw std::runtime_error("Invalid base64 encoding");
    if (size >= 0 && result.size() != size) throw std::runtime_error("Invalid binary length");
    return result;
}

static QJsonObject parse(const QByteArray &bytes) {
    QJsonParseError error;
    const auto doc = QJsonDocument::fromJson(bytes, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) throw std::runtime_error("Invalid JSON");
    return doc.object();
}

QJsonObject encryptEnvelope(const QByteArray &plain, const QByteArray &key, const QByteArray &aad) {
    const auto box = seal(plain, key, aad);
    return {{"nonce", QString::fromLatin1(box.left(12).toBase64())}, {"ciphertext", QString::fromLatin1(box.mid(12, box.size() - 28).toBase64())}, {"tag", QString::fromLatin1(box.right(16).toBase64())}};
}

QByteArray decryptEnvelope(const QJsonObject &envelope, const QByteArray &key, const QByteArray &aad) {
    auto cipher = decode(envelope.value("ciphertext"));
    if (cipher.size() > 12 * 1024 * 1024) throw std::runtime_error("Encrypted message too large");
    return unseal(decode(envelope.value("nonce"), 12) + cipher + decode(envelope.value("tag"), 16), key, aad);
}

QByteArray publicSigningKey(const QByteArray &privateKey) {
    auto key = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>(EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, nullptr, reinterpret_cast<const unsigned char *>(privateKey.constData()), privateKey.size()), EVP_PKEY_free);
    if (!key) throw std::runtime_error("Invalid signing key");
    QByteArray publicKey(32, Qt::Uninitialized);
    size_t size = publicKey.size();
    if (EVP_PKEY_get_raw_public_key(key.get(), reinterpret_cast<unsigned char *>(publicKey.data()), &size) != 1 || size != 32) throw std::runtime_error("Signing key unavailable");
    return publicKey;
}

QByteArray signSnapshot(const QByteArray &privateKey, const QByteArray &payloadBase64) {
    auto key = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>(EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, nullptr, reinterpret_cast<const unsigned char *>(privateKey.constData()), privateKey.size()), EVP_PKEY_free);
    auto context = std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)>(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    if (!key || !context || EVP_DigestSignInit(context.get(), nullptr, nullptr, nullptr, key.get()) != 1) throw std::runtime_error("Signing unavailable");
    const auto bytes = QByteArray("harbor.snapshot.v1\n") + payloadBase64;
    QByteArray signature(64, Qt::Uninitialized);
    size_t size = signature.size();
    if (EVP_DigestSign(context.get(), reinterpret_cast<unsigned char *>(signature.data()), &size, reinterpret_cast<const unsigned char *>(bytes.constData()), bytes.size()) != 1 || size != 64) throw std::runtime_error("Signing failed");
    return signature;
}

SyncServer::SyncServer(Vault &vault, QObject *parent) : QObject(parent), vault_(vault) {
    connect(&server_, &QTcpServer::newConnection, this, &SyncServer::accept);
    rateWindow_.start();
}

bool SyncServer::start(quint16 port) {
    if (!vault_.unlocked()) return false;
    if (running()) return true;
    auto key = signingPrivateKey();
    wipe(key);
    return server_.listen(QHostAddress::Any, port);
}

void SyncServer::stop() {
    server_.close();
    cancelInvite();
    for (auto &invitation : approved_) { wipe(invitation.secret); wipe(invitation.nonce); wipe(invitation.boundRequest); }
    approved_.clear();
    for (auto socket : findChildren<QTcpSocket *>()) socket->abort();
}
bool SyncServer::running() const { return server_.isListening(); }
quint16 SyncServer::port() const { return server_.serverPort(); }
QJsonArray SyncServer::devices() const { return vault_.data().value("devices").toArray(); }

QByteArray SyncServer::signingPrivateKey() {
    auto data = vault_.data();
    if (data.value("signingKey").toString().isEmpty()) {
        auto key = randomBytes(32);
        data["signingKey"] = QString::fromLatin1(key.toBase64());
        vault_.replace(data);
        wipe(key);
    }
    return decode(vault_.data().value("signingKey"), 32);
}

static bool privateAddress(const QHostAddress &address) {
    if (address.isLoopback()) return true;
    if (address.protocol() == QAbstractSocket::IPv4Protocol) {
        auto n = address.toIPv4Address();
        return (n >> 24) == 10 || (n >> 20) == 0xac1 || (n >> 16) == 0xc0a8 || (n >> 16) == 0xa9fe;
    }
    if (address.protocol() == QAbstractSocket::IPv6Protocol) {
        auto n = address.toIPv6Address();
        return (n[0] & 0xfe) == 0xfc || (n[0] == 0xfe && (n[1] & 0xc0) == 0x80);
    }
    return false;
}

QJsonObject SyncServer::invite(const QString &origin) {
    if (!running()) throw std::runtime_error("Enable sharing first");
    QUrl url(origin);
    QHostAddress address(url.host());
    if (url.scheme() != "http" || !privateAddress(address) || !url.userInfo().isEmpty() || url.hasQuery() || url.hasFragment() || (!url.path().isEmpty() && url.path() != "/") || url.port() != port()) throw std::runtime_error("Use a local IP address and the sharing port");
    for (auto it = approved_.begin(); it != approved_.end();) {
        if (it->expires <= QDateTime::currentSecsSinceEpoch()) { wipe(it->secret); wipe(it->nonce); wipe(it->boundRequest); it = approved_.erase(it); }
        else ++it;
    }
    if (!invitation_.response.isEmpty() && invitation_.expires > QDateTime::currentSecsSinceEpoch()) {
        if (approved_.size() >= 32) throw std::runtime_error("Pairing limit reached; wait for older invitations to expire");
        approved_.insert(invitation_.id, std::move(invitation_));
        invitation_ = {};
    }
    cancelInvite();
    invitation_.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    invitation_.secret = randomBytes(32);
    invitation_.expires = QDateTime::currentSecsSinceEpoch() + 300;
    auto privateKey = signingPrivateKey();
    const auto publicKey = publicSigningKey(privateKey);
    wipe(privateKey);
    auto clean = url;
    clean.setPath("");
    return {{"version", 1}, {"url", clean.toString()}, {"vaultId", vault_.data().value("vaultId")}, {"pairId", invitation_.id}, {"secret", QString::fromLatin1(invitation_.secret.toBase64())}, {"publicKey", QString::fromLatin1(publicKey.toBase64())}, {"expiresAt", invitation_.expires}, {"desktopName", QHostInfo::localHostName()}};
}

void SyncServer::cancelInvite(bool onlyUnapproved) { if (onlyUnapproved && !invitation_.response.isEmpty()) return; wipe(invitation_.secret); wipe(invitation_.nonce); wipe(invitation_.boundRequest); invitation_ = {}; }

void SyncServer::approve(const QString &deviceId) {
    if (deviceId != invitation_.deviceId || deviceId.isEmpty() || invitation_.expires <= QDateTime::currentSecsSinceEpoch() || invitation_.denied || !invitation_.response.isEmpty()) return;
    auto key = randomBytes(32);
    auto data = vault_.data();
    auto devices = data.value("devices").toArray();
    for (const auto &device : devices) if (device.toObject().value("id").toString() == deviceId) throw std::runtime_error("Device identity is already paired");
    if (devices.size() >= 100) throw std::runtime_error("Paired device limit reached");
    devices.append(QJsonObject{{"id", deviceId}, {"name", invitation_.deviceName}, {"syncKey", QString::fromLatin1(key.toBase64())}, {"pairedAt", QDateTime::currentSecsSinceEpoch()}});
    data["devices"] = devices;
    vault_.replace(data);
    const QJsonObject response{{"version", 1}, {"deviceId", deviceId}, {"vaultId", data.value("vaultId")}, {"syncKey", QString::fromLatin1(key.toBase64())}, {"desktopName", QHostInfo::localHostName()}};
    invitation_.response = encryptEnvelope(QJsonDocument(response).toJson(QJsonDocument::Compact), invitation_.secret, "harbor/pair-response/v1/" + invitation_.id.toUtf8());
    wipe(key);
}

void SyncServer::deny(const QString &deviceId) { if (deviceId == invitation_.deviceId) invitation_.denied = true; }

void SyncServer::revoke(const QString &deviceId) {
    auto data = vault_.data();
    auto devices = data.value("devices").toArray();
    for (int i = devices.size() - 1; i >= 0; --i) if (devices[i].toObject().value("id").toString() == deviceId) devices.removeAt(i);
    data["devices"] = devices;
    vault_.replace(data);
    if (deviceId == invitation_.deviceId) cancelInvite();
    for (auto it = approved_.begin(); it != approved_.end();) {
        if (it->deviceId == deviceId) { wipe(it->secret); wipe(it->nonce); wipe(it->boundRequest); it = approved_.erase(it); }
        else ++it;
    }
}

void SyncServer::respond(QTcpSocket *socket, int status, const QJsonObject &body) {
    const auto payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    if (payload.size() > 16 * 1024 * 1024) { respond(socket, 500); return; }
    QByteArray phrase = status == 200 ? "OK" : status == 202 ? "Accepted" : "Rejected";
    socket->write("HTTP/1.1 " + QByteArray::number(status) + ' ' + phrase + "\r\nContent-Type: application/json\r\nContent-Length: " + QByteArray::number(payload.size()) + "\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" + payload);
    socket->disconnectFromHost();
}

void SyncServer::accept() {
    while (auto socket = server_.nextPendingConnection()) {
        if (active_ >= 32) { socket->abort(); socket->deleteLater(); continue; }
        ++active_;
        socket->setParent(this);
        auto buffer = std::make_shared<QByteArray>();
        auto handled = std::make_shared<bool>(false);
        connect(socket, &QTcpSocket::disconnected, this, [this, socket] { --active_; socket->deleteLater(); });
        QTimer::singleShot(10000, socket, [socket] { socket->abort(); });
        connect(socket, &QTcpSocket::readyRead, this, [this, socket, buffer, handled] {
            if (*handled) return;
            *buffer += socket->readAll();
            auto fail = [this, socket, handled](int status) { *handled = true; respond(socket, status); };
            const int end = buffer->indexOf("\r\n\r\n");
            if (end == -1) { if (buffer->size() > 16384) fail(431); return; }
            if (end > 16384 || buffer->size() > 512 * 1024 + 16384) { fail(413); return; }
            const auto lines = buffer->left(end).split('\n');
            const auto request = lines.value(0).trimmed().split(' ');
            if (request.size() != 3 || request[2] != "HTTP/1.1" || request[0] != "POST") { fail(405); return; }
            qint64 length = -1;
            int lengths = 0;
            bool hostHeader = false;
            for (int i = 1; i < lines.size(); ++i) {
                const auto line = lines[i].trimmed();
                const int colon = line.indexOf(':');
                if (colon <= 0) { fail(400); return; }
                const auto name = line.left(colon).toLower();
                const auto value = line.mid(colon + 1).trimmed();
                if (name == "transfer-encoding") { fail(400); return; }
                if (name == "host") hostHeader = !value.isEmpty();
                if (name == "content-length") {
                    ++lengths;
                    bool valid = false;
                    length = value.toLongLong(&valid);
                    if (!valid || value.isEmpty() || value.contains('+') || value.contains('-')) { fail(400); return; }
                }
            }
            if (!hostHeader || lengths != 1 || length < 0 || length > 512 * 1024) { fail(length > 512 * 1024 ? 413 : 400); return; }
            if (buffer->size() < end + 4 + length) return;
            if (buffer->size() != end + 4 + length) { fail(400); return; }
            *handled = true;
            handle(socket, request[0], request[1], buffer->mid(end + 4));
            wipe(*buffer);
        });
    }
}

void SyncServer::handle(QTcpSocket *socket, const QByteArray &, const QByteArray &path, const QByteArray &body) {
    if (!vault_.unlocked() || !running()) { respond(socket, 503); return; }
    try {
        if (path.startsWith("/v1/pair/")) {
            if (rateWindow_.elapsed() > 60000) { rateWindow_.restart(); attempts_ = 0; }
            if (++attempts_ > 120) { respond(socket, 429); return; }
            const auto id = QString::fromUtf8(path.mid(9));
            if (id != invitation_.id) {
                auto previous = approved_.find(id);
                if (previous == approved_.end() || previous->expires <= QDateTime::currentSecsSinceEpoch()) { respond(socket, 410); return; }
                if (body != previous->boundRequest) { respond(socket, 403); return; }
                respond(socket, 200, previous->response);
                return;
            }
            if (invitation_.expires <= QDateTime::currentSecsSinceEpoch() || invitation_.id.isEmpty()) { respond(socket, 410); return; }
            auto plain = decryptEnvelope(parse(body), invitation_.secret, "harbor/pair-request/v1/" + id.toUtf8());
            const auto request = parse(plain);
            wipe(plain);
            const auto deviceId = request.value("deviceId").toString();
            const auto name = request.value("deviceName").toString();
            const auto nonce = decode(request.value("clientNonce"), 32);
            static const QRegularExpression uuid("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
            if (!uuid.match(deviceId).hasMatch() || name.trimmed().isEmpty() || name.size() > 80) { respond(socket, 400); return; }
            if (invitation_.deviceId.isEmpty()) {
                invitation_.deviceId = deviceId;
                invitation_.deviceName = name;
                invitation_.nonce = nonce;
                invitation_.boundRequest = body;
                const auto digest = QCryptographicHash::hash(invitation_.secret + nonce, QCryptographicHash::Sha256);
                const auto b = reinterpret_cast<const unsigned char *>(digest.constData());
                const quint32 n = quint32(b[0]) << 24 | quint32(b[1]) << 16 | quint32(b[2]) << 8 | b[3];
                const auto code = QString::number(n % 1000000).rightJustified(6, '0');
                QTimer::singleShot(0, this, [this, deviceId, name, code] { emit pairingRequested(deviceId, name, code); });
            } else if (invitation_.deviceId != deviceId || invitation_.nonce != nonce || invitation_.boundRequest != body) { respond(socket, 403); return; }
            if (invitation_.denied) respond(socket, 403);
            else if (!invitation_.response.isEmpty()) respond(socket, 200, invitation_.response);
            else respond(socket, 202, {{"status", "pending"}});
            return;
        }
        if (path != "/v1/sync") { respond(socket, 404); return; }
        const auto envelope = parse(body);
        const auto id = envelope.value("deviceId").toString();
        QJsonObject device;
        for (const auto &entry : devices()) if (entry.toObject().value("id").toString() == id) { device = entry.toObject(); break; }
        if (device.isEmpty()) { respond(socket, 403); return; }
        auto key = decode(device.value("syncKey"), 32);
        auto plain = decryptEnvelope(envelope, key, "harbor/sync-request/v1/" + id.toUtf8());
        const auto request = parse(plain);
        wipe(plain);
        decode(request.value("requestId"), 32);
        if (request.value("version").toInt() != 1 || request.value("vaultId") != vault_.data().value("vaultId")) { wipe(key); respond(socket, 403); return; }
        auto snapshot = vault_.snapshot();
        snapshot["version"] = 1;
        snapshot["generatedAt"] = QDateTime::currentSecsSinceEpoch();
        snapshot["requestId"] = request.value("requestId");
        auto bytes = QJsonDocument(snapshot).toJson(QJsonDocument::Compact);
        if (bytes.size() > 8 * 1024 * 1024) { wipe(bytes); wipe(key); respond(socket, 413); return; }
        const auto payload = bytes.toBase64();
        wipe(bytes);
        auto privateKey = signingPrivateKey();
        const auto signature = signSnapshot(privateKey, payload);
        wipe(privateKey);
        const QJsonObject signedObject{{"payload", QString::fromLatin1(payload)}, {"signature", QString::fromLatin1(signature.toBase64())}};
        const auto response = encryptEnvelope(QJsonDocument(signedObject).toJson(QJsonDocument::Compact), key, "harbor/sync-response/v1/" + id.toUtf8());
        wipe(key);
        respond(socket, 200, response);
    } catch (...) { respond(socket, 400); }
}
