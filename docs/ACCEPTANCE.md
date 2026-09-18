# Verification contract

Record executed commands and actual results in TEST-RESULTS.md. A source review is not a runtime test, and a Linux test cannot certify the Swift app. All fixtures use disposable credentials.

## Desktop management

- Create, edit, search, group and delete hosts; preserve edits across restart.
- Password and private-key credentials survive encrypted persistence. Wrong passphrase, corrupt tag and truncated file fail without replacing the vault.
- Never overwrite an unreadable existing vault as an empty new vault.
- Editing address or port invalidates prior server verification; explicit fingerprint verification precedes connection. Changing the server key blocks an existing record until desktop re-verification.
- Lock closes terminal sessions, clears visible host information and stops sharing. Cancelled unlock preserves data.
- Dark interface has readable focus, dialogs, errors and terminal text, with working keyboard navigation and window resize.

## Pairing and sync

- QR scan and paste reach the same parser; malformed or expired invitations are rejected before networking.
- Both ends compute the same comparison code; pairing waits for desktop approval.
- Rejected, cancelled and expired invitations cannot create a paired device. A valid retry obtains the same accepted response. A second device cannot reuse a bound invitation.
- Independent implementations agree on AES-GCM AAD, Ed25519 signature bytes, integer fields and base64 encodings through shared fixed test vectors.
- The actual Linux service interoperates with Android's Dart protocol code over loopback using a fixture origin; the production Android UI uses the LAN address.
- First sync, repeat sync, edits and removals replace the whole mobile snapshot. A failed sync retains previous valid data.
- Tampered ciphertext/tag, wrong signing key, bad signature, changed vault, wrong requestId, revision rollback, duplicates and invalid host data are rejected atomically.
- Revocation prevents another sync. Previously copied credentials remain usable until changed on SSH servers, as documented.
- Oversized requests, duplicate Content-Length, chunked uploads, invalid JSON and slow/incomplete requests do not crash or hang the listener.

## SSH sessions

- Real disposable SSH server: password login, private-key login and encrypted private-key login.
- Terminal carries input/output and control characters, Unicode, resize and connection close; a fake log panel is insufficient.
- Incorrect server identity fails before any password is disclosed. Missing desktop pin prevents mobile connection.
- Offline servers, bad passwords and abrupt disconnects produce understandable errors without orphaned processes.
- Session cleanup removes temporary private keys and askpass material.

## Build and handoff

- Linux CMake build and executable, automated checks and actual UI screenshot.
- Android flutter analyze, unit/widget tests, APK build; emulator checks if tooling permits. Identify debug signing versus release signing explicitly.
- macOS project, pinned dependency, helper embedding, syntax checks where possible, Mac test targets and build instructions. Native Xcode build/runtime validation remains pending without Mac access.
- Source code contains no explanatory comments written for this app; third-party files/license notices are preserved as required. Build tools' mandatory metadata directives are not stripped blindly.
- Repository excludes local credentials, SDKs, build caches and temporary test identity material. Artifacts have filenames/checksums and a documented launch path.
