#include "window.h"
#include "terminal.h"
#include <QApplication>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QTreeWidget>
#include <QTreeWidgetItemIterator>
#include <QTabWidget>
#include <QStackedWidget>
#include <QScrollArea>
#include <QScrollBar>
#include <QPushButton>
#include <QLabel>
#include <QLineEdit>
#include <QDialog>
#include <QDialogButtonBox>
#include <QEventLoop>
#include <QTimer>
#include <QCryptographicHash>
#include <functional>
#include <iostream>
#include <stdexcept>

static void check(bool value, const char *message) { if (!value) throw std::runtime_error(message); }

static QJsonObject readHost(const QString &path) {
    QFile file(path);
    check(file.open(QIODevice::ReadOnly), "Could not read SSH fixture");
    return QJsonDocument::fromJson(file.readAll()).object();
}

static bool waitFor(const std::function<bool()> &condition, int milliseconds = 8000) {
    if (condition()) return true;
    QEventLoop loop;
    QTimer poll;
    QTimer deadline;
    deadline.setSingleShot(true);
    QObject::connect(&poll, &QTimer::timeout, &loop, [&] { if (condition()) loop.quit(); });
    QObject::connect(&deadline, &QTimer::timeout, &loop, &QEventLoop::quit);
    poll.start(20);
    deadline.start(milliseconds);
    loop.exec();
    return condition();
}

