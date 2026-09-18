# Harbor for macOS

Native SwiftUI app with SwiftTerm terminals and system OpenSSH. Requires macOS 14 or later and Xcode 16 or later.

## Build and run

Open `Harbor.xcodeproj` in Xcode, select your signing team for Harbor and HarborAskPass, and run the Harbor scheme. Keep the helper bundled with the app.

For an unsigned build, run from this directory:

```sh
./scripts/build.sh
```

For local verification:

```sh
./scripts/test.sh
./scripts/check-models.sh
```

The checked-in Xcode project is ready to build. If XcodeGen is installed, the scripts regenerate it from `project.yml`.

## Use

Unlock Harbor, add a host, and verify its server fingerprint. Choose password, private key, or server-authorized passwordless authentication. Use **Devices → Pair Android** to share your host library with your phone.

The library is encrypted with a key stored in macOS Keychain. Locking Harbor closes its SSH sessions and stops sharing. Backups require both the encrypted library and its Keychain key.

For installation, copy a signed Harbor.app into Applications. Public macOS distribution requires Developer ID signing and notarization.
