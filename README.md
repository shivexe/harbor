# Harbor

An SSH manager for macOS, Linux, and Android. Organize servers on your desktop, pair your phone with a QR code, and connect from either device.

- Password, private-key, and passphrase-encrypted key support.
- Encrypted host storage and manual desktop-to-phone sync.
- Direct SSH connections with server-key verification.
- Multiple terminal sessions and a dark interface.

## Get started

Build the app for [macOS](macos/README.md), [Linux](linux/README.md), or [Android](android/README.md).

1. Open Harbor on your desktop and add a host.
2. Verify the server fingerprint before connecting.
3. To pair Android, put both devices on the same local network or private VPN. Open **Devices → Pair Android**, scan the QR code, compare the codes, and approve.
4. Tap **Sync** on Android after changing your desktop hosts.

Android keeps a read-only copy of your host settings and connects directly to servers, even when the desktop is offline. Each phone pairs with one desktop; Mac and Linux libraries are independent. No Harbor account or cloud service is required.

## Learn more

[Architecture](docs/architecture/harbor-architecture.svg) · [Sync protocol](docs/PROTOCOL.md) · [Supported key formats](docs/ENCRYPTED-KEYS.md) · [Linux dependency notices](linux/THIRD_PARTY_NOTICES.md)
