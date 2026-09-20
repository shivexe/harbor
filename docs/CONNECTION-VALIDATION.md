# Harbor 1.1.2 connection validation

## Reported host-key failure

The error was reproduced with an approved key in a session directory containing spaces. OpenSSH parsed the unquoted `UserKnownHostsFile` option as multiple filenames and could not find the approved ED25519 key. Quoting the filename inside the option value allowed the same key to verify. Harbor now quotes that value correctly. Approved keys and strict verification are preserved.

## Android

Flutter analysis and sixteen tests passed. Widget checks cover terminal visibility before shell acceptance, stage ordering, rekey stability, read-only recovery, retry using the latest stored host, cancellation and compact layouts. Live production connection checks passed password, private-key, encrypted-private-key and SSH `none` authentication, plus delayed sign-in banners and missing/changed key rejection.

The terminal appears only after the SSH library accepts the shell request. A fifteen-second shell timeout bounds an unresponsive server. Sanitized server messages remain selectable during authentication. Spoofed connection-status text in a banner did not advance the connection stages. Retry and Edit on desktop remain visible in a footer at 320×568; the body scrolls.

The signed APK is version 1.1.2/code 4, minimum API 24 and target API 36. Its existing release signature verifies. Screenshots are widget captures of the application UI; no new Android emulator or physical-device run was performed for this patch.

## Linux

The real Qt/OpenSSH connection fixture passed successful shell opening, refused port, bad credentials, changed pinned key, rejected shell, first-key approval and persistence, pre-authentication sign-in messages, cancellation, and Edit Config followed by Retry with the updated username. It also ran with a runtime directory containing spaces and retained strict host-key verification.

The final Linux build, CTest security checks and first-host/encrypted-pairing UI fixture passed. Existing QTermWidget checks passed all four authentication methods, command execution, Unicode, PTY resizing, keyboard editing, full-screen Vim and changed-key rejection. The Debian package metadata is version 1.1.2 for amd64.

Root reviewed the failure and first-key screenshots. Recovery actions remain visible at small window sizes; a full fingerprint is available before approval. Server messages are plain text with ANSI and formatting controls removed. Their contents do not determine connection milestones. The terminal is shown only after OpenSSH reports acceptance of the shell request through its private diagnostic channel.

## macOS

The full native suite completed with twenty cases, four opt-in fixture skips and no failures. Focused live tests connected passwordless and unencrypted-private-key sessions under a root containing `Application Support`, checked actual terminal view mounting after shell acceptance, rejected an altered key, and verified immediate cancellation/cleanup. A delayed banner test kept the sign-in URL visible while forged connection-status text left the phase unchanged. Root reviewed the native connecting, failure and banner captures.

The terminal view is observed separately so phase changes mount the actual terminal after shell acceptance. Development validation also exposed a Keychain approval request for the newly signed Debug credential helper. Password and encrypted-key Mac checks were not validated in that signing environment because helper approval was pending; those fixture checks remain available. The helper's access controls were not relaxed. This does not affect the verified passwordless path.

The universal Release app and helper contain arm64 and x86_64, report version 1.1.2/build 4, and passed deep, strict ad hoc signature verification. The staged app was not launched against the owner's vault.

## Delivery

The updated Mac app is staged separately as `Harbor-1.1.2.app`; existing app copies and owner sessions are preserved. The Android APK is copied to the supplied Mac's Downloads folder. Versioned artifacts and screenshots are retained alongside earlier releases. Source and artifact checksums accompany the delivery.
