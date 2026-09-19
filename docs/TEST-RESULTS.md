# Executed verification

Validation performed on Ubuntu 26.04 amd64, an Android API 30 emulator, and the user's Apple silicon Mac with Xcode 27. Disposable servers and credentials were used. These checks establish tested behavior; they do not constitute an external security audit or app-store certification.

## Linux

The optimized CMake Release build produced the Qt app, credential helper and separate test binaries. CTest passed. Root independently reran the security binary, CTest, live protocol suite and GUI fixture after the final fixes.

- Authenticated vault encryption, wrong-password handling, encrypted CRUD/restart persistence, private file permissions, SSH argument-injection rejection and fixed cryptographic vectors passed.
- Actual QTermWidget/OpenSSH sessions passed password, private-key and encrypted-private-key authentication against a disposable AsyncSSH server backed by a real Bash PTY.
- Terminal checks passed commands, decoded Unicode, resize to 41 rows by 108 columns, physical Qt keyboard cursor/edit/Return input, and Vim alternate-screen entry, insertion, Escape and exit.
- An altered SSH server key was rejected before authentication.
- Root inspected the actual dark Qt screenshot. No fixture bypass or test binary is installed in the Debian package.

The package is `artifacts/harbor-1.0.0-linux-amd64.deb`, targeting Ubuntu 26.04 amd64 libraries. Package metadata/content were inspected, and its binaries have no temporary sysroot runtime path. Other Linux distributions need a source build with compatible Qt/QTermWidget dependencies. System package installation was not executed because this workspace has no passwordless sudo.

## Protocol and interoperability

`shared/verify_protocol.py` independently passed fixed AES-GCM messages, wrong-AAD/tampered-tag rejection, Ed25519 signature verification/tamper rejection, pairing comparison codes and PBKDF2 vectors.

`shared/test_sync_integration.py` passed against the actual C++ listener:

- Pairing encryption, device/nonce binding, competitor rejection and retry of an approved response after creation of another invitation.
- Pinned Ed25519 signatures, fresh request identifiers, encrypted snapshots and tamper rejection.
- Full-snapshot deletions, device revocation and stopping sharing on lock.
- Malformed HTTP framing, duplicate/unsupported framing and size bounds.
- Incomplete requests terminate at the deadline.
- A non-reading client receiving a 3.6 MB snapshot loses its connection slot at the total ten-second deadline, including after request handling.

The actual Android Dart client paired with Linux and accepted signed snapshots. Root independently ran its pairing/sync CLI against the live C++ fixture. The Android agent also verified that removing a desktop host changed three hosts at revision 4 to two at revision 5; revocation then returned HTTP 403 and preserved the previous accepted snapshot.

## Android

Direct Dart SSH tests passed password, key and encrypted-key authentication, command execution, PTY allocation and terminal resize. These were repeated against Ed25519 and RSA SSH server identities; RSA SHA-2 negotiation works with an `ssh-rsa` wire-format pin. Missing and incorrect desktop-approved keys were rejected before authentication. Root independently ran the three authentication modes against the real disposable server.

Flutter widget tests exercised a read-only grouped/searchable host list, a narrow pairing screen, device-authentication gating, cancellation and relocking after backgrounding. Screenshots use real fonts and Material icons. Terminal input regression tests verify that human input counts as activity while remote DSR replies cannot keep the idle lock alive or consume the user's Ctrl modifier.

Final `flutter analyze` reported no issues and `flutter test` passed all seven tests, including the later RFC6598 address checks. Root independently ran analysis and tests before that address-only update. The release APK built successfully and its APK v2 signature was verified with `apksigner`. It uses a dedicated local RSA-4096 release identity rather than the Android debug key. Manifest inspection confirmed `dev.harbor.app`, version 1.0.0/1, minimum API 24, target API 36, and arm64-v8a/armeabi-v7a/x86_64 libraries.

The signed release APK was installed and tested on an Android 11/API 30 x86_64 emulator before the later RFC6598 address-only update. Root independently confirmed the installed package and completed emulator boot. The Android agent executed these native checks successfully:

