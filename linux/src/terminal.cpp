#include "terminal.h"
#include "vault.h"
#include <qtermwidget6/qtermwidget.h>
#include <QApplication>
#include <QVBoxLayout>
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

Terminal::Terminal(const QJsonObject &host, QWidget *parent) : QWidget(parent), terminal_(new QTermWidget(0, this)), temporary_(std::make_unique<QTemporaryDir>(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/harbor-XXXXXX")) {
    if (!temporary_->isValid() || !QFile::setPermissions(temporary_->path(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner)) throw std::runtime_error("Cannot create a private session directory");
    if (host.value("hostKey").toString().isEmpty() || !validateHost(host).isEmpty()) throw std::runtime_error("Verify a valid server key before connecting");
    auto layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->addWidget(terminal_);
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
    QStringList arguments{"-F", "/dev/null", "-tt", "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=" + known.fileName(), "-o", "GlobalKnownHostsFile=/dev/null", "-o", "ForwardAgent=no", "-o", "IdentityAgent=none", "-o", "ClearAllForwardings=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3", "-o", "NumberOfPasswordPrompts=" + QString(auth == "none" ? "0" : "1"), "-p", QString::number(host.value("port").toInt()), "-l", host.value("username").toString()};
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
    terminal_->setEnvironment(environment.toStringList());
    const auto ssh = QStandardPaths::findExecutable("ssh");
    if (ssh.isEmpty()) throw std::runtime_error("OpenSSH client is missing; install openssh-client");
    terminal_->setShellProgram(ssh);
    terminal_->setArgs(arguments);
    terminal_->setTerminalFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    terminal_->setColorScheme(":/harbor.colorscheme");
    terminal_->setScrollBarPosition(QTermWidget::ScrollBarRight);
    terminal_->setHistorySize(10000);
    connect(terminal_, &QTermWidget::finished, this, [this] { wipe(password_); wipe(passphrase_); wipe(capability_); askpass_.close(); temporary_.reset(); emit finished(); });
    terminal_->startShellProgram();
    terminal_->setFocus();
}

Terminal::~Terminal() { delete terminal_; wipe(password_); wipe(passphrase_); wipe(capability_); askpass_.close(); }
