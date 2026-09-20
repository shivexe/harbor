# Harbor 1.2.1 icons and Mac installation

This revision replaces the Mac and Android launcher artwork and fixes the Mac icon declaration. SSH, vault and sync behavior are unchanged. Linux remains at 1.2.0.

## Design and production

The new identity uses a substantial ivory anchor on deep maritime blue. The anchor's squared eye, broad stock and upward flukes retain a recognizable silhouette at launcher sizes. The palette is `#F2F0E8` and `#214E57`. Platform exports share an editable SVG master; macOS uses a rounded tile, and Android supplies its own launcher mask.

The original Mac app included `Harbor.icns` but omitted `CFBundleIconFile` from its processed Info.plist. The build-setting value alone did not survive automatic plist generation. An explicit plist now declares the icon and retains the app's existing identity, version substitutions and usage descriptions. Native icon resolution is checked using an absolute app path.

Android previously used a single drawable as its launcher icon. The update provides legacy density assets for Android 7, separate foreground/background adaptive assets for Android 8 and later, and a monochrome variant for themed launchers on Android 13 and later. The app's existing interface colours are unchanged.

## Install on macOS

1. Quit the older Harbor copy, allowing any active SSH sessions to end normally.
2. In Finder, choose Go → Go to Folder and enter `~/shivansh/notsg/Harbor/artifacts`.
3. Open `harbor-1.2.1-macos-universal.dmg`.
4. Drag `Harbor.app` onto the Applications shortcut in that window.
5. Eject the disk image and open Harbor from Finder → Applications. It can also be found through Spotlight after indexing.

The copied app retains the same bundle identifier and uses the existing Harbor vault. Keep the old app closed while opening the installed version. Installation copies the app; running it directly from the mounted disk image does not install it.

This is a local ad hoc signed build, not a Developer ID notarized distribution. If macOS blocks first launch, follow Apple's per-app Open Anyway flow in System Settings → Privacy & Security. The credential helper may request Keychain access again for the new signature. No global security settings or credential-access rules need to be weakened.

## Verification

The macOS 1.2.1 build 6 app and credential helper contain arm64 and x86_64 slices. Strict deep ad hoc signature verification passed for the staged app, the app mounted from the DMG, and the extracted ZIP. The processed plist contains `CFBundleIconFile=Harbor.icns`. `NSWorkspace.icon(forFile:)` resolves the new artwork using an absolute app path; `artifacts/mac-1.2.1-icon.png` is the system-rendered result, including macOS's own surface treatment. The older app resolves to the generic app icon. The DMG was verified and mounted read-only; its Applications shortcut points to `/Applications`. No owner app was launched or installed over an existing copy.

The Android release reports `dev.harbor.app`, version 1.2.1, code 6, minimum API 24 and target API 36. APK signature verification passed with the same certificate as 1.2.0. Compiled resources contain five legacy density PNGs plus adaptive API-26 and monochrome API-33 definitions. The signed APK installed successfully on the isolated API-30 emulator, and PackageManager reported the expected version. A native launcher screenshot was blocked by that test emulator's existing PIN, which was left intact; the launcher UI and themed-icon rendering are not claimed as visually tested on a physical device. The emulator was shut down after verification.

Both SVGs parse and their PNG exports are 1024×1024 with alpha. The anchor's 702×740 source bounds are scaled to fit Android's safe area; the Mac tile has a transparent exterior and a 896×896 face. Root reviewed the vector export, legacy Android raster and actual macOS-resolved icon. `git diff --check` passed. SSH and cryptographic tests were not rerun for this icon-only patch; their 1.2.0 evidence remains in the earlier validation reports.

## Sources

- [Apple app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
- [Apple app installation instructions](https://support.apple.com/guide/mac-help/install-and-uninstall-other-apps-mh35835/mac)
- [Apple per-app first-launch approval](https://support.apple.com/en-us/102445)

## Artwork provenance

The built-in image-generation tool was used to explore the anchor concept. Its raster output had edge artifacts and is not shipped. The production artwork is a fresh, precisely constructed SVG with native platform exports.

The generation prompt was:

> Create one exceptionally well-designed app icon artwork for Harbor, a serious SSH terminal app for Mac and Android. This is a production logo asset, not a presentation/mockup/contact sheet. 1024x1024 square, transparent background. Only a centered warm ivory (#F2F0E8) anchor symbol, no app tile behind it. The anchor should be a custom crisp geometric silhouette, the visual quality of an established independent Mac software studio: confident weight, precise optical balance, unmistakable at 24 pixels. Its top eye is a small squared aperture with softly rounded corners; straight substantial vertical shank; simple horizontal stock; the bottom arms curve gently outward to decisive upward triangular flukes. Avoid thin strokes, rope, circles around it, outlines, shading, gradients, glow, 3D, texture, lettering, H monograms, ships, water, extra decorations. Flat two-dimensional vector-like artwork with clean edges and transparent negative spaces. Anchor silhouette should occupy about 650 pixels wide and 740 pixels tall, centrally balanced with generous transparent margin. This should feel like a sober handcrafted maritime instrument mark. No text whatsoever.
