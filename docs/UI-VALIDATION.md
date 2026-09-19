# Version 1.1 interface verification

This record covers the redesign requested after the user reviewed version 1.0. The design research, audit and intended flows are in [UI-REDESIGN.md](UI-REDESIGN.md). Earlier SSH and protocol evidence remains in [TEST-RESULTS.md](TEST-RESULTS.md); it must not be mistaken for a rerun of every check against version 1.1.

## Visual review

Root inspected Android widget captures of onboarding, scanner layout, paste fallback, comparison and grouped hosts. The scan action is primary, the paste form is secondary, and the comparison remains within the pairing route. The scanner image uses an explicitly labeled test camera placeholder; it is not evidence of a physical camera scan.

Root inspected native Mac captures of the empty library, host editor, saved-host details and pairing. The normal editor shows hostname, username, authentication, password, More options and Save together. The saved record is selected and exposes Connect. Final captures include the revised graphite selection highlight and explicit field-focus rings.

Root inspected actual Qt captures of the same desktop flows. A second pass moved server identity controls into More options, simplified the empty Devices dialog, removed the isolated Overview tab until a session exists, and reduced sidebar button weight. Root accepted the final editor, small-window advanced form, selected host, Devices, QR, network options and comparison views. A capture-timing issue initially made field edges appear clipped; the fixture now waits for settled layout and asserts that the content fits the viewport at both normal and small sizes. Expanded network options use a separate state on the pairing page so controls cannot overlap the QR.

Both desktop pairing screenshots decoded successfully with the independent zxing-cpp decoder. Each contained a complete version-1 Harbor invitation with endpoint and cryptographic fields. Only disposable invitations were captured; their listeners are stopped after the test. This verifies rendered QR readability, not physical-device camera compatibility or network reachability.

The proposed text colors were checked mathematically: primary text on canvas 15.71:1, secondary text on canvas 8.18:1, secondary text on raised controls 6.59:1, dark text on action fill 9.12:1. Individual widget states still need visual inspection; palette ratios alone are not an accessibility certification.

## Runtime checks

The final Android source completed Flutter analysis without issues and passed all eleven tests. Coverage includes comparison, first-sync retry, replacement-pair session cleanup and the existing authentication/terminal/protocol checks. Native API 30 emulator validation confirmed system credential unlock; camera permission allow returning to the live scanner; camera denial with recovery guidance and paste fallback; actual invitation submission, encrypted pairing and first sync of three disposable hosts; direct password SSH; background lock closing the session; and reauthentication restoring saved hosts. Comparison was inspected in the widget capture because the autoapproving native fixture advanced too quickly for a native comparison capture.

The final small Android changes addressed session cleanup when a replacement desktop identity commits and the paste sheet's controller lifecycle. After those changes, the final APK was reinstalled and checked for retained hosts, force-stop/authentication, scanner/fallback entry and background locking while the fallback sheet was open. The complete SSH authentication matrix was not rerun against this UI-only revision; prior version 1.0 results remain separately documented.

Root verified the final Android APK signature and manifest: package `dev.harbor.app`, version 1.1.0/build 2, minimum API 24 and target API 36. The existing local release signing identity was retained. Disposable test listeners, files and the temporary emulator were cleaned up.

The Mac passed all thirteen self-contained native tests, covering the actual listener's pairing/retry/sync, cryptographic vectors, vault behavior, host validation, network filtering/ranking, display-name fallback and all four native screenshot captures. The two external-fixture SSH and Dart interop tests were excluded from this run because their disposable servers were not running; those passed during version 1.0 validation. The new native SSH implementation change is terminal colors only. Screenshot tests use a DEBUG-only injected vault and do not read or modify the owner's vault.

The version 1.1 universal Release build passed through `macos/scripts/build.sh`; its log is `.work/logs/build-ui-1.1.log` on the supplied Mac. Root checked both arm64 and x86_64 slices, version 1.1.0/build 2, signed the embedded helper and app ad hoc with hardened runtime, and passed deep/strict signature verification. The staged app is `~/shivansh/notsg/Harbor/Harbor-1.1.app`. It was not launched over the owner's running app. Quit the old copy before opening the update; the existing vault is retained.

Linux security CTest passed, including interface filtering/ranking checks. The separate UI fixture passed actual first-host saving/selection, small-window scrolling, automatic QR creation, a real encrypted pairing request, comparison, clicking Approve, persisted device identity and a successful encrypted retry. The actual QTermWidget fixture passed password/key/encrypted-key login, Unicode, remote resize, keyboard editing, Vim full-screen operation and changed-key rejection. A test-only dangling lambda capture in the screenshot fixture was corrected before the successful runs.

Root independently ran `shared/test_sync_integration.py` against the updated Linux listener. Pairing binding, authenticated encryption, pinned signatures, request freshness, tampering, framing bounds, deletion, revocation, lock and the ten-second nonreading-peer deadline all passed. The local test runtime used `/tmp/harbor-sysroot/usr/lib/x86_64-linux-gnu` and its `libproxy` subdirectory in `LD_LIBRARY_PATH`.

A final review removed an ephemeral-port fallback from Linux's production UI: the phone stores the pairing endpoint, so its port must remain stable across desktop restarts. Harbor uses port 45873 and reports a conflict instead of silently choosing a temporary port. The UI fixture then passed again while asserting the advertised fixed port. The regenerated Debian package reports version 1.1.0 and installs only the app, credential helper, desktop/icon resources and documentation.

## Delivery

The 1.1 artifacts comprise the Android APK, Linux Debian package, universal Mac ZIP, source ZIP and platform screenshots. Checksums are in `artifacts/SHA256SUMS`; copies are placed in the supplied Mac's `Harbor/artifacts/` directory. Source is committed locally. No cloud publishing occurred. The Mac app uses local ad hoc signing, and the APK uses the existing private release identity. A physical-phone camera scan and Developer ID notarization were not performed.
