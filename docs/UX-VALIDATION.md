# Harbor 1.2.0 UX validation

This report concerns the revision in [UX-REVAMP.md](UX-REVAMP.md). The original UX checks and the subsequent encrypted-key checks are separated below. Earlier release evidence does not count as a rerun against this version.

## Required evidence

| Area | Observable result |
| --- | --- |
| Host library | First save selects the host; edit survives reopening; search can clear; group and delete actions work. |
| Host details | Details are accessible while sessions remain open, including clicking the already selected host. |
| More options | Clicking the label or activating with the keyboard reveals usable fields in the viewport; values survive collapse and save. |
| Private key | Import and direct entry preserve the previous draft on error/cancel; saved keys survive encrypted reload and authenticate. |
| Pairing networks | Options has a coherent layout; network selection updates the QR endpoint; Back returns to a readable QR. |
| Pairing lifecycle | Comparison can interrupt network options; approval, rejection, cancellation and expiry have clear results. |
| Sync | First/repeated sync updates read-only hosts; failed replacement pairing retains previous usable data. |
| Terminal lifecycle | A normal remote shell exit removes the tab/route; a transport failure keeps recovery. |
| Session navigation | Multiple sessions can be resumed and closed; viewing a host does not destroy them. |
| Lock and persistence | Lock removes visible hosts and active sessions; unlocking/restart restores encrypted saved data. |
| Visual review | Ordinary/small windows, long content, keyboard focus and large mobile text remain usable. |

## Execution record

Native Mac, Qt Linux and Android emulator workflows were exercised with isolated vaults and disposable services. Screenshots alone are not evidence of a completed end-to-end workflow.

Root reran `python3 shared/verify_protocol.py`: AES-GCM, AAD/tampering, Ed25519, comparison-code and PBKDF2 vectors passed.

The Android owner executed these checks on the API 30 emulator against disposable Linux SSH and sync fixtures:

- Native PIN unlock; camera permission denial with usable fallback, retry, permission grant and live scanner view. Pairing used a pasted one-time invitation, followed by the first signed encrypted sync of four hosts.
- Real SSH password, unencrypted key, encrypted key and credential-free authentication. Commands entered through the Android keyboard created server-side markers. Normal shell exit removed the route and session card in all four modes; exiting a nested shell preserved the main session.
- Two simultaneous sessions; one ended while in the background and its card disappeared without closing the other. Explicit close removed the remaining session.
- Repeat sync propagated a removed desktop host. Desktop revocation blocked further sync while preserving three saved hosts and direct SSH access.
- Backgrounding an active terminal locked the app. PIN authentication restored saved hosts with no active sessions. Force-stop and cold launch also required authentication and restored saved data.
- WindowManager confirmed `FLAG_SECURE`; secure preferences contained none of the fixture password, private key, host IP or sync key in plaintext.

The native replacement-pairing check also passed: Switch desktop and its confirmation opened; cancellation preserved the original three hosts. A second listener approved pairing through a disposable proxy that returned HTTP 503 for the first sync. Android explained that the old hosts remained available, and Done returned to the original three hosts. Canceling Unpair also retained the library.

Before the encrypted-PEM addition, Android checks passed: `dart format lib test` made no changes, `flutter analyze --no-pub` was clean, and `HARBOR_CAPTURE_PROGRESS=1 flutter test --no-pub` passed all 22 tests. The signed release APK reports `dev.harbor.app`, version 1.2.0, code 5 and verifies with APK Signature Scheme v2. Its signing certificate is the existing Harbor release identity. The release installed on the isolated emulator, launched, authenticated with the device PIN and showed onboarding with `FLAG_SECURE` enabled. Native end-to-end flows above used the Debug QA build; the release install/unlock was a separate smoke test.

The Linux owner ran the real Qt interaction fixture against an isolated vault: imported a key through the file chooser, rejected a public-key paste without closing the dialog, accepted a valid CRLF private key, canceled a replacement without losing the previous key, preserved advanced form drafts, exercised grouped search, and approved pairing. Real QTermWidget sessions passed all four authentication modes, command input, Unicode, resize, keyboard editing, Vim, changed-key rejection, same/different host selection without losing sessions, subshell exit and final shell exit. The connection fixture passed refused port, wrong credentials, changed key, denied shell, first-use trust, delayed/spoofed banner, cancellation, edit-and-retry, and an actual abrupt SSH transport drop that preserved recovery. The compact fingerprint panel was corrected after this run exposed clipping.

Before the encrypted-PEM addition, Linux commands passed with Qt's offscreen platform and the local Qt/QTermWidget runtime configured:

```sh
ctest --test-dir linux/build --output-on-failure
linux/build/harbor-ui-fixture /tmp/harbor-revamp-captures
linux/build/harbor-gui-fixture .work/qa-linux-android/ssh/hosts.json /tmp/harbor-revamp-captures/linux-1.2.0-terminal.png
linux/build/harbor-connection-fixture .work/qa-linux-android/ssh/none.json .work/qa-linux-connection/delayed/none.json .work/qa-linux-connection/reject/none.json /tmp/harbor-revamp-captures .work/qa-linux-disconnect/ssh/none.json
/tmp/harbor-qa/bin/python shared/test_sync_integration.py ./linux/build/harbor-sync-fixture
```

