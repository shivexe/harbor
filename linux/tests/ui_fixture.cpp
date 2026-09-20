#include "window.h"
#include <QApplication>
#include <QTemporaryDir>
#include <QDir>
#include <QTimer>
#include <QDialog>
#include <QDialogButtonBox>
#include <QScrollArea>
#include <QScrollBar>
#include <QTreeWidget>
#include <QLineEdit>
#include <QComboBox>
#include <QPushButton>
#include <QLabel>
#include <QToolButton>
#include <QMenu>
#include <QSpinBox>
#include <QStackedWidget>
#include <QPlainTextEdit>
#include <QFileDialog>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QClipboard>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkProxy>
#include <QEventLoop>
#include <QMessageBox>
#include <iostream>

int main(int argc, char **argv) {
    QApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
    QApplication application(argc, argv);
    if (argc != 2) return 1;
    applyTheme(application);
    QDir output(argv[1]);
    if (!output.exists() && !QDir().mkpath(output.path())) return 1;
    QTemporaryDir directory;
    const auto keyPath = directory.filePath("editor-key");
    QProcess keygen;
    keygen.setProgram("ssh-keygen");
    keygen.setArguments({"-q", "-t", "ed25519", "-N", "", "-f", keyPath});
    keygen.setStandardOutputFile(QProcess::nullDevice());
    keygen.setStandardErrorFile(QProcess::nullDevice());
    keygen.start();
    if (!keygen.waitForFinished(10000) || keygen.exitCode() != 0) return 1;
    QFile keyFile(keyPath);
    if (!keyFile.open(QIODevice::ReadOnly)) return 1;
    const auto keyData = keyFile.readAll();
    QFile publicFile(keyPath + ".pub");
    if (!publicFile.open(QIODevice::ReadOnly)) return 1;
    const auto publicData = publicFile.readAll();
    Vault vault(directory.path() + "/vault.json");
    vault.unlock("disposable UI test passphrase");
    Window window(vault);
    window.show();
    QNetworkAccessManager network(&window);
    network.setProxy(QNetworkProxy::NoProxy);
    int result = 0;
    auto save = [&](QWidget *widget, const QString &name) {
        QEventLoop settle;
        QTimer::singleShot(80, &settle, &QEventLoop::quit);
        settle.exec();
        application.processEvents();
        if (!widget->grab().save(output.filePath(name))) result = 1;
    };
    QTimer::singleShot(300, &window, [&] {
        save(&window, "linux-1.2.0-empty.png");
        auto add = window.findChild<QPushButton *>("emptyAddHost");
        if (!add) { application.exit(1); return; }
        QTimer::singleShot(100, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            if (!dialog) { result = 1; return; }
            save(dialog, "linux-1.2.0-editor.png");
            auto scroll = dialog->findChild<QScrollArea *>();
            if (!scroll || scroll->horizontalScrollBar()->maximum() != 0 || scroll->widget()->width() > scroll->viewport()->width()) result = 1;
            dialog->resize(500, 480);
            application.processEvents();
            if (!scroll || scroll->verticalScrollBar()->maximum() == 0) result = 1;
            auto more = dialog->findChild<QToolButton *>("moreHostOptions");
            if (!more) result = 1;
            else {
                more->click();
                application.processEvents();
                if (scroll->horizontalScrollBar()->maximum() != 0 || scroll->widget()->width() > scroll->viewport()->width() || scroll->verticalScrollBar()->maximum() == 0) result = 1;
                save(dialog, "linux-1.2.0-editor-small-more.png");
                scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
                save(dialog, "linux-1.2.0-editor-small-more-bottom.png");
                scroll->verticalScrollBar()->setValue(0);
                more->click();
            }
            save(dialog, "linux-1.2.0-editor-small.png");
            auto address = dialog->findChild<QLineEdit *>("hostAddress");
            auto username = dialog->findChild<QLineEdit *>("hostUsername");
            auto password = dialog->findChild<QLineEdit *>("hostPassword");
            auto auth = dialog->findChild<QComboBox *>("hostAuthentication");
            auto buttons = dialog->findChild<QDialogButtonBox *>();
            if (!address || !username || !password || !auth || !buttons || auth->currentData() != "none" || password->isVisible()) { result = 1; dialog->reject(); return; }
            address->setText("example.net");
            username->setText("deploy");
            buttons->button(QDialogButtonBox::Save)->click();
        });
        add->click();
        auto tree = window.findChild<QTreeWidget *>();
        auto title = window.findChild<QLabel *>("hostTitle");
        if (vault.hosts().size() != 1) { application.exit(1); return; }
        auto saved = vault.hosts().first().toObject();
        if (!tree || !tree->currentItem() || !title || title->text() != "example.net" || saved.value("authType") != "none" || !saved.value("password").toString().isEmpty()) result = 1;
        auto actions = window.findChild<QToolButton *>("hostActions");
        if (!actions || !actions->menu() || actions->menu()->actions().size() != 2) { application.exit(1); return; }
        QTimer::singleShot(100, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto auth = dialog ? dialog->findChild<QComboBox *>("hostAuthentication") : nullptr;
            auto password = dialog ? dialog->findChild<QLineEdit *>("hostPassword") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            if (!dialog || !auth || !password || !buttons) { result = 1; if (dialog) dialog->reject(); return; }
            auth->setCurrentIndex(0);
            password->setText("disposable-password");
            buttons->button(QDialogButtonBox::Save)->click();
        });
        actions->menu()->actions().first()->trigger();
        saved = vault.hosts().first().toObject();
        if (saved.value("authType") != "password" || saved.value("password") != "disposable-password") result = 1;
        QTimer::singleShot(100, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto auth = dialog ? dialog->findChild<QComboBox *>("hostAuthentication") : nullptr;
            auto password = dialog ? dialog->findChild<QLineEdit *>("hostPassword") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            if (!dialog || !auth || !password || !buttons) { result = 1; if (dialog) dialog->reject(); return; }
            auth->setCurrentIndex(2);
            if (password->isVisible()) result = 1;
            buttons->button(QDialogButtonBox::Save)->click();
        });
        actions->menu()->actions().first()->trigger();
        saved = vault.hosts().first().toObject();
        if (saved.value("authType") != "none" || !saved.value("password").toString().isEmpty() || !saved.value("privateKey").toString().isEmpty() || !saved.value("passphrase").toString().isEmpty()) result = 1;
        window.resize(1160, 760);
        save(&window, "linux-1.2.0-host.png");
        QTimer::singleShot(100, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto more = dialog ? dialog->findChild<QToolButton *>("moreHostOptions") : nullptr;
            auto name = dialog ? dialog->findChild<QLineEdit *>("hostDisplayName") : nullptr;
            auto group = dialog ? dialog->findChild<QLineEdit *>("hostGroup") : nullptr;
            auto notes = dialog ? dialog->findChild<QPlainTextEdit *>("hostEditorNotes") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            if (!more || !name || !group || !notes || !buttons) { result = 1; if (dialog) dialog->reject(); return; }
            more->click();
            name->setText("Airtel gateway");
            group->setText("Home lab");
            notes->setPlainText("<b>literal notes</b>");
            more->click();
            more->click();
            if (name->text() != "Airtel gateway" || group->text() != "Home lab" || notes->toPlainText() != "<b>literal notes</b>") result = 1;
            buttons->button(QDialogButtonBox::Save)->click();
        });
        actions->menu()->actions().first()->trigger();
        saved = vault.hosts().first().toObject();
        auto notesLabel = window.findChild<QLabel *>("hostNotes");
        if (saved.value("name") != "Airtel gateway" || saved.value("group") != "Home lab" || saved.value("notes") != "<b>literal notes</b>" || !notesLabel || notesLabel->textFormat() != Qt::PlainText || notesLabel->text() != "<b>literal notes</b>") result = 1;
        auto search = window.findChild<QLineEdit *>();
        if (!search) result = 1;
        else {
            search->setText("no-matching-host");
            if (tree->currentItem() || tree->topLevelItemCount() != 0) result = 1;
            search->clear();
            if (tree->topLevelItemCount() != 1 || tree->topLevelItem(0)->childCount() != 1) result = 1;
            else tree->setCurrentItem(tree->topLevelItem(0)->child(0));
            if (title->text() != "Airtel gateway") result = 1;
        }
        auto extra = saved;
        extra.remove("id");
        extra["name"] = "Staging server";
        extra["group"] = "Production";
        vault.upsert(extra);
        const auto stagingId = vault.hosts().last().toObject().value("id").toString();
        extra["name"] = "Metrics node";
        vault.upsert(extra);
        const auto metricsId = vault.hosts().last().toObject().value("id").toString();
        extra["name"] = "Backup server";
        extra["group"] = "Home lab";
        vault.upsert(extra);
        const auto backupId = vault.hosts().last().toObject().value("id").toString();
        save(&window, "linux-1.2.0-grouped.png");
        vault.remove(stagingId);
        vault.remove(metricsId);
        vault.remove(backupId);
        QTimer::singleShot(100, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto auth = dialog ? dialog->findChild<QComboBox *>("hostAuthentication") : nullptr;
            auto pasteButton = dialog ? dialog->findChild<QPushButton *>("pastePrivateKey") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            if (!auth || !pasteButton || !buttons) { result = 1; if (dialog) dialog->reject(); return; }
            auth->setCurrentIndex(1);
            save(dialog, "linux-1.2.0-key-editor.png");
            QTimer::singleShot(80, dialog, [&] {
                auto paste = dialog->findChild<QDialog *>("pasteKeyDialog");
                auto editor = paste ? paste->findChild<QPlainTextEdit *>("privateKeyPasteText") : nullptr;
                auto pasteButtons = paste ? paste->findChild<QDialogButtonBox *>() : nullptr;
                if (!paste || !editor || !pasteButtons) { result = 1; if (paste) paste->reject(); return; }
                save(paste, "linux-1.2.0-key-paste.png");
                editor->setPlainText(QString::fromUtf8(publicData));
                pasteButtons->button(QDialogButtonBox::Save)->click();
                auto pasteMessage = paste->findChild<QLabel *>("privateKeyPasteMessage");
                if (!paste->isVisible() || !pasteMessage || !pasteMessage->isVisible() || !pasteMessage->text().contains("not a public key")) result = 1;
                auto windowsKey = keyData;
                windowsKey.replace("\n", "\r\n");
                editor->setPlainText(QString::fromUtf8(windowsKey));
                pasteButtons->button(QDialogButtonBox::Save)->click();
            });
            pasteButton->click();
            if (dialog->findChild<QLabel *>("privateKeyState")->text() != "Private key ready to save in encrypted workspace") result = 1;
            buttons->button(QDialogButtonBox::Save)->click();
        });
        actions->menu()->actions().first()->trigger();
        saved = vault.hosts().first().toObject();
        if (saved.value("authType") != "key" || saved.value("privateKey").toString().toUtf8().trimmed() != keyData.trimmed()) result = 1;
        QTimer::singleShot(100, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            auto import = dialog ? dialog->findChild<QPushButton *>("importPrivateKey") : nullptr;
            auto pasteButton = dialog ? dialog->findChild<QPushButton *>("pastePrivateKey") : nullptr;
            auto keyState = dialog ? dialog->findChild<QLabel *>("privateKeyState") : nullptr;
            auto buttons = dialog ? dialog->findChild<QDialogButtonBox *>() : nullptr;
            if (!import || !pasteButton || !keyState || !buttons || !keyState->text().contains("saved")) { result = 1; if (dialog) dialog->reject(); return; }
            QTimer::singleShot(80, dialog, [&] {
                auto paste = dialog->findChild<QDialog *>("pasteKeyDialog");
                auto editor = paste ? paste->findChild<QPlainTextEdit *>("privateKeyPasteText") : nullptr;
                auto pasteButtons = paste ? paste->findChild<QDialogButtonBox *>() : nullptr;
                if (!paste || !editor || !pasteButtons) { result = 1; if (paste) paste->reject(); return; }
                editor->setPlainText("-----BEGIN OPENSSH PRIVATE KEY-----\ntruncated");
                pasteButtons->button(QDialogButtonBox::Save)->click();
                if (!paste->isVisible()) result = 1;
                pasteButtons->button(QDialogButtonBox::Cancel)->click();
            });
            pasteButton->click();
            if (!keyState->text().contains("saved")) result = 1;
            QTimer::singleShot(80, dialog, [&] {
                auto chooser = qobject_cast<QFileDialog *>(QApplication::activeModalWidget());
                if (!chooser) { result = 1; if (auto modal = QApplication::activeModalWidget()) modal->close(); return; }
                chooser->setDirectory(QFileInfo(keyPath).absolutePath());
                QTimer::singleShot(200, chooser, [chooser, keyPath] {
                    auto filename = chooser->findChild<QLineEdit *>("fileNameEdit");
                    if (filename) filename->setText(keyPath);
                });
                QTimer::singleShot(400, chooser, [chooser] {
                    static_cast<QDialog *>(chooser)->accept();
                });
                QTimer::singleShot(1200, chooser, [&, chooser] { if (chooser->isVisible()) { result = 1; chooser->reject(); } });
            });
            import->click();
            if (!keyState->text().contains("ready")) result = 1;
            buttons->button(QDialogButtonBox::Save)->click();
        });
        actions->menu()->actions().first()->trigger();
        saved = vault.hosts().first().toObject();
        if (saved.value("authType") != "key" || saved.value("privateKey").toString().toUtf8().trimmed() != keyData.trimmed()) result = 1;
        auto devices = window.findChild<QPushButton *>("devicesButton");
        if (!devices) { application.exit(1); return; }
        QTimer::singleShot(0, &window, [&] {
            auto dialog = window.findChild<QDialog *>("devicesDialog");
            if (!dialog) { result = 1; return; }
            save(dialog, "linux-1.2.0-devices.png");
            dialog->reject();
        });
        devices->click();
        QTimer::singleShot(0, &window, [&] {
            auto dialog = window.findChild<QDialog *>("devicesDialog");
            auto pair = dialog ? dialog->findChild<QPushButton *>("pairAndroid") : nullptr;
            if (!pair) { result = 1; if (dialog) dialog->reject(); return; }
            pair->click();
        });
        devices->click();
        QTimer::singleShot(400, &window, [&, title] {
            auto dialog = window.findChild<QDialog *>("pairingDialog");
            auto qr = dialog ? dialog->findChild<QLabel *>("pairingQr") : nullptr;
            if (!dialog || !qr || qr->pixmap().isNull()) { if (dialog) dialog->reject(); application.exit(1); return; }
            save(dialog, "linux-1.2.0-pairing.png");
            auto options = dialog->findChild<QPushButton *>("pairNetworkOptions");
            auto copy = dialog->findChild<QPushButton *>("copyPairingDetails");
            if (!options || !copy) { dialog->reject(); application.exit(1); return; }
            options->click();
            auto pages = dialog->findChild<QStackedWidget *>();
            auto back = dialog->findChild<QPushButton *>("pairNetworkBack");
            auto networkChoice = dialog->findChild<QComboBox *>("pairingNetwork");
            if (!pages || pages->currentIndex() != 4 || !back || !back->isVisible() || !copy->isVisible() || !networkChoice || networkChoice->count() < 1) result = 1;
            save(dialog, "linux-1.2.0-network-options.png");
            back->click();
            if (pages->currentIndex() != 0 || qr->pixmap().isNull()) result = 1;
            options->click();
            if (networkChoice->count() > 1) {
                networkChoice->setCurrentIndex(1);
                if (pages->currentIndex() != 0 || qr->pixmap().isNull()) result = 1;
                options->click();
            }
            copy->click();
            const auto invitation = QJsonDocument::fromJson(QApplication::clipboard()->text().toUtf8()).object();
            const auto pairId = invitation.value("pairId").toString();
            const auto secret = QByteArray::fromBase64(invitation.value("secret").toString().toLatin1());
            const QString deviceId = "22222222-2222-4222-8222-222222222222";
            if (pairId.isEmpty() || secret.size() != 32 || QUrl(invitation.value("url").toString()).port() != 45873) { dialog->reject(); application.exit(1); return; }
            const auto requestData = QJsonObject{{"deviceId", deviceId}, {"deviceName", "Disposable UI verifier"}, {"clientNonce", QString::fromLatin1(randomBytes(32).toBase64())}};
            const auto body = QJsonDocument(encryptEnvelope(QJsonDocument(requestData).toJson(QJsonDocument::Compact), secret, "harbor/pair-request/v1/" + pairId.toUtf8())).toJson(QJsonDocument::Compact);
            QNetworkRequest request(QUrl(invitation.value("url").toString() + "/v1/pair/" + pairId));
            request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
            auto pending = network.post(request, body);
            QObject::connect(pending, &QNetworkReply::finished, dialog, [&, pending, dialog, request, body, secret, pairId, deviceId, title] {
                const auto code = pending->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                pending->deleteLater();
                QTimer::singleShot(50, dialog, [&, dialog, request, body, secret, pairId, deviceId, title, code] {
                    auto pages = dialog->findChild<QStackedWidget *>();
                    auto approve = dialog->findChild<QPushButton *>("approvePairing");
                    if (code != 202 || !pages || pages->currentIndex() != 1 || !approve) { dialog->reject(); application.exit(1); return; }
                    save(dialog, "linux-1.2.0-compare.png");
                    approve->click();
                    if (pages->currentIndex() != 2 || vault.data().value("devices").toArray().size() != 1) { dialog->reject(); application.exit(1); return; }
                    save(dialog, "linux-1.2.0-approved.png");
                    auto accepted = network.post(request, body);
                    QObject::connect(accepted, &QNetworkReply::finished, dialog, [&, accepted, dialog, secret, pairId, deviceId, title] {
                        const auto status = accepted->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                        try {
                            const auto response = QJsonDocument::fromJson(accepted->readAll()).object();
                            const auto plain = decryptEnvelope(response, secret, "harbor/pair-response/v1/" + pairId.toUtf8());
                            if (status != 200 || QJsonDocument::fromJson(plain).object().value("deviceId").toString() != deviceId) result = 1;
                        } catch (...) { result = 1; }
                        accepted->deleteLater();
                        dialog->reject();
                        const bool hostSelected = title && title->text() == "Airtel gateway";
                        QTimer::singleShot(50, &window, [&] {
                            auto confirmation = qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
                            if (confirmation) confirmation->button(QMessageBox::Yes)->click();
                            else result = 1;
                        });
                        auto actions = window.findChild<QToolButton *>("hostActions");
                        if (actions) actions->menu()->actions().last()->trigger();
                        else result = 1;
                        if (!vault.hosts().isEmpty()) result = 1;
                        std::cout << "host selected=" << hostSelected << " UI pairing approved and host deleted=" << (result == 0) << '\n';
                        application.exit(result);
                    });
                });
            });
        });
    });
    return application.exec();
}
