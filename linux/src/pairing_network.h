#pragma once
#include <QHostAddress>
#include <QNetworkInterface>

struct PairingNetwork {
    QString label;
    QString interfaceName;
    QHostAddress address;
    int priority;
};

int pairingNetworkPriority(const QString &name, QNetworkInterface::InterfaceType type, const QHostAddress &address);
QList<PairingNetwork> pairingNetworks();
