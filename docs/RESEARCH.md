# Research and design decisions

## Product reference

Termius combines hosts, credentials, groups and terminal access with an encrypted vault: https://termius.com/vault . Harbor deliberately uses user-controlled desktop authority and local-network manual sync, with no hosted account service.

## Components

- Qt 6 supports Linux desktop: https://doc.qt.io/qt-6/supported-platforms.html . Qt Widgets integrates the established QTermWidget directly, avoiding a custom terminal emulator and a QML bridge.
- QTermWidget is a Unicode-capable Qt6 terminal engine: https://github.com/lxqt/qtermwidget . It is GPL-2.0-or-later; distribution must preserve notices and meet applicable source obligations. Do not silently label the combined Linux binary proprietary or MIT.
- SwiftTerm provides AppKit terminal views and a local-process PTY integration: https://github.com/migueldeicaza/SwiftTerm . Pin a known release and verify its APIs rather than relying on current main.
- dartssh2 supports direct sockets, shell/PTY sessions, password and in-memory key authentication: https://pub.dev/documentation/dartssh2/latest/ . Host-key signature verification alone does not pin server identity; compare against the public key approved by the desktop.
- Dart cryptography provides AES-GCM and Ed25519: https://pub.dev/packages/cryptography . Apple CryptoKit provides equivalent platform primitives: https://developer.apple.com/documentation/cryptokit . Linux uses OpenSSL.
- flutter_secure_storage uses platform-secured storage with Android encryption: https://pub.dev/packages/flutter_secure_storage . Disable app backup and avoid plaintext fallbacks.

## Security boundaries

Authenticated encryption hides host configuration and credentials in transit/storage. A separately pinned desktop signing key authenticates authoritative snapshots even though the receiving app possesses a symmetric decryption key. Short-lived out-of-band invitations plus explicit comparison bind first pairing. This protocol needs interoperability and adversarial tests; it has not undergone external security audit.

Read-only means the Android product exposes no authoritative configuration mutation, and only accepts desktop-signed records. It cannot stop a fully compromised device or modified client from extracting secrets already decrypted for SSH. Revoking a device stops future sync, not access using previously delivered credentials. Rotate server credentials for that.

The Linux workflow validates protocol interoperability and Linux behavior, not Swift/AppKit behavior. macOS build and runtime validation remain distinct.

The user's Mac is reachable at a `100.64.x.x` address. All three pairing-origin validators accept exactly RFC6598 `100.64.0.0/10` in addition to private/link-local addresses; boundary tests reject adjacent public ranges. [Tailscale's official address documentation](https://tailscale.com/docs/concepts/tailscale-ip-addresses) confirms its use of this shared address space. The wire format and cryptographic checks are unchanged.
