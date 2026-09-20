# Harbor progress

## Version 1.1.2: connection progress and host-key path fix

The reported ED25519 strict-checking failure was reproduced with a correctly approved key under a directory containing spaces. OpenSSH's `UserKnownHostsFile` value is now quoted correctly; strict checking and saved trust remain enabled. All three clients show connection steps and reveal the terminal only after shell acceptance, with visible recovery controls. Desktop Retry reads current host settings; Android retains read-only configuration and can sync before retry. Tailscale-style sign-in banners remain visible without controlling progress.

Linux security, UI, terminal and connection fixtures passed; Android analysis, sixteen tests and real connection checks passed. Mac's full suite completed twenty cases with four opt-in skips and no failures; focused native no-password/private-key, altered-key, cancellation, spaced-path and delayed-banner checks passed. The newly signed Debug Mac credential helper requested Keychain approval, so password/passphrase Mac checks are explicitly unverified in that environment. See [CONNECTION-VALIDATION.md](CONNECTION-VALIDATION.md) for exact evidence.

The update is delivered as `~/shivansh/notsg/Harbor/Harbor-1.1.2.app` on the supplied Mac and `~/Downloads/harbor-1.1.2-android.apk`. Quit the older Mac app before opening the update. Versioned installers, screenshots and source are in `artifacts/`; existing app copies, owner sessions and vaults are preserved.

## Version 1.1.1: passwordless SSH

The user reported that Tailscale SSH needs only hostname and username. All three clients now support `authType: "none"`. Desktop new-host editors default to No password (Tailscale SSH), clear inactive credentials when saved, and retain server fingerprint verification. Existing password/key records remain unchanged. Mac native tests and a real passwordless terminal connection, Android analysis/tests and four SSH modes, Linux security/UI/terminal checks, and real Linux-to-Android encrypted sync passed. See [PASSWORDLESS-VALIDATION.md](PASSWORDLESS-VALIDATION.md).

The new Mac copy is `~/shivansh/notsg/Harbor/Harbor-1.1.1.app`; quit the old app before opening it. The signed Android update is also copied to `~/Downloads/harbor-1.1.1-android.apk` on the supplied Mac. Upgrade Android before syncing passwordless hosts because older versions reject the new authentication value. All installers and the source archive use `1.1.1` filenames. Existing app copies and vaults are preserved.

## Version 1.1: interface redesign

The user rejected the first version's visual quality, first-host form and address-driven pairing flow. Version 1.1.0 redesigns all three platforms with simpler host forms, automatic network selection and QR-first pairing. The researched brief is in [UI-REDESIGN.md](UI-REDESIGN.md); the reviewed screenshots and runtime evidence are described in [UI-VALIDATION.md](UI-VALIDATION.md). Root handled research and visual/integration review; the existing Sol high agents wrote the platform implementations. Prior functional validation below describes version 1.0.0. Updated binaries and screenshots use `1.1` filenames in `artifacts/`. On the supplied Mac, `Harbor-1.1.app` is staged beside the original app; quit the old copy before opening the update. Existing vaults are retained.

## Objective

Build Swift macOS, Qt Linux and Flutter Android SSH managers. Desktop authority, encrypted read-only Android sync, actual terminals, dark mode. User asleep; resolve routine choices autonomously. No implementation comments, minimal modular code. All implementation by GPT-5.6 Sol high agents.

## Completed assignments

- `/root/linux`: Linux app, user-local Qt/compiler setup, terminal and desktop sync.
- `/root/android`: Flutter SDK/Android tooling, Android app, signed APK, unit/widget and native emulator tests.
- `/root/macos`: Swift app and reproducible Mac build.
- Root: research, protocol/design contract, integration review and verification coordination.

## Environment

Initial workspace: Ubuntu 26.04.1. Linux development tools were bootstrapped without system changes: Qt/compiler under `/tmp/harbor-sysroot`, Flutter, Android SDK, Java and Swift under `/home/notsg/.local/share/harbor-tools`, Python QA environment under `/tmp/harbor-qa`. On 2026-09-19 the user provided SSH access to their Mac and authorized normal tool installation/app storage. Mac project: `/Users/notsg/shivansh/notsg/Harbor`, with Xcode 27/Swift 6.4 and the official Apple Metal compiler installed for the build.

## Decisions

- Working product name Harbor.
- Protocol defined in PROTOCOL.md: AES-GCM application encryption, Ed25519 signed snapshots, explicit QR comparison/approval, desktop pinned SSH host keys.
- Linux uses Qt Widgets with QTermWidget to avoid an unnecessary QML/terminal bridge.
- Dark design: navy surfaces, restrained blue action accent, standard platform fonts, monospace only in terminal/address displays; sidebars and session tabs on desktop, searchable host list and session toolbar on Android.
- Work used a persistent goal and these durable checkpoints. No five-minute timer was installed or claimed. Goal continuation was the available mechanism, rather than an unverified idle-message scheduler.

## Verification

Linux Release app, askpass helper, security tests, live protocol tests and Debian package are built. Real QTermWidget sessions passed password, key and encrypted-key authentication, Unicode, resize, physical keyboard editing, Vim alternate-screen operation and changed-key rejection. Independent Python protocol tests cover pairing binding, approved-response retry, encrypted signed snapshots, tampering, deletions, revocation, lock, malformed framing, incomplete requests and non-reading response deadlines.

Actual Dart code paired and synced with Linux, observed deletion and rejected revoked sync. Dart SSH passed password, key and encrypted-key authentication with both Ed25519 and RSA server keys, command execution, PTY and resize. Final Flutter analysis is clean and all seven tests passed independently. The signed release APK also passed native API 30 emulator checks: real PIN gate, pairing/full sync, encrypted persistence, cold restart, all three SSH authentication methods, terminal software-keyboard input, background lock, and offline-desktop SSH. Screenshots and binaries are in `artifacts/`.

Native universal Mac Release build succeeded. Eleven native XCTest cases passed, including all three SSH authentication methods through the real credential helper, command execution, server-side PTY resize, changed-key rejection, encrypted storage and the actual loopback pairing/sync listener. A separate twelfth fixture test passed with Android's actual Dart client pairing and syncing directly over the Mac's `100.64.x.x` address. Root inspected the native terminal bitmap. See MAC-VALIDATION.md.

## Review progress

Review corrections include invalidating server trust after address changes, single-instance desktop vault ownership, scoped credential helpers, approved pairing retries after dialog dismissal and new invitations, serialized mobile operations, correct lazy-list group headers and authenticated Mac startup. Mac's terminal delegate blocks implicit OSC52 clipboard access. Linux bounds both request reads and response writes. Android counts human terminal input without allowing automatic remote replies to keep the idle lock alive.

Latest available test harnesses: `linux/tests/security.cpp`, `linux/tests/sync_fixture.cpp`, `android/test/protocol_test.dart`, `android/tool/integration.dart`, `android/tool/ssh_check.dart`, `macos/Tests/HarborTests.swift`.

## Handoff

Linux and Android binaries, source archive, screenshots and checksums are collected in `artifacts/`. Source is committed locally. See TEST-RESULTS.md for the executed evidence and README.md for installation. SDKs and private Android release signing material remain under the user-local tools directory for future builds. Disposable services and credentials are cleaned up after testing.

The Mac app and updated Linux/Android artifacts are delivered with the source. Remaining release checks are interactive owner authentication, manual QR approval in the release UI, broader device/OS compatibility, and Developer ID signing/notarization. Windows, cloud service, desktop-to-desktop sync and app-store publication remain outside scope.
