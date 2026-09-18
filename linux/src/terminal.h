#pragma once
#include <QWidget>
#include <QLocalServer>
#include <QTemporaryDir>
#include <QJsonObject>
#include <memory>
class QTermWidget;
class Terminal : public QWidget {
    Q_OBJECT
public:
    Terminal(const QJsonObject &host, QWidget *parent = nullptr);
    ~Terminal();
    static bool trustHost(QJsonObject &host, QWidget *parent);
signals:
    void finished();
private:
    QTermWidget *terminal_;
    QLocalServer askpass_;
    std::unique_ptr<QTemporaryDir> temporary_;
    QByteArray password_;
    QByteArray passphrase_;
    QByteArray capability_;
};