int main(int argc, char **argv) {
    QApplication application(argc, argv);
    if (argc != 5 && argc != 6) return 1;
    applyTheme(application);
    try {
        QDir output(argv[4]);
        check(output.exists() || QDir().mkpath(output.path()), "Could not create screenshot directory");
        QTemporaryDir directory;
        Vault vault(directory.path() + "/vault.json");
        vault.unlock("disposable connection test passphrase");
        const auto base = readHost(argv[1]);
        auto add = [&](QJsonObject host, const QString &name, bool verified = false) {
            host.remove("id");
            host["name"] = name;
            vault.upsert(host, verified);
            return vault.hosts().last().toObject().value("id").toString();
        };
        const auto successId = add(base, "Ready server");
        auto wrong = base;
        auto parts = wrong.value("hostKey").toString().toLatin1().split(' ');
        auto wire = QByteArray::fromBase64(parts[1]);
        wire[wire.size() - 1] = wire.back() ^ 1;
        wrong["hostKey"] = QString::fromLatin1(parts[0] + ' ' + wire.toBase64());
        const auto wrongId = add(wrong, "Changed server key");
        auto refused = base;
        refused["port"] = 1;
        const auto refusedId = add(refused, "Refused SSH port", true);
        auto bad = base;
        bad["username"] = "wronguser";
        const auto badId = add(bad, "Rejected sign in");
        auto untrusted = base;
        untrusted["hostKey"] = "";
        const auto untrustedId = add(untrusted, "First server key");
        const auto delayedId = add(readHost(argv[2]), "Check mode banner");
        const auto rejectId = add(readHost(argv[3]), "Shell denied");
        const auto dropId = argc == 6 ? add(readHost(argv[5]), "Interrupted connection") : QString();
        Window window(vault);
        window.show();
        auto tree = window.findChild<QTreeWidget *>();
        auto tabs = window.findChild<QTabWidget *>();
        QPushButton *connectButton = nullptr;
        for (auto button : window.findChildren<QPushButton *>()) if (button->text() == "Connect") connectButton = button;
        check(tree && tabs && connectButton, "Missing connection controls");
        auto open = [&](const QString &id) {
            QTreeWidgetItem *item = nullptr;
            for (QTreeWidgetItemIterator it(tree); *it; ++it) if ((*it)->data(0, Qt::UserRole).toString() == id) { item = *it; break; }
            check(item, "Missing saved host item");
            tree->setCurrentItem(item);
            connectButton->click();
            auto session = qobject_cast<Terminal *>(tabs->currentWidget());
            check(session, "Missing connection tab");
            auto pages = session->findChild<QStackedWidget *>();
            check(pages && pages->currentIndex() == 0 && !session->connected(), "Terminal appeared before shell acceptance");
            return session;
        };
        auto reason = [](Terminal *session) { auto label = session->findChild<QLabel *>("connectionDetail"); return label ? label->text() : QString(); };
        auto save = [&](const QString &name) { application.processEvents(); check(window.grab().save(output.filePath(name)), "Could not save connection screenshot"); };
        auto success = open(successId);
        check(waitFor([&] { return success->connected(); }), "Real no-password shell did not open");
        check(success->findChild<QStackedWidget *>()->currentIndex() == 1, "Ready shell stayed hidden");
        auto changed = open(wrongId);
        check(waitFor([&] { return reason(changed).contains("saved server key does not match"); }), "Changed key was not explained");
        check(!changed->connected() && changed->findChild<QStackedWidget *>()->currentIndex() == 0, "Changed key exposed terminal");
        save("linux-1.2.0-failure.png");
        auto deniedPort = open(refusedId);
        check(waitFor([&] { return reason(deniedPort).contains("refused SSH on this port"); }), "Refused port was not explained");
        auto deniedAuth = open(badId);
        check(waitFor([&] { return reason(deniedAuth).contains("rejected the sign-in details"); }), "Authentication failure was not explained");
        auto edit = deniedAuth->findChild<QPushButton *>("editConnection");
        auto retry = deniedAuth->findChild<QPushButton *>("retryConnection");
        check(edit && retry, "Failure recovery controls missing");
        QTimer::singleShot(30, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto username = dialog ? dialog->findChild<QLineEdit *>("hostUsername") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            if (!username || !buttons) { if (dialog) dialog->reject(); return; }
            username->setText("noauth");
            buttons->button(QDialogButtonBox::Save)->click();
        });
        edit->click();
        check(vault.hosts().size() == (argc == 6 ? 8 : 7), "Edit lost a host");
        check([&] { for (const auto &entry : vault.hosts()) if (entry.toObject().value("id") == badId) return entry.toObject().value("username") == "noauth"; return false; }(), "Edit did not save updated username");
        retry->click();
        auto retried = qobject_cast<Terminal *>(tabs->currentWidget());
        check(retried && retried != deniedAuth && waitFor([&] { return retried->connected(); }), "Retry did not use edited host");
        auto shellDenied = open(rejectId);
        check(waitFor([&] { return reason(shellDenied).contains("did not open a shell"); }), "Rejected shell was not explained");
        window.resize(780, 520);
        auto first = open(untrustedId);
        auto trust = first->findChild<QPushButton *>("trustServerKey");
        check(waitFor([&] { return trust && trust->isVisible(); }), "First server key was not offered for approval");
        auto fingerprint = first->findChild<QLabel *>("connectionFingerprint");
        auto scroll = first->findChild<QScrollArea *>();
        check(fingerprint && fingerprint->text().contains("SHA256:") && scroll && scroll->widget()->width() <= scroll->viewport()->width(), "Compact fingerprint panel clipped");
        save("linux-1.2.0-trust.png");
        trust->click();
        check(waitFor([&] { return first->connected(); }), "Approved first key did not open a shell");
        check([&] { for (const auto &entry : vault.hosts()) if (entry.toObject().value("id") == untrustedId) return !entry.toObject().value("hostKey").toString().isEmpty(); return false; }(), "Approved server key was not saved");
        window.resize(1160, 760);
        auto delayed = open(delayedId);
        auto message = delayed->findChild<QLabel *>("connectionServerMessage");
        check(waitFor([&] { return message && message->text().contains("https://login.tailscale.com/a/harbor-fixture"); }), "Pre-auth server sign-in URL was hidden");
        check(message->text().contains("shell request accepted") && !delayed->connected() && delayed->findChild<QStackedWidget *>()->currentIndex() == 0, "Spoofed banner advanced trusted progress");
        save("linux-1.2.0-progress.png");
        check(waitFor([&] { return delayed->connected(); }), "Delayed real shell did not open");
        const auto before = tabs->count();
        auto canceled = open(successId);
        auto cancel = canceled->findChild<QPushButton *>("cancelConnection");
        check(cancel && cancel->isVisible(), "Active attempt has no Cancel control");
        cancel->click();
        check(tabs->count() == before, "Cancel left a connection tab");
        QEventLoop settle;
        QTimer::singleShot(400, &settle, &QEventLoop::quit);
        settle.exec();
        check(tabs->count() == before, "Canceled attempt reappeared");
        if (!dropId.isEmpty()) {
            auto dropped = open(dropId);
            check(waitFor([&] { return dropped->connected(); }), "Abrupt transport fixture did not open a shell");
            check(waitFor([&] { return reason(dropped).contains("ended unexpectedly"); }, 9000), "Abrupt disconnect did not show recovery");
            check(!dropped->connected() && tabs->indexOf(dropped) >= 0 && dropped->findChild<QPushButton *>("retryConnection")->isVisible(), "Abrupt disconnect lost its recovery tab");
            save("linux-1.2.0-disconnect.png");
        }
        std::cout << "ready/refused/auth/key/shell/trust/banner/cancel/retry passed\n";
        return 0;
    } catch (const std::exception &exception) { std::cerr << exception.what() << '\n'; return 1; }
}
