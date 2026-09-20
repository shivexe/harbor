# Harbor 1.2 UX revision

## Brief

The working SSH engine is retained. The interface needs the density, hierarchy and predictable interactions of a desktop utility, with a coordinated Android companion. Success means complete, usable flows at small sizes as well as better screenshots. Existing data, strict server identity checks, encrypted storage and read-only Android configuration remain compatible.

## Research

- [Reddit: How can you tell a design is AI?](https://www.reddit.com/r/UI_Design/comments/1uchh8o/how_can_you_tell_a_design_is_ai/) and [AI fatigue](https://www.reddit.com/r/UI_Design/comments/1tvb91q/ai_fatigue_from_seeing_same_designs/) describe repeated visual templates and inconsistent decisions. These are qualitative community opinions, not usability studies.
- [Reddit: modern SSH clients](https://www.reddit.com/r/macapps/comments/1j344zu/best_modern_terminalssh_client_with_a_clean_ui/) emphasizes ordinary terminal usability and familiar keyboard behavior. Harbor should prioritize the terminal and server library.
- [Linear's 2024 redesign](https://linear.app/now/how-we-redesigned-the-linear-ui) informed density and alignment. [Its 2026 refresh](https://linear.app/now/behind-the-latest-design-refresh) informed quieter navigation and consistent action placement. These principles support a native utility; they do not prescribe copying Linear's UI.
- [Panic Prompt](https://panic.com/prompt/) provides a native SSH reference. Its [key import guidance](https://help.panic.com/prompt/prompt-key-security/) distinguishes private keys from public keys and unsupported PuTTY files. Harbor needs equally clear validation and direct entry.
- [Rauno Freiberg's interaction work](https://rauno.me/craft) and [Emil Kowalski's animation examples](https://emilkowal.ski/ui/good-vs-great-animations) informed the review of focus, expansion and transitions. Motion should explain a user action, without delaying frequent operations.
- X searches located posts by [Karri Saarinen](https://x.com/karrisaarinen/status/2046307519816216718) and [Neta Dror](https://x.com/netadror/status/2049581817229983932). Direct access returned empty content or HTTP 403, so their contents are not presented as verified evidence. Dror's [own site](https://hadigitalit.com/) independently lists a talk about poor AI product design.

## Design direction

Use a compact native workstation: charcoal gray, white text, conventional blue actions, restrained outlines and platform typography. Replace oversized headings, lavender fills, ornamental icons and large undifferentiated gaps. No decorative gradients, glass backgrounds, hero panels, promotional copy or invented server status.

Base tokens: canvas `#242426`, navigation `#1C1C1E`, input/raised `#303033`, main text `#F2F2F2`, secondary text `#B1B1B6`, action text `#409CFF`. Use white on filled blue at a darker fill (`#0068D9`). Root calculated main text on canvas at 13.84:1, secondary on raised at 6.16:1 and white on the filled action at 5.27:1. The initial `#0A84FF` text accent reached only 4.25:1 on canvas, so it was replaced with the lighter link color before review. Semantic success/error colors accompany text or icons. Native control rendering is preferred where it gives better platform behavior.

SF Pro on Mac, the desktop system sans on Linux, Roboto on Android; terminal monospace is reserved for shell and exact addresses/fingerprints. Desktop body/control size about 13–14 points, section headings 15–16, page titles 18–20. Android body 16, screen titles 20–24; retain 48-point touch targets. Spacing uses 4/8/12/16/24; desktop button heights 30–34, input heights 32–36, corners 5–6. Mobile fields/buttons can be taller with 8-point corners. A 42–48-point desktop toolbar replaces the oversized page header.

Desktop composition:

```
Hosts                 + | Selected host                 Connect  …
Search hosts            | ----------------------------------------
Group                   | Connection
  name                  | Hostname     gateway
  username@address      | Username     shivansh
                        | Port         22
                        | Authentication    No password
                        |
                        | Server identity                Verify…
                        | Approved fingerprint / Not verified
                        |
Devices             Lock| Notes (only when present)
```

Keep the useful master/detail layout but rebuild its proportions and information hierarchy. A 220–250-point sidebar holds searchable hosts; aligned rows make connection details readable. Contextual toolbar actions avoid a second oversized title/action cluster. Delete belongs in a labeled menu with confirmation. Selecting a host must reveal its details even while other sessions exist, without disconnecting those sessions. Active session tabs remain compact and closable, with an obvious route back to host details. Empty states are concise and task-specific.

Android composition: a single Hosts app bar with visible Sync and an accessible overflow menu, one compact desktop/sync status line, search, then grouped edge-to-edge rows. Avoid a second Hosts heading below the app bar. Onboarding introduces pairing in a short sentence and a clear Scan QR code action. Pairing and recovery preserve context; user-facing text says what to do next. Terminal chrome gives the shell maximum room.

## Required flow changes

- Host editor: compact labeled form with hostname and port, username, authentication and the applicable secret control. Optional display name/group/notes live under a full-row More options button that responds to its label and keyboard. Expansion brings the new fields into view and keeps Save/Cancel fixed. Collapse/re-expand preserves drafts. Keyboard traversal is predictable.
- Private keys: Import file and Paste key are explicit alternatives. Paste uses a separate bounded editor and confirmation; the main form shows a saved/imported state, not existing secret contents. Reject public keys, unsupported formats, invalid/truncated material and oversized data with actionable errors. Do not read the clipboard automatically. Cancel preserves the previous key. File and paste paths share validation. Encrypted key passphrases remain supported; opening options must not clear credentials.
- Pairing: large readable QR in the normal path. Network options opens a dedicated, clearly titled view/sheet or coherent panel with a Back action. Network choices are usable immediately, have friendly names and secondary addresses, and regenerate the QR when changed. Do not replace the QR with blank space or expand controls off screen. Cancellation, expiry, rejection, approval, revocation and sync availability must have explicit outcomes.
- Session exit: normal remote shell termination closes its terminal tab/route and returns to another active session or the selected host. Unexpected transport failure retains actionable recovery. Detect process/channel completion, not typed text, so an `exit` inside a subshell does not close the application session prematurely.
- Android pairing replacement: retain the old pairing and hosts until the replacement's first verified snapshot succeeds. Failed sync cannot silently erase usable configuration. Keep Android read-only.

## Acceptance and review

Each platform owner must provide actual runnable interaction checks and captures. Model-only assertions cannot establish that a control is clickable or a field is visible. Use isolated QA vaults, disposable keys and test servers; do not alter the owner's saved records.

Cover create/edit/save/reopen/search/clear/group/delete/cancel; invalid input; key import and direct entry including passphrase/cancel/replace; full-row options toggling and changed advanced values; pairing network open/change/back, QR decode, compare/approve/reject/cancel/retry/expiry, repeat sync and revocation; no-password/password/private-key/encrypted-key SSH, trust rejection, connection failure retry/edit, normal exit, unexpected disconnect, multiple sessions and lock. Inspect ordinary and small windows plus large mobile text. Record what actually ran and any environment limits in a new validation report.

Critique before delivery: compare real before/after screens, check all action targets and overflow controls, remove redundant headings and decorative borders, verify long endpoints and fingerprints, inspect focus and text contrast. Package only after the relevant regressions pass.
