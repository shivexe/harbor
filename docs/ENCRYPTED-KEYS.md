# Passphrase-encrypted private keys

Harbor 1.2.0 accepts passphrase-encrypted OpenSSH keys and common encrypted PEM keys. On the desktop, import a private-key file or choose Paste key, enter its passphrase, and save the host. Sync the host to Android to use the same credentials there. Android keeps host configuration read-only.

The original encrypted key text and its passphrase are stored inside the encrypted vault and transferred through signed, encrypted sync. Decryption needed for authentication happens in memory. The app does not replace the saved encrypted key with a decrypted copy. Passphrases are not put in process arguments, environment variables or logs.

## Compatibility

| Container | Linux | macOS | Android |
| --- | --- | --- | --- |
| Encrypted OpenSSH | Native OpenSSH; Ed25519 tested | Native OpenSSH; Ed25519 tested | dartssh2; bcrypt Ed25519 tested, including a 100-round fixture |
| Encrypted PKCS#8, PBES2/PBKDF2/AES-CBC | RSA, P-256 EC and Ed25519 authenticated | Native RSA validation and direct SSH authenticated | RSA, NIST EC and Ed25519 authenticated |
| Traditional encrypted RSA PEM | AES-256-CBC authenticated | Delegated to system key tools; not separately authenticated in this revision | Existing parser; encrypted RSA regression passed |
| Traditional encrypted EC PEM | AES-256-CBC authenticated | AES-256-CBC validation passed | AES-CBC adapter; real SSH passed |

Android supports PBKDF2 HMAC SHA-1, SHA-256, SHA-384 and SHA-512 with AES-128/192/256-CBC. PKCS#8 contents may be RSA, NIST P-256/P-384/P-521 EC or a standard 32-byte Ed25519 seed. Tested vectors exercise AES-128/192/256 and SHA-1/SHA-256; this does not claim every algorithm combination was independently authenticated. Unsupported containers and algorithms produce an explicit error.

Desktop compatibility also depends on the installed OpenSSH/OpenSSL implementation. A key accepted by a native desktop tool is not a guarantee of Android compatibility outside the matrix above. PuTTY PPK files and public-key files are not private-key imports.

## Validation and resource limits

Import and paste share validation. Encrypted input can remain a draft while a passphrase is entered. Missing or wrong passphrases preserve the editor and previous saved host. Replacing a key clears the previous passphrase. Save-time desktop validation runs away from the UI; cancellation or vault locking discards pending results.

Private-key input is limited to 256 KiB. Android bounds PBKDF2 to 2,000,000 iterations with an 8–64-byte salt, and OpenSSH bcrypt to 1,024 rounds with a 1–64-byte salt. Derivation runs in an isolate. Linux bounds PKCS#8 PBKDF2 work before calling OpenSSL and bounds external OpenSSH validation with a timeout. Mac validation uses a bounded system-tool subprocess with a three-second deadline and termination fallback. Mac PEM passphrases are limited to 4096 UTF-8 bytes; Linux accepts up to 32 KiB. Desktop validation rejects NUL and line breaks in passphrases.

Linux passes OpenSSH validation material through protected, sealed anonymous file descriptors and uses an in-memory callback for PEM. Mac writes only the original encrypted key into a mode-0600 temporary file, supplies the passphrase through bounded stdin and discards tool output. Android uses the existing ASN.1 and cryptographic libraries to adapt unsupported envelopes in memory before passing keys to dartssh2.

## Evidence

Android passed all 30 tests during the encrypted-key revision. The final bcrypt compatibility change passed all eight focused key tests and static analysis, including a real 100-round OpenSSH fixture and rejection of 1,025 rounds before derivation. Real SSH tests authenticated RSA, EC and Ed25519 encrypted PKCS#8 keys and traditional encrypted EC.

Mac's final native suite executed 29 tests with nine opt-in fixture skips and no failures. Coverage includes correct/wrong/missing passphrases, malformed keys, invalid passphrase characters and size boundaries, early child exit, asynchronous save progress, canceled completion, encrypted reload and unchanged wire data. An isolated native OpenSSH session authenticated with encrypted PKCS#8 RSA. A newly signed Debug credential helper requires fresh interactive Keychain approval, so a new app-integrated encrypted-PEM session remains unverified; the previously approved bundle completed password, plain-key and encrypted-OpenSSH sessions.

Linux's final validation is recorded in [UX-VALIDATION.md](UX-VALIDATION.md). The implementation authenticated six encrypted variants: PKCS#8 RSA/EC/Ed25519, traditional RSA/EC and encrypted OpenSSH Ed25519. Disposable fixture keys checked into the Android tests are public test vectors and must never be authorized on a real server.

## Primary references

[OpenSSL pkey](https://docs.openssl.org/3.0/man1/openssl-pkey/) documents password input sources and output suppression. The [dartssh2 source](https://github.com/vicajilau/dartssh2), specifically the pinned 4.1.0 implementation, establishes its supported formats. [OpenSSH's key parser](https://github.com/openssh/openssh-portable/blob/master/sshkey.c) provides the native PEM parsing reference; actual OS builds still require runtime tests.
