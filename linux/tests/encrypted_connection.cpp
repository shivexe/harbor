#include "terminal.h"
#include "vault.h"
#include <QApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QJsonDocument>
#include <QTimer>
#include <iostream>
#include <stdexcept>

static void check(bool value, const char *message) { if (!value) throw std::runtime_error(message); }

static QByteArray readFile(const QString &path) {
    QFile file(path);
    check(file.open(QIODevice::ReadOnly), "Could not read encrypted SSH fixture");
    return file.readAll();
}

int main(int argc, char **argv) {
    QApplication application(argc, argv);
    if (argc != 3) return 1;
    try {
        const QDir fixtures(argv[1]);
        auto passphrase = readFile(fixtures.filePath("passphrase")).trimmed();
        const auto server = QJsonDocument::fromJson(readFile(argv[2])).array().first().toObject();
        for (const auto &name : {"rsa-pkcs8-encrypted.pem", "ec-pkcs8-encrypted.pem", "ed25519-pkcs8-encrypted.pem", "rsa-traditional-encrypted.pem", "ec-traditional-encrypted.pem", "openssh-encrypted"}) {
            auto host = server;
            host["name"] = "Encrypted connection fixture";
            host["username"] = "harbor";
            host["authType"] = "key";
            host["password"] = "";
            host["privateKey"] = QString::fromUtf8(readFile(fixtures.filePath(name)));
            host["passphrase"] = QString::fromUtf8(passphrase);
            Terminal terminal(host);
            terminal.resize(900, 600);
            terminal.show();
            QEventLoop wait;
            QTimer deadline;
            deadline.setSingleShot(true);
            QObject::connect(&terminal, &Terminal::ready, &wait, &QEventLoop::quit);
            QObject::connect(&terminal, &Terminal::failed, &wait, &QEventLoop::quit);
            QObject::connect(&deadline, &QTimer::timeout, &wait, &QEventLoop::quit);
            deadline.start(15000);
            terminal.start();
            wait.exec();
            check(terminal.connected(), "Encrypted key did not authenticate to the real SSH listener");
            terminal.cancel();
        }
        wipe(passphrase);
        std::cout << "Real SSH authentication passed for six encrypted key envelopes\n";
        return 0;
    } catch (const std::exception &exception) { std::cerr << exception.what() << '\n'; return 1; }
}
