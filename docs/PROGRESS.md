# Harbor progress

## Objective

Build Swift macOS, Qt Linux and Flutter Android SSH managers. Desktop authority, encrypted read-only Android sync, actual terminals, dark mode. User asleep; resolve routine choices autonomously. No implementation comments, minimal modular code. All implementation by GPT-5.6 Sol high agents.

## Completed assignments

- `/root/linux`: Linux app, user-local Qt/compiler setup, terminal and desktop sync.
- `/root/android`: Flutter SDK/Android tooling, Android app, signed APK, unit/widget and native emulator tests.
- `/root/macos`: Swift app and reproducible Mac build.
- Root: research, protocol/design contract, integration review and verification coordination.

## Environment

Workspace Ubuntu 26.04.1. No sudo passwordless access; Docker socket unavailable. Development tools were bootstrapped without system changes: Qt/compiler under `/tmp/harbor-sysroot`, Flutter, Android SDK, Java and Swift under `/home/notsg/.local/share/harbor-tools`, Python QA environment under `/tmp/harbor-qa`. Xcode is unavailable; Mac build/runtime checks require Mac access later.

## Decisions

- Working product name Harbor.
- Protocol defined in PROTOCOL.md: AES-GCM application encryption, Ed25519 signed snapshots, explicit QR comparison/approval, desktop pinned SSH host keys.
- Linux uses Qt Widgets with QTermWidget to avoid an unnecessary QML/terminal bridge.
- Dark design: navy surfaces, restrained blue action accent, standard platform fonts, monospace only in terminal/address displays; sidebars and session tabs on desktop, searchable host list and session toolbar on Android.
- Work used a persistent goal and these durable checkpoints. No five-minute timer was installed or claimed. Goal continuation was the available mechanism, rather than an unverified idle-message scheduler.

## Verification

Linux Release app, askpass helper, security tests, live protocol tests and Debian package are built. Real QTermWidget sessions passed password, key and encrypted-key authentication, Unicode, resize, physical keyboard editing, Vim alternate-screen operation and changed-key rejection. Independent Python protocol tests cover pairing binding, approved-response retry, encrypted signed snapshots, tampering, deletions, revocation, lock, malformed framing, incomplete requests and non-reading response deadlines.

Actual Dart code paired and synced with Linux, observed deletion and rejected revoked sync. Dart SSH passed password, key and encrypted-key authentication with both Ed25519 and RSA server keys, command execution, PTY and resize. Final Flutter analysis is clean and all seven tests passed independently. The signed release APK also passed native API 30 emulator checks: real PIN gate, pairing/full sync, encrypted persistence, cold restart, all three SSH authentication methods, terminal software-keyboard input, background lock, and offline-desktop SSH. Screenshots and binaries are in `artifacts/`.

Swift 6.2.3 parsed all Mac application/helper/test sources. The actual portable host model compiled and passed executable validation. XcodeGen generated the checked-in Xcode project successfully. Native Mac runtime remains untested.

## Review progress

Review corrections include invalidating server trust after address changes, single-instance desktop vault ownership, scoped credential helpers, approved pairing retries after dialog dismissal and new invitations, serialized mobile operations, correct lazy-list group headers and authenticated Mac startup. Mac's terminal delegate blocks implicit OSC52 clipboard access. Linux bounds both request reads and response writes. Android counts human terminal input without allowing automatic remote replies to keep the idle lock alive.

Latest available test harnesses: `linux/tests/security.cpp`, `linux/tests/sync_fixture.cpp`, `android/test/protocol_test.dart`, `android/tool/integration.dart`, `android/tool/ssh_check.dart`, `macos/Tests/HarborTests.swift`.

## Handoff

Linux and Android binaries, source archive, screenshots and checksums are collected in `artifacts/`. Source is committed locally. See TEST-RESULTS.md for the executed evidence and README.md for installation. SDKs and private Android release signing material remain under the user-local tools directory for future builds. Disposable services and credentials are cleaned up after testing.

The remaining platform validation requires a Mac: run `macos/scripts/build.sh` and `macos/scripts/test.sh`, then verify native authentication, Keychain/helper access, terminals and Mac-to-Android pairing. No native Mac build or runtime success is claimed. Windows, cloud service, desktop-to-desktop sync and app-store publication remain outside scope.
