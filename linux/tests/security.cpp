#include "vault.h"
#include "sync.h"
#include "pairing_network.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QJsonDocument>
#include <openssl/evp.h>
#include <stdexcept>
#include <iostream>
static void check(bool ok) { if (!ok) throw std::runtime_error("Security check failed"); }
static bool rejects(auto action) { try { action(); return false; } catch (...) { return true; } }
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
