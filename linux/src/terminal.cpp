#include "terminal.h"
#include "vault.h"
#include <qtermwidget6/qtermwidget.h>
#include <QApplication>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QStackedWidget>
#include <QLabel>
#include <QPushButton>
#include <QProgressBar>
#include <QScrollArea>
#include <QLocalSocket>
#include <QProcess>
#include <QProcessEnvironment>
#include <QFile>
#include <QDir>
#include <QFontDatabase>
#include <QMessageBox>
#include <QCryptographicHash>
#include <QTimer>
#include <QStandardPaths>
#include <QFileInfo>
#include <QJsonDocument>
#include <stdexcept>
#include <unistd.h>
#include <sys/socket.h>

static QString hostKeyName(const QJsonObject &host) {
    const auto address = host.value("hostname").toString();
    const auto port = host.value("port").toInt();
    return port == 22 ? address : QString("[%1]:%2").arg(address).arg(port);
}

bool Terminal::trustHost(QJsonObject &host, QWidget *parent) {
    QProcess scan;
    scan.start("ssh-keyscan", {"-T", "5", "-p", QString::number(host.value("port").toInt()), "-t", "ed25519,ecdsa,rsa", host.value("hostname").toString()});
    if (!scan.waitForFinished(10000)) { scan.kill(); scan.waitForFinished(); QMessageBox::warning(parent, "Host verification", "Could not retrieve the host key. Check the address and network, then try again."); return false; }
    QByteArray selected;
    for (const auto &line : scan.readAllStandardOutput().split('\n')) {
        const auto parts = line.simplified().split(' ');
        if (parts.size() != 3 || parts[0] != hostKeyName(host).toUtf8()) continue;
        if (QByteArray::fromBase64(parts[2], QByteArray::AbortOnBase64DecodingErrors).isEmpty()) continue;
        selected = parts[1] + ' ' + parts[2];
        if (parts[1] == "ssh-ed25519") break;
    }
    if (selected.isEmpty()) { QMessageBox::warning(parent, "Host verification", "The server did not provide a supported host key."); return false; }
    const auto key = QByteArray::fromBase64(selected.split(' ')[1]);
    const auto fingerprint = QString::fromLatin1(QCryptographicHash::hash(key, QCryptographicHash::Sha256).toBase64(QByteArray::OmitTrailingEquals));
    const auto result = QMessageBox::question(parent, "Verify this server", "Before connecting to " + host.value("hostname").toString() + ", compare this fingerprint with the server administrator.\n\n" + QString::fromLatin1(selected.split(' ')[0]) + "\nSHA256:" + fingerprint + "\n\nTrust this key?", QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
    if (result != QMessageBox::Yes) return false;
    host["hostKey"] = QString::fromLatin1(selected);
    return true;
}

Terminal::Terminal(const QJsonObject &host, QWidget *parent) : QWidget(parent), host_(host), terminal_(new QTermWidget(0, this)), temporary_(std::make_unique<QTemporaryDir>(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/harbor-XXXXXX")) {
    if (!temporary_->isValid() || !QFile::setPermissions(temporary_->path(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner)) throw std::runtime_error("Cannot create a private session directory");
    if (!validateHost(host).isEmpty()) throw std::runtime_error("Check this host's address and sign-in settings");
    auto layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    pages_ = new QStackedWidget(this);
    layout->addWidget(pages_);
    auto connectionPage = new QWidget(pages_);
    auto pageLayout = new QVBoxLayout(connectionPage);
    pageLayout->setContentsMargins(0, 0, 0, 0);
    pageLayout->setSpacing(0);
    auto panel = new QWidget(connectionPage);
    panel->setObjectName("connectionPanel");
    auto content = new QVBoxLayout(panel);
    content->setContentsMargins(52, 36, 52, 24);
    content->setSpacing(16);
    heading_ = new QLabel("Connecting to " + host.value("name").toString(), panel);
    heading_->setObjectName("connectionHeading");
    heading_->setProperty("heading", true);
    heading_->setWordWrap(true);
    content->addWidget(heading_);
    auto endpoint = new QLabel(host.value("username").toString() + "@" + host.value("hostname").toString() + ":" + QString::number(host.value("port").toInt()), panel);
    endpoint->setProperty("endpoint", true);
    endpoint->setWordWrap(true);
    endpoint->setTextInteractionFlags(Qt::TextSelectableByMouse);
    content->addWidget(endpoint);
    detail_ = new QLabel("Opening a secure SSH session.", panel);
    detail_->setObjectName("connectionDetail");
    detail_->setProperty("muted", true);
    detail_->setWordWrap(true);
    detail_->setMaximumWidth(580);
    content->addWidget(detail_);
    fingerprint_ = new QLabel(panel);
    fingerprint_->setObjectName("connectionFingerprint");
    fingerprint_->setTextInteractionFlags(Qt::TextSelectableByMouse);
    fingerprint_->setWordWrap(true);
    fingerprint_->setMaximumWidth(580);
    fingerprint_->hide();
    content->addWidget(fingerprint_);
    content->addSpacing(20);
    const QStringList names{"Reaching server", "Verifying server identity", "Signing in", "Opening shell"};
    for (int i = 0; i < 4; ++i) {
        steps_[i] = new QLabel(panel);
        steps_[i]->setObjectName(QString("connectionStep%1").arg(i));
        content->addWidget(steps_[i]);
    }
    progress_ = new QProgressBar(panel);
    progress_->setRange(0, 0);
    progress_->setTextVisible(false);
    progress_->setMaximumWidth(340);
    progress_->setFixedHeight(4);
    progress_->setStyleSheet("QProgressBar { border: none; border-radius: 2px; background: #343844; } QProgressBar::chunk { background: #a8b8fa; }");
    content->addSpacing(12);
    content->addWidget(progress_);
    messageBox_ = new QWidget(panel);
    messageBox_->setObjectName("serverMessageBox");
    messageBox_->setStyleSheet("QWidget#serverMessageBox { background: #272b35; border: 1px solid #414651; border-radius: 8px; }");
    auto messageLayout = new QVBoxLayout(messageBox_);
    messageLayout->setContentsMargins(14, 12, 14, 12);
    auto messageHeading = new QLabel("Server message", messageBox_);
    messageHeading->setStyleSheet("font-weight: 600; color: #f1f2f6;");
    messageLayout->addWidget(messageHeading);
    message_ = new QLabel(messageBox_);
    message_->setObjectName("connectionServerMessage");
    message_->setTextFormat(Qt::PlainText);
    message_->setTextInteractionFlags(Qt::TextSelectableByMouse);
    message_->setWordWrap(true);
    message_->setStyleSheet("color: #c6cbda; font-family: monospace;");
    messageLayout->addWidget(message_);
    messageBox_->hide();
    content->addWidget(messageBox_);
    content->addStretch();
    auto footer = new QWidget(connectionPage);
    auto actions = new QHBoxLayout(footer);
    actions->setContentsMargins(52, 12, 52, 22);
    trust_ = new QPushButton("Trust server key", footer);
    trust_->setObjectName("trustServerKey");
    trust_->setProperty("primary", true);
    trust_->hide();
    actions->addWidget(trust_);
    retry_ = new QPushButton("Retry", footer);
    retry_->setObjectName("retryConnection");
    retry_->setProperty("primary", true);
    retry_->hide();
    actions->addWidget(retry_);
    edit_ = new QPushButton("Edit Config", footer);
    edit_->setObjectName("editConnection");
    edit_->hide();
    actions->addWidget(edit_);
    cancel_ = new QPushButton("Cancel", footer);
    cancel_->setObjectName("cancelConnection");
    actions->addWidget(cancel_);
    actions->addStretch();
    auto scroll = new QScrollArea(connectionPage);
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    scroll->setWidget(panel);
    pageLayout->addWidget(scroll, 1);
    pageLayout->addWidget(footer);
    pages_->addWidget(connectionPage);
    pages_->addWidget(terminal_);
    pages_->setCurrentIndex(0);
    for (int i = 0; i < 4; ++i) steps_[i]->setText((i == 0 ? "◌  " : "○  ") + names[i]);
    steps_[0]->setStyleSheet("color: #a8b8fa; font-weight: 600;");
    for (int i = 1; i < 4; ++i) steps_[i]->setStyleSheet("color: #777d8b;");
    connect(trust_, &QPushButton::clicked, this, [this] { emit trustRequested(host_.value("hostKey").toString()); });
    connect(retry_, &QPushButton::clicked, this, &Terminal::retryRequested);
    connect(edit_, &QPushButton::clicked, this, &Terminal::editRequested);
    connect(cancel_, &QPushButton::clicked, this, &Terminal::cancelRequested);
    connect(terminal_, &QTermWidget::receivedData, this, &Terminal::appendServerMessage);
    diagnostics_ = new QTimer(this);
    diagnostics_->setInterval(80);
    connect(diagnostics_, &QTimer::timeout, this, &Terminal::readDiagnostics);
}

void Terminal::startSsh() {
    try {
    const auto &host = host_;
    started_ = true;
    const auto auth = host.value("authType").toString();
    auto environment = QProcessEnvironment::systemEnvironment();
    if (auth != "none") {
        capability_ = randomBytes(32).toBase64();
        password_ = auth == "password" ? host.value("password").toString().toUtf8() : QByteArray();
        passphrase_ = auth == "key" ? host.value("passphrase").toString().toUtf8() : QByteArray();
        askpass_.setSocketOptions(QLocalServer::UserAccessOption);
        const auto socketName = temporary_->path() + "/askpass";
        if (!askpass_.listen(socketName)) throw std::runtime_error("Cannot open credential channel");
        connect(&askpass_, &QLocalServer::newConnection, this, [this] {
            while (auto socket = askpass_.nextPendingConnection()) {
                struct ucred peer{};
                socklen_t size = sizeof(peer);
                if (getsockopt(socket->socketDescriptor(), SOL_SOCKET, SO_PEERCRED, &peer, &size) != 0 || peer.uid != getuid() || QFileInfo(QString("/proc/%1/exe").arg(peer.pid)).canonicalFilePath() != QFileInfo(QApplication::applicationDirPath() + "/harbor-askpass").canonicalFilePath()) { socket->abort(); socket->deleteLater(); continue; }
                QFile process(QString("/proc/%1/status").arg(peer.pid));
                bool child = false;
                if (process.open(QIODevice::ReadOnly)) for (const auto &line : process.readAll().split('\n')) if (line.startsWith("PPid:")) child = line.mid(5).trimmed().toInt() == terminal_->getShellPID();
                if (!child) { socket->abort(); socket->deleteLater(); continue; }
                socket->setParent(this);
                auto buffer = std::make_shared<QByteArray>();
                connect(socket, &QLocalSocket::readyRead, this, [this, socket, buffer] {
                    *buffer += socket->readAll();
                    if (buffer->size() > 4096) { socket->abort(); return; }
                    if (!buffer->contains('\n')) return;
                    const auto request = QJsonDocument::fromJson(buffer->split('\n').first()).object();
                    if (request.value("capability").toString().toLatin1() != capability_) { socket->abort(); return; }
                    const auto prompt = request.value("prompt").toString().toLower();
                    QByteArray answer;
                    if (prompt.contains("passphrase")) answer = passphrase_;
                    else if (prompt.contains("password")) answer = password_;
                    socket->write(answer.toBase64() + '\n');
                    socket->flush();
                    wipe(answer);
                    socket->disconnectFromServer();
                });
                connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
                QTimer::singleShot(10000, socket, [socket] { socket->abort(); socket->deleteLater(); });
            }
        });
        const auto helper = QApplication::applicationDirPath() + "/harbor-askpass";
        if (!QFile::exists(helper)) throw std::runtime_error("The harbor-askpass helper is missing");
        environment.insert("SSH_ASKPASS", helper);
        environment.insert("SSH_ASKPASS_REQUIRE", "force");
        environment.insert("HARBOR_ASKPASS_SOCKET", socketName);
        environment.insert("HARBOR_ASKPASS_CAPABILITY", QString::fromLatin1(capability_));
        environment.insert("DISPLAY", environment.value("DISPLAY", ":0"));
    } else {
        for (const auto &name : {"SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "HARBOR_ASKPASS_SOCKET", "HARBOR_ASKPASS_CAPABILITY", "SSH_AUTH_SOCK", "SSH_AGENT_PID"}) environment.remove(name);
    }
    QFile known(temporary_->path() + "/known_hosts");
    const auto pinned = hostKeyName(host).toUtf8() + ' ' + host.value("hostKey").toString().toUtf8() + '\n';
    if (!known.open(QIODevice::WriteOnly) || !known.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner) || known.write(pinned) != pinned.size() || !known.flush()) throw std::runtime_error("Cannot prepare pinned server key");
    QFile log(temporary_->path() + "/ssh.log");
    if (!log.open(QIODevice::WriteOnly) || !log.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)) throw std::runtime_error("Cannot prepare private SSH diagnostics");
    auto knownPath = known.fileName();
    knownPath.replace("\\", "\\\\").replace("\"", "\\\"");
    QStringList arguments{"-F", "/dev/null", "-vv", "-E", log.fileName(), "-tt", "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\"" + knownPath + "\"", "-o", "GlobalKnownHostsFile=/dev/null", "-o", "ForwardAgent=no", "-o", "IdentityAgent=none", "-o", "ClearAllForwardings=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3", "-o", "NumberOfPasswordPrompts=" + QString(auth == "none" ? "0" : "1"), "-p", QString::number(host.value("port").toInt()), "-l", host.value("username").toString()};
    if (auth == "key") {
        QFile key(temporary_->path() + "/identity");
        auto contents = host.value("privateKey").toString().toUtf8();
        if (!contents.endsWith('\n')) contents += '\n';
        if (!key.open(QIODevice::WriteOnly) || !key.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner) || key.write(contents) != contents.size() || !key.flush()) { wipe(contents); throw std::runtime_error("Cannot prepare private key"); }
        wipe(contents);
        arguments << "-o" << "IdentitiesOnly=yes" << "-o" << "PreferredAuthentications=publickey" << "-i" << key.fileName();
    } else if (auth == "password") arguments << "-o" << "PubkeyAuthentication=no" << "-o" << "PreferredAuthentications=password,keyboard-interactive";
    else arguments << "-o" << "BatchMode=yes" << "-o" << "IdentitiesOnly=yes" << "-o" << "PubkeyAuthentication=no" << "-o" << "PasswordAuthentication=no" << "-o" << "KbdInteractiveAuthentication=no" << "-o" << "HostbasedAuthentication=no" << "-o" << "GSSAPIAuthentication=no";
    arguments << "--" << host.value("hostname").toString();
    environment.insert("LC_ALL", "C.UTF-8");
    terminal_->setEnvironment(environment.toStringList());
    const auto ssh = QStandardPaths::findExecutable("ssh");
    if (ssh.isEmpty()) throw std::runtime_error("OpenSSH client is missing; install openssh-client");
    terminal_->setShellProgram(ssh);
    terminal_->setArgs(arguments);
    terminal_->setTerminalFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    terminal_->setColorScheme(":/harbor.colorscheme");
    terminal_->setScrollBarPosition(QTermWidget::ScrollBarRight);
    terminal_->setHistorySize(10000);
    connect(terminal_, &QTermWidget::finished, this, [this] {
        readDiagnostics();
        cleanup();
        if (connected_) {
            connected_ = false;
            started_ = false;
            pages_->setCurrentIndex(0);
            heading_->setText("Session ended");
            detail_->setText("The remote shell closed. You can reconnect or edit this host's settings.");
            progress_->hide();
            retry_->show();
            edit_->show();
            cancel_->setText("Close");
            emit finished();
        } else if (!failed_) showFailure(failureReason());
    });
    diagnostics_->start();
    terminal_->startShellProgram();
    QTimer::singleShot(60000, this, [this] { if (started_ && !connected_ && !failed_) showFailure("The connection took too long. Check that SSH is reachable and try again."); });
    } catch (const std::exception &exception) { showFailure(QString::fromUtf8(exception.what())); }
}

Terminal::~Terminal() {
    if (scan_ && scan_->state() != QProcess::NotRunning) { scan_->kill(); scan_->waitForFinished(1000); }
    delete terminal_;
    cleanup();
}

void Terminal::start() {
    if (started_ || failed_ || scan_) return;
    if (!host_.value("hostKey").toString().isEmpty()) { startSsh(); return; }
    detail_->setText("Looking up the server key. Compare its fingerprint before you trust it.");
    scan_ = new QProcess(this);
    scan_->setProgram("ssh-keyscan");
    scan_->setArguments({"-T", "5", "-p", QString::number(host_.value("port").toInt()), "-t", "ed25519,ecdsa,rsa", host_.value("hostname").toString()});
    scan_->setStandardErrorFile("/dev/null");
    auto process = scan_;
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process] { if (process->bytesAvailable() > 65536) showFailure("The server sent too much identity data. Check its address."); });
    connect(process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) { if (error == QProcess::FailedToStart) showFailure("The SSH key scanner could not start. Install openssh-client and try again."); });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this, process] {
        if (scan_ != process || failed_) return;
        const auto output = process->readAllStandardOutput();
        scan_ = nullptr;
        process->deleteLater();
        QByteArray selected;
        for (const auto &line : output.split('\n')) {
            const auto parts = line.simplified().split(' ');
            if (parts.size() != 3 || parts[0] != hostKeyName(host_).toUtf8()) continue;
            if (QByteArray::fromBase64(parts[2], QByteArray::AbortOnBase64DecodingErrors).isEmpty()) continue;
            selected = parts[1] + ' ' + parts[2];
            if (parts[1] == "ssh-ed25519") break;
        }
        if (selected.isEmpty()) { showFailure("Could not retrieve a supported server key. Check the address and SSH port."); return; }
        host_["hostKey"] = QString::fromLatin1(selected);
        const auto key = QByteArray::fromBase64(selected.split(' ')[1]);
        const auto fingerprint = QCryptographicHash::hash(key, QCryptographicHash::Sha256).toBase64(QByteArray::OmitTrailingEquals);
        fingerprint_->setText(QString::fromLatin1(selected.split(' ')[0]) + "\nSHA256:" + QString::fromLatin1(fingerprint) + "\n\nCompare this fingerprint with the server administrator before trusting it.");
        fingerprint_->show();
        progress_->hide();
        trust_->show();
        setStage(1);
        detail_->setText("Is this the server you meant to connect to?");
    });
    process->start();
    QTimer::singleShot(10000, process, [process] { if (process->state() != QProcess::NotRunning) process->kill(); });
}

