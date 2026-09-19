#include "pairing_network.h"
#include <algorithm>

int pairingNetworkPriority(const QString &name, QNetworkInterface::InterfaceType type, const QHostAddress &address) {
    const auto lower = name.toLower();
    if (lower == "lo" || lower.startsWith("docker") || lower.startsWith("br-") || lower.startsWith("veth") || lower.startsWith("virbr") || lower.startsWith("podman")) return -1;
    int family = -1;
    if (address.protocol() == QAbstractSocket::IPv4Protocol) {
        const auto n = address.toIPv4Address();
        if ((n >> 24) == 10 || (n >> 20) == 0xac1 || (n >> 16) == 0xc0a8) family = 0;
        else if ((n & 0xffc00000u) == 0x64400000u) family = 8;
        else if ((n >> 16) == 0xa9fe) family = 45;
    } else if (address.protocol() == QAbstractSocket::IPv6Protocol) {
        const auto bytes = address.toIPv6Address();
        if ((bytes[0] & 0xfe) == 0xfc) family = 20;
    }
    if (family < 0 || address.isLoopback()) return -1;
    if (type == QNetworkInterface::Wifi) return family;
    if (lower.startsWith("tailscale")) return 24 + family;
    if (lower.startsWith("wg") || lower.startsWith("tun")) return 28 + family;
    if (type == QNetworkInterface::Ethernet) return 12 + family;
    if (type == QNetworkInterface::Virtual) return 60 + family;
    return 40 + family;
}

QList<PairingNetwork> pairingNetworks() {
    QList<PairingNetwork> result;
    for (const auto &network : QNetworkInterface::allInterfaces()) {
        if (!(network.flags() & QNetworkInterface::IsUp) || (network.flags() & QNetworkInterface::IsLoopBack)) continue;
        const auto name = network.name();
        QString label;
        if (name.startsWith("tailscale", Qt::CaseInsensitive)) label = "Tailscale";
        else if (network.type() == QNetworkInterface::Wifi) label = "Wi-Fi";
        else if (network.type() == QNetworkInterface::Ethernet) label = "Ethernet";
        else if (name.startsWith("wg") || name.startsWith("tun")) label = "Private VPN";
        else label = network.humanReadableName().isEmpty() ? name : network.humanReadableName();
        for (const auto &entry : network.addressEntries()) {
            const auto priority = pairingNetworkPriority(name, network.type(), entry.ip());
            if (priority < 0) continue;
            result.append({label, name, entry.ip(), priority});
        }
    }
    std::sort(result.begin(), result.end(), [](const auto &a, const auto &b) {
        if (a.priority != b.priority) return a.priority < b.priority;
        if (a.label != b.label) return a.label < b.label;
        return a.address.toString() < b.address.toString();
    });
    return result;
}
