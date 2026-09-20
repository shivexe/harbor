# Releases

GitHub Actions checks Android, macOS, and Linux on pull requests and pushes to `main`.

To test packaging without publishing, open **Actions → Release → Run workflow**, select `main`, and enter a version such as `1.2.2`. Download the installers from the completed run.

To publish, tag the tested commit:

```sh
git tag v1.2.2
git push origin v1.2.2
```

Use a new version for each release. The workflow takes the app version from the tag and supplies an increasing Android/macOS build number. After checks and all three builds succeed, it publishes one release containing an Android APK, universal Mac DMG, Ubuntu 26.04 AMD64 DEB, and SHA-256 checksums. Published releases are not overwritten.

## Signing

Android uses the existing release key stored in repository Actions secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, and `ANDROID_KEY_ALIAS`. Keep a separate private backup of that key. Replacing it prevents ordinary updates to existing installations.

The Mac app is ad hoc signed and not notarized. After copying Harbor to Applications and trying to open it, users may need **System Settings → Privacy & Security → Open Anyway**.

## Checks

Android runs analysis, tests, and a debug build. Linux runs CTest and protocol integration checks. macOS runs the noninteractive test selection and model checks; interactive Keychain, camera, and real-device checks remain manual. Release jobs also verify their packages before upload.
