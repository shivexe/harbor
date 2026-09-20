#include "window.h"
#include "terminal.h"
#include "pairing_network.h"
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
#include <QDialog>
#include <QDialogButtonBox>
#include <QComboBox>
#include <QSpinBox>
#include <QFileDialog>
#include <QPlainTextEdit>
#include <QMessageBox>
#include <QClipboard>
#include <QJsonDocument>
#include <QCryptographicHash>
#include <QListWidget>
#include <QFile>
#include <QFontDatabase>
#include <QTimer>
#include <QThread>
#include <QShortcut>
#include <QScrollArea>
#include <QToolButton>
#include <QFrame>
#include <QGridLayout>
#include <QMenu>
#include <QAction>
#include <QStackedWidget>
#include <QDateTime>
#include <QPainter>
#include <QIcon>
#include <qrencode.h>
#include <stdexcept>

static QPixmap phoneImage(int size) {
    QPixmap image(size, size);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.scale(size / 24.0, size / 24.0);
    painter.setPen(QPen(QColor("#b1b1b6"), 1.6));
    painter.drawRoundedRect(QRectF(6, 2, 12, 20), 2.3, 2.3);
    painter.drawLine(QPointF(10, 5), QPointF(14, 5));
    painter.drawPoint(QPointF(12, 19));
    return image;
}

static QPixmap lockImage() {
    QPixmap image(24, 24);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(QPen(QColor("#b1b1b6"), 1.6));
    painter.drawArc(QRectF(7, 3, 10, 12), 0, 180 * 16);
    painter.drawRoundedRect(QRectF(5, 10, 14, 11), 2, 2);
    return image;
}

static QPixmap serverImage() {
    QPixmap image(24, 24);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(QPen(QColor("#b1b1b6"), 1.6));
    painter.drawRoundedRect(QRectF(4, 3, 16, 18), 2, 2);
    painter.drawLine(QPointF(8, 9), QPointF(16, 9));
    painter.drawLine(QPointF(8, 14), QPointF(16, 14));
    painter.drawPoint(QPointF(8, 18));
    return image;
}

