#include "vault.h"
#include "sync.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QSaveFile>
#include <QJsonDocument>
#include <QSocketNotifier>
#include <QTcpSocket>
#include <iostream>
#include <unistd.h>
int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    if (argc < 3) { std::cerr << "Usage: harbor-sync-fixture host-fixture.json invitation.json [port]\n"; return 1; }
    QTemporaryDir directory;
    Vault vault(directory.path() + "/vault.json");
    try {
        vault.unlock("disposable fixture passphrase");
        QFile hosts(argv[1]);
        if (!hosts.open(QIODevice::ReadOnly)) return 1;
        auto document = QJsonDocument::fromJson(hosts.readAll());
        if (document.isObject()) vault.upsert(document.object());
        else for (const auto &host : document.array()) vault.upsert(host.toObject());
        SyncServer server(vault);
        if (!server.start(argc > 3 ? QString(argv[3]).toUShort() : 0)) return 1;
        auto writeInvite = [&] {
            QSaveFile output(argv[2]);
            if (!output.open(QIODevice::WriteOnly) || !output.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)) throw std::runtime_error("Cannot write invitation");
            output.write(QJsonDocument(server.invite("http://127.0.0.1:" + QString::number(server.port()))).toJson(QJsonDocument::Compact));
            if (!output.commit()) throw std::runtime_error("Cannot save invitation");
        };
        writeInvite();
        QObject::connect(&server, &SyncServer::pairingRequested, &application, [&](const QString &id, const QString &, const QString &) { server.approve(id); std::cout << "paired " << id.toStdString() << std::endl; });
        QSocketNotifier input(STDIN_FILENO, QSocketNotifier::Read, &application);
        QByteArray pending;
        QObject::connect(&input, &QSocketNotifier::activated, &application, [&] {
            char bytes[16384];
            const auto count = ::read(STDIN_FILENO, bytes, sizeof(bytes));
            if (count <= 0) { input.setEnabled(false); return; }
            pending.append(bytes, count);
            while (pending.contains('\n')) {
                const auto end = pending.indexOf('\n');
                const auto command = QJsonDocument::fromJson(pending.left(end)).object();
                pending.remove(0, end + 1);
                const auto op = command.value("op").toString();
                if (op == "stats") {
                    int active = 0;
                    for (auto socket : server.findChildren<QTcpSocket *>()) if (socket->state() != QAbstractSocket::UnconnectedState) ++active;
                    std::cout << "active " << active << std::endl;
                }
                else if (op == "invite") writeInvite();
                else if (op == "remove") vault.remove(command.value("id").toString());
                else if (op == "upsert") vault.upsert(command.value("host").toObject());
                else if (op == "revoke") server.revoke(command.value("id").toString());
                else if (op == "lock") { server.stop(); vault.lock(); }
                else if (op == "quit") application.quit();
                std::cout << "ok " << op.toStdString() << std::endl;
            }
        });
        std::cout << "ready " << server.port() << std::endl;
        return application.exec();
    } catch (const std::exception &exception) { std::cerr << exception.what() << std::endl; return 1; }
}
