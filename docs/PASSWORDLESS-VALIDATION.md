# Harbor 1.1.1: passwordless SSH

The desktop editors now default new hosts to **No password (Tailscale SSH)**. Enter a hostname and username, then save. Existing hosts retain their selected authentication method. Choosing No password clears inactive credentials before saving; the shared `authType: "none"` record requires empty password, private key and passphrase fields. Android accepts this record through its encrypted, signed snapshot path and remains read-only.

[Tailscale documents SSH `none` authentication](https://tailscale.com/docs/features/tailscale-ssh) for destinations running Tailscale SSH with access permitted by the tailnet policy. A regular SSH server reached over Tailscale can still require a key or password. Harbor keeps server fingerprint verification for all methods and does not use saved credentials or inherited SSH identities in No password mode.

## macOS

- Fourteen self-contained native tests passed, including credential clearing, validation and wire export for `none`.
- A separate native SwiftTerm/OpenSSH test scanned the disposable server key, connected with SSH `none`, reached a shell and executed a computed output marker. The session directory contained only `known_hosts`, with no private-key file.
- Root reviewed the native editor screenshot: all three authentication options, hostname, username, More options and Save remain visible without a credential field in No password mode.
- Universal Release app and helper contain arm64 and x86_64. Version 1.1.1/build 3 passed deep, strict ad hoc signature verification. The app is staged as `Harbor-1.1.1.app` beside existing copies; no owner app or vault was replaced or opened during testing.

## Android

- Flutter analysis and all eleven tests passed. The encrypted, signed snapshot regression imports a clean `none` record and rejects a record containing stale credentials.
- The production Dart SSH client passed password, private-key, encrypted-private-key and SSH `none` authentication against a disposable server, including command execution, an interactive PTY and terminal resizing. Missing and changed server keys were rejected for the passwordless host.
- The existing SSH library sends `none` when neither a password callback nor an identity is supplied; no new SSH dependency or custom authentication implementation was needed.
- The APK retains the existing release signing identity. Signature verification passed; metadata is version 1.1.1/code 3, minimum Android API 24, target API 36.

## Linux

- CTest security checks passed, including accepting empty credentials for `none` and rejecting stale password, key or passphrase data.
- The real Qt editor fixture saved a new host using only hostname and username, then verified that changing a password host to No password clears its previous secret.
- Actual QTermWidget sessions passed all four authentication modes, including SSH `none`, command execution, Unicode, resizing, keyboard editing and full-screen terminal behavior. An altered server key on the passwordless host was rejected.
- Passwordless sessions bypass the credential helper and socket while retaining strict server-key checking. New UI evidence uses `1.1.1` filenames to preserve prior release screenshots.

## Cross-platform sync

Root independently paired the Android Dart client with the rebuilt Linux sync listener using the four-host fixture bundle. The client verified all four records at revision 5, including `none`, and successfully repeated sync with a fresh request identifier.

These checks use a disposable server implementing the same SSH authentication method as Tailscale SSH. They do not change or test the user's tailnet access policy. Physical Android-device testing and Mac Developer ID notarization are outside this patch's validation. Earlier UI and native Android emulator evidence is in [UI-VALIDATION.md](UI-VALIDATION.md).
