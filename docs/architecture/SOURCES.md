# Harbor architecture: source notes

The SVGs describe the implemented app at commit `7e43af9` (Mac/Android 1.2.1; Linux 1.2.0), not a proposed redesign. No application behavior was changed for this explanation.

The explanation uses [ELI Adult](https://github.com/kavyabhand/claude-eli5/tree/main/skills/eli-adult) and the family's [core rules](https://github.com/kavyabhand/claude-eli5/blob/main/skills/eli5-mode/references/core-rules.md): short sentences, plain-language comparisons, and accuracy before simplification. Technical names are retained where needed to identify real mechanisms.

## Trace a chart step to the code

| Flow | Source |
| --- | --- |
| Ownership, shared messages and fields | [Protocol](../PROTOCOL.md), [Android records](../../android/lib/models.dart), [Mac wire records](../../macos/Harbor/SyncCrypto.swift) |
| Mac unlock, single-instance guard, local save and lock | [LibraryStore.swift](../../macos/Harbor/LibraryStore.swift), [Vault.swift](../../macos/Harbor/Vault.swift), [HarborApp.swift](../../macos/Harbor/HarborApp.swift) |
| Linux local vault, password derivation and writes | [vault.cpp](../../linux/src/vault.cpp), [main.cpp](../../linux/src/main.cpp), [window.cpp](../../linux/src/window.cpp) |
| Host input and private-key validation | [HostEditor.swift](../../macos/Harbor/HostEditor.swift), [Linux editor](../../linux/src/window.cpp), [Linux validator](../../linux/src/vault.cpp) |
| QR, device binding, approval and revocation | [SharingService.swift](../../macos/Harbor/SharingService.swift), [SharingView.swift](../../macos/Harbor/SharingView.swift), [sync.cpp](../../linux/src/sync.cpp) |
| Listener bounds and network selection | [HTTPServer.swift](../../macos/Harbor/HTTPServer.swift), [pairing_network.cpp](../../linux/src/pairing_network.cpp), [sync.cpp](../../linux/src/sync.cpp) |
| Android invitation parsing and pairing screen | [sync_client.dart](../../android/lib/sync_client.dart), [pair_screen.dart](../../android/lib/screens/pair_screen.dart) |
| Signed sync, replacement and local save | [sync_client.dart](../../android/lib/sync_client.dart), [sync.dart](../../android/lib/sync.dart), [vault.dart](../../android/lib/vault.dart), [SyncCrypto.swift](../../macos/Harbor/SyncCrypto.swift) |
| Device unlock, screen protection and backups | [MainActivity.kt](../../android/android/app/src/main/kotlin/dev/harbor/app/MainActivity.kt), [security_gate.dart](../../android/lib/security_gate.dart), [manifest](../../android/android/app/src/main/AndroidManifest.xml), [backup exclusions](../../android/android/app/src/main/res/xml/data_extraction_rules.xml) |
| Android local records, sessions, lock and unpair | [main.dart](../../android/lib/main.dart), [vault.dart](../../android/lib/vault.dart) |
| Android SSH, key adaptation and terminal states | [ssh_client.dart](../../android/lib/ssh_client.dart), [private_key_loader.dart](../../android/lib/private_key_loader.dart), [ssh_session.dart](../../android/lib/ssh_session.dart), [terminal_screen.dart](../../android/lib/screens/terminal_screen.dart), [interactive_terminal.dart](../../android/lib/interactive_terminal.dart) |
| Desktop SSH and credential helpers | [SSH.swift](../../macos/Harbor/SSH.swift), [Mac helper](../../macos/HarborAskPass/main.swift), [terminal.cpp](../../linux/src/terminal.cpp), [Linux helper](../../linux/src/askpass.cpp) |

## Details checked beyond the protocol document

- Android uses `flutter_secure_storage` **10.3.4**, pinned in [pubspec.lock](../../android/pubspec.lock). Its Android defaults create a **16-byte AES-128 GCM data key**, wrapped by an AndroidKeyStore RSA key using OAEP/SHA-256 with MGF1-SHA1. This differs from the **AES-256 GCM** used by Harbor's sync messages and desktop vaults.
- The plugin's `StorageCipherImplementationGCM.java`, `KeyCipherImplementationRSA18.java`, `KeyCipherImplementationRSAOAEP.java`, `FlutterSecureStorage.java` and `lib/options/android_options.dart` were read from the installed 10.3.4 package. The RSA wrapping path does not require a new user authentication for every key use. Hardware backing is not established by Harbor's configuration.
- The Android credential dialog gates the app UI. It is separate from the storage key policy. `FLAG_SECURE` blocks ordinary capture of the app window; it is not protection from a compromised OS or an external camera. Users can explicitly copy terminal text.
- Android saves pairing and snapshot in one logical value. The plugin uses `SharedPreferences.Editor.apply()`, an asynchronous disk write. This avoids separate pairing/host updates but is not a guarantee of crash-durable database transactions or detection of every later disk-write failure.
- Local Unpair clears the plugin's data entries. It does not explicitly destroy the AndroidKeyStore RSA alias or wrapped-key preference. Desktop Revoke blocks future sync; neither operation automatically changes credentials on the SSH server.
- Both desktop listeners bind **all interfaces**. Network options choose the private address advertised in the QR. The current UI does not expose a different port when 45873 is occupied.
- Mac encrypted **PEM** passphrases are checked before Save. Mac encrypted **OpenSSH** containers are checked structurally, but their passphrase is not validated until the connection. Linux validates these passphrases before Save. The chart keeps this difference visible.
- Linux pairing retries require the same encrypted request body. Mac binds the decrypted device ID and client nonce. Android retries the same body, so its flow satisfies both.
- Sync freshness uses the new request ID and a nondecreasing revision. `generatedAt` is checked as a valid number; it is not used as a wall-clock expiry.

## Platform references

Android's [app sandbox](https://source.android.com/docs/security/app-sandbox) separates ordinary apps' private data. Its [Keystore](https://developer.android.com/privacy-and-security/keystore) restricts an app's key use; Harbor's pinned storage plugin determines which key policy it actually requests. The wrapped AES data key is unwrapped into Harbor's process, while the AndroidKeyStore RSA private key remains managed by Android. This distinction explains why encrypted files and in-use secrets have different exposure.

## Reading the flow

A box is an action or stored value. A diamond is a question. Each arrow names the action or data it carries. The lane tells you which device owns that step. Failure branches state whether previous data remains usable. The separate learning guide shows how to build the same kind of map from another app's requirements; it is not part of the Harbor architecture SVG.
