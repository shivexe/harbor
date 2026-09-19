# Native Mac validation

Validation started on 2026-09-19 after the user provided SSH access to their Mac. The project is at `/Users/notsg/shivansh/notsg/Harbor`. Existing personal files and SSH configuration are outside the work scope. The user clarified that normal tool installation and application storage are permitted.

## Environment and build

- Apple silicon Mac, macOS 27, Xcode 27.0 (27A266a), Swift 6.4.
- Source transferred from the local Git repository into a previously nonexistent Harbor folder.
- Apple Metal Toolchain was missing. Apple's downloader exported its bundle under `.work/tools/metal` and also registered the compiler through MobileAsset. The user was informed and confirmed that tool installation is acceptable.
- SwiftTerm remains pinned to 1.20.0. Its build plugin and generator were reviewed before command-scoped plugin validation was skipped; they generate package version information.
- Native Release build succeeded for both arm64 and x86_64. The app and its embedded credential helper are universal binaries.
- Build products, dependency checkouts, result bundles and logs are under `.work/`. The first successful native build log is `.work/logs/build-metal.log`.

## Changes prompted by validation

- Opening the locked app no longer creates its vault directory or cleans up Keychain/session data. Those actions occur only after successful device authentication.
- A terminal session only removes an askpass Keychain item if that session stored one.
- Debug tests can inject a disposable encrypted vault to exercise the actual listener and storage without authenticating as the Mac owner. This constructor is absent from Release and is not exposed by the app UI.
- The Mac's actual `100.64.x.x` address revealed a pairing-origin compatibility issue. Mac, Linux and Android now accept exactly RFC6598 `100.64.0.0/10`, with tests for both included edges and adjacent rejected addresses. Updated Linux and Android artifacts were rebuilt and checked.

## Results

The first native hosted XCTest run passed all ten tests with zero failures. It exercised the actual loopback Network.framework listener for pairing, approval, retry after another invitation, signed sync, deletion, revocation and lock; shared cross-platform vectors; encrypted vault persistence/tampering; host input validation; HTTP framing; invitation address constraints; and denial of automatic clipboard access. Result bundle: `.work/tests-native-first.xcresult`.

Debug tests ran with ad hoc signing and no Apple developer team. Build and test scripts now use the checked-in project if XcodeGen is absent, and reuse the repository-root `.work` build/dependency directories.

The expanded eleven-test native suite then passed with zero failures in `.work/tests-native-full.xcresult`. Its real SwiftTerm/OpenSSH test verified password, private-key and encrypted-private-key authentication through the Keychain helper, command execution, server-side PTY resizing, changed-key rejection and session cleanup. Root inspected `.work/mac-terminal.png`.

Android's actual Dart client subsequently paired directly over `100.64.207.29:48606` and verified two fresh signed encrypted snapshots. The separate Mac fixture test also passed: `.work/tests-native-dart.xcresult`. These fixture-only tests use disposable data and automatic approval only inside the Debug XCTest bundle, not the release UI.

The final Release build succeeded through `macos/scripts/build.sh`. The app was copied to `Harbor.app` in the project root, its helper and app were ad hoc signed, and deep/strict code-signature verification passed. The app was launched successfully and left running for the user. A universal ZIP is provided in `artifacts/`.

Interactive owner authentication, manual QR approval in the release UI and Developer ID signing/notarization are distinct manual release checks. The delivered app retains its normal authentication gate.
