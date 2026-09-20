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
#include <QStackedWidget>
#include <QClipboard>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkProxy>
#include <iostream>

int main(int argc, char **argv) {
    QApplication application(argc, argv);
    if (argc != 2) return 1;
    applyTheme(application);
    QDir output(argv[1]);
    if (!output.exists() && !QDir().mkpath(output.path())) return 1;
    QTemporaryDir directory;
    Vault vault(directory.path() + "/vault.json");
    vault.unlock("disposable UI test passphrase");
    Window window(vault);
    window.show();
    QNetworkAccessManager network(&window);
    network.setProxy(QNetworkProxy::NoProxy);
    int result = 0;
    auto save = [&](QWidget *widget, const QString &name) { application.processEvents(); if (!widget->grab().save(output.filePath(name))) result = 1; };
    QTimer::singleShot(300, &window, [&] {
        save(&window, "linux-1.1.1-empty.png");
        auto add = window.findChild<QPushButton *>("emptyAddHost");
        if (!add) { application.exit(1); return; }
        QTimer::singleShot(100, &window, [&] {
            auto dialog = window.findChild<QDialog *>("hostEditor");
            if (!dialog) { result = 1; return; }
            save(dialog, "linux-1.1.1-editor.png");
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
                save(dialog, "linux-1.1.1-editor-small-more.png");
                scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
                save(dialog, "linux-1.1.1-editor-small-more-bottom.png");
                scroll->verticalScrollBar()->setValue(0);
                more->click();
            }
            save(dialog, "linux-1.1.1-editor-small.png");
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
        auto edit = window.findChild<QPushButton *>("editHost");
        if (!edit) { application.exit(1); return; }
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
        edit->click();
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
        edit->click();
        saved = vault.hosts().first().toObject();
        if (saved.value("authType") != "none" || !saved.value("password").toString().isEmpty() || !saved.value("privateKey").toString().isEmpty() || !saved.value("passphrase").toString().isEmpty()) result = 1;
        window.resize(1160, 760);
        save(&window, "linux-1.1.1-host.png");
        auto devices = window.findChild<QPushButton *>("devicesButton");
        if (!devices) { application.exit(1); return; }
        QTimer::singleShot(0, &window, [&] {
            auto dialog = window.findChild<QDialog *>("devicesDialog");
            if (!dialog) { result = 1; return; }
            save(dialog, "linux-1.1.1-devices.png");
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
            save(dialog, "linux-1.1.1-pairing.png");
            QToolButton *options = nullptr;
            for (auto button : dialog->findChildren<QToolButton *>()) if (button->text() == "Connection options") options = button;
            auto copy = dialog->findChild<QPushButton *>("copyPairingDetails");
            if (!options || !copy) { dialog->reject(); application.exit(1); return; }
            options->click();
            save(dialog, "linux-1.1.1-network-options.png");
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
                    save(dialog, "linux-1.1.1-compare.png");
                    approve->click();
                    if (pages->currentIndex() != 2 || vault.data().value("devices").toArray().size() != 1) { dialog->reject(); application.exit(1); return; }
                    save(dialog, "linux-1.1.1-approved.png");
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
                        std::cout << "first host selected=" << (title && title->text() == "example.net") << " UI pairing approved=" << (result == 0) << '\n';
                        application.exit(result);
                    });
                });
            });
        });
    });
    return application.exec();
}
