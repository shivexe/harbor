#pragma once
#include <QObject>
#include <QJsonObject>
#include <QJsonArray>
#include <QString>

QByteArray randomBytes(int size);
QByteArray deriveKey(const QByteArray &password, const QByteArray &salt, int rounds = 600000);
QByteArray seal(const QByteArray &plain, const QByteArray &key, const QByteArray &aad = {});
QByteArray unseal(const QByteArray &box, const QByteArray &key, const QByteArray &aad = {});
void wipe(QByteArray &value);
QString validateHost(const QJsonObject &host);
QString validateHostEndpoint(const QString &hostname, int port);
QString validatePrivateKey(const QByteArray &contents, const QByteArray &passphrase = {}, bool requireDecryption = false);

class Vault : public QObject {
    Q_OBJECT
public:
    explicit Vault(QString path, QObject *parent = nullptr);
    ~Vault();
    bool exists() const;
    void unlock(const QString &passphrase);
    void save();
    void lock();
    bool unlocked() const;
    QJsonObject data() const;
    void replace(const QJsonObject &data);
    QJsonArray hosts() const;
    void upsert(QJsonObject host, bool keyVerified = false);
    void remove(const QString &id);
    QJsonObject snapshot() const;
    QString directory() const;
signals:
    void changed();
private:
    QString path_;
    QByteArray key_;
    QByteArray salt_;
    QJsonObject data_;
};
