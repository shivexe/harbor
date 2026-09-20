#include "window.h"
#include <QApplication>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFile>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QTemporaryDir>
#include <QTimer>
#include <QElapsedTimer>
#include <QThread>
#include <QToolButton>
#include <QTreeWidget>
#include <iostream>
#include <functional>
#include <stdexcept>

static void check(bool value, const char *message) { if (!value) throw std::runtime_error(message); }

static QByteArray readFile(const QString &path) {
    QFile file(path);
    check(file.open(QIODevice::ReadOnly), "Could not read encrypted key fixture");
    return file.readAll();
}

static void waitFor(const std::function<bool()> &condition, const char *message, int timeout = 12000) {
    QElapsedTimer timer;
    timer.start();
    while (!condition() && timer.elapsed() < timeout) {
        QApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(1);
    }
    check(condition(), message);
}

int main(int argc, char **argv) {
    QApplication application(argc, argv);
    if (argc != 2) return 1;
    try {
        const QDir fixtures(argv[1]);
        auto passphrase = readFile(fixtures.filePath("passphrase")).trimmed();
        const auto originalKey = readFile(fixtures.filePath("rsa-pkcs8-encrypted.pem"));
        const auto replacementKey = readFile(fixtures.filePath("ec-pkcs8-encrypted.pem"));
        const auto canceledKey = readFile(fixtures.filePath("openssh-encrypted"));
        QTemporaryDir directory;
        Vault vault(directory.filePath("vault.json"));
        vault.unlock("encrypted editor fixture passphrase");
        vault.upsert({{"name", "Encrypted editor"}, {"hostname", "127.0.0.1"}, {"port", 22}, {"username", "harbor"}, {"group", "Tests"}, {"authType", "key"}, {"password", ""}, {"privateKey", QString::fromUtf8(originalKey)}, {"passphrase", QString::fromUtf8(passphrase)}, {"hostKey", ""}, {"notes", ""}});
        Window window(vault);
        window.show();
        auto tree = window.findChild<QTreeWidget *>();
        check(tree && tree->topLevelItemCount() == 1 && tree->topLevelItem(0)->childCount() == 1, "Missing encrypted fixture host");
        tree->setCurrentItem(tree->topLevelItem(0)->child(0));
        auto actions = window.findChild<QToolButton *>("hostActions");
        check(actions && actions->menu() && !actions->menu()->actions().isEmpty(), "Missing host editor action");
        bool interactionPassed = false;
        QTimer::singleShot(50, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto paste = dialog ? dialog->findChild<QPushButton *>("pastePrivateKey") : nullptr;
            auto passphraseField = dialog ? dialog->findChild<QLineEdit *>("keyPassphrase") : nullptr;
            auto state = dialog ? dialog->findChild<QLabel *>("privateKeyState") : nullptr;
            auto message = dialog ? dialog->findChild<QLabel *>("hostEditorMessage") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            check(dialog && paste && passphraseField && state && message && buttons, "Missing encrypted key editor controls");
            check(passphraseField->text().toUtf8() == passphrase && state->text().contains("saved"), "Saved encrypted credentials did not load");
            QTimer::singleShot(30, dialog, [&] {
                auto pasteDialog = dialog->findChild<QDialog *>("pasteKeyDialog");
                auto editor = pasteDialog ? pasteDialog->findChild<QPlainTextEdit *>("privateKeyPasteText") : nullptr;
                auto pasteButtons = pasteDialog ? pasteDialog->findChild<QDialogButtonBox *>() : nullptr;
                check(editor && pasteButtons, "Missing private key paste controls");
                editor->setPlainText(QString::fromUtf8(replacementKey));
                pasteButtons->button(QDialogButtonBox::Save)->click();
            });
            paste->click();
            check(passphraseField->text().isEmpty() && state->text().contains("ready"), "Replacing a key retained its old passphrase");
            buttons->button(QDialogButtonBox::Save)->click();
            check(state->text().contains("Validating") && !buttons->button(QDialogButtonBox::Save)->isEnabled(), "Save did not enter a single validating state");
            waitFor([&] { return buttons->button(QDialogButtonBox::Save)->isEnabled(); }, "Missing-passphrase validation did not finish");
            check(dialog->isVisible() && message->text().contains("Enter the passphrase") && vault.hosts().first().toObject().value("privateKey").toString().toUtf8() == originalKey, "Missing passphrase replaced the saved draft");
            passphraseField->setText("incorrect fixture passphrase");
            buttons->button(QDialogButtonBox::Save)->click();
            waitFor([&] { return buttons->button(QDialogButtonBox::Save)->isEnabled(); }, "Wrong-passphrase validation did not finish");
            check(dialog->isVisible() && message->text().contains("incorrect") && state->text().contains("ready") && vault.hosts().first().toObject().value("privateKey").toString().toUtf8() == originalKey, "Wrong passphrase replaced the saved draft");
            QTimer::singleShot(30, dialog, [&] {
                auto pasteDialog = dialog->findChild<QDialog *>("pasteKeyDialog");
                auto editor = pasteDialog ? pasteDialog->findChild<QPlainTextEdit *>("privateKeyPasteText") : nullptr;
                auto pasteMessage = pasteDialog ? pasteDialog->findChild<QLabel *>("privateKeyPasteMessage") : nullptr;
                auto pasteButtons = pasteDialog ? pasteDialog->findChild<QDialogButtonBox *>() : nullptr;
                check(editor && pasteMessage && pasteButtons, "Missing retryable paste controls");
                editor->setPlainText("-----BEGIN ENCRYPTED PRIVATE KEY-----\ncorrupted\n-----END ENCRYPTED PRIVATE KEY-----");
                pasteButtons->button(QDialogButtonBox::Save)->click();
                check(pasteDialog->isVisible() && pasteMessage->isVisible(), "Corrupted replacement closed the paste dialog");
                pasteButtons->button(QDialogButtonBox::Cancel)->click();
            });
            paste->click();
            check(state->text().contains("ready") && passphraseField->text() == "incorrect fixture passphrase", "Canceled paste changed the current draft");
            passphraseField->setText(QString::fromUtf8(passphrase));
            buttons->button(QDialogButtonBox::Save)->click();
            waitFor([&] { return !dialog->isVisible(); }, "Correct-passphrase validation did not save");
            interactionPassed = true;
        });
        actions->menu()->actions().first()->trigger();
        check(interactionPassed, "Encrypted editor interaction did not finish");
        auto saved = vault.hosts().first().toObject();
        check(saved.value("privateKey").toString().toUtf8() == replacementKey && saved.value("passphrase").toString().toUtf8() == passphrase, "Correct passphrase did not save the encrypted draft");
        QTimer::singleShot(50, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto paste = dialog ? dialog->findChild<QPushButton *>("pastePrivateKey") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            check(dialog && paste && buttons, "Missing cancel test controls");
            QTimer::singleShot(30, dialog, [&] {
                auto pasteDialog = dialog->findChild<QDialog *>("pasteKeyDialog");
                auto editor = pasteDialog ? pasteDialog->findChild<QPlainTextEdit *>("privateKeyPasteText") : nullptr;
                auto pasteButtons = pasteDialog ? pasteDialog->findChild<QDialogButtonBox *>() : nullptr;
                check(editor && pasteButtons, "Missing cancel test paste controls");
                editor->setPlainText(QString::fromUtf8(canceledKey));
                pasteButtons->button(QDialogButtonBox::Save)->click();
            });
            paste->click();
            buttons->button(QDialogButtonBox::Cancel)->click();
        });
        actions->menu()->actions().first()->trigger();
        saved = vault.hosts().first().toObject();
        check(saved.value("privateKey").toString().toUtf8() == replacementKey && saved.value("passphrase").toString().toUtf8() == passphrase, "Cancel changed saved encrypted credentials");
        QTimer::singleShot(50, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto state = dialog ? dialog->findChild<QLabel *>("privateKeyState") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            check(dialog && state && buttons, "Missing validation cancel controls");
            buttons->button(QDialogButtonBox::Save)->click();
            check(state->text().contains("Validating") && !buttons->button(QDialogButtonBox::Save)->isEnabled(), "Validation did not disable duplicate saves");
            buttons->button(QDialogButtonBox::Cancel)->click();
        });
        actions->menu()->actions().first()->trigger();
        waitFor([&] { return vault.hosts().first().toObject().value("privateKey").toString().toUtf8() == replacementKey; }, "Canceled validation changed saved credentials", 1000);
        QTimer::singleShot(50, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            check(dialog && buttons, "Missing validation lock controls");
            buttons->button(QDialogButtonBox::Save)->click();
            vault.lock();
        });
        actions->menu()->actions().first()->trigger();
        check(!vault.unlocked(), "Lock during validation was ignored");
        vault.unlock("encrypted editor fixture passphrase");
        saved = vault.hosts().first().toObject();
        check(saved.value("privateKey").toString().toUtf8() == replacementKey && saved.value("passphrase").toString().toUtf8() == passphrase, "Lock during validation changed saved credentials");
        vault.lock();
        vault.unlock("encrypted editor fixture passphrase");
        saved = vault.hosts().first().toObject();
        check(saved.value("privateKey").toString().toUtf8() == replacementKey && saved.value("passphrase").toString().toUtf8() == passphrase, "Encrypted credentials changed after vault reload");
        wipe(passphrase);
        std::cout << "Encrypted key editor retry, cancel and reload checks passed\n";
        return 0;
    } catch (const std::exception &exception) { std::cerr << exception.what() << '\n'; return 1; }
}
