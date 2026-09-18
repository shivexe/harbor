#include "vault.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QUuid>
#include <QRegularExpression>
#include <QSet>
#include <QHostAddress>
#include <QtEndian>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/crypto.h>
#include <memory>
#include <stdexcept>

static void require(bool ok, const char *message) {
    if (!ok) throw std::runtime_error(message);
}

QByteArray randomBytes(int size) {
    QByteArray bytes(size, Qt::Uninitialized);
    require(RAND_bytes(reinterpret_cast<unsigned char *>(bytes.data()), size) == 1, "Secure randomness unavailable");
    return bytes;
}

void wipe(QByteArray &value) {
    if (!value.isEmpty()) OPENSSL_cleanse(value.data(), value.size());
    value.clear();
}

QByteArray deriveKey(const QByteArray &password, const QByteArray &salt, int rounds) {
    require(salt.size() == 16 && rounds >= 600000 && rounds <= 2000000, "Invalid key derivation parameters");
    QByteArray key(32, Qt::Uninitialized);
    require(PKCS5_PBKDF2_HMAC(password.constData(), password.size(), reinterpret_cast<const unsigned char *>(salt.constData()), salt.size(), rounds, EVP_sha256(), key.size(), reinterpret_cast<unsigned char *>(key.data())) == 1, "Key derivation failed");
    return key;
}

QByteArray seal(const QByteArray &plain, const QByteArray &key, const QByteArray &aad) {
    require(key.size() == 32, "Invalid encryption key");
    auto nonce = randomBytes(12);
    auto context = std::unique_ptr<EVP_CIPHER_CTX, decltype(&EVP_CIPHER_CTX_free)>(EVP_CIPHER_CTX_new(), EVP_CIPHER_CTX_free);
    require(bool(context), "Encryption unavailable");
    int length = 0, finalLength = 0;
    QByteArray cipher(plain.size() + 16, Qt::Uninitialized), tag(16, Qt::Uninitialized);
    require(EVP_EncryptInit_ex(context.get(), EVP_aes_256_gcm(), nullptr, reinterpret_cast<const unsigned char *>(key.constData()), reinterpret_cast<const unsigned char *>(nonce.constData())) == 1, "Encryption failed");
    if (!aad.isEmpty()) require(EVP_EncryptUpdate(context.get(), nullptr, &length, reinterpret_cast<const unsigned char *>(aad.constData()), aad.size()) == 1, "Encryption failed");
    require(EVP_EncryptUpdate(context.get(), reinterpret_cast<unsigned char *>(cipher.data()), &length, reinterpret_cast<const unsigned char *>(plain.constData()), plain.size()) == 1, "Encryption failed");
    require(EVP_EncryptFinal_ex(context.get(), reinterpret_cast<unsigned char *>(cipher.data()) + length, &finalLength) == 1, "Encryption failed");
    cipher.resize(length + finalLength);
    require(EVP_CIPHER_CTX_ctrl(context.get(), EVP_CTRL_GCM_GET_TAG, 16, tag.data()) == 1, "Encryption failed");
    return nonce + cipher + tag;
}

QByteArray unseal(const QByteArray &box, const QByteArray &key, const QByteArray &aad) {
    require(key.size() == 32 && box.size() >= 28 && box.size() <= 16 * 1024 * 1024, "Invalid encrypted data");
    auto context = std::unique_ptr<EVP_CIPHER_CTX, decltype(&EVP_CIPHER_CTX_free)>(EVP_CIPHER_CTX_new(), EVP_CIPHER_CTX_free);
    require(bool(context), "Decryption unavailable");
    int length = 0, finalLength = 0;
    QByteArray plain(box.size() - 28 + 16, Qt::Uninitialized);
    require(EVP_DecryptInit_ex(context.get(), EVP_aes_256_gcm(), nullptr, reinterpret_cast<const unsigned char *>(key.constData()), reinterpret_cast<const unsigned char *>(box.constData())) == 1, "Decryption failed");
    if (!aad.isEmpty()) require(EVP_DecryptUpdate(context.get(), nullptr, &length, reinterpret_cast<const unsigned char *>(aad.constData()), aad.size()) == 1, "Decryption failed");
    require(EVP_DecryptUpdate(context.get(), reinterpret_cast<unsigned char *>(plain.data()), &length, reinterpret_cast<const unsigned char *>(box.constData()) + 12, box.size() - 28) == 1, "Decryption failed");
    require(EVP_CIPHER_CTX_ctrl(context.get(), EVP_CTRL_GCM_SET_TAG, 16, const_cast<char *>(box.constData()) + box.size() - 16) == 1, "Decryption failed");
    if (EVP_DecryptFinal_ex(context.get(), reinterpret_cast<unsigned char *>(plain.data()) + length, &finalLength) != 1) {
        wipe(plain);
        throw std::runtime_error("Incorrect passphrase or damaged encrypted data");
    }
    plain.resize(length + finalLength);
    return plain;
}

