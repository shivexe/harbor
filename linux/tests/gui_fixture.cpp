#include "window.h"
#include "terminal.h"
#include <qtermwidget6/qtermwidget.h>
#include <QApplication>
#include <QTreeWidget>
#include <QPushButton>
#include <QTabWidget>
#include <QTemporaryDir>
#include <QFile>
#include <QJsonDocument>
#include <QTimer>
#include <QKeyEvent>
#include <QLabel>
#include <QDialog>
#include <QDialogButtonBox>
#include <QLineEdit>
#include <iostream>
int main(int argc, char **argv) {
    QApplication application(argc, argv);
    if (argc != 3) return 1;
    applyTheme(application);
    QTemporaryDir directory;
    Vault vault(directory.path() + "/vault.json");
    vault.unlock("disposable GUI test passphrase");
    QFile fixture(argv[1]);
    if (!fixture.open(QIODevice::ReadOnly)) return 1;
    const auto hosts = QJsonDocument::fromJson(fixture.readAll()).array();
    if (hosts.size() != 4 || !validatePrivateKey(hosts[1].toObject().value("privateKey").toString().toUtf8()).isEmpty() || !validatePrivateKey(hosts[2].toObject().value("privateKey").toString().toUtf8()).isEmpty()) return 1;
    for (const auto &host : hosts) vault.upsert(host.toObject());
    Window window(vault);
    window.show();
    auto tree = window.findChild<QTreeWidget *>();
    auto tabs = window.findChild<QTabWidget *>();
    QPushButton *connectButton = nullptr;
    for (auto button : window.findChildren<QPushButton *>()) if (button->text() == "Connect") connectButton = button;
    if (!connectButton || !tree || !tabs || hosts.size() != 4) return 1;
    QStringList outputs;
    outputs.resize(4);
    QList<QTermWidget *> terminals;
    for (int i = 0; i < 4; ++i) {
        tree->setCurrentItem(tree->topLevelItem(0)->child(i));
        connectButton->click();
        auto terminal = tabs->currentWidget()->findChild<QTermWidget *>();
        if (!terminal) return 1;
        terminals.append(terminal);
        QObject::connect(terminal, &QTermWidget::receivedData, &window, [&, i](const QString &data) { outputs[i] += data; });
    }
    auto wrong = hosts.last().toObject();
    wrong.remove("id");
    wrong["name"] = "Changed host key rejected";
    auto parts = wrong.value("hostKey").toString().toLatin1().split(' ');
    auto key = QByteArray::fromBase64(parts[1]);
    key[key.size() - 1] = key.back() ^ 1;
    wrong["hostKey"] = QString::fromLatin1(parts[0] + ' ' + key.toBase64());
    vault.upsert(wrong);
    tree->setCurrentItem(tree->topLevelItem(0)->child(4));
    connectButton->click();
    auto rejected = qobject_cast<Terminal *>(tabs->currentWidget());
    if (!rejected) return 1;
    QTimer::singleShot(2500, &window, [&] {
        window.resize(1060, 690);
        for (int i = 0; i < terminals.size(); ++i) {
            tabs->setCurrentIndex(i + 1);
            QString marker = QString("HARBOR_AUTH_%1_OK").arg(i);
            QString escaped;
            for (const auto character : marker.toLatin1()) escaped += QString("\\x%1").arg(static_cast<unsigned char>(character), 2, 16, QChar('0'));
            terminals[i]->sendText("printf '" + escaped + "\\n'; stty size; printf '\\033[34mUnicode terminal ✓\\033[0m\\n'\n");
        }
    });
    QTimer::singleShot(3500, &window, [&] {
        tabs->setCurrentIndex(1);
        terminals[0]->sendText("echo HARBOR_KEYBOARD_xOK");
        QKeyEvent left(QEvent::KeyPress, Qt::Key_Left, Qt::NoModifier);
        QKeyEvent backspace(QEvent::KeyPress, Qt::Key_Backspace, Qt::NoModifier);
        QKeyEvent enter(QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier);
        terminals[0]->sendKeyEvent(&left);
        terminals[0]->sendKeyEvent(&left);
        terminals[0]->sendKeyEvent(&backspace);
        terminals[0]->sendKeyEvent(&enter);
        tabs->setCurrentIndex(3);
        terminals[2]->sendText("vim -Nu NONE -n -i NONE\n");
    });
    QTimer::singleShot(4500, &window, [&] {
        terminals[2]->sendText("iHarbor fullscreen editor ✓");
        QKeyEvent escape(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
        terminals[2]->sendKeyEvent(&escape);
        terminals[2]->sendText(":q!\r");
    });
    QTimer::singleShot(6500, &window, [&] {
        bool passed = true;
        for (int i = 0; i < 4; ++i) {
            if (!outputs[i].contains(QString("HARBOR_AUTH_%1_OK").arg(i)) || outputs[i].contains("fixture-password") || outputs[i].contains("fixture-key-passphrase")) passed = false;
            terminals[i]->setSelectionStart(0, 0);
            terminals[i]->setSelectionEnd(terminals[i]->screenLinesCount() - 1, terminals[i]->screenColumnsCount() - 1);
            if (!terminals[i]->selectedText().contains("Unicode terminal ✓")) passed = false;
            terminals[i]->setSelectionStart(0, 0);
            terminals[i]->setSelectionEnd(0, 0);
            std::cout << "session " << i << " authenticated=" << outputs[i].contains(QString("HARBOR_AUTH_%1_OK").arg(i)) << " rows=" << terminals[i]->screenLinesCount() << " cols=" << terminals[i]->screenColumnsCount() << '\n';
        }
        if (!outputs[0].contains("HARBOR_KEYBOARD_OK\r") || !outputs[2].contains("?1049h") || !outputs[2].contains("?1049l")) passed = false;
        std::cout << "keyboard editing=" << outputs[0].contains("HARBOR_KEYBOARD_OK\r") << " fullscreen editor=" << (outputs[2].contains("?1049h") && outputs[2].contains("?1049l")) << '\n';
        auto reason = rejected->findChild<QLabel *>("connectionDetail");
        const bool wrongKeyRejected = reason && reason->text().contains("saved server key does not match") && !rejected->connected();
        if (!wrongKeyRejected) passed = false;
        std::cout << "changed-key rejected=" << wrongKeyRejected << '\n';
        const int sessionCount = tabs->count();
        tabs->setCurrentIndex(2);
        auto item = tree->topLevelItem(0)->child(1);
        tree->setCurrentItem(item);
        const bool differentHostShowsDetails = tabs->currentIndex() == 0 && tabs->count() == sessionCount;
        tabs->setCurrentIndex(2);
        tree->itemClicked(item, 0);
        const bool sameHostShowsDetails = tabs->currentIndex() == 0 && tabs->count() == sessionCount;
        if (!differentHostShowsDetails || !sameHostShowsDetails) passed = false;
        std::cout << "host selection keeps sessions=" << (differentHostShowsDetails && sameHostShowsDetails) << '\n';
        tabs->setCurrentIndex(3);
        if (passed) terminals[2]->sendText("clear; printf 'Harbor integration lab\\n\\nEncrypted private key authenticated.\\nPassword, key, and Tailscale-style no-auth sessions verified.\\nHost key changes refused before authentication.\\nANSI color and Unicode: ✓\\n\\n'; stty size\n");
        if (!passed) for (int i = 0; i < outputs.size(); ++i) std::cerr << "session " << i << ": " << outputs[i].toStdString() << '\n';
        QTimer::singleShot(500, &window, [&, passed] {
            window.grab().save(QString(argv[2]));
            if (!passed) { application.exit(1); return; }
            const int count = tabs->count();
            tabs->setCurrentIndex(1);
            terminals[0]->sendText("sh\n");
            QTimer::singleShot(400, &window, [&, count] {
                terminals[0]->sendText("exit\n");
                QTimer::singleShot(400, &window, [&, count] {
                    const bool subshellKeptTab = tabs->count() == count && terminals[0]->isVisible();
                    terminals[0]->sendText("exit\n");
                    QTimer::singleShot(900, &window, [&, count, subshellKeptTab] {
                        const bool remoteExitClosedTab = tabs->count() == count - 1;
                        std::cout << "subshell kept tab=" << subshellKeptTab << " remote exit closed tab=" << remoteExitClosedTab << '\n';
                        auto lock = window.findChild<QPushButton *>("lockButton");
                        if (!lock) { application.exit(1); return; }
                        QTimer::singleShot(80, &window, [&] {
                            auto dialog = window.findChild<QDialog *>("vaultDialog");
                            auto passphrase = dialog ? dialog->findChild<QLineEdit *>() : nullptr;
                            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
                            if (!passphrase || !buttons) { if (dialog) dialog->reject(); return; }
                            passphrase->setText("disposable GUI test passphrase");
                            buttons->button(QDialogButtonBox::Ok)->click();
                        });
                        lock->click();
                        const bool lockClosedSessions = tabs->count() == 1 && vault.unlocked();
                        std::cout << "lock closed sessions=" << lockClosedSessions << '\n';
                        application.exit(subshellKeptTab && remoteExitClosedTab && lockClosedSessions ? 0 : 1);
                    });
                });
            });
        });
    });
    return application.exec();
}
