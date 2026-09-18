#include "window.h"
#include "terminal.h"
#include <QApplication>
#include <QTreeWidget>
#include <QLineEdit>
#include <QTabWidget>
#include <QTabBar>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QSplitter>
#include <QFormLayout>
#include <QDialog>
#include <QDialogButtonBox>
#include <QComboBox>
#include <QSpinBox>
#include <QFileDialog>
#include <QPlainTextEdit>
#include <QMessageBox>
#include <QInputDialog>
#include <QNetworkInterface>
#include <QClipboard>
#include <QJsonDocument>
#include <QCryptographicHash>
#include <QListWidget>
#include <QFile>
#include <QFontDatabase>
#include <QTimer>
#include <QShortcut>
#include <QStyle>
#include <qrencode.h>
#include <stdexcept>

void applyTheme(QApplication &application) {
    application.setStyle("Fusion");
    auto font = QFontDatabase::systemFont(QFontDatabase::GeneralFont);
    font.setPointSize(11);
    application.setFont(font);
    QPalette palette;
    palette.setColor(QPalette::Window, QColor("#101827"));
    palette.setColor(QPalette::WindowText, QColor("#e5edf8"));
    palette.setColor(QPalette::Base, QColor("#152239"));
    palette.setColor(QPalette::AlternateBase, QColor("#1c2c44"));
    palette.setColor(QPalette::Text, QColor("#e5edf8"));
    palette.setColor(QPalette::Button, QColor("#223752"));
    palette.setColor(QPalette::ButtonText, QColor("#e5edf8"));
    palette.setColor(QPalette::Highlight, QColor("#3276b7"));
    palette.setColor(QPalette::HighlightedText, QColor("#ffffff"));
    palette.setColor(QPalette::Disabled, QPalette::Text, QColor("#7d90a8"));
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor("#7d90a8"));
    palette.setColor(QPalette::PlaceholderText, QColor("#7d90a8"));
    palette.setColor(QPalette::Link, QColor("#63a9ff"));
    application.setPalette(palette);
    application.setStyleSheet(R"(
        QMainWindow, QDialog { background: #101827; }
        QPushButton { padding: 9px 15px; border: 1px solid #354e6d; border-radius: 5px; background: #223752; }
        QPushButton:hover { background: #2b4567; }
        QPushButton:focus { border: 2px solid #63a9ff; padding: 8px 14px; }
        QPushButton:disabled { background: #19273b; border-color: #293c55; }
        QPushButton[primary="true"] { background: #3276b7; border-color: #63a9ff; color: white; }
        QLineEdit, QComboBox, QSpinBox, QPlainTextEdit { border: 1px solid #354e6d; border-radius: 4px; padding: 8px; background: #152239; }
        QLineEdit:focus, QPlainTextEdit:focus { border-color: #63a9ff; }
        QTreeWidget { background: #152239; border: none; padding: 6px; }
        QTreeWidget::item { padding: 10px 4px; border-radius: 4px; }
        QTreeWidget::item:selected { background: #28496d; }
        QTabWidget::pane { border: none; }
        QTabBar::tab { padding: 11px 18px; background: #152239; border-bottom: 2px solid transparent; }
        QTabBar::tab:selected { background: #1c2c44; border-bottom: 2px solid #63a9ff; }
        QLabel[muted="true"] { color: #9bb0c9; }
        QLabel[heading="true"] { font-size: 28px; font-weight: 600; }
        QSplitter::handle { background: #293c55; width: 1px; }
        QToolTip { color: #e5edf8; background: #223752; border: 1px solid #63a9ff; padding: 5px; }
    )");
}

bool unlockVault(Vault &vault, QWidget *parent) {
    while (true) {
        QDialog dialog(parent);
        dialog.setWindowTitle(vault.exists() ? "Unlock Harbor" : "Create your Harbor vault");
        dialog.setMinimumWidth(420);
        auto layout = new QVBoxLayout(&dialog);
        layout->setContentsMargins(28, 28, 28, 28);
        auto heading = new QLabel(vault.exists() ? "Welcome back" : "Your servers, secured", &dialog);
        heading->setProperty("heading", true);
        layout->addWidget(heading);
        auto description = new QLabel(vault.exists() ? "Enter your master passphrase to open your workspace." : "Choose a master passphrase of at least 12 characters. It encrypts your hosts, credentials and paired devices. Keep it safe; it cannot be recovered.", &dialog);
        description->setWordWrap(true);
        description->setProperty("muted", true);
        layout->addWidget(description);
        auto password = new QLineEdit(&dialog);
        password->setEchoMode(QLineEdit::Password);
        password->setPlaceholderText("Master passphrase");
        password->setAccessibleName("Master passphrase");
        layout->addWidget(password);
        QLineEdit *confirmation = nullptr;
        if (!vault.exists()) {
            confirmation = new QLineEdit(&dialog);
            confirmation->setEchoMode(QLineEdit::Password);
            confirmation->setPlaceholderText("Confirm master passphrase");
            confirmation->setAccessibleName("Confirm master passphrase");
            layout->addWidget(confirmation);
        }
        auto buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
        buttons->button(QDialogButtonBox::Ok)->setText(vault.exists() ? "Unlock" : "Create vault");
        layout->addWidget(buttons);
        QObject::connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
        QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
        password->setFocus();
        if (dialog.exec() != QDialog::Accepted) return false;
        if (confirmation && confirmation->text() != password->text()) { QMessageBox::warning(parent, "Passphrase", "The passphrases do not match."); continue; }
        try { vault.unlock(password->text()); password->clear(); if (confirmation) confirmation->clear(); return true; }
        catch (const std::exception &exception) { QMessageBox::warning(parent, "Could not unlock vault", exception.what()); }
    }
}

Window::Window(Vault &vault) : vault_(vault), sync_(vault, this) {
    setWindowTitle("Harbor — SSH workspace");
    resize(1180, 760);
    setMinimumSize(800, 560);
    auto central = new QWidget(this);
    auto outer = new QVBoxLayout(central);
    outer->setContentsMargins(0, 0, 0, 0);
    outer->setSpacing(0);
    auto top = new QHBoxLayout;
    top->setContentsMargins(20, 14, 20, 14);
    auto brand = new QLabel("Harbor", this);
    brand->setStyleSheet("font-size: 22px; font-weight: 600; color: #b9d9ff;");
    top->addWidget(brand);
    top->addSpacing(18);
    status_ = new QLabel("Desktop vault", this);
    status_->setProperty("muted", true);
    top->addWidget(status_);
    top->addStretch();
    sharing_ = new QPushButton("Sharing off", this);
    sharing_->setCheckable(true);
    top->addWidget(sharing_);
    auto pairButton = new QPushButton("Pair phone", this);
    top->addWidget(pairButton);
    auto deviceButton = new QPushButton("Devices", this);
    top->addWidget(deviceButton);
    auto lockButton = new QPushButton("Lock", this);
    top->addWidget(lockButton);
    outer->addLayout(top);
    auto split = new QSplitter(Qt::Horizontal, this);
    auto sidebar = new QWidget(split);
    sidebar->setStyleSheet("background: #152239;");
    auto side = new QVBoxLayout(sidebar);
    side->setContentsMargins(16, 18, 16, 16);
    search_ = new QLineEdit(this);
    search_->setPlaceholderText("Search hosts");
    search_->setAccessibleName("Search hosts");
    side->addWidget(search_);
    hosts_ = new QTreeWidget(this);
    hosts_->setHeaderHidden(true);
    hosts_->setAccessibleName("Hosts grouped by folder");
    hosts_->setIndentation(16);
    side->addWidget(hosts_, 1);
    auto add = new QPushButton("Add host", this);
    add->setStyleSheet("background: #3276b7; border-color: #63a9ff; color: white;");
    side->addWidget(add);
    tabs_ = new QTabWidget(split);
    tabs_->setTabsClosable(true);
    tabs_->setMovable(false);
    auto home = new QWidget(this);
    auto content = new QVBoxLayout(home);
    content->setContentsMargins(42, 40, 42, 36);
    content->setSpacing(22);
    title_ = new QLabel("Your SSH workspace", this);
    title_->setProperty("heading", true);
    content->addWidget(title_);
    details_ = new QLabel("Add a host to start a secure terminal session.\n\nManage connections here, then pair your phone to take a read-only copy with you.", this);
    details_->setWordWrap(true);
    details_->setTextInteractionFlags(Qt::TextSelectableByMouse);
    details_->setProperty("muted", true);
    content->addWidget(details_);
    auto actions = new QHBoxLayout;
    connect_ = new QPushButton("Connect", this);
    connect_->setStyleSheet("background: #3276b7; border-color: #63a9ff; color: white;");
    edit_ = new QPushButton("Edit host", this);
    remove_ = new QPushButton("Delete host", this);
    actions->addWidget(connect_);
    actions->addWidget(edit_);
    actions->addWidget(remove_);
    actions->addStretch();
    content->addLayout(actions);
    content->addStretch();
    auto foot = new QLabel("Host keys are checked before credentials are sent.\nYour desktop owns the vault; phones receive a signed copy when you sync.", this);
    foot->setProperty("muted", true);
    content->addWidget(foot);
    tabs_->addTab(home, "Overview");
    tabs_->tabBar()->setTabButton(0, QTabBar::RightSide, nullptr);
    split->setSizes({285, 895});
    split->setStretchFactor(1, 1);
    outer->addWidget(split, 1);
    setCentralWidget(central);
    connect(search_, &QLineEdit::textChanged, this, &Window::refresh);
    connect(hosts_, &QTreeWidget::itemSelectionChanged, this, &Window::select);
    connect(hosts_, &QTreeWidget::itemDoubleClicked, this, [this] { connectHost(); });
    connect(add, &QPushButton::clicked, this, [this] { editHost(true); });
    connect(edit_, &QPushButton::clicked, this, [this] { editHost(false); });
    connect(connect_, &QPushButton::clicked, this, &Window::connectHost);
    connect(remove_, &QPushButton::clicked, this, &Window::removeHost);
    connect(pairButton, &QPushButton::clicked, this, &Window::pair);
    connect(deviceButton, &QPushButton::clicked, this, &Window::devices);
    connect(lockButton, &QPushButton::clicked, this, &Window::lockVault);
    connect(sharing_, &QPushButton::toggled, this, &Window::sharing);
    connect(tabs_, &QTabWidget::tabCloseRequested, this, [this](int index) {
        if (index == 0) return;
        if (QMessageBox::question(this, "Close terminal", "Close this SSH session?", QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes) return;
        auto widget = tabs_->widget(index);
        tabs_->removeTab(index);
        delete widget;
    });
    connect(&vault_, &Vault::changed, this, &Window::refresh);
    connect(&sync_, &SyncServer::pairingRequested, this, [this](const QString &id, const QString &name, const QString &code) {
        const auto result = QMessageBox::question(this, "Approve " + name, "Compare this code with your phone:\n\n" + code + "\n\nApprove only if both devices show the same code. This phone will receive your saved SSH credentials.", QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
        try { if (result == QMessageBox::Yes) sync_.approve(id); else sync_.deny(id); }
        catch (const std::exception &exception) { error(exception); }
    });
    auto addShortcut = new QShortcut(QKeySequence("Ctrl+N"), this);
    connect(addShortcut, &QShortcut::activated, this, [this] { editHost(true); });
    auto searchShortcut = new QShortcut(QKeySequence("Ctrl+F"), this);
    connect(searchShortcut, &QShortcut::activated, search_, qOverload<>(&QWidget::setFocus));
    refresh();
}

void Window::error(const std::exception &exception) { QMessageBox::critical(this, "Harbor", QString::fromUtf8(exception.what())); }

QJsonObject Window::selectedHost() const {
    if (!vault_.unlocked()) return {};
    for (const auto &host : vault_.hosts()) if (host.toObject().value("id").toString() == selected_) return host.toObject();
    return {};
}

void Window::refresh() {
    const auto current = selected_;
    hosts_->blockSignals(true);
    hosts_->clear();
    QHash<QString, QTreeWidgetItem *> groups;
    if (vault_.unlocked()) {
        status_->setText(QString::number(vault_.hosts().size()) + " hosts  •  Desktop vault");
        const auto query = search_->text().trimmed();
        for (const auto &entry : vault_.hosts()) {
            const auto host = entry.toObject();
            if (!query.isEmpty() && !(host.value("name").toString() + " " + host.value("hostname").toString() + " " + host.value("group").toString()).contains(query, Qt::CaseInsensitive)) continue;
            const auto groupName = host.value("group").toString().isEmpty() ? "Ungrouped" : host.value("group").toString();
            if (!groups.contains(groupName)) {
                auto group = new QTreeWidgetItem(hosts_, {groupName});
                group->setFlags(group->flags() & ~Qt::ItemIsSelectable);
                group->setExpanded(true);
                groups[groupName] = group;
            }
            auto item = new QTreeWidgetItem(groups[groupName], {host.value("name").toString()});
            item->setData(0, Qt::UserRole, host.value("id").toString());
            item->setToolTip(0, host.value("username").toString() + "@" + host.value("hostname").toString());
            item->setIcon(0, style()->standardIcon(QStyle::SP_ComputerIcon));
            if (host.value("id").toString() == current) hosts_->setCurrentItem(item);
        }
    }
    hosts_->blockSignals(false);
    select();
}

void Window::select() {
    const auto item = hosts_->currentItem();
    selected_ = item ? item->data(0, Qt::UserRole).toString() : QString();
    const auto host = selectedHost();
    connect_->setEnabled(!host.isEmpty());
    edit_->setEnabled(!host.isEmpty());
    remove_->setEnabled(!host.isEmpty());
    if (host.isEmpty()) {
        title_->setText("Your SSH workspace");
        details_->setText(vault_.unlocked() && vault_.hosts().isEmpty() ? "Add your first host to open a terminal.\n\nSave a password or import a private key. Your credentials stay encrypted in your desktop vault." : "Select a host to see its connection details.");
        return;
    }
    title_->setText(host.value("name").toString());
    const auto key = host.value("hostKey").toString().section(' ', 1, 1).toLatin1();
    const auto fingerprint = key.isEmpty() ? QString("Not verified yet — you will verify before connecting") : QString("SHA256:") + QString::fromLatin1(QCryptographicHash::hash(QByteArray::fromBase64(key), QCryptographicHash::Sha256).toBase64(QByteArray::OmitTrailingEquals));
    details_->setText(host.value("username").toString() + "@" + host.value("hostname").toString() + ":" + QString::number(host.value("port").toInt()) + "\n\nAuthentication: " + (host.value("authType") == "key" ? "Private key" : "Password") + "\nGroup: " + (host.value("group").toString().isEmpty() ? "Ungrouped" : host.value("group").toString()) + "\n\nHost key\n" + fingerprint + "\n\n" + host.value("notes").toString());
}

void Window::editHost(bool creating) {
    auto original = creating ? QJsonObject() : selectedHost();
    if (!creating && original.isEmpty()) return;
    QDialog dialog(this);
    dialog.setWindowTitle(creating ? "Add host" : "Edit host");
    dialog.setMinimumWidth(540);
    auto layout = new QVBoxLayout(&dialog);
    auto form = new QFormLayout;
    auto name = new QLineEdit(original.value("name").toString(), &dialog);
    auto hostname = new QLineEdit(original.value("hostname").toString(), &dialog);
    auto port = new QSpinBox(&dialog);
    port->setRange(1, 65535);
    port->setValue(original.value("port").toInt(22));
    auto username = new QLineEdit(original.value("username").toString(), &dialog);
    auto group = new QLineEdit(original.value("group").toString(), &dialog);
    auto auth = new QComboBox(&dialog);
    auth->addItem("Password", "password");
    auth->addItem("Private key", "key");
    auth->setCurrentIndex(original.value("authType").toString() == "key" ? 1 : 0);
    auto password = new QLineEdit(original.value("password").toString(), &dialog);
    password->setEchoMode(QLineEdit::Password);
    auto keyButton = new QPushButton(original.value("privateKey").toString().isEmpty() ? "Import private key…" : "Replace private key…", &dialog);
    auto passphrase = new QLineEdit(original.value("passphrase").toString(), &dialog);
    passphrase->setEchoMode(QLineEdit::Password);
    auto notes = new QPlainTextEdit(original.value("notes").toString(), &dialog);
    notes->setMaximumHeight(110);
    auto verify = new QPushButton("Scan and verify server key", &dialog);
    form->addRow("Name", name);
    form->addRow("Hostname", hostname);
    form->addRow("Port", port);
    form->addRow("Username", username);
    form->addRow("Group", group);
    form->addRow("Authentication", auth);
    form->addRow("Password", password);
    form->addRow("Private key", keyButton);
    form->addRow("Key passphrase", passphrase);
    form->addRow("Notes", notes);
    form->addRow("Host key", verify);
    layout->addLayout(form);
    auto message = new QLabel("Verify the server key before syncing to your phone.", &dialog);
    message->setWordWrap(true);
    message->setProperty("muted", true);
    layout->addWidget(message);
    auto buttons = new QDialogButtonBox(QDialogButtonBox::Save | QDialogButtonBox::Cancel, &dialog);
    layout->addWidget(buttons);
    QString privateKey = original.value("privateKey").toString();
    QString hostKey = original.value("hostKey").toString();
    bool keyVerified = false;
    auto build = [&] {
        auto host = original;
        host["name"] = name->text().trimmed();
        host["hostname"] = hostname->text().trimmed();
        host["port"] = port->value();
        host["username"] = username->text().trimmed();
        host["group"] = group->text().trimmed();
        host["authType"] = auth->currentData().toString();
        host["password"] = auth->currentIndex() == 0 ? password->text() : QString();
        host["privateKey"] = auth->currentIndex() == 1 ? privateKey : QString();
        host["passphrase"] = auth->currentIndex() == 1 ? passphrase->text() : QString();
        host["hostKey"] = hostKey;
        host["notes"] = notes->toPlainText();
        return host;
    };
    auto update = [&] { password->setEnabled(auth->currentIndex() == 0); keyButton->setEnabled(auth->currentIndex() == 1); passphrase->setEnabled(auth->currentIndex() == 1); };
    connect(auth, &QComboBox::currentIndexChanged, &dialog, update);
    update();
    connect(keyButton, &QPushButton::clicked, &dialog, [&] {
        const auto path = QFileDialog::getOpenFileName(&dialog, "Import private key");
        if (path.isEmpty()) return;
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly) || file.size() > 256 * 1024) { message->setText("Could not read the key, or it exceeds 256 KiB."); return; }
        privateKey = QString::fromUtf8(file.readAll());
        keyButton->setText("Private key imported — replace…");
    });
    connect(verify, &QPushButton::clicked, &dialog, [&] {
        auto host = build();
        const auto validation = validateHost(host);
        if (!validation.isEmpty()) { message->setText(validation); return; }
        if (Terminal::trustHost(host, &dialog)) { hostKey = host.value("hostKey").toString(); keyVerified = true; message->setText("Server key verified. Save this host to include the key in your next sync."); }
    });
    connect(hostname, &QLineEdit::textChanged, &dialog, [&] { hostKey.clear(); keyVerified = false; });
    connect(port, &QSpinBox::valueChanged, &dialog, [&] { hostKey.clear(); keyVerified = false; });
    connect(buttons, &QDialogButtonBox::accepted, &dialog, [&] {
        try { auto host = build(); vault_.upsert(host, keyVerified); selected_ = creating ? vault_.hosts().last().toObject().value("id").toString() : original.value("id").toString(); dialog.accept(); }
        catch (const std::exception &exception) { message->setText(exception.what()); }
    });
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    if (dialog.exec() == QDialog::Accepted) refresh();
}

void Window::connectHost() {
    auto host = selectedHost();
    if (host.isEmpty()) return;
    try {
        if (host.value("hostKey").toString().isEmpty()) {
            if (!Terminal::trustHost(host, this)) return;
            vault_.upsert(host);
        }
        auto terminal = new Terminal(host, tabs_);
        const auto index = tabs_->addTab(terminal, host.value("name").toString());
        tabs_->setCurrentIndex(index);
        connect(terminal, &Terminal::finished, this, [this, terminal] { const int i = tabs_->indexOf(terminal); if (i >= 0) tabs_->setTabText(i, tabs_->tabText(i) + " (closed)"); });
    } catch (const std::exception &exception) { error(exception); }
}

void Window::removeHost() {
    auto host = selectedHost();
    if (host.isEmpty()) return;
    if (QMessageBox::question(this, "Delete host", "Delete " + host.value("name").toString() + "? It will be removed from your phone on its next sync.", QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes) return;
    try { vault_.remove(selected_); } catch (const std::exception &exception) { error(exception); }
}

void Window::sharing(bool enabled) {
    try {
        if (!enabled) sync_.stop();
        else if (!sync_.start()) {
            bool accepted = false;
            const auto port = QInputDialog::getInt(this, "Sharing port", "Port 45873 is unavailable. Choose another local port:", 45874, 1024, 65535, 1, &accepted);
            if (!accepted || !sync_.start(port)) { sharing_->setChecked(false); return; }
        }
        sharing_->setText(enabled ? "Sharing on · " + QString::number(sync_.port()) : "Sharing off");
    } catch (const std::exception &exception) { sharing_->setChecked(false); error(exception); }
}

static QPixmap pairingQr(const QByteArray &text) {
    auto qr = std::unique_ptr<QRcode, decltype(&QRcode_free)>(QRcode_encodeString(text.constData(), 0, QR_ECLEVEL_M, QR_MODE_8, 1), QRcode_free);
    if (!qr) throw std::runtime_error("Could not create pairing QR code");
    const int size = qr->width + 8;
    QImage image(size, size, QImage::Format_RGB32);
    image.fill(Qt::white);
    for (int y = 0; y < qr->width; ++y) for (int x = 0; x < qr->width; ++x) if (qr->data[y * qr->width + x] & 1) image.setPixelColor(x + 4, y + 4, Qt::black);
    const int scale = qMax(3, 320 / size);
    return QPixmap::fromImage(image.scaled(size * scale, size * scale, Qt::KeepAspectRatio, Qt::FastTransformation));
}

void Window::pair() {
    if (!sharing_->isChecked()) sharing_->setChecked(true);
    if (!sync_.running()) return;
    QDialog dialog(this);
    dialog.setWindowTitle("Pair your phone");
    dialog.setMinimumWidth(620);
    auto layout = new QVBoxLayout(&dialog);
    auto label = new QLabel("Both devices must reach the same local network or private VPN. Choose the desktop address your phone can reach.", &dialog);
    label->setWordWrap(true);
    layout->addWidget(label);
    auto addresses = new QComboBox(&dialog);
    for (const auto &address : QNetworkInterface::allAddresses()) {
        if (address.isLoopback() || address.protocol() != QAbstractSocket::IPv4Protocol) continue;
        const quint32 n = address.toIPv4Address();
        if ((n >> 24) == 10 || (n >> 20) == 0xac1 || (n >> 16) == 0xc0a8 || (n >> 16) == 0xa9fe) addresses->addItem("http://" + address.toString() + ":" + QString::number(sync_.port()));
    }
    addresses->addItem("http://127.0.0.1:" + QString::number(sync_.port()));
    addresses->setEditable(true);
    layout->addWidget(addresses);
    auto generate = new QPushButton("Create pairing invitation", &dialog);
    layout->addWidget(generate);
    auto qr = new QLabel(&dialog);
    qr->setAlignment(Qt::AlignCenter);
    layout->addWidget(qr);
    auto json = new QPlainTextEdit(&dialog);
    json->setReadOnly(true);
    json->setMaximumHeight(110);
    json->setPlaceholderText("Pairing JSON will appear here. Keep this invitation private.");
    layout->addWidget(json);
    auto copy = new QPushButton("Copy pairing JSON", &dialog);
    copy->setEnabled(false);
    layout->addWidget(copy);
    auto hint = new QLabel("Invitations expire in five minutes. Scan the QR code in Harbor on Android, or paste the pairing JSON. Keep this window open until your phone finishes pairing.", &dialog);
    hint->setWordWrap(true);
    hint->setProperty("muted", true);
    layout->addWidget(hint);
    auto close = new QDialogButtonBox(QDialogButtonBox::Close, &dialog);
    layout->addWidget(close);
    connect(close, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    QTimer expiry(&dialog);
    expiry.setSingleShot(true);
    connect(&expiry, &QTimer::timeout, &dialog, [&] { json->clear(); qr->clear(); copy->setEnabled(false); sync_.cancelInvite(); hint->setText("Invitation expired. Create another to pair your phone."); });
    const auto initialDevices = sync_.devices().size();
    connect(&vault_, &Vault::changed, &dialog, [&] { if (vault_.unlocked() && sync_.devices().size() > initialDevices) hint->setText("Device approved. Keep this window open until your phone confirms pairing and downloads its first sync."); });
    connect(generate, &QPushButton::clicked, &dialog, [&] {
        try {
            const auto text = QJsonDocument(sync_.invite(addresses->currentText())).toJson(QJsonDocument::Compact);
            json->setPlainText(QString::fromUtf8(text));
            qr->setPixmap(pairingQr(text));
            copy->setEnabled(true);
            expiry.start(300000);
        } catch (const std::exception &exception) { hint->setText(exception.what()); }
    });
    connect(copy, &QPushButton::clicked, &dialog, [&] { QApplication::clipboard()->setText(json->toPlainText()); });
    dialog.exec();
    sync_.cancelInvite(true);
}

void Window::devices() {
    QDialog dialog(this);
    dialog.setWindowTitle("Paired devices");
    dialog.setMinimumSize(460, 320);
    auto layout = new QVBoxLayout(&dialog);
    auto list = new QListWidget(&dialog);
    layout->addWidget(list);
    auto populate = [&] {
        list->clear();
        for (const auto &entry : sync_.devices()) {
            const auto device = entry.toObject();
            auto item = new QListWidgetItem(device.value("name").toString(), list);
            item->setData(Qt::UserRole, device.value("id").toString());
        }
        if (list->count() == 0) { auto item = new QListWidgetItem("No paired devices", list); item->setFlags(Qt::NoItemFlags); }
    };
    populate();
    auto revoke = new QPushButton("Revoke selected device", &dialog);
    layout->addWidget(revoke);
    auto hint = new QLabel("Revoking stops future sync. To remove access from an offline phone, rotate the SSH credentials on your servers.", &dialog);
    hint->setWordWrap(true);
    hint->setProperty("muted", true);
    layout->addWidget(hint);
    auto close = new QDialogButtonBox(QDialogButtonBox::Close, &dialog);
    layout->addWidget(close);
    connect(close, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    connect(revoke, &QPushButton::clicked, &dialog, [&] {
        const auto item = list->currentItem();
        if (!item || item->data(Qt::UserRole).toString().isEmpty()) return;
        if (QMessageBox::question(&dialog, "Revoke device", "Stop " + item->text() + " from syncing this vault?", QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes) return;
        try { sync_.revoke(item->data(Qt::UserRole).toString()); populate(); } catch (const std::exception &exception) { error(exception); }
    });
    dialog.exec();
}

void Window::lockVault() {
    sharing_->setChecked(false);
    sync_.stop();
    while (tabs_->count() > 1) { auto widget = tabs_->widget(1); tabs_->removeTab(1); delete widget; }
    selected_.clear();
    vault_.lock();
    if (!unlockVault(vault_, this)) { close(); return; }
    refresh();
}