QString validateHost(const QJsonObject &host) {
    const QStringList fields{"name", "hostname", "username", "group", "authType", "password", "privateKey", "passphrase", "hostKey", "notes"};
    for (const auto &field : fields) if (!host.value(field).isString()) return "Host fields must be strings.";
    if (!host.value("port").isDouble() || host.value("port").toDouble() != host.value("port").toInt()) return "Port must be an integer.";
    if (!host.value("id").isUndefined()) {
        static const QRegularExpression uuid("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
        if (!host.value("id").isString() || !uuid.match(host.value("id").toString()).hasMatch()) return "Invalid host identity.";
    }
    if (host.value("privateKey").toString().toUtf8().size() > 256 * 1024 || QJsonDocument(host).toJson(QJsonDocument::Compact).size() > 1024 * 1024) return "Host record exceeds size limits.";
    const auto pinned = host.value("hostKey").toString();
    if (!pinned.isEmpty()) {
        const auto parts = pinned.toLatin1().split(' ');
        if (parts.size() != 2 || !(parts[0] == "ssh-ed25519" || parts[0] == "ssh-rsa" || parts[0].startsWith("ecdsa-sha2-")) || pinned.contains('\n') || pinned.contains('\r') || QByteArray::fromBase64(parts[1], QByteArray::AbortOnBase64DecodingErrors).isEmpty()) return "Invalid server public key.";
        const auto wire = QByteArray::fromBase64(parts[1], QByteArray::AbortOnBase64DecodingErrors);
        if (wire.size() < 8 || wire.size() > 32768 || wire.toBase64() != parts[1]) return "Invalid server public key encoding.";
        const auto length = qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(wire.constData()));
        if (length > 100 || length + 4 > static_cast<quint32>(wire.size()) || wire.mid(4, length) != parts[0]) return "Server key algorithm does not match its data.";
        if (parts[0] == "ssh-ed25519" && (wire.size() != 51 || qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(wire.constData() + 15)) != 32)) return "Invalid Ed25519 server key.";
    }
    static const QRegularExpression address("^[A-Za-z0-9][A-Za-z0-9.:%_-]{0,252}$");
    if (host.value("name").toString().trimmed().isEmpty() || host.value("name").toString().size() > 120) return "Enter a host name of at most 120 characters.";
    if (QHostAddress(host.value("hostname").toString()).isNull() && !address.match(host.value("hostname").toString()).hasMatch()) return "Enter a hostname or IP address without spaces.";
    const auto username = host.value("username").toString();
    static const QRegularExpression usernamePattern("^[A-Za-z_][A-Za-z0-9_.-]{0,63}[$]?$");
    if (!usernamePattern.match(username).hasMatch()) return "Enter a valid SSH username.";
    const int port = host.value("port").toInt();
    if (port < 1 || port > 65535) return "Port must be between 1 and 65535.";
    const auto auth = host.value("authType").toString();
    if (auth != "password" && auth != "key") return "Choose an authentication method.";
    for (const auto &credential : {host.value("password").toString(), host.value("passphrase").toString()}) if (credential.toUtf8().size() > 32768 || credential.contains('\n') || credential.contains('\r') || credential.contains(QChar(0))) return "Credential contains unsupported characters or exceeds 32 KiB.";
    if (auth == "password" && host.value("password").toString().isEmpty()) return "Enter a password.";
    if (auth == "key" && !host.value("privateKey").toString().contains("PRIVATE KEY-----")) return "Import a valid PEM or OpenSSH private key.";
    if (host.value("group").toString().size() > 120) return "Group must be at most 120 characters.";
    return {};
}

Vault::Vault(QString path, QObject *parent) : QObject(parent), path_(std::move(path)) {}
Vault::~Vault() { lock(); }
bool Vault::exists() const { return QFileInfo::exists(path_); }
bool Vault::unlocked() const { return key_.size() == 32; }
QString Vault::directory() const { return QFileInfo(path_).absolutePath(); }
QJsonObject Vault::data() const { require(unlocked(), "Vault is locked"); return data_; }
QJsonArray Vault::hosts() const { return data().value("hosts").toArray(); }