void Terminal::acceptHostKey(const QString &key) {
    if (!trust_->isVisible() || failed_ || key != host_.value("hostKey").toString()) return;
    trust_->hide();
    fingerprint_->hide();
    progress_->show();
    detail_->setText("Verifying the saved server key with SSH.");
    startSsh();
}

void Terminal::setStage(int stage) {
    if (stage <= stage_ || failed_ || connected_) return;
    stage_ = stage;
    const QStringList names{"Reaching server", "Verifying server identity", "Signing in", "Opening shell"};
    for (int i = 0; i < 4; ++i) {
        steps_[i]->setText((i < stage ? "✓  " : i == stage ? "◌  " : "○  ") + names[i]);
        steps_[i]->setStyleSheet(i < stage ? "color: #c8d7ce;" : i == stage ? "color: #a8b8fa; font-weight: 600;" : "color: #777d8b;");
    }
    if (stage == 1) detail_->setText("Server reached. Checking its saved identity.");
    if (stage == 2) detail_->setText("Server identity matches. Signing in.");
    if (stage == 3) detail_->setText("Signed in. Waiting for the remote shell.");
    if (stage == 4) {
        connected_ = true;
        diagnostics_->setInterval(1000);
        pages_->setCurrentWidget(terminal_);
        terminal_->setFocus();
        emit ready();
    }
}