void applyTheme(QApplication &application) {
    application.setStyle("Fusion");
    auto font = QFontDatabase::systemFont(QFontDatabase::GeneralFont);
    font.setPointSize(11);
    application.setFont(font);
    QPalette palette;
    palette.setColor(QPalette::Window, QColor("#242426"));
    palette.setColor(QPalette::WindowText, QColor("#f2f2f2"));
    palette.setColor(QPalette::Base, QColor("#303033"));
    palette.setColor(QPalette::AlternateBase, QColor("#1c1c1e"));
    palette.setColor(QPalette::Text, QColor("#f2f2f2"));
    palette.setColor(QPalette::Button, QColor("#303033"));
    palette.setColor(QPalette::ButtonText, QColor("#f2f2f2"));
    palette.setColor(QPalette::Highlight, QColor("#0a84ff"));
    palette.setColor(QPalette::HighlightedText, QColor("#ffffff"));
    palette.setColor(QPalette::Disabled, QPalette::Text, QColor("#8e8e93"));
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor("#8e8e93"));
    palette.setColor(QPalette::PlaceholderText, QColor("#8e8e93"));
    palette.setColor(QPalette::Link, QColor("#409cff"));
    application.setPalette(palette);
    application.setStyleSheet(R"(
        QMainWindow, QDialog { background: #242426; }
        QPushButton { min-height: 32px; padding: 3px 12px; border: 1px solid #48484a; border-radius: 6px; background: #303033; color: #f2f2f2; }
        QPushButton:hover { background: #3a3a3c; }
        QPushButton:focus, QToolButton:focus, QComboBox:focus, QTreeWidget:focus { border: 2px solid #0a84ff; }
        QPushButton:disabled { color: #8e8e93; background: #29292c; border-color: #3a3a3e; }
        QPushButton[primary="true"] { background: #0068d9; border-color: #0068d9; color: #ffffff; font-weight: 600; }
        QPushButton[primary="true"]:hover { background: #0077ed; }
        QLineEdit, QComboBox, QSpinBox, QPlainTextEdit { min-height: 32px; border: 1px solid #48484a; border-radius: 6px; padding: 3px 9px; background: #303033; color: #f2f2f2; }
        QLineEdit:focus, QPlainTextEdit:focus, QSpinBox:focus { border: 2px solid #0a84ff; }
        QTreeWidget { background: transparent; border: none; outline: none; }
        QTreeWidget::item { min-height: 31px; padding: 3px 6px; }
        QTreeWidget::item:selected { background: #3a3a3c; color: #f2f2f2; }
        QTabWidget::pane { border: none; }
        QTabBar::tab { min-height: 31px; padding: 2px 12px; background: #1c1c1e; border-bottom: 2px solid transparent; }
        QTabBar::tab:selected { background: #303033; border-bottom: 2px solid #0a84ff; }
        QLabel[muted="true"] { color: #b1b1b6; }
        QLabel[heading="true"] { font-size: 22px; font-weight: 600; }
        QLabel[section="true"] { font-size: 17px; font-weight: 600; }
        QLabel[small="true"] { font-size: 12px; }
        QLabel[endpoint="true"] { font-family: monospace; color: #d0d0d4; }
        QSplitter::handle { background: #3a3a3e; width: 1px; }
        QToolTip { color: #f2f2f2; background: #303033; border: 1px solid #0a84ff; padding: 5px; }
    )");
}

bool unlockVault(Vault &vault, QWidget *parent) {
    QDialog dialog(parent);
    const bool existing = vault.exists();
    dialog.setObjectName("vaultDialog");
    dialog.setWindowTitle(existing ? "Unlock Harbor" : "Create your Harbor workspace");
    dialog.setMinimumWidth(460);
    auto layout = new QVBoxLayout(&dialog);
    layout->setContentsMargins(36, 34, 36, 30);
    layout->setSpacing(14);
    auto brand = new QLabel("Harbor", &dialog);
    brand->setStyleSheet("font-size: 22px; font-weight: 650; color: #f2f2f2;");
    layout->addWidget(brand);
    layout->addSpacing(18);
    auto heading = new QLabel(existing ? "Welcome back" : "Secure your workspace", &dialog);
    heading->setProperty("heading", true);
    layout->addWidget(heading);
    auto description = new QLabel(existing ? "Unlock your saved servers and sessions." : "Create a master passphrase to encrypt your SSH hosts and credentials on this computer.", &dialog);
    description->setProperty("muted", true);
    description->setWordWrap(true);
    layout->addWidget(description);
    layout->addSpacing(10);
    auto passwordLabel = new QLabel("Master passphrase", &dialog);
    layout->addWidget(passwordLabel);
    auto password = new QLineEdit(&dialog);
    password->setEchoMode(QLineEdit::Password);
    password->setAccessibleName("Master passphrase");
    layout->addWidget(password);
    QLineEdit *confirmation = nullptr;
    if (!existing) {
        auto confirmLabel = new QLabel("Confirm passphrase", &dialog);
        layout->addWidget(confirmLabel);
        confirmation = new QLineEdit(&dialog);
        confirmation->setEchoMode(QLineEdit::Password);
        confirmation->setAccessibleName("Confirm passphrase");
        layout->addWidget(confirmation);
        auto recovery = new QLabel("Use at least 12 characters. Harbor cannot recover a lost passphrase.", &dialog);
        recovery->setProperty("muted", true);
        recovery->setProperty("small", true);
        recovery->setWordWrap(true);
        layout->addWidget(recovery);
    }
    auto message = new QLabel(&dialog);
    message->setStyleSheet("color: #ff9b9b;");
    message->setWordWrap(true);
    message->hide();
    layout->addWidget(message);
    layout->addSpacing(12);
    auto buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    buttons->button(QDialogButtonBox::Ok)->setText(existing ? "Unlock workspace" : "Create workspace");
    buttons->button(QDialogButtonBox::Ok)->setProperty("primary", true);
    buttons->button(QDialogButtonBox::Ok)->setStyleSheet("background: #0068d9; border-color: #0068d9; color: #ffffff; font-weight: 600;");
    layout->addWidget(buttons);
    QObject::connect(buttons, &QDialogButtonBox::accepted, &dialog, [&] {
        if (confirmation && confirmation->text() != password->text()) { message->setText("The passphrases do not match."); message->show(); return; }
        try { vault.unlock(password->text()); password->clear(); if (confirmation) confirmation->clear(); dialog.accept(); }
        catch (const std::exception &exception) { message->setText(exception.what()); message->show(); password->selectAll(); password->setFocus(); }
    });
    QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    password->setFocus();
    return dialog.exec() == QDialog::Accepted;
}

Window::Window(Vault &vault) : vault_(vault), sync_(vault, this) {
    setWindowTitle("Harbor — SSH workspace");
    resize(1160, 760);
    setMinimumSize(780, 520);
    auto central = new QWidget(this);
    auto outer = new QVBoxLayout(central);
    outer->setContentsMargins(0, 0, 0, 0);
    outer->setSpacing(0);
    auto split = new QSplitter(Qt::Horizontal, this);
    auto sidebar = new QWidget(split);
    sidebar->setStyleSheet("background: #1c1c1e;");
    auto side = new QVBoxLayout(sidebar);
    side->setContentsMargins(16, 16, 16, 16);
    side->setSpacing(10);
    auto brand = new QLabel("Harbor", sidebar);
    brand->setStyleSheet("font-size: 21px; font-weight: 650; color: #f2f2f2;");
    side->addWidget(brand);
    side->addSpacing(10);
    search_ = new QLineEdit(sidebar);
    search_->setPlaceholderText("Search hosts");
    search_->setAccessibleName("Search hosts");
    search_->setClearButtonEnabled(true);
    side->addWidget(search_);
    status_ = new QLabel(sidebar);
    status_->setProperty("muted", true);
    status_->setProperty("small", true);
    side->addWidget(status_);
    hosts_ = new QTreeWidget(sidebar);
    hosts_->setHeaderHidden(true);
    hosts_->setAccessibleName("Hosts grouped by folder");
    hosts_->setIndentation(14);
    side->addWidget(hosts_, 1);
    auto sideRule = new QFrame(sidebar);
    sideRule->setFrameShape(QFrame::HLine);
    sideRule->setStyleSheet("color: #3a3a3e;");
    side->addWidget(sideRule);
    auto deviceButton = new QPushButton("Devices", sidebar);
    deviceButton->setObjectName("devicesButton");
    deviceButton->setIcon(QIcon(phoneImage(24)));
    deviceButton->setIconSize(QSize(20, 20));
    deviceButton->setStyleSheet("text-align: left; background: transparent; border: none; padding-left: 4px; color: #d0d0d4;");
    side->addWidget(deviceButton);
    auto lockButton = new QPushButton("Lock workspace", sidebar);
    lockButton->setObjectName("lockButton");
    lockButton->setIcon(QIcon(lockImage()));
    lockButton->setIconSize(QSize(20, 20));
    lockButton->setStyleSheet("text-align: left; background: transparent; border: none; padding-left: 4px; color: #b1b1b6;");
    side->addWidget(lockButton);
    auto workspace = new QWidget(split);
    auto workLayout = new QVBoxLayout(workspace);
    workLayout->setContentsMargins(0, 0, 0, 0);
    workLayout->setSpacing(0);
    auto header = new QWidget(workspace);
    auto headerLayout = new QHBoxLayout(header);
    headerLayout->setContentsMargins(24, 10, 24, 10);
    headerLayout->setSpacing(8);
    title_ = new QLabel(header);
    title_->setObjectName("hostTitle");
    title_->setTextFormat(Qt::PlainText);
    title_->setProperty("section", true);
    headerLayout->addWidget(title_);
    headerLayout->addStretch();
    connect_ = new QPushButton("Connect", header);
    connect_->setProperty("primary", true);
    connect_->setObjectName("connectHost");
    headerLayout->addWidget(connect_);
    hostMenu_ = new QToolButton(header);
    hostMenu_->setObjectName("hostActions");
    hostMenu_->setText("Actions  ▾");
    hostMenu_->setPopupMode(QToolButton::InstantPopup);
    hostMenu_->setStyleSheet("QToolButton { min-height: 32px; padding: 3px 12px; border: 1px solid #48484a; border-radius: 6px; background: #303033; color: #f2f2f2; } QToolButton::menu-indicator { width: 0px; image: none; }");
    auto hostActions = new QMenu(hostMenu_);
    auto editAction = hostActions->addAction("Edit host");
    auto deleteAction = hostActions->addAction("Delete host");
    hostMenu_->setMenu(hostActions);
    headerLayout->addWidget(hostMenu_);
    auto add = new QPushButton("Add host", header);
    add_ = add;
    add->setObjectName("addHostTop");
    headerLayout->addWidget(add);
    workLayout->addWidget(header);
    tabs_ = new QTabWidget(workspace);
    tabs_->setTabsClosable(true);
    tabs_->setMovable(false);
    auto home = new QWidget(tabs_);
    auto content = new QVBoxLayout(home);
    content->setContentsMargins(32, 26, 32, 24);
    content->setSpacing(14);
    details_ = new QLabel(home);
    details_->setTextFormat(Qt::PlainText);
    details_->setWordWrap(true);
    details_->setTextInteractionFlags(Qt::TextSelectableByMouse);
    details_->setProperty("muted", true);
    content->addWidget(details_);
    connectionHeading_ = new QLabel("Connection", home);
    connectionHeading_->setProperty("section", true);
    content->addWidget(connectionHeading_);
    hostFields_ = new QWidget(home);
    auto grid = new QGridLayout(hostFields_);
    grid->setContentsMargins(0, 8, 0, 0);
    grid->setHorizontalSpacing(28);
    grid->setVerticalSpacing(18);
    grid->setColumnMinimumWidth(0, 140);
    grid->setColumnStretch(1, 1);
    auto row = [&](int index, const QString &caption, QLabel *&value) {
        auto label = new QLabel(caption, hostFields_);
        label->setProperty("muted", true);
        grid->addWidget(label, index, 0, Qt::AlignTop);
        value = new QLabel(hostFields_);
        value->setTextFormat(Qt::PlainText);
        value->setTextInteractionFlags(Qt::TextSelectableByMouse);
        value->setWordWrap(true);
        grid->addWidget(value, index, 1);
    };
    row(0, "Address", endpoint_);
    row(1, "Username", username_);
    row(2, "Port", port_);
    row(3, "Authentication", authentication_);
    row(4, "Server identity", fingerprint_);
    row(5, "Notes", notes_);
    notes_->setObjectName("hostNotes");
    content->addWidget(hostFields_);
    emptyAdd_ = new QPushButton("Add your first host", home);
    emptyAdd_->setObjectName("emptyAddHost");
    emptyAdd_->setProperty("primary", true);
    emptyAdd_->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    content->addWidget(emptyAdd_);
    clearSearch_ = new QPushButton("Clear search", home);
    clearSearch_->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    content->addWidget(clearSearch_);
    content->addStretch();
    tabs_->addTab(home, "Overview");
    tabs_->tabBar()->setTabButton(0, QTabBar::RightSide, nullptr);
    tabs_->tabBar()->hide();
    workLayout->addWidget(tabs_, 1);
    split->setSizes({240, 920});
    split->setStretchFactor(1, 1);
    outer->addWidget(split, 1);
    setCentralWidget(central);
    connect(search_, &QLineEdit::textChanged, this, &Window::refresh);
    connect(hosts_, &QTreeWidget::itemSelectionChanged, this, [this] { select(); tabs_->setCurrentIndex(0); });
    connect(hosts_, &QTreeWidget::itemClicked, this, [this] { select(); tabs_->setCurrentIndex(0); });
    connect(hosts_, &QTreeWidget::itemDoubleClicked, this, [this] { connectHost(); });
    connect(add, &QPushButton::clicked, this, [this] { editHost(true); });
    connect(emptyAdd_, &QPushButton::clicked, this, [this] { editHost(true); });
    connect(clearSearch_, &QPushButton::clicked, search_, &QLineEdit::clear);
    connect(editAction, &QAction::triggered, this, [this] { editHost(false); });
    connect(connect_, &QPushButton::clicked, this, &Window::connectHost);
    connect(deleteAction, &QAction::triggered, this, &Window::removeHost);
    connect(deviceButton, &QPushButton::clicked, this, &Window::devices);
    connect(lockButton, &QPushButton::clicked, this, &Window::lockVault);
    connect(tabs_, &QTabWidget::tabCloseRequested, this, [this](int index) {
        if (index == 0) return;
        auto widget = tabs_->widget(index);
        auto terminal = qobject_cast<Terminal *>(widget);
        if (terminal && terminal->connected() && QMessageBox::question(this, "Close terminal", "Close this SSH session?", QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes) return;
        if (terminal) terminal->cancel();
        tabs_->removeTab(index);
        delete widget;
        if (tabs_->count() == 1) tabs_->tabBar()->hide();
    });
    connect(&vault_, &Vault::changed, this, &Window::refresh);
    auto addShortcut = new QShortcut(QKeySequence("Ctrl+N"), this);
    connect(addShortcut, &QShortcut::activated, this, [this] { editHost(true); });
    auto searchShortcut = new QShortcut(QKeySequence("Ctrl+F"), this);
    connect(searchShortcut, &QShortcut::activated, search_, qOverload<>(&QWidget::setFocus));
    refresh();
    if (vault_.hosts().isEmpty()) emptyAdd_->setFocus();
}

void Window::error(const std::exception &exception) { QMessageBox::critical(this, "Harbor", QString::fromUtf8(exception.what())); }

QJsonObject Window::selectedHost() const {
    return hostById(selected_);
}

QJsonObject Window::hostById(const QString &id) const {
    if (!vault_.unlocked() || id.isEmpty()) return {};
    for (const auto &host : vault_.hosts()) if (host.toObject().value("id").toString() == id) return host.toObject();
    return {};
}

void Window::refresh() {
    const auto current = selected_;
    hosts_->blockSignals(true);
    hosts_->clear();
    QHash<QString, QTreeWidgetItem *> groups;
    if (vault_.unlocked()) {
        const int count = vault_.hosts().size();
        status_->setText(count == 1 ? "1 host" : QString::number(count) + " hosts");
        const auto query = search_->text().trimmed();
        for (const auto &entry : vault_.hosts()) {
            const auto host = entry.toObject();
            if (!query.isEmpty() && !(host.value("name").toString() + " " + host.value("hostname").toString() + " " + host.value("group").toString()).contains(query, Qt::CaseInsensitive)) continue;
            const auto groupName = host.value("group").toString();
            if (!groupName.isEmpty() && !groups.contains(groupName)) {
                auto groupItem = new QTreeWidgetItem(hosts_, {groupName});
                groupItem->setFlags(groupItem->flags() & ~Qt::ItemIsSelectable);
                groupItem->setExpanded(true);
                groups[groupName] = groupItem;
            }
            auto item = groupName.isEmpty() ? new QTreeWidgetItem(hosts_, {host.value("name").toString()}) : new QTreeWidgetItem(groups[groupName], {host.value("name").toString()});
            item->setData(0, Qt::UserRole, host.value("id").toString());
            item->setToolTip(0, host.value("username").toString() + "@" + host.value("hostname").toString());
            item->setIcon(0, QIcon(serverImage()));
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
    const bool selected = !host.isEmpty();
    const bool first = vault_.unlocked() && vault_.hosts().isEmpty();
    const bool emptySearch = !first && !selected && !search_->text().trimmed().isEmpty() && hosts_->topLevelItemCount() == 0;
    connect_->setVisible(selected);
    hostMenu_->setVisible(selected);
    connectionHeading_->setVisible(selected);
    hostFields_->setVisible(selected);
    emptyAdd_->setVisible(first);
    add_->setVisible(!first);
    clearSearch_->setVisible(emptySearch);
    if (host.isEmpty()) {
        details_->show();
        title_->setText(first ? "Hosts" : emptySearch ? "No matching hosts" : "Hosts");
        details_->setText(first ? "Add a server with its address and SSH username." : emptySearch ? "Try a different name or clear your search." : "Select a host to see its connection details.");
        return;
    }
    title_->setText(host.value("name").toString());
    details_->clear();
    details_->hide();
    endpoint_->setText(host.value("hostname").toString());
    username_->setText(host.value("username").toString());
    port_->setText(QString::number(host.value("port").toInt()));
    const auto authentication = host.value("authType").toString();
    const auto authenticationLabel = authentication == "none" ? "Tailscale SSH · No password" : authentication == "key" ? "Private key authentication" : "Password authentication";
    authentication_->setText(authenticationLabel);
    const auto key = host.value("hostKey").toString().section(' ', 1, 1).toLatin1();
    fingerprint_->setText(key.isEmpty() ? "Verify on first connection" : "SHA256:" + QString::fromLatin1(QCryptographicHash::hash(QByteArray::fromBase64(key), QCryptographicHash::Sha256).toBase64(QByteArray::OmitTrailingEquals)));
    notes_->setText(host.value("notes").toString());
    qobject_cast<QGridLayout *>(hostFields_->layout())->itemAtPosition(5, 0)->widget()->setVisible(!notes_->text().isEmpty());
    notes_->setVisible(!notes_->text().isEmpty());
}

void Window::editHost(bool creating, const QString &id) {
    const auto original = creating ? QJsonObject() : id.isEmpty() ? selectedHost() : hostById(id);
    if (!creating && original.isEmpty()) return;
    QDialog dialog(this);
    dialog.setObjectName("hostEditor");
    dialog.setWindowTitle(creating ? "Add host" : "Edit host");
    dialog.resize(620, 560);
    dialog.setMinimumSize(500, 480);
    auto layout = new QVBoxLayout(&dialog);
    layout->setContentsMargins(28, 24, 28, 24);
    layout->setSpacing(12);
    auto heading = new QLabel(creating ? "Add a host" : "Edit host", &dialog);
    heading->setProperty("heading", true);
    layout->addWidget(heading);
    auto scroll = new QScrollArea(&dialog);
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    auto body = new QWidget(scroll);
    body->setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
    auto fields = new QVBoxLayout(body);
    fields->setContentsMargins(0, 12, 8, 12);
    fields->setSpacing(8);
    auto field = [&](QVBoxLayout *target, const QString &caption, QWidget *input) {
        auto label = new QLabel(caption, body);
        target->addWidget(label);
        target->addWidget(input);
        target->addSpacing(8);
    };
    auto endpointRow = new QWidget(body);
    auto endpointLayout = new QHBoxLayout(endpointRow);
    endpointLayout->setContentsMargins(0, 0, 0, 0);
    endpointLayout->setSpacing(12);
    auto addressColumn = new QVBoxLayout;
    addressColumn->setContentsMargins(0, 0, 0, 0);
    addressColumn->setSpacing(6);
    auto hostname = new QLineEdit(original.value("hostname").toString(), endpointRow);
    hostname->setObjectName("hostAddress");
    hostname->setPlaceholderText("server.example.com");
    hostname->setAccessibleName("Hostname or IP address");
    addressColumn->addWidget(new QLabel("Hostname or IP address", endpointRow));
    addressColumn->addWidget(hostname);
    endpointLayout->addLayout(addressColumn, 1);
    auto portColumn = new QVBoxLayout;
    portColumn->setContentsMargins(0, 0, 0, 0);
    portColumn->setSpacing(6);
    auto port = new QSpinBox(endpointRow);
    port->setObjectName("hostPort");
    port->setRange(1, 65535);
    port->setValue(original.value("port").toInt(22));
    port->setButtonSymbols(QAbstractSpinBox::NoButtons);
    port->setFixedWidth(110);
    portColumn->addWidget(new QLabel("SSH port", endpointRow));
    portColumn->addWidget(port);
    endpointLayout->addLayout(portColumn);
    fields->addWidget(endpointRow);
    fields->addSpacing(8);
    auto username = new QLineEdit(original.value("username").toString(), body);
    username->setObjectName("hostUsername");
    username->setPlaceholderText("Your SSH username");
    field(fields, "Username", username);
    auto auth = new QComboBox(body);
    auth->setObjectName("hostAuthentication");
    auth->addItem("Password", "password");
    auth->addItem("Private key", "key");
    auth->addItem("No password (Tailscale SSH)", "none");
    auth->setCurrentIndex(original.value("authType").toString() == "key" ? 1 : original.value("authType").toString() == "password" ? 0 : 2);
    field(fields, "Sign in with", auth);
    auto passwordBlock = new QWidget(body);
    auto passwordLayout = new QVBoxLayout(passwordBlock);
    passwordLayout->setContentsMargins(0, 0, 0, 0);
    auto password = new QLineEdit(original.value("password").toString(), passwordBlock);
    password->setObjectName("hostPassword");
    password->setEchoMode(QLineEdit::Password);
    password->setAccessibleName("SSH password");
    field(passwordLayout, "SSH password", password);
    fields->addWidget(passwordBlock);
    auto keyBlock = new QWidget(body);
    auto keyLayout = new QVBoxLayout(keyBlock);
    keyLayout->setContentsMargins(0, 0, 0, 0);
    auto keyButton = new QPushButton("Import file…", keyBlock);
    keyButton->setObjectName("importPrivateKey");
    auto pasteButton = new QPushButton("Paste key…", keyBlock);
    pasteButton->setObjectName("pastePrivateKey");
    keyLayout->addWidget(new QLabel("Private key", keyBlock));
    auto keyActions = new QHBoxLayout;
    keyActions->addWidget(keyButton);
    keyActions->addWidget(pasteButton);
    keyActions->addStretch();
    keyLayout->addLayout(keyActions);
    auto keyState = new QLabel(original.value("privateKey").toString().isEmpty() ? "No key added" : "Private key saved in encrypted workspace", keyBlock);
    keyState->setObjectName("privateKeyState");
    keyState->setProperty("muted", true);
    keyLayout->addWidget(keyState);
    auto passphrase = new QLineEdit(original.value("passphrase").toString(), keyBlock);
    passphrase->setObjectName("keyPassphrase");
    passphrase->setEchoMode(QLineEdit::Password);
    field(keyLayout, "Key passphrase, if needed", passphrase);
    fields->addWidget(keyBlock);
    auto noneHint = new QLabel("Tailscale SSH uses your tailnet identity. The destination must have Tailscale SSH enabled.", body);
    noneHint->setProperty("muted", true);
    noneHint->setWordWrap(true);
    fields->addWidget(noneHint);
    auto updateAuthentication = [&] { passwordBlock->setVisible(auth->currentData() == "password"); keyBlock->setVisible(auth->currentData() == "key"); noneHint->setVisible(auth->currentData() == "none"); };
    connect(auth, &QComboBox::currentIndexChanged, &dialog, updateAuthentication);
    updateAuthentication();
    auto more = new QToolButton(body);
    more->setObjectName("moreHostOptions");
    more->setText("More options");
    more->setCheckable(true);
    more->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    more->setArrowType(Qt::RightArrow);
    more->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    more->setMinimumHeight(34);
    more->setStyleSheet("QToolButton { color: #409cff; background: #303033; border: 1px solid #48484a; border-radius: 6px; padding: 7px 10px; text-align: left; font-weight: 600; }");
    fields->addWidget(more);
    auto options = new QWidget(body);
    auto optionLayout = new QVBoxLayout(options);
    optionLayout->setContentsMargins(0, 4, 0, 0);
    optionLayout->setSpacing(8);
    auto name = new QLineEdit(original.value("name").toString(), options);
    name->setObjectName("hostDisplayName");
    name->setPlaceholderText("Uses the hostname if empty");
    field(optionLayout, "Display name (optional)", name);
    auto group = new QLineEdit(original.value("group").toString(), options);
    group->setObjectName("hostGroup");
    group->setPlaceholderText("Optional folder");
    field(optionLayout, "Group", group);
    auto notes = new QPlainTextEdit(original.value("notes").toString(), options);
    notes->setObjectName("hostEditorNotes");
    notes->setMaximumHeight(100);
    field(optionLayout, "Notes", notes);
    auto identity = new QLabel("Server identity", options);
    identity->setProperty("section", true);
    optionLayout->addWidget(identity);
    auto identityHint = new QLabel("Compare the fingerprint with your server administrator before trusting a new server.", options);
    identityHint->setProperty("muted", true);
    identityHint->setWordWrap(true);
    optionLayout->addWidget(identityHint);
    auto verify = new QPushButton("Verify server key", options);
    verify->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    optionLayout->addWidget(verify);
    auto verified = new QLabel(original.value("hostKey").toString().isEmpty() ? "Not verified yet. Harbor will ask before the first connection." : "Server key verified for this address.", options);
    verified->setProperty("muted", true);
    verified->setProperty("small", true);
    verified->setWordWrap(true);
    optionLayout->addWidget(verified);
    fields->addWidget(options);
    fields->addStretch();
    const bool openOptions = !creating && (!original.value("group").toString().isEmpty() || !original.value("notes").toString().isEmpty() || original.value("port").toInt(22) != 22 || original.value("name").toString() != original.value("hostname").toString());
    more->setChecked(openOptions);
    options->setVisible(openOptions);
    more->setArrowType(openOptions ? Qt::DownArrow : Qt::RightArrow);
    connect(more, &QToolButton::toggled, options, &QWidget::setVisible);
    connect(more, &QToolButton::toggled, &dialog, [more, scroll, name](bool shown) {
        more->setArrowType(shown ? Qt::DownArrow : Qt::RightArrow);
        more->setText(shown ? "Fewer options" : "More options");
        if (shown) QTimer::singleShot(0, scroll, [scroll, name] { scroll->ensureWidgetVisible(name, 0, 48); });
    });
    scroll->setWidget(body);
    layout->addWidget(scroll, 1);
    auto message = new QLabel(&dialog);
    message->setObjectName("hostEditorMessage");
    message->setStyleSheet("color: #ff9b9b;");
    message->setWordWrap(true);
    message->hide();
    layout->addWidget(message);
    auto buttons = new QDialogButtonBox(QDialogButtonBox::Save | QDialogButtonBox::Cancel, &dialog);
    buttons->button(QDialogButtonBox::Save)->setText(creating ? "Save host" : "Save changes");
    buttons->button(QDialogButtonBox::Save)->setProperty("primary", true);
    buttons->button(QDialogButtonBox::Save)->setStyleSheet("background: #0068d9; border-color: #0068d9; color: #ffffff; font-weight: 600;");
    layout->addWidget(buttons);
    QString privateKey = original.value("privateKey").toString();
    QString hostKey = original.value("hostKey").toString();
    bool keyVerified = false;
    auto showError = [&](const QString &error) { message->setText(error); message->show(); };
    auto build = [&] {
        auto host = original;
        host["hostname"] = hostname->text().trimmed();
        host["name"] = name->text().trimmed().isEmpty() ? hostname->text().trimmed() : name->text().trimmed();
        host["port"] = port->value();
        host["username"] = username->text().trimmed();
        host["group"] = group->text().trimmed();
        host["authType"] = auth->currentData().toString();
        host["password"] = auth->currentData() == "password" ? password->text() : QString();
        host["privateKey"] = auth->currentData() == "key" ? privateKey : QString();
        host["passphrase"] = auth->currentData() == "key" ? passphrase->text() : QString();
        host["hostKey"] = hostKey;
        host["notes"] = notes->toPlainText();
        return host;
    };
    auto setKey = [&](const QByteArray &contents) {
        auto normalized = contents;
        normalized.replace("\r\n", "\n");
        if (privateKey.toUtf8() != normalized) passphrase->clear();
        privateKey = QString::fromUtf8(normalized);
        keyState->setText("Private key ready to save in encrypted workspace");
        message->hide();
    };
    auto acceptKey = [&](const QByteArray &contents) {
        const auto validation = validatePrivateKey(contents);
        if (!validation.isEmpty()) { showError(validation); return; }
        setKey(contents);
    };
    connect(keyButton, &QPushButton::clicked, &dialog, [&] {
        const auto path = QFileDialog::getOpenFileName(&dialog, "Import private key", {}, {}, nullptr, QFileDialog::DontUseNativeDialog);
        if (path.isEmpty()) return;
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) { showError("Could not read this private key."); return; }
        if (file.size() > 256 * 1024) { showError("This key is larger than 256 KiB."); return; }
        acceptKey(file.read(256 * 1024 + 1));
    });
    connect(pasteButton, &QPushButton::clicked, &dialog, [&] {
        QDialog paste(&dialog);
        paste.setObjectName("pasteKeyDialog");
        paste.setWindowTitle("Paste private key");
        paste.resize(580, 420);
        auto pasteLayout = new QVBoxLayout(&paste);
        pasteLayout->setContentsMargins(24, 24, 24, 20);
        pasteLayout->setSpacing(12);
        auto pasteHeading = new QLabel("Paste private key", &paste);
        pasteHeading->setProperty("section", true);
        pasteLayout->addWidget(pasteHeading);
        auto hint = new QLabel("Paste the complete OpenSSH or PEM private key. It will be saved only in your encrypted workspace.", &paste);
        hint->setProperty("muted", true);
        hint->setWordWrap(true);
        pasteLayout->addWidget(hint);
        auto editor = new QPlainTextEdit(&paste);
        editor->setObjectName("privateKeyPasteText");
        editor->setPlaceholderText("-----BEGIN OPENSSH PRIVATE KEY-----");
        editor->setAccessibleName("Private key text");
        pasteLayout->addWidget(editor, 1);
        auto pasteMessage = new QLabel(&paste);
        pasteMessage->setObjectName("privateKeyPasteMessage");
        pasteMessage->setStyleSheet("color: #ff9b9b;");
        pasteMessage->setWordWrap(true);
        pasteMessage->hide();
        pasteLayout->addWidget(pasteMessage);
        auto pasteButtons = new QDialogButtonBox(QDialogButtonBox::Save | QDialogButtonBox::Cancel, &paste);
        pasteButtons->button(QDialogButtonBox::Save)->setText("Use this key");
        pasteButtons->button(QDialogButtonBox::Save)->setProperty("primary", true);
        pasteButtons->button(QDialogButtonBox::Save)->setStyleSheet("background: #0068d9; border-color: #0068d9; color: #ffffff; font-weight: 600;");
        pasteLayout->addWidget(pasteButtons);
        connect(pasteButtons, &QDialogButtonBox::accepted, &paste, [&] {
            const auto contents = editor->toPlainText().toUtf8();
            const auto validation = validatePrivateKey(contents);
            if (!validation.isEmpty()) { pasteMessage->setText(validation); pasteMessage->show(); return; }
            setKey(contents);
            paste.accept();
        });
        connect(pasteButtons, &QDialogButtonBox::rejected, &paste, &QDialog::reject);
        editor->setFocus();
        paste.exec();
        editor->clear();
    });
    connect(verify, &QPushButton::clicked, &dialog, [&] {
        const auto validation = validateHostEndpoint(hostname->text().trimmed(), port->value());
        if (!validation.isEmpty()) { showError(validation); return; }
        auto host = build();
        if (Terminal::trustHost(host, &dialog)) {
            hostKey = host.value("hostKey").toString();
            keyVerified = true;
            verified->setText("Server key verified for this address.");
            message->hide();
        }
    });
    auto endpointChanged = [&] { hostKey.clear(); keyVerified = false; verified->setText("Address changed. Verify the new server key before connecting."); };
    connect(hostname, &QLineEdit::textChanged, &dialog, endpointChanged);
    connect(port, &QSpinBox::valueChanged, &dialog, endpointChanged);
    connect(&vault_, &Vault::changed, &dialog, [&] { if (!vault_.unlocked()) dialog.reject(); });
    connect(buttons, &QDialogButtonBox::accepted, &dialog, [&] {
        const auto endpointError = validateHostEndpoint(hostname->text().trimmed(), port->value());
        if (!endpointError.isEmpty()) { showError(endpointError); return; }
        try {
            auto host = build();
            if (host.value("authType") != "key") {
                vault_.upsert(host, keyVerified);
                selected_ = creating ? vault_.hosts().last().toObject().value("id").toString() : original.value("id").toString();
                dialog.accept();
                return;
            }
            auto keyBytes = host.value("privateKey").toString().toUtf8();
            auto passphraseBytes = host.value("passphrase").toString().toUtf8();
            const auto previousState = keyState->text();
            keyState->setText("Validating private key…");
            message->hide();
            scroll->setEnabled(false);
            buttons->button(QDialogButtonBox::Save)->setEnabled(false);
            auto result = std::make_shared<QString>();
            auto worker = QThread::create([keyBytes = std::move(keyBytes), passphraseBytes = std::move(passphraseBytes), result]() mutable {
                *result = validatePrivateKey(keyBytes, passphraseBytes, true);
                wipe(keyBytes);
                wipe(passphraseBytes);
            });
            connect(worker, &QThread::finished, &dialog, [&, host, verified = keyVerified, result, previousState] {
                scroll->setEnabled(true);
                buttons->button(QDialogButtonBox::Save)->setEnabled(true);
                keyState->setText(previousState);
                if (!result->isEmpty()) { showError(*result); return; }
                if (!vault_.unlocked()) return;
                try {
                    vault_.upsert(host, verified);
                    selected_ = creating ? vault_.hosts().last().toObject().value("id").toString() : original.value("id").toString();
                    dialog.accept();
                } catch (const std::exception &exception) { showError(exception.what()); }
            });
            connect(worker, &QThread::finished, worker, &QObject::deleteLater);
            worker->start();
        } catch (const std::exception &exception) { showError(exception.what()); }
    });
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    if (dialog.exec() == QDialog::Accepted) { refresh(); if (id.isEmpty()) tabs_->setCurrentIndex(0); }
}

void Window::connectHost() {
    openHost(selectedHost());
}

void Window::openHost(const QJsonObject &host) {
    if (host.isEmpty()) return;
    try {
        auto terminal = new Terminal(host, tabs_);
        const auto index = tabs_->addTab(terminal, host.value("name").toString());
        tabs_->tabBar()->show();
        tabs_->setCurrentIndex(index);
        const auto id = host.value("id").toString();
        auto closeAttempt = [this, terminal] {
            const int i = tabs_->indexOf(terminal);
            if (i < 0) return;
            terminal->cancel();
            tabs_->removeTab(i);
            terminal->deleteLater();
            if (tabs_->count() == 1) { tabs_->tabBar()->hide(); tabs_->setCurrentIndex(0); }
        };
        connect(terminal, &Terminal::trustRequested, this, [this, terminal, host, id](const QString &key) {
            try {
                auto latest = hostById(id);
                if (latest.isEmpty() || latest.value("hostname") != host.value("hostname") || latest.value("port") != host.value("port")) { terminal->showFailure("This host changed while its key was being checked. Retry with the latest settings."); return; }
                latest["hostKey"] = key;
                vault_.upsert(latest, true);
                terminal->acceptHostKey(key);
            } catch (const std::exception &exception) { terminal->showFailure(QString::fromUtf8(exception.what())); }
        });
        connect(terminal, &Terminal::retryRequested, this, [this, closeAttempt, id] { closeAttempt(); openHost(hostById(id)); });
        connect(terminal, &Terminal::editRequested, this, [this, id] { editHost(false, id); });
        connect(terminal, &Terminal::cancelRequested, this, closeAttempt);
        connect(terminal, &Terminal::failed, this, [this, terminal] { const int i = tabs_->indexOf(terminal); if (i >= 0) tabs_->setTabText(i, tabs_->tabText(i) + " (failed)"); });
        connect(terminal, &Terminal::shellEnded, this, closeAttempt);
        QTimer::singleShot(0, terminal, [terminal] { terminal->start(); });
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
        else if (!sync_.start()) QMessageBox::warning(this, "Sync unavailable", "Local sync port 45873 is in use. Close the service using it, then try again.");
    } catch (const std::exception &exception) { error(exception); }
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
    if (!sync_.running()) sharing(true);
    if (!sync_.running()) return;
    QDialog dialog(this);
    dialog.setObjectName("pairingDialog");
    dialog.setWindowTitle("Pair Android");
    dialog.resize(560, 690);
    dialog.setMinimumSize(460, 520);
    auto layout = new QVBoxLayout(&dialog);
    layout->setContentsMargins(32, 28, 32, 28);
    layout->setSpacing(12);
    auto heading = new QLabel("Pair Android", &dialog);
    heading->setProperty("heading", true);
    layout->addWidget(heading);
    auto intro = new QLabel("Open Harbor on your phone and scan this code. Keep both devices on the same network or private VPN.", &dialog);
    intro->setProperty("muted", true);
    intro->setWordWrap(true);
    layout->addWidget(intro);
    auto pages = new QStackedWidget(&dialog);
    layout->addWidget(pages, 1);
    auto scanPage = new QWidget(pages);
    auto scanLayout = new QVBoxLayout(scanPage);
    scanLayout->setContentsMargins(0, 12, 0, 0);
    scanLayout->setSpacing(12);
    auto qr = new QLabel(scanPage);
    qr->setObjectName("pairingQr");
    qr->setAccessibleName("Pairing QR code");
    qr->setAlignment(Qt::AlignCenter);
    qr->setMinimumSize(320, 320);
    scanLayout->addWidget(qr);
    auto networkName = new QLabel(scanPage);
    networkName->setAlignment(Qt::AlignCenter);
    networkName->setProperty("muted", true);
    scanLayout->addWidget(networkName);
    auto optionsButton = new QPushButton("Network options", scanPage);
    optionsButton->setObjectName("pairNetworkOptions");
    optionsButton->setStyleSheet("QPushButton { color: #409cff; background: transparent; border: none; }");
    scanLayout->addWidget(optionsButton, 0, Qt::AlignCenter);
    scanLayout->addStretch();
    pages->addWidget(scanPage);
    auto options = new QWidget(pages);
    auto optionsLayout = new QVBoxLayout(options);
    optionsLayout->setContentsMargins(0, 28, 0, 0);
    optionsLayout->setSpacing(14);
    auto back = new QPushButton("← Back to code", options);
    back->setObjectName("pairNetworkBack");
    back->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    optionsLayout->addWidget(back);
    auto networkHeading = new QLabel("Choose a network", options);
    networkHeading->setProperty("section", true);
    optionsLayout->addWidget(networkHeading);
    auto optionHint = new QLabel("If your phone cannot connect, choose the network it shares with this computer.", options);
    optionHint->setProperty("muted", true);
    optionHint->setWordWrap(true);
    optionsLayout->addWidget(optionHint);
    auto networkChoice = new QComboBox(options);
    networkChoice->setObjectName("pairingNetwork");
    networkChoice->setAccessibleName("Network for pairing");
    optionsLayout->addWidget(networkChoice);
    auto copy = new QPushButton("Copy pairing details", options);
    copy->setObjectName("copyPairingDetails");
    copy->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    optionsLayout->addWidget(copy);
    optionsLayout->addStretch();
    auto comparePage = new QWidget(pages);
    auto compareLayout = new QVBoxLayout(comparePage);
    compareLayout->setContentsMargins(0, 28, 0, 0);
    compareLayout->setSpacing(20);
    auto compareHeading = new QLabel("Compare this code", comparePage);
    compareHeading->setProperty("section", true);
    compareLayout->addWidget(compareHeading);
    auto phoneName = new QLabel(comparePage);
    phoneName->setTextFormat(Qt::PlainText);
    phoneName->setProperty("muted", true);
    phoneName->setWordWrap(true);
    compareLayout->addWidget(phoneName);
    auto code = new QLabel(comparePage);
    code->setObjectName("pairingCode");
    code->setStyleSheet("font-family: monospace; font-size: 40px; font-weight: 600; color: #f2f2f2; background: #303033; border-radius: 12px; padding: 26px;");
    code->setAlignment(Qt::AlignCenter);
    compareLayout->addWidget(code);
    auto compareHint = new QLabel("Approve only if the same code appears on your phone. A paired phone receives your saved SSH credentials.", comparePage);
    compareHint->setProperty("muted", true);
    compareHint->setWordWrap(true);
    compareLayout->addWidget(compareHint);
    auto compareActions = new QHBoxLayout;
    auto deny = new QPushButton("Decline", comparePage);
    auto approve = new QPushButton("Approve device", comparePage);
    approve->setObjectName("approvePairing");
    approve->setProperty("primary", true);
    compareActions->addWidget(deny);
    compareActions->addWidget(approve);
    compareActions->addStretch();
    compareLayout->addLayout(compareActions);
    compareLayout->addStretch();
    pages->addWidget(comparePage);
    auto pairedPage = new QWidget(pages);
    auto pairedLayout = new QVBoxLayout(pairedPage);
    pairedLayout->setContentsMargins(0, 52, 0, 0);
    auto pairedHeading = new QLabel("Device approved", pairedPage);
    pairedHeading->setProperty("section", true);
    pairedLayout->addWidget(pairedHeading);
    auto pairedHint = new QLabel("Your phone can now finish pairing and sync its copy of this workspace.", pairedPage);
    pairedHint->setProperty("muted", true);
    pairedHint->setWordWrap(true);
    pairedLayout->addWidget(pairedHint);
    pairedLayout->addStretch();
    pages->addWidget(pairedPage);
    auto failedPage = new QWidget(pages);
    auto failedLayout = new QVBoxLayout(failedPage);
    failedLayout->setContentsMargins(0, 52, 0, 0);
    failedLayout->setSpacing(12);
    auto failureHeading = new QLabel(failedPage);
    failureHeading->setProperty("section", true);
    failedLayout->addWidget(failureHeading);
    auto failureDetail = new QLabel(failedPage);
    failureDetail->setProperty("muted", true);
    failureDetail->setWordWrap(true);
    failedLayout->addWidget(failureDetail);
    auto retry = new QPushButton("Generate new code", failedPage);
    retry->setProperty("primary", true);
    retry->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    failedLayout->addWidget(retry);
    failedLayout->addStretch();
    pages->addWidget(failedPage);
    pages->addWidget(options);
    auto remainingLabel = new QLabel(&dialog);
    remainingLabel->setAlignment(Qt::AlignCenter);
    remainingLabel->setProperty("muted", true);
    remainingLabel->setProperty("small", true);
    layout->addWidget(remainingLabel);
    auto footer = new QDialogButtonBox(QDialogButtonBox::Close, &dialog);
    layout->addWidget(footer);
    connect(footer, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    connect(optionsButton, &QPushButton::clicked, &dialog, [pages, intro] { intro->setText("Choose the address your phone can reach."); pages->setCurrentIndex(4); });
    connect(back, &QPushButton::clicked, &dialog, [pages, intro] { intro->setText("Open Harbor on your phone and scan this code. Keep both devices on the same network or private VPN."); pages->setCurrentIndex(0); });
    QTimer expiry(&dialog);
    expiry.setSingleShot(true);
    QTimer ticker(&dialog);
    ticker.setInterval(1000);
    QString invitation;
    QString pendingDevice;
    qint64 expiresAt = 0;
    QList<PairingNetwork> networks;
    auto updateCountdown = [&] {
        const auto seconds = qMax<qint64>(0, expiresAt - QDateTime::currentSecsSinceEpoch());
        remainingLabel->setText(QString("Code expires in %1:%2").arg(seconds / 60).arg(seconds % 60, 2, 10, QChar('0')));
    };
    connect(&ticker, &QTimer::timeout, &dialog, updateCountdown);
    auto fail = [&](const QString &title, const QString &detail, const QString &action) {
        ticker.stop();
        remainingLabel->hide();
        intro->setText("Pairing needs a new code to continue.");
        failureHeading->setText(title);
        failureDetail->setText(detail);
        retry->setText(action);
        pages->setCurrentIndex(3);
    };
    auto generate = [&] {
        expiry.stop();
        if (networkChoice->currentIndex() < 0 || networkChoice->currentIndex() >= networks.size()) {
            sync_.cancelInvite(true);
            invitation.clear();
            fail("No local network found", "Connect this computer to Wi-Fi, Ethernet, or a private VPN, then try again.", "Check again");
            return;
        }
        try {
            const auto &network = networks[networkChoice->currentIndex()];
            const auto address = network.address.toString();
            const auto origin = "http://" + (network.address.protocol() == QAbstractSocket::IPv6Protocol ? "[" + address + "]" : address) + ":" + QString::number(sync_.port());
            const auto payload = sync_.invite(origin);
            invitation = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));
            expiresAt = payload.value("expiresAt").toInteger();
            qr->setPixmap(pairingQr(invitation.toUtf8()));
            networkName->setText("Using " + network.label);
            pendingDevice.clear();
            expiry.start(qMax<qint64>(1, (expiresAt - QDateTime::currentSecsSinceEpoch()) * 1000));
            updateCountdown();
            remainingLabel->show();
            ticker.start();
            intro->setText("Open Harbor on your phone and scan this code. Keep both devices on the same network or private VPN.");
            pages->setCurrentIndex(0);
        } catch (const std::exception &exception) {
            sync_.cancelInvite(true);
            invitation.clear();
            fail("Could not create a code", exception.what(), "Try again");
        }
    };
    auto refreshNetworks = [&] {
        networks = pairingNetworks();
        networkChoice->blockSignals(true);
        networkChoice->clear();
        for (const auto &network : networks) networkChoice->addItem(network.label + " · " + network.address.toString(), network.address.toString());
        networkChoice->blockSignals(false);
        generate();
    };
    connect(networkChoice, &QComboBox::currentIndexChanged, &dialog, [&](int) { generate(); });
    connect(retry, &QPushButton::clicked, &dialog, refreshNetworks);
    connect(copy, &QPushButton::clicked, &dialog, [&] { QApplication::clipboard()->setText(invitation); });
    connect(&expiry, &QTimer::timeout, &dialog, [&] {
        if (pages->currentIndex() == 2) return;
        sync_.cancelInvite(true);
        qr->clear();
        invitation.clear();
        fail("Code expired", "Pairing codes expire after five minutes. Generate a new code to continue.", "Generate new code");
    });
    connect(&sync_, &SyncServer::pairingRequested, &dialog, [&](const QString &id, const QString &name, const QString &comparison) {
        if ((pages->currentIndex() != 0 && pages->currentIndex() != 4) || QDateTime::currentSecsSinceEpoch() >= expiresAt) return;
        pendingDevice = id;
        phoneName->setText(name + " is requesting access. Check the code on both screens.");
        code->setText(comparison);
        intro->setText("Confirm that the same six digits appear on your phone.");
        pages->setCurrentIndex(1);
    });
    connect(approve, &QPushButton::clicked, &dialog, [&] {
        if (pendingDevice.isEmpty() || QDateTime::currentSecsSinceEpoch() >= expiresAt) {
            fail("Code expired", "Generate a new code and try again.", "Generate new code");
            return;
        }
        try {
            sync_.approve(pendingDevice);
            bool paired = false;
            for (const auto &entry : sync_.devices()) if (entry.toObject().value("id").toString() == pendingDevice) paired = true;
            if (!paired) { fail("Could not approve device", "Generate a new code and try again.", "Generate new code"); return; }
            expiry.stop();
            ticker.stop();
            remainingLabel->hide();
            intro->setText("Your phone can now finish pairing.");
            pages->setCurrentIndex(2);
        } catch (const std::exception &exception) { fail("Could not approve device", exception.what(), "Generate new code"); }
    });
    connect(deny, &QPushButton::clicked, &dialog, [&] {
        sync_.deny(pendingDevice);
        expiry.stop();
        fail("Pairing declined", "This request was not approved. Generate a new code when you are ready.", "Generate new code");
    });
    refreshNetworks();
    dialog.exec();
    sync_.cancelInvite(true);
    if (!invitation.isEmpty() && QApplication::clipboard()->text() == invitation) QApplication::clipboard()->clear();
}

void Window::devices() {
    QDialog dialog(this);
    dialog.setObjectName("devicesDialog");
    dialog.setWindowTitle("Devices");
    dialog.resize(540, 500);
    dialog.setMinimumSize(460, 400);
    auto layout = new QVBoxLayout(&dialog);
    layout->setContentsMargins(28, 28, 28, 24);
    layout->setSpacing(12);
    auto heading = new QLabel("Devices", &dialog);
    heading->setProperty("heading", true);
    layout->addWidget(heading);
    auto description = new QLabel("Pair Harbor on Android to carry a read-only copy of your SSH hosts.", &dialog);
    description->setProperty("muted", true);
    description->setWordWrap(true);
    layout->addWidget(description);
    auto list = new QListWidget(&dialog);
    list->setObjectName("pairedDevices");
    list->setStyleSheet("QListWidget { background: #303033; border: 1px solid #48484a; border-radius: 8px; padding: 8px; } QListWidget::item { padding: 12px; border-radius: 6px; } QListWidget::item:selected { background: #3a3a3c; }");
    layout->addWidget(list, 1);
    auto empty = new QWidget(&dialog);
    auto emptyLayout = new QVBoxLayout(empty);
    emptyLayout->setContentsMargins(0, 16, 0, 12);
    emptyLayout->setSpacing(12);
    auto icon = new QLabel(empty);
    icon->setPixmap(phoneImage(62));
    emptyLayout->addWidget(icon);
    auto emptyHeading = new QLabel("Bring your hosts to Android", empty);
    emptyHeading->setProperty("section", true);
    emptyLayout->addWidget(emptyHeading);
    auto emptyDescription = new QLabel("Scan a code on your phone to pair it with this workspace.", empty);
    emptyDescription->setProperty("muted", true);
    emptyDescription->setWordWrap(true);
    emptyLayout->addWidget(emptyDescription);
    layout->addWidget(empty);
    auto actions = new QHBoxLayout;
    auto pairButton = new QPushButton("Pair Android", &dialog);
    pairButton->setObjectName("pairAndroid");
    pairButton->setProperty("primary", true);
    actions->addWidget(pairButton);
    auto revoke = new QPushButton("Revoke device", &dialog);
    actions->addWidget(revoke);
    actions->addStretch();
    layout->addLayout(actions);
    layout->addStretch();
    auto syncRow = new QHBoxLayout;
    auto syncLabel = new QLabel("Local sync", &dialog);
    syncLabel->setProperty("muted", true);
    syncRow->addWidget(syncLabel);
    syncRow->addStretch();
    auto syncButton = new QPushButton(&dialog);
    syncButton->setObjectName("syncToggle");
    syncButton->setStyleSheet("QPushButton { background: transparent; border: none; color: #409cff; }");
    auto syncText = [&] { syncButton->setText(sync_.running() ? "On · Turn off" : "Off · Turn on"); };
    syncText();
    syncRow->addWidget(syncButton);
    layout->addLayout(syncRow);
    auto close = new QDialogButtonBox(QDialogButtonBox::Close, &dialog);
    layout->addWidget(close);
    auto populate = [&] {
        list->clear();
        for (const auto &entry : sync_.devices()) {
            const auto device = entry.toObject();
            auto item = new QListWidgetItem(device.value("name").toString(), list);
            item->setData(Qt::UserRole, device.value("id").toString());
        }
        const bool hasDevices = list->count() != 0;
        empty->setVisible(!hasDevices);
        list->setVisible(hasDevices);
        description->setVisible(hasDevices);
        revoke->setVisible(hasDevices);
        revoke->setEnabled(false);
    };
    populate();
    connect(list, &QListWidget::itemSelectionChanged, &dialog, [=] { revoke->setEnabled(list->currentItem() != nullptr); });
    connect(syncButton, &QPushButton::clicked, &dialog, [&] { sharing(!sync_.running()); syncText(); });
    connect(close, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    connect(pairButton, &QPushButton::clicked, &dialog, [&] { dialog.accept(); QTimer::singleShot(0, this, &Window::pair); });
    connect(revoke, &QPushButton::clicked, &dialog, [&] {
        const auto item = list->currentItem();
        if (!item) return;
        if (QMessageBox::question(&dialog, "Revoke device", "Stop " + item->text() + " from syncing this vault? An offline copy may still have saved credentials. Rotate those credentials on your servers if needed.", QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes) return;
        try { sync_.revoke(item->data(Qt::UserRole).toString()); populate(); } catch (const std::exception &exception) { error(exception); }
    });
    dialog.exec();
}

void Window::lockVault() {
    sync_.stop();
    while (tabs_->count() > 1) { auto widget = tabs_->widget(1); tabs_->removeTab(1); delete widget; }
    tabs_->tabBar()->hide();
    selected_.clear();
    vault_.lock();
    if (!unlockVault(vault_, this)) { close(); return; }
    refresh();
    if (vault_.hosts().isEmpty()) emptyAdd_->setFocus();
}
