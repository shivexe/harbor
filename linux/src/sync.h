#pragma once
#include "vault.h"
#include <QTcpServer>
#include <QHash>
#include <QElapsedTimer>

QJsonObject encryptEnvelope(const QByteArray &plain, const QByteArray &key, const QByteArray &aad);
QByteArray decryptEnvelope(const QJsonObject &envelope, const QByteArray &key, const QByteArray &aad);
QByteArray publicSigningKey(const QByteArray &privateKey);
QByteArray signSnapshot(const QByteArray &privateKey, const QByteArray &payloadBase64);

class SyncServer : public QObject {
    Q_OBJECT
public:
    explicit SyncServer(Vault &vault, QObject *parent = nullptr);
    bool start(quint16 port = 45873);
    void stop();
    bool running() const;
    quint16 port() const;
    QJsonObject invite(const QString &origin);
    void cancelInvite(bool onlyUnapproved = false);
    void approve(const QString &deviceId);
    void deny(const QString &deviceId);
    void revoke(const QString &deviceId);
    QJsonArray devices() const;
signals:
    void pairingRequested(QString deviceId, QString deviceName, QString code);
private:
    struct Invitation {
        QString id;
        QByteArray secret;
        qint64 expires = 0;
        QString deviceId;
        QString deviceName;
        QByteArray nonce;
        QByteArray boundRequest;
        QJsonObject response;
        bool denied = false;
    };
    Vault &vault_;
    QTcpServer server_;
    Invitation invitation_;
    QHash<QString, Invitation> approved_;
    int active_ = 0;
    int attempts_ = 0;
    QElapsedTimer rateWindow_;
    void accept();
    void handle(class QTcpSocket *socket, const QByteArray &method, const QByteArray &path, const QByteArray &body);
    void respond(class QTcpSocket *socket, int status, const QJsonObject &body = {});
    QByteArray signingPrivateKey();
};