void Terminal::readDiagnostics() {
    if (!started_ || failed_ || !temporary_) return;
    QFile file(temporary_->path() + "/ssh.log");
    if (!file.open(QIODevice::ReadOnly)) return;
    if (connected_) {
        if (file.size() > 65536) { file.close(); if (file.open(QIODevice::ReadWrite)) file.resize(0); }
        return;
    }
    if (file.size() > 262144) { showFailure("SSH diagnostics grew too large before a shell opened. Check the server and try again."); return; }
    if (!file.seek(diagnosticOffset_)) return;
    const auto data = file.readAll();
    diagnosticOffset_ += data.size();
    pending_ += data;
    if (pending_.size() > 65536) { showFailure("SSH diagnostics were incomplete. Check the server and try again."); return; }
    while (true) {
        const int end = pending_.indexOf('\n');
        if (end < 0) break;
        auto line = pending_.left(end).trimmed();
        pending_.remove(0, end + 1);
        if (!line.startsWith("Received disconnect") && !line.contains(": Remote:")) {
            diagnosticErrors_ += QString::fromUtf8(line) + '\n';
            if (diagnosticErrors_.size() > 16384) diagnosticErrors_ = diagnosticErrors_.right(16384);
        }
        if (line == "debug1: Connection established.") setStage(1);
        else if (line.startsWith("debug1: Host '") && line.contains("' is known and matches the ")) setStage(2);
        else if (line.startsWith("Authenticated to ")) setStage(3);
        else if (line == "debug2: shell request accepted on channel 0") { setStage(4); break; }
    }
}