void Vault::unlock(const QString &passphrase) {
    require(passphrase.size() >= 12, "Use a master passphrase of at least 12 characters");
    auto password = passphrase.toUtf8();
    try {
        if (exists()) {
            QFile file(path_);
            require(file.open(QIODevice::ReadOnly) && file.size() <= 16 * 1024 * 1024, "Cannot read vault");
            const auto envelope = QJsonDocument::fromJson(file.readAll()).object();
            require(envelope.value("rounds").toInt() == 600000, "Unsupported vault key derivation");
            require(envelope.value("version").toInt() == 1, "Unsupported vault format");
            salt_ = QByteArray::fromBase64(envelope.value("salt").toString().toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
            auto key = deriveKey(password, salt_, envelope.value("rounds").toInt());
            auto plain = unseal(QByteArray::fromBase64(envelope.value("box").toString().toLatin1(), QByteArray::AbortOnBase64DecodingErrors), key, "harbor-vault-v1");
            QJsonParseError error;
            const auto doc = QJsonDocument::fromJson(plain, &error);
            wipe(plain);
            require(error.error == QJsonParseError::NoError && doc.isObject(), "Damaged vault contents");
            const auto contents = doc.object();
            require(contents.value("hosts").isArray() && contents.value("hosts").toArray().size() <= 10000, "Invalid host collection");
            QSet<QString> identities;
            for (const auto &entry : contents.value("hosts").toArray()) {
                const auto host = entry.toObject();
                const auto identity = host.value("id").toString();
                require(entry.isObject() && validateHost(host).isEmpty() && !identity.isEmpty() && !identities.contains(identity), "Invalid or duplicate saved host");
                identities.insert(identity);
            }
            require(contents.value("revision").toInteger() >= 1 && contents.value("revision").toInteger() <= 9007199254740991LL, "Invalid vault revision");
            data_ = contents;
            key_ = key;
            wipe(key);
        } else {
            salt_ = randomBytes(16);
            key_ = deriveKey(password, salt_);
            data_ = {{"vaultId", QUuid::createUuid().toString(QUuid::WithoutBraces)}, {"revision", 1}, {"hosts", QJsonArray()}, {"devices", QJsonArray()}};
            save();
        }
        wipe(password);
    } catch (...) { wipe(password); lock(); throw; }
}

void Vault::save() {
    require(unlocked(), "Vault is locked");
    require(QDir().mkpath(directory()), "Cannot create vault directory");
    require(QFile::setPermissions(directory(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner), "Cannot secure vault directory");
    auto plain = QJsonDocument(data_).toJson(QJsonDocument::Compact);
    require(plain.size() <= 8 * 1024 * 1024 && data_.value("hosts").toArray().size() <= 10000, "Vault size limit exceeded");
    auto box = seal(plain, key_, "harbor-vault-v1");
    wipe(plain);
    QJsonObject envelope{{"version", 1}, {"rounds", 600000}, {"salt", QString::fromLatin1(salt_.toBase64())}, {"box", QString::fromLatin1(box.toBase64())}};
    QSaveFile file(path_);
    require(file.open(QIODevice::WriteOnly), "Cannot open vault for saving");
    require(file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner), "Cannot secure vault file");
    const auto serialized = QJsonDocument(envelope).toJson(QJsonDocument::Compact);
    require(file.write(serialized) == serialized.size() && file.commit(), "Cannot save vault");
}

void Vault::replace(const QJsonObject &data) {
    require(unlocked(), "Vault is locked");
    auto previous = data_;
    data_ = data;
    try { save(); } catch (...) { data_ = previous; throw; }
    emit changed();
}

void Vault::upsert(QJsonObject host, bool keyVerified) {
    const auto error = validateHost(host);
    require(error.isEmpty(), qPrintable(error));
    auto next = data();
    auto array = next.value("hosts").toArray();
    if (!host.value("id").toString().isEmpty()) {
        for (const auto &existing : array) {
            const auto previous = existing.toObject();
            if (!keyVerified && previous.value("id") == host.value("id") && (previous.value("hostname") != host.value("hostname") || previous.value("port") != host.value("port"))) host["hostKey"] = "";
        }
    }
    if (host.value("id").toString().isEmpty()) host["id"] = QUuid::createUuid().toString(QUuid::WithoutBraces);
    bool found = false;
    for (int i = 0; i < array.size(); ++i) if (array[i].toObject().value("id") == host.value("id")) { array[i] = host; found = true; break; }
    if (!found) array.append(host);
    next["hosts"] = array;
    next["revision"] = next.value("revision").toInteger() + 1;
    replace(next);
}

void Vault::remove(const QString &id) {
    auto next = data();
    auto array = next.value("hosts").toArray();
    for (int i = array.size() - 1; i >= 0; --i) if (array[i].toObject().value("id").toString() == id) array.removeAt(i);
    next["hosts"] = array;
    next["revision"] = next.value("revision").toInteger() + 1;
    replace(next);
}

QJsonObject Vault::snapshot() const {
    const auto current = data();
    return {{"vaultId", current.value("vaultId")}, {"revision", current.value("revision")}, {"hosts", current.value("hosts")}};
}

void Vault::lock() { data_ = {}; wipe(key_); wipe(salt_); emit changed(); }
