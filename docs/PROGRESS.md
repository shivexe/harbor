# Harbor progress

## Objective

Build Swift macOS, Qt Linux and Flutter Android SSH managers. Desktop authority, encrypted read-only Android sync, actual terminals, dark mode. User asleep; resolve routine choices autonomously. No implementation comments, minimal modular code. All implementation by GPT-5.6 Sol high agents.

## Active assignments

- `/root/linux`: Linux app, user-local Qt/compiler setup, terminal and desktop sync.
- `/root/android`: Flutter SDK/Android tooling, Android app, APK and tests.
- `/root/macos`: Swift app and reproducible Mac build.
- Root: research, protocol/design contract, integration review and verification coordination.

## Environment

Workspace Ubuntu 26.04.1. No sudo passwordless access; Docker socket unavailable. Development tools were bootstrapped without system changes: Qt/compiler under `/tmp/harbor-sysroot`, Flutter, Android SDK, Java and Swift under `/home/notsg/.local/share/harbor-tools`, Python QA environment under `/tmp/harbor-qa`. Xcode is unavailable; Mac build/runtime checks require Mac access later.

## Decisions

- Working product name Harbor.
- Protocol defined in PROTOCOL.md: AES-GCM application encryption, Ed25519 signed snapshots, explicit QR comparison/approval, desktop pinned SSH host keys.
- Linux uses Qt Widgets with QTermWidget to avoid an unnecessary QML/terminal bridge.
- Dark design: navy surfaces, restrained blue action accent, standard platform fonts, monospace only in terminal/address displays; sidebars and session tabs on desktop, searchable host list and session toolbar on Android.
- Persistent goal is active. No five-minute timer has been installed or claimed. Current-session goal continuation is the available mechanism; checkpoints survive through these files.

## Verification

Linux Release app, askpass helper, security tests, live protocol tests and Debian package are built. Real QTermWidget sessions passed password, key and encrypted-key authentication, Unicode, resize, physical keyboard editing, Vim alternate-screen operation and changed-key rejection. Independent Python protocol tests cover pairing binding, approved-response retry, encrypted signed snapshots, tampering, deletions, revocation, lock, malformed framing, incomplete requests and non-reading response deadlines.

Actual Dart code paired and synced with Linux, observed deletion and rejected revoked sync. Dart SSH passed password, key and encrypted-key authentication with both Ed25519 and RSA server keys, command execution, PTY and resize. Flutter UI screenshots and lock lifecycle tests are available. Android APK and emulator verification are being completed.

Swift 6.2.3 parsed all Mac application/helper/test sources. The actual portable host model compiled and passed executable validation. XcodeGen generated the checked-in Xcode project successfully. Native Mac runtime remains untested.

## Review progress

Review corrections include invalidating server trust after address changes, single-instance desktop vault ownership, scoped credential helpers, approved pairing retries after dialog dismissal, serialized mobile operations, correct lazy-list group headers and authenticated Mac startup. Mac's terminal delegate blocks implicit OSC52 clipboard access. Linux now bounds both request reads and response writes. Android's idle timer is being hardened to count human input without counting automatic remote terminal replies.

Latest available test harnesses: `linux/tests/security.cpp`, `linux/tests/sync_fixture.cpp`, `android/test/protocol_test.dart`, `android/tool/integration.dart`, `android/tool/ssh_check.dart`, `macos/Tests/HarborTests.swift`.

## Next

Finish Android release APK and available emulator checks; rerun final analysis/tests after idle-input correction. Consolidate executed evidence in TEST-RESULTS.md, collect binaries/screenshots/checksums, review source hygiene, create a source archive and finish the handoff. Do not claim native Mac validation.