void Terminal::appendServerMessage(const QString &text) {
    if (!started_ || connected_ || failed_ || serverText_.size() >= 4096) return;
    for (const auto character : text) {
        const auto value = character.unicode();
        if (escapeState_ == 1) { escapeState_ = character == '[' ? 2 : character == ']' || character == 'P' ? 3 : 0; continue; }
        if (escapeState_ == 2) { if (value >= 0x40 && value <= 0x7e) escapeState_ = 0; continue; }
        if (escapeState_ == 3) { if (value == 7) escapeState_ = 0; else if (value == 27) escapeState_ = 4; continue; }
        if (escapeState_ == 4) { escapeState_ = character == '\\' ? 0 : 3; continue; }
        if (value == 27) { escapeState_ = 1; continue; }
        if (value == '\r' || character.category() == QChar::Other_Format || (value < 32 && value != '\n' && value != '\t') || value == 127 || (value >= 0x80 && value <= 0x9f)) continue;
        if (serverText_.size() == 4096) break;
        serverText_.append(value == '\t' ? QChar(' ') : character);
    }
    if (!serverText_.trimmed().isEmpty()) { message_->setText(serverText_.trimmed()); messageBox_->show(); }
}

QString Terminal::failureReason() const {
    const auto &text = diagnosticErrors_;
    if (text.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") || text.contains("Host key verification failed")) return "The saved server key does not match. Confirm the server's fingerprint, then use Edit Config to verify the new key.";
    if (text.contains("Permission denied")) return "The server rejected the sign-in details. Check the username and authentication method in Edit Config.";
    if (text.contains("Connection refused")) return "The server refused SSH on this port. Check the address and SSH port in Edit Config.";
    if (text.contains("Could not resolve hostname")) return "The server address could not be found. Check the hostname and your network.";
    if (text.contains("Connection timed out") || text.contains("Operation timed out")) return "The server did not answer. Check that it is online and reachable from this network.";
    if (text.contains("shell request failed") || text.contains("PTY allocation request failed")) return "The server signed you in but did not open a shell for this account.";
    return "SSH ended before a shell opened. Check the server, network, and sign-in settings.";
}

void Terminal::showFailure(const QString &reason) {
    if (failed_ || connected_) return;
    cancel();
    heading_->setText("Could not connect");
    detail_->setText(reason);
    progress_->hide();
    fingerprint_->hide();
    trust_->hide();
    retry_->show();
    edit_->show();
    cancel_->setText("Close");
    const QStringList names{"Reaching server", "Verifying server identity", "Signing in", "Opening shell"};
    if (stage_ < 4) { steps_[stage_]->setText("×  " + names[stage_]); steps_[stage_]->setStyleSheet("color: #f3adad; font-weight: 600;"); }
    emit failed();
}

void Terminal::cancel() {
    if (failed_) return;
    failed_ = true;
    if (scan_) { disconnect(scan_, nullptr, this, nullptr); if (scan_->state() != QProcess::NotRunning) scan_->kill(); scan_->deleteLater(); scan_ = nullptr; }
    if (terminal_) { disconnect(terminal_, nullptr, this, nullptr); terminal_->deleteLater(); terminal_ = nullptr; }
    cleanup();
}

bool Terminal::connected() const { return connected_; }

void Terminal::cleanup() {
    if (diagnostics_) diagnostics_->stop();
    wipe(password_);
    wipe(passphrase_);
    wipe(capability_);
    askpass_.close();
    temporary_.reset();
}