- The real Android device-credential PIN prompt gated access; cancellation exposed no hosts.
- The actual app paired with the Linux listener and received a signed encrypted three-host snapshot.
- Platform secure-storage preferences contained no plaintext fixture credentials or snapshot. The native window had `FLAG_SECURE` enabled.
- Password SSH connected, and a command entered through the terminal's software keyboard created the expected server-side marker.
- Encrypted-private-key SSH connected. Backgrounding and resuming locked the app and removed sessions.
- Force-stop and cold launch required PIN authentication again and then restored all three persisted hosts.
- With the desktop listener stopped, plain-private-key SSH still connected from the saved vault.
- No native or Flutter fatal errors appeared in the checked logcat output.

Physical-phone camera/QR scanning, hardware-backed Keystore behavior and broader Android-version/device compatibility were not tested. QR parsing/paste and pairing were exercised separately from the physical camera.

## macOS

The following checks ran on Linux:

- Swift 6.2.3 parsed every application, credential-helper and XCTest source file successfully.
- The actual portable host model compiled and passed executable validation via `macos/scripts/check-models.sh`.
- The approved-pairing reply cache passed portable Swift runtime assertions for retained replies, device/nonce binding, expiry, revocation, capacity and clearing. Matching XCTest coverage is included. Root reran full Swift syntax parsing and portable host checks after this final change.
- Build/test shell scripts passed syntax validation.
- XcodeGen 2.42 generated the checked-in Xcode project, including the standalone helper dependency, its `Contents/Helpers` copy phase, the test target and shared-vector resource.
- The exact SwiftTerm 1.20.0 APIs were reviewed against its tagged source. The delegate bridge preserves PTY behavior and denies automatic terminal clipboard access.
- The ICNS application icon decoded successfully.

On 2026-09-19 native verification ran on the supplied Mac:

- Xcode 27 built the Release app and embedded helper as universal arm64/x86_64 binaries. The final build script succeeded using the checked-in project, without XcodeGen installed.
- All eleven native XCTest cases passed with zero failures. They covered shared vectors, vault encryption/tampering, validation/framing, the actual Network.framework pairing/sync listener, approved-response retries, deletion, revocation, lock and clipboard protection.
- The native terminal test authenticated with password, private key and encrypted private key through the real SwiftTerm/OpenSSH session and Keychain credential helper. Computed shell output proved command execution; remote `stty size` verified PTY resize. An altered pinned host key was rejected and session files were cleaned up.
- Root inspected a native terminal bitmap showing the actual command result.
- A separate twelfth native fixture test passed while Android's actual Dart client paired directly with the Mac at `100.64.207.29:48606` and verified two fresh encrypted, Ed25519-signed snapshots. Both the Dart command and the native test exited successfully.
- All three applications now accept exactly RFC6598 `100.64.0.0/10` for pairing. Boundary tests passed; Linux and Android artifacts were rebuilt, and the Android signature verified.
- The delivered Mac app and helper were ad hoc signed for local use. `codesign --verify --deep --strict` passed; the app launched successfully from `~/shivansh/notsg/Harbor/Harbor.app` and remained running.

The SSH test initially used a newer SwiftTerm inspection API and then encountered a test-created NSWindow ownership crash. Both test issues were corrected before the successful runs. The actual app compiled successfully before those test corrections.

Interactive owner LocalAuthentication, manual QR approval in the release UI, physical-phone camera scanning, broader macOS/device coverage and Developer ID signing/notarization remain manual release checks. See [MAC-VALIDATION.md](MAC-VALIDATION.md) and `macos/README.md` for details and commands.

## Source and delivery

Application code was written by GPT-5.6 Sol high agents; root coordinated research, protocol design, review and independent verification. Authored application sources have no explanatory comments. Required third-party notices and Gradle wrapper license notices remain intact. Signing material, credentials, SDKs, test secrets and build caches are excluded from the repository. Source was committed locally and archived; no remote publishing occurred. Final artifact checksums are stored beside the deliverables.
