#pragma once
#include <QWidget>
#include <QLocalServer>
#include <QTemporaryDir>
#include <QJsonObject>
#include <memory>
class QTermWidget;
class QStackedWidget;
class QLabel;
class QPushButton;
class QProgressBar;
class QTimer;
class QProcess;
class Terminal : public QWidget {
    Q_OBJECT
public:
    Terminal(const QJsonObject &host, QWidget *parent = nullptr);
    ~Terminal();
    static bool trustHost(QJsonObject &host, QWidget *parent);
    void start();
    void acceptHostKey(const QString &key);
    void showFailure(const QString &reason);
    void cancel();
    bool connected() const;
signals:
    void finished();
    void ready();
    void failed();
    void retryRequested();
    void editRequested();
    void cancelRequested();
    void trustRequested(const QString &key);
private:
    void startSsh();
    void readDiagnostics();
    void appendServerMessage(const QString &text);
    void setStage(int stage);
    QString failureReason() const;
    void cleanup();
    QJsonObject host_;
    QTermWidget *terminal_;
    QStackedWidget *pages_;
    QLabel *heading_;
    QLabel *detail_;
    QLabel *fingerprint_;
    QWidget *messageBox_;
    QLabel *message_;
    QLabel *steps_[4];
    QPushButton *trust_;
    QPushButton *retry_;
    QPushButton *edit_;
    QPushButton *cancel_;
    QProgressBar *progress_;
    QTimer *diagnostics_;
    QProcess *scan_ = nullptr;
    QLocalServer askpass_;
    std::unique_ptr<QTemporaryDir> temporary_;
    QByteArray password_;
    QByteArray passphrase_;
    QByteArray capability_;
    QByteArray pending_;
    QString diagnosticErrors_;
    QString serverText_;
    qint64 diagnosticOffset_ = 0;
    int stage_ = 0;
    int escapeState_ = 0;
    bool started_ = false;
    bool connected_ = false;
    bool failed_ = false;
};
