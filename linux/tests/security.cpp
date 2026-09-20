#include "vault.h"
#include "sync.h"
#include "pairing_network.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <openssl/evp.h>
#include <stdexcept>
#include <iostream>
static void check(bool ok) { if (!ok) throw std::runtime_error("Security check failed"); }
static bool rejects(auto action) { try { action(); return false; } catch (...) { return true; } }
static QByteArray pem(const QByteArray &der) {
    auto encoded = der.toBase64();
    QByteArray result("-----BEGIN ENCRYPTED PRIVATE KEY-----\n");
    while (!encoded.isEmpty()) { result += encoded.left(64) + '\n'; encoded.remove(0, 64); }
    return result + "-----END ENCRYPTED PRIVATE KEY-----\n";
}
int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    try {
        QFile vectorsFile(HARBOR_VECTOR_FILE);
        check(vectorsFile.open(QIODevice::ReadOnly));
        const auto vectors = QJsonDocument::fromJson(vectorsFile.readAll()).object();
        for (const auto &entry : vectors.value("messages").toArray()) {
            const auto message = entry.toObject();
            const auto vectorKey = QByteArray::fromBase64(message.value("key").toString().toLatin1());
            check(decryptEnvelope(message.value("envelope").toObject(), vectorKey, message.value("aad").toString().toUtf8()) == message.value("plaintext").toString().toUtf8());
        }
        const auto vectorSeed = QByteArray::fromBase64(vectors.value("signingSeed").toString().toLatin1());
        check(publicSigningKey(vectorSeed).toBase64() == vectors.value("publicKey").toString().toLatin1());
        check(signSnapshot(vectorSeed, vectors.value("payload").toString().toLatin1()).toBase64() == vectors.value("signature").toString().toLatin1());
        const auto kdf = vectors.value("pbkdf2").toObject();
        check(deriveKey(kdf.value("password").toString().toUtf8(), QByteArray::fromBase64(kdf.value("salt").toString().toLatin1()), kdf.value("rounds").toInt()).toBase64() == kdf.value("key").toString().toLatin1());
        auto key = randomBytes(32);
        const auto envelope = encryptEnvelope("private data", key, "bound-context");
        check(decryptEnvelope(envelope, key, "bound-context") == "private data");
        check(rejects([&] { decryptEnvelope(envelope, key, "wrong-context"); }));
        auto altered = envelope;
        altered["tag"] = QString::fromLatin1(QByteArray(16, '\0').toBase64());
        check(rejects([&] { decryptEnvelope(altered, key, "bound-context"); }));
        auto seed = randomBytes(32);
        const auto publicKey = publicSigningKey(seed);
        const auto payload = QByteArray("e30=");
        const auto signature = signSnapshot(seed, payload);
        auto verificationKey = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr, reinterpret_cast<const unsigned char *>(publicKey.constData()), publicKey.size());
        auto context = EVP_MD_CTX_new();
        check(EVP_DigestVerifyInit(context, nullptr, nullptr, nullptr, verificationKey) == 1);
        const auto signedBytes = QByteArray("harbor.snapshot.v1\n") + payload;
        check(EVP_DigestVerify(context, reinterpret_cast<const unsigned char *>(signature.constData()), signature.size(), reinterpret_cast<const unsigned char *>(signedBytes.constData()), signedBytes.size()) == 1);
        EVP_MD_CTX_free(context);
        EVP_PKEY_free(verificationKey);
        QTemporaryDir directory;
        const auto keyPath = directory.filePath("identity");
        QProcess keygen;
        keygen.setProgram("ssh-keygen");
        keygen.setArguments({"-q", "-t", "ed25519", "-N", "", "-f", keyPath});
        keygen.setStandardOutputFile(QProcess::nullDevice());
        keygen.setStandardErrorFile(QProcess::nullDevice());
        keygen.start();
        check(keygen.waitForFinished(10000) && keygen.exitCode() == 0);
        QFile privateFile(keyPath), publicFile(keyPath + ".pub");
        check(privateFile.open(QIODevice::ReadOnly) && publicFile.open(QIODevice::ReadOnly));
        const auto privateData = privateFile.readAll();
        check(validatePrivateKey(privateData).isEmpty());
        auto windowsData = privateData;
        windowsData.replace("\n", "\r\n");
        check(validatePrivateKey(windowsData).isEmpty());
        check(validatePrivateKey(publicFile.readAll()).contains("not a public key"));
        check(validatePrivateKey(privateData.left(privateData.size() / 2)).contains("incomplete or invalid"));
        check(validatePrivateKey(QByteArray(256 * 1024 + 1, 'x')).contains("larger than"));
        if (argc == 2) {
            QDir fixtures(argv[1]);
            QFile passphraseFile(fixtures.filePath("passphrase"));
            check(passphraseFile.open(QIODevice::ReadOnly));
            auto fixturePassphrase = passphraseFile.readAll().trimmed();
            QByteArray encryptedForReload;
            QByteArray encryptedOpenSsh;
            for (const auto &name : {"rsa-pkcs8-encrypted.pem", "ec-pkcs8-encrypted.pem", "ed25519-pkcs8-encrypted.pem", "rsa-traditional-encrypted.pem", "ec-traditional-encrypted.pem", "openssh-encrypted"}) {
                QFile fixture(fixtures.filePath(name));
                check(fixture.open(QIODevice::ReadOnly));
                const auto encrypted = fixture.readAll();
                const auto draftError = validatePrivateKey(encrypted);
                const auto missingError = validatePrivateKey(encrypted, {}, true);
                const auto correctError = validatePrivateKey(encrypted, fixturePassphrase, true);
                const auto wrongError = validatePrivateKey(encrypted, "incorrect fixture passphrase", true);
                if (!draftError.isEmpty() || !missingError.contains("Enter the passphrase") || !correctError.isEmpty() || !wrongError.contains("incorrect")) throw std::runtime_error((QString(name) + ": " + draftError + " | " + missingError + " | " + correctError + " | " + wrongError).toStdString());
                auto corrupted = encrypted;
                corrupted.remove(corrupted.size() / 2, 7);
                if (validatePrivateKey(corrupted, fixturePassphrase, true).isEmpty()) throw std::runtime_error((QString(name) + ": corrupted key accepted").toStdString());
                if (name == QByteArray("rsa-pkcs8-encrypted.pem")) {
                    encryptedForReload = encrypted;
                    auto encoded = encrypted.split('\n');
                    QByteArray der;
                    for (const auto &line : encoded) if (!line.startsWith("-----") && !line.isEmpty()) der += line;
                    der = QByteArray::fromBase64(der);
                    check(der.size() > 54 && der.mid(52, 4) == QByteArray::fromHex("02020800") && static_cast<unsigned char>(der[1]) == 0x82);
                    if (!validatePrivateKey(pem(der), fixturePassphrase, true).isEmpty()) throw std::runtime_error("PKCS#8 test PEM rewrapping changed the fixture");
                    auto excessive = der;
                    excessive[3] = excessive[3] + 2;
                    for (const auto offset : {5, 18, 20, 33}) excessive[offset] = excessive[offset] + 2;
                    excessive.replace(52, 4, QByteArray::fromHex("02047fffffff"));
                    auto malformed = der;
                    malformed[31] = malformed[31] ^ 1;
                    QElapsedTimer kdfTimer;
                    kdfTimer.start();
                    const auto excessiveError = validatePrivateKey(pem(excessive), fixturePassphrase, true);
                    const auto malformedError = validatePrivateKey(pem(malformed), fixturePassphrase, true);
                    if (!excessiveError.contains("key derivation")) throw std::runtime_error(("Excessive PKCS#8 KDF was not rejected before decryption: " + excessiveError).toStdString());
                    if (!malformedError.contains("key derivation")) throw std::runtime_error(("Malformed PKCS#8 KDF was not rejected before decryption: " + malformedError).toStdString());
                    if (kdfTimer.elapsed() >= 1000) throw std::runtime_error("Invalid PKCS#8 KDF validation exceeded its work bound");
                }
                if (name == QByteArray("openssh-encrypted")) encryptedOpenSsh = encrypted;
            }
            QElapsedTimer maximumPassphraseTimer;
            maximumPassphraseTimer.start();
            if (!validatePrivateKey(encryptedOpenSsh, QByteArray(32768, 'x'), true).contains("incorrect")) throw std::runtime_error("Longest accepted OpenSSH passphrase was not consumed safely");
            if (maximumPassphraseTimer.elapsed() >= 12000) throw std::runtime_error("Longest accepted OpenSSH passphrase validation timed out");
            const auto fakeBin = directory.filePath("fake-bin");
            check(QDir().mkdir(fakeBin));
            QFile fakeKeygen(fakeBin + "/ssh-keygen");
            check(fakeKeygen.open(QIODevice::WriteOnly) && fakeKeygen.write("#!/bin/sh\nexit 1\n") == 17);
            fakeKeygen.close();
            check(fakeKeygen.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner));
            const auto originalPath = qgetenv("PATH");
            check(qputenv("PATH", fakeBin.toUtf8()));
            QElapsedTimer earlyExitTimer;
            earlyExitTimer.start();
            if (validatePrivateKey(encryptedOpenSsh, QByteArray(32768, 'x'), true).isEmpty()) throw std::runtime_error("Early ssh-keygen exit accepted an encrypted key");
            if (earlyExitTimer.elapsed() >= 2000) throw std::runtime_error("Early ssh-keygen exit blocked validation");
            check(qputenv("PATH", originalPath));
            if (!validatePrivateKey(privateData, fixturePassphrase, true).contains("not encrypted")) throw std::runtime_error("Unencrypted key accepted a passphrase");
            QJsonObject encryptedHost{{"name", "Encrypted fixture"}, {"hostname", "127.0.0.1"}, {"port", 22}, {"username", "harbor"}, {"group", "Tests"}, {"authType", "key"}, {"password", ""}, {"privateKey", QString::fromUtf8(encryptedForReload)}, {"passphrase", QString::fromUtf8(fixturePassphrase)}, {"hostKey", ""}, {"notes", ""}};
            Vault encryptedVault(directory.path() + "/encrypted-vault.json");
            encryptedVault.unlock("encrypted fixture vault passphrase");
            encryptedVault.upsert(encryptedHost);
            encryptedVault.lock();
            encryptedVault.unlock("encrypted fixture vault passphrase");
            const auto reloaded = encryptedVault.hosts().first().toObject();
            if (reloaded.value("privateKey").toString().toUtf8() != encryptedForReload || reloaded.value("passphrase").toString().toUtf8() != fixturePassphrase) throw std::runtime_error("Encrypted vault reload changed credentials");
            wipe(fixturePassphrase);
        }
        check(pairingNetworkPriority("wlo1", QNetworkInterface::Wifi, QHostAddress("192.168.10.5")) < pairingNetworkPriority("en0", QNetworkInterface::Ethernet, QHostAddress("10.0.0.5")));
        check(pairingNetworkPriority("en0", QNetworkInterface::Ethernet, QHostAddress("10.0.0.5")) < pairingNetworkPriority("tailscale0", QNetworkInterface::Virtual, QHostAddress("100.64.0.1")));
        check(pairingNetworkPriority("tailscale0", QNetworkInterface::Virtual, QHostAddress("100.127.255.254")) >= 0);
        check(pairingNetworkPriority("tailscale0", QNetworkInterface::Virtual, QHostAddress("100.63.255.254")) < 0);
        check(pairingNetworkPriority("tailscale0", QNetworkInterface::Virtual, QHostAddress("100.128.0.1")) < 0);
        check(pairingNetworkPriority("docker0", QNetworkInterface::Ethernet, QHostAddress("10.0.0.1")) < 0);
        check(pairingNetworkPriority("br-1234", QNetworkInterface::Ethernet, QHostAddress("10.0.1.1")) < 0);
        check(pairingNetworkPriority("wlo1", QNetworkInterface::Wifi, QHostAddress("8.8.8.8")) < 0);
        check(pairingNetworkPriority("wlo1", QNetworkInterface::Wifi, QHostAddress("127.0.0.1")) < 0);
        check(pairingNetworkPriority("tailscale0", QNetworkInterface::Virtual, QHostAddress("fd7a:115c::1")) >= 0);
        check(pairingNetworkPriority("tailscale0", QNetworkInterface::Virtual, QHostAddress("fe80::1")) < 0);
        Vault vault(directory.path() + "/vault.json");
        vault.unlock("correct horse harbor battery");
        {
            SyncServer server(vault);
            check(server.start(0));
            auto origin = [&](const QString &address) { return QString("http://%1:%2").arg(address).arg(server.port()); };
            check(server.invite(origin("100.64.0.0")).value("url").toString() == origin("100.64.0.0"));
            check(server.invite(origin("100.127.255.255")).value("url").toString() == origin("100.127.255.255"));
            check(rejects([&] { server.invite(origin("100.63.255.255")); }));
            check(rejects([&] { server.invite(origin("100.128.0.0")); }));
        }
        QJsonObject host{{"name", "Test host"}, {"hostname", "127.0.0.1"}, {"port", 22}, {"username", "harbor"}, {"group", "Tests"}, {"authType", "password"}, {"password", "never plaintext"}, {"privateKey", ""}, {"passphrase", ""}, {"hostKey", ""}, {"notes", ""}};
        auto noAuth = host;
        noAuth["authType"] = "none";
        noAuth["password"] = "";
        check(validateHost(noAuth).isEmpty());
        noAuth["password"] = "unexpected";
        check(!validateHost(noAuth).isEmpty());
        noAuth["password"] = "";
        noAuth["privateKey"] = "unexpected";
        check(!validateHost(noAuth).isEmpty());
        noAuth["privateKey"] = "";
        noAuth["passphrase"] = "unexpected";
        check(!validateHost(noAuth).isEmpty());
        vault.upsert(host);
        check(vault.hosts().size() == 1 && vault.data().value("revision").toInt() == 2);
        QFile file(directory.path() + "/vault.json");
        check(file.open(QIODevice::ReadOnly));
        auto saved = file.readAll();
        check(!saved.contains("never plaintext") && !saved.contains("Test host"));
        check((file.permissions() & (QFileDevice::ReadGroup | QFileDevice::ReadOther | QFileDevice::WriteGroup | QFileDevice::WriteOther)) == 0);
        auto id = vault.hosts().first().toObject().value("id").toString();
        host = vault.hosts().first().toObject();
        host["port"] = 22.5;
        check(!validateHost(host).isEmpty());
        host["port"] = 22;
        host["hostname"] = "-oProxyCommand=evil";
        check(!validateHost(host).isEmpty());
        auto endpointEdit = vault.hosts().first().toObject();
        QByteArray wire("\0\0\0\13ssh-ed25519\0\0\0\40", 19);
        wire += publicKey;
        endpointEdit["hostKey"] = "ssh-ed25519 " + QString::fromLatin1(wire.toBase64());
        vault.upsert(endpointEdit);
        endpointEdit["port"] = 2222;
        vault.upsert(endpointEdit);
        check(vault.hosts().first().toObject().value("hostKey").toString().isEmpty());
        vault.lock();
        check(rejects([&] { vault.unlock("wrong master passphrase"); }));
        check(!vault.unlocked());
        vault.unlock("correct horse harbor battery");
        check(vault.hosts().size() == 1);
        vault.remove(id);
        check(vault.hosts().isEmpty() && vault.data().value("revision").toInt() == 5);
        vault.lock();
        vault.unlock("correct horse harbor battery");
        check(vault.hosts().isEmpty());
        std::cout << "Authenticated encryption, signature, injection, permissions and vault persistence checks passed\n";
        return 0;
    } catch (const std::exception &exception) { std::cerr << exception.what() << '\n'; return 1; }
}