CTest passed 1/1 security test. The independent live protocol suite verified pairing binding, encryption, pinned signatures, fresh request IDs, tamper rejection, bounded framing, deletion, revocation, lock and the non-reading response deadline. The Linux release package reports version 1.2.0 and architecture amd64. These are real Qt widgets, SSH processes and sockets, but offscreen automation does not establish compatibility with every Linux window manager.

The Mac owner used isolated native windows with mouse events and Vision OCR to verify More options expansion/collapse, visible advanced fields, Network options navigation and Back. A mouse-driven Save host check persisted and reopened an encrypted record. Native key validation and encrypted reload passed CRLF, encrypted-key acceptance, public/truncated/oversized rejection and absence of plaintext key data in the archive. A real nested shell exit retained its session; the final remote exit removed it. A separate SSH server aborting the transport kept Retry/Edit/Close visible. The grouped library was captured at 900×600 using the production hidden-titlebar style.

Root reviewed actual Mac editor, host details and pairing captures, Qt editor/details/network captures, and Android widget captures of onboarding, hosts, progress and recovery. Review corrections included compact form proportions, expanded-field visibility, a fully painted network dialog, clear text instead of an unsupported glyph, contrast-safe links and removal of duplicated headings.

Root independently decoded the rendered Mac and Linux pairing QR images using zxing-cpp. Each contained a complete version-1 Harbor invitation with the required pairing and cryptographic fields. This checks rendered QR readability, not a physical phone camera or network reachability.

## Encrypted-key follow-up

Android's encrypted-key revision passed all 30 tests and static analysis. The final change raised the bounded bcrypt ceiling to 1,024; eight focused key tests and analysis passed again, including an independently generated 100-round OpenSSH key and rejection of 1,025 rounds before derivation. Real disposable SSH tests authenticated original encrypted PKCS#8 RSA, EC and Ed25519 keys and traditional encrypted EC. The final release APK is version 1.2.0, code 5, signed with the existing release certificate and verified with APK Signature Scheme v2. The earlier native release smoke test predates the encrypted-PEM adapter; the later adapter has unit and live SSH coverage.

Mac's final native suite executed 29 tests, with nine opt-in fixture skips and zero failures. Its PEM and asynchronous-save cases cover correct/wrong/missing passphrases, NUL/line-break and 4096/4097-byte boundaries, corrupted ciphertext and early child exit, truncated input, progress, canceled completion, failed-save draft preservation, canceled paste, and exact encrypted vault/wire reload. Direct native encrypted-PKCS#8 SSH passed. The Keychain limitation below applies to the newly signed app-integrated fixture.

Linux's final review reran security both with and without external key fixtures, the key editor, six encrypted-key SSH variants, the full UI fixture, and the terminal GUI fixture. All passed. Editor checks include missing/wrong passphrase recovery, replacement, duplicate prevention, cancellation and vault lock during validation, and encrypted reload. Security checks include a 32 KiB passphrase, an early-exiting key tool and immediate malformed/excessive PBKDF2 rejection. The terminal fixture again passed all four original authentication modes, changed-key rejection, session retention, locking, keyboard editing and full-screen Vim. An intermediate offscreen keyboard/Vim run failed because its working directory lacked the QTermWidget keyboard layouts; rerunning with the correct layout directory passed. Root reran the final UI fixture with the configured DejaVu font environment and reviewed the compact editor capture; the host, pairing and deletion checks passed. The final DEB contains both Harbor and its askpass helper and reports version 1.2.0/amd64.

## Limits

Encrypted-key compatibility and resource limits are documented in [ENCRYPTED-KEYS.md](ENCRYPTED-KEYS.md). Native desktop tools may support formats beyond the Android adapter; the tested matrix is the compatibility claim, rather than every possible encrypted PEM variant.

Actual Android camera decoding is unverified. A bounded API 30 virtual-camera attempt loaded independently decoded QR images as emulator wall/table posters, but they did not enter the headless camera view and no scanner callback fired. Native camera permission denial/grant and scanner initialization passed; native pairing and sync used the supported paste fallback. No physical Android phone was available for this run.

Mac tests use disposable vaults and native QA windows. The owner's running app, vault and saved hosts were not used for testing. The newly signed Debug helper initially needed interactive Keychain approval. After the user approved it, password, unencrypted-key and encrypted-key sessions connected and executed commands without changing credential-access rules. After the encrypted-PEM and asynchronous-save changes, the final native suite executed 29 tests with nine opt-in fixture skips and no failures. The newly signed helper needs fresh Keychain approval for a new app-integrated encrypted-PEM fixture, so that case was skipped. An isolated direct native OpenSSH connection using encrypted PKCS#8 RSA passed. The staged universal Release app and helper contain arm64 and x86_64 slices and pass deep strict ad hoc signature verification; they are not Developer ID signed or notarized.
