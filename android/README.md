# Harbor for Android

Flutter app that pairs with a Harbor desktop, stores an encrypted copy of its hosts, and connects directly over SSH. Requires Android 7.0 or later and a device PIN, password, or pattern.

## Build and test

Install Flutter, Java 17, and Android SDK platforms 35 and 36. Run from this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

For a release build, configure your own signing key in the Git-ignored `android/key.properties`:

```properties
storeFile=/absolute/path/to/release.jks
storePassword=<keystore-password>
keyPassword=<key-password>
keyAlias=<key-alias>
```

Then run `flutter build apk --release`. Keep your signing key and passwords private; future updates require the same signing identity.

## Use

Unlock Harbor and scan the QR from **Devices → Pair Android** on your desktop. Compare the codes and approve. Tap **Sync** when you want desktop changes copied to your phone.

Host settings are read-only on Android. SSH connects directly to the server and works while the desktop is offline. Backgrounding Harbor or leaving it idle for five minutes locks the app and closes its sessions.

The keys under `test/fixtures/encrypted_keys` are public test data. Never authorize them on a real server.
