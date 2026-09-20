#include "vault.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QUuid>
#include <QRegularExpression>
#include <QSet>
#include <QHostAddress>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QtEndian>
#include <openssl/evp.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/crypto.h>
#include <openssl/x509.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
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

QString validateHostEndpoint(const QString &hostname, int port) {
    static const QRegularExpression address("^[A-Za-z0-9][A-Za-z0-9.:%_-]{0,252}$");
    if (QHostAddress(hostname).isNull() && !address.match(hostname).hasMatch()) return "Enter a hostname or IP address without spaces.";
    if (port < 1 || port > 65535) return "Port must be between 1 and 65535.";
    return {};
}

static QString runOpenSshKeyValidation(const QByteArray &contents, const QByteArray &passphrase) {
    const auto tool = QStandardPaths::findExecutable("ssh-keygen");
    if (tool.isEmpty()) return "OpenSSH key validation is unavailable. Install openssh-client and try again.";
    const auto descriptor = memfd_create("harbor-key", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (descriptor < 0 || fchmod(descriptor, S_IRUSR | S_IWUSR) != 0) { if (descriptor >= 0) close(descriptor); return "Could not validate this private key. Try again."; }
    QFile key;
    if (!key.open(descriptor, QIODevice::ReadWrite, QFileDevice::AutoCloseHandle) || key.write(contents) != contents.size() || !key.flush() || !key.seek(0) || fcntl(descriptor, F_ADD_SEALS, F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_WRITE | F_SEAL_SEAL) != 0) return "Could not validate this private key. Try again.";
    int passphraseDescriptor = -1;
    QFile passphraseFile;
    if (!passphrase.isEmpty()) {
        passphraseDescriptor = memfd_create("harbor-passphrase", MFD_CLOEXEC | MFD_ALLOW_SEALING);
        if (passphraseDescriptor < 0 || fchmod(passphraseDescriptor, S_IRUSR | S_IWUSR) != 0) { if (passphraseDescriptor >= 0) close(passphraseDescriptor); return "Could not validate this private key. Try again."; }
        if (!passphraseFile.open(passphraseDescriptor, QIODevice::ReadWrite, QFileDevice::AutoCloseHandle)) { close(passphraseDescriptor); return "Could not validate this private key. Try again."; }
        auto answer = passphrase + '\n';
        const bool ready = passphraseFile.write(answer) == answer.size() && passphraseFile.flush() && passphraseFile.seek(0) && fcntl(passphraseDescriptor, F_ADD_SEALS, F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_WRITE | F_SEAL_SEAL) == 0;
        wipe(answer);
        if (!ready) return "Could not validate this private key. Try again.";
    }
    QProcess process;
    process.setProgram(tool);
    process.setArguments({passphrase.isEmpty() ? "-l" : "-y", "-f", QString("/proc/self/fd/%1").arg(descriptor)});
    process.setStandardOutputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
    process.setStandardInputFile(QProcess::nullDevice());
    auto environment = QProcessEnvironment::systemEnvironment();
    for (const auto &name : {"SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "HARBOR_ASKPASS_FD", "HARBOR_ASKPASS_SOCKET", "HARBOR_ASKPASS_CAPABILITY"}) environment.remove(name);
    if (passphrase.isEmpty()) {
        environment.insert("SSH_ASKPASS_REQUIRE", "never");
    } else {
        const auto helper = QCoreApplication::applicationDirPath() + "/harbor-askpass";
        if (!QFileInfo::exists(helper)) return "OpenSSH passphrase validation is unavailable. Reinstall Harbor and try again.";
        environment.insert("SSH_ASKPASS", helper);
        environment.insert("SSH_ASKPASS_REQUIRE", "force");
        environment.insert("HARBOR_ASKPASS_FD", QString::number(passphraseDescriptor));
        environment.insert("DISPLAY", environment.value("DISPLAY", ":0"));
    }
    process.setProcessEnvironment(environment);
    process.setChildProcessModifier([&process, descriptor, passphraseDescriptor] {
        if (setpgid(0, 0) != 0) process.failChildProcessModifier("Could not isolate validator", errno);
        if (fcntl(descriptor, F_SETFD, 0) != 0) process.failChildProcessModifier("Could not inherit private key", errno);
        if (passphraseDescriptor >= 0 && fcntl(passphraseDescriptor, F_SETFD, 0) != 0) process.failChildProcessModifier("Could not inherit passphrase", errno);
    });
    process.start();
    if (!process.waitForStarted(3000)) return "Could not validate this private key. Try again.";
    if (!process.waitForFinished(10000)) {
        const auto pid = process.processId();
        if (pid <= 0 || (::kill(-pid, SIGKILL) != 0 && errno != ESRCH)) process.kill();
        process.waitForFinished(1000);
        return "Could not validate this private key. Try again.";
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0 ? QString() : "The key passphrase is incorrect, or the encrypted key is damaged.";
}

static QString validatePkcs8Kdf(const QByteArray &der) {
    const auto error = QString("This encrypted private key uses unsupported or excessive key derivation parameters.");
    const unsigned char *cursor = reinterpret_cast<const unsigned char *>(der.constData());
    auto end = cursor + der.size();
    auto envelope = std::unique_ptr<X509_SIG, decltype(&X509_SIG_free)>(d2i_X509_SIG(nullptr, &cursor, der.size()), X509_SIG_free);
    if (!envelope || cursor != end) return error;
    const X509_ALGOR *algorithm = nullptr;
    const ASN1_OCTET_STRING *ciphertext = nullptr;
    X509_SIG_get0(envelope.get(), &algorithm, &ciphertext);
    const ASN1_OBJECT *object = nullptr;
    const void *parameters = nullptr;
    int type = 0;
    X509_ALGOR_get0(&object, &type, &parameters, algorithm);
    if (!object || OBJ_obj2nid(object) != NID_pbes2 || type != V_ASN1_SEQUENCE || !parameters) return error;
    auto sequence = static_cast<const ASN1_STRING *>(parameters);
    cursor = ASN1_STRING_get0_data(sequence);
    end = cursor + ASN1_STRING_length(sequence);
    auto pbes2 = std::unique_ptr<PBE2PARAM, decltype(&PBE2PARAM_free)>(d2i_PBE2PARAM(nullptr, &cursor, end - cursor), PBE2PARAM_free);
    if (!pbes2 || cursor != end) return error;
    X509_ALGOR_get0(&object, &type, &parameters, pbes2->keyfunc);
    if (!object || OBJ_obj2nid(object) != NID_id_pbkdf2 || type != V_ASN1_SEQUENCE || !parameters) return error;
    sequence = static_cast<const ASN1_STRING *>(parameters);
    cursor = ASN1_STRING_get0_data(sequence);
    end = cursor + ASN1_STRING_length(sequence);
    auto pbkdf2 = std::unique_ptr<PBKDF2PARAM, decltype(&PBKDF2PARAM_free)>(d2i_PBKDF2PARAM(nullptr, &cursor, end - cursor), PBKDF2PARAM_free);
    int64_t rounds = 0;
    if (!pbkdf2 || cursor != end || ASN1_INTEGER_get_int64(&rounds, pbkdf2->iter) != 1 || rounds < 1 || rounds > 2000000 || !pbkdf2->salt || pbkdf2->salt->type != V_ASN1_OCTET_STRING || !pbkdf2->salt->value.octet_string || pbkdf2->salt->value.octet_string->length < 1 || pbkdf2->salt->value.octet_string->length > 1024) return error;
    return {};
}

static int pemPassword(char *buffer, int size, int, void *data) {
    const auto &passphrase = *static_cast<QByteArray *>(data);
    if (passphrase.isEmpty() || passphrase.size() > size) return 0;
    std::memcpy(buffer, passphrase.constData(), passphrase.size());
    return passphrase.size();
}

QString validatePrivateKey(const QByteArray &contents, const QByteArray &passphrase, bool requireDecryption) {
    if (contents.size() > 256 * 1024) return "This key is larger than 256 KiB.";
    if (passphrase.size() > 32768 || passphrase.contains('\0') || passphrase.contains('\n') || passphrase.contains('\r')) return "The key passphrase contains unsupported characters or exceeds 32 KiB.";
    auto normalized = contents;
    normalized.replace("\r\n", "\n");
    const auto text = QString::fromUtf8(normalized).trimmed();
    if (text.startsWith("ssh-") || text.startsWith("ecdsa-") || text.startsWith("PuTTY-User-Key-File-") || !text.startsWith("-----BEGIN ") || !text.contains(" PRIVATE KEY-----")) return "Choose an OpenSSH or PEM private key, not a public key or PuTTY file.";
    if (text.startsWith("-----BEGIN OPENSSH PRIVATE KEY-----")) {
        const auto encoded = text.section('\n', 1, -2).remove('\n').toLatin1();
        const auto binary = QByteArray::fromBase64(encoded, QByteArray::AbortOnBase64DecodingErrors);
        if (binary.size() < 19 || binary.left(15) != QByteArray("openssh-key-v1\0", 15)) return "This private key is incomplete or invalid. Export it again and retry.";
        const auto size = qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(binary.constData() + 15));
        if (size > 64 || binary.size() < 19 + static_cast<int>(size)) return "This private key is incomplete or invalid. Export it again and retry.";
        const bool encrypted = binary.mid(19, size) != "none";
        const auto structure = runOpenSshKeyValidation(normalized, {});
        if (!structure.isEmpty()) return "This private key is incomplete or invalid. Export it again and retry.";
        if (encrypted && passphrase.isEmpty()) return requireDecryption ? "Enter the passphrase for this encrypted private key." : QString();
        if (!encrypted && !passphrase.isEmpty()) return requireDecryption ? "This private key is not encrypted. Clear the key passphrase and retry." : QString();
        return encrypted ? runOpenSshKeyValidation(normalized, passphrase) : QString();
    }
    static const QRegularExpression envelope("^-----BEGIN ([A-Z0-9 ]*PRIVATE KEY)-----\\n([\\s\\S]+)\\n-----END \\1-----$");
    const auto match = envelope.match(text);
    if (normalized.contains('\0') || normalized.contains('\r') || text.toUtf8() != normalized.trimmed() || !match.hasMatch()) return "This private key is incomplete or invalid. Export it again and retry.";
    const auto body = match.captured(2);
    const bool encrypted = match.captured(1) == "ENCRYPTED PRIVATE KEY" || body.contains("Proc-Type: 4,ENCRYPTED");
    QByteArray encoded;
    for (const auto &line : body.split('\n')) if (!line.isEmpty() && !line.contains(':')) encoded += line.toLatin1();
    const auto decoded = QByteArray::fromBase64(encoded, QByteArray::AbortOnBase64DecodingErrors);
    if (decoded.size() < 16) return "This private key is incomplete or invalid. Export it again and retry.";
    if (match.captured(1) == "ENCRYPTED PRIVATE KEY") {
        ERR_clear_error();
        const auto kdfError = validatePkcs8Kdf(decoded);
        ERR_clear_error();
        if (!kdfError.isEmpty()) return kdfError;
    }
    if (encrypted && passphrase.isEmpty()) return requireDecryption ? "Enter the passphrase for this encrypted private key." : QString();
    if (!encrypted && !passphrase.isEmpty()) return requireDecryption ? "This private key is not encrypted. Clear the key passphrase and retry." : QString();
    auto password = passphrase;
    auto bio = BIO_new_mem_buf(normalized.constData(), normalized.size());
    ERR_clear_error();
    auto key = bio ? PEM_read_bio_PrivateKey(bio, nullptr, pemPassword, &password) : nullptr;
    auto context = key ? EVP_PKEY_CTX_new(key, nullptr) : nullptr;
    const bool valid = context && EVP_PKEY_private_check(context) == 1;
    if (context) EVP_PKEY_CTX_free(context);
    if (key) EVP_PKEY_free(key);
    if (bio) BIO_free(bio);
    ERR_clear_error();
    wipe(password);
    if (!valid) return encrypted ? "The key passphrase is incorrect, or the encrypted key is damaged." : "This private key is incomplete or invalid. Export it again and retry.";
    return {};
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
    if (host.value("name").toString().trimmed().isEmpty() || host.value("name").toString().size() > 120) return "Enter a host name of at most 120 characters.";
    const auto endpointError = validateHostEndpoint(host.value("hostname").toString(), host.value("port").toInt());
    if (!endpointError.isEmpty()) return endpointError;
    const auto username = host.value("username").toString();
    static const QRegularExpression usernamePattern("^[A-Za-z_][A-Za-z0-9_.-]{0,63}[$]?$");
    if (!usernamePattern.match(username).hasMatch()) return "Enter a valid SSH username.";
    const auto auth = host.value("authType").toString();
    if (auth != "password" && auth != "key" && auth != "none") return "Choose an authentication method.";
    for (const auto &credential : {host.value("password").toString(), host.value("passphrase").toString()}) if (credential.toUtf8().size() > 32768 || credential.contains('\n') || credential.contains('\r') || credential.contains(QChar(0))) return "Credential contains unsupported characters or exceeds 32 KiB.";
    if (auth == "password" && host.value("password").toString().isEmpty()) return "Enter a password.";
    if (auth == "key" && !host.value("privateKey").toString().contains("PRIVATE KEY-----")) return "Import a valid PEM or OpenSSH private key.";
    if (auth == "none" && (!host.value("password").toString().isEmpty() || !host.value("privateKey").toString().isEmpty() || !host.value("passphrase").toString().isEmpty())) return "No-password hosts cannot store SSH credentials.";
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
