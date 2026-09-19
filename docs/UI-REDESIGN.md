# Harbor interface redesign

## Brief and research

The first version passed functional tests but failed the user's usability and visual expectations. This revision addresses the whole workspace, with first-host creation and QR pairing as the acceptance priorities. A recolor alone does not satisfy the brief.

Reviewed references:

- [Termius product interface](https://www.termius.com/): a searchable host collection, groups and a persistent terminal workspace. Borrow the clear library/session separation, not cloud accounts, marketing copy or unrelated features.
- [Termius groups documentation](https://docs.termius.com/): groups organize connection records. Harbor's existing groups remain useful navigation; no new inheritance system is needed for this redesign.
- [Panic Prompt's Mac server editor](https://help.panic.com/prompt/prompt-mac-new-server/): an optional nickname falls back to the server address, and advanced settings have a separate entry point. This supports simplifying Harbor's initial form without losing connection controls.
- [Apple onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding): let the first real task teach the app and postpone optional setup.
- [Apple Form](https://developer.apple.com/documentation/swiftui/form) and [Material text fields](https://m1.material.io/components/text-fields.html): group related input, keep labels identifiable and explain errors where users can correct them.
- [Signal device linking](https://signal.org/blog/a-synchronized-start-for-linked-devices/): a QR code carries the information required to bootstrap encrypted pairing. Harbor already has this capability; network configuration should not precede it in the normal UI.

The design decisions below are Harbor's interpretation of those references. They do not claim that another product implements Harbor's local-network protocol.

## Audit

- Mac first-save leaves selection empty, so the first-host invitation persists after a successful save.
- The Mac editor gives every field equal weight, disables scrolling, and can crowd its own Save/error area.
- Desktop pairing asks for a raw address before showing the existing QR code. Mac can default to loopback, and Linux offers container bridges ahead of useful network choices.
- Android makes scanning secondary to pasting an opaque invitation. Scanning then loses context when the comparison code appears in the hosts screen.
- Desktop chrome, host details, device dialogs and mobile screens use inconsistent spacing and weak action hierarchy. Existing screenshots mainly prove terminals work; new verification must inspect the actual onboarding and form states.

## Visual system

Use graphite surfaces rather than the current uniformly navy panels. Colors: canvas `#17191F`, sidebar `#1D2028`, raised/input `#272B35`, primary text `#F1F2F6`, secondary text `#ABB1C0`, action `#A8B8FA`. Success and error may use semantic colors, with icons/text as well as color. Bright accent fills need dark, legible button labels. Borders separate regions, not every sentence.

Use SF Pro on Mac, the native Linux sans family, and Roboto on Android. Monospace is reserved for terminal content, server endpoints and comparison codes. Desktop text: 28-point main heading, 18-point section heading, 14-point body/control, 12-point supporting text. Mobile body is 16, secondary 14. Use 8/12/16/24/32 spacing deliberately, desktop controls at least 36 high and mobile touch targets at least 48. Rounded inputs about 8 points, dialogs about 16; avoid large pill buttons everywhere.

The characteristic visual is a quiet, persistent server sidebar next to a generous working area. An active session owns the canvas. No decorative gradients, fake terminal output, made-up online badges, metrics, or nonfunctional navigation.

## Desktop layout and first host

```
Harbor / library sidebar  | Hosts                    Add host
Search                   | ---------------------------------
Group                    | First-use: Add your first host
  host                   | Hostname, credentials, then connect.
  host                   | [Add host]
                         |
Devices             Lock | Selected: name / endpoint / Connect
```

Keep alignment predominantly left. Reduce oversized titlebar padding and inconsistent tiny controls. The initial workspace has one clear task and a short description. Once saved, select the new host and show its real connection details and Connect action. Existing hosts with no selection must not show first-use copy. Search-empty is a distinct state with a clear-reset action. Preserve session tabs, group navigation, keyboard shortcuts and visible focus.

The host editor is a bounded, scrollable sheet/dialog with persistent Cancel and Save host actions. Show Hostname or IP, Username, an explicit Password / Private key choice and only the applicable credential fields. Display name is optional, falling back to the hostname. Port defaults to 22; port, group and notes live in a collapsed More options section, expanded for edits with nondefault values. Labels remain visible while typing. Import key is a clear file action. Preserve imported credentials while merely opening optional sections. Validate before persistence; keep failures in the editor. Fingerprint trust remains an explicit informed action; do not silently trust or conflate endpoint inspection with credential validation.

## QR pairing

Devices → Pair Android → a large crisp QR appears immediately → Android scans → both show the comparison code → desktop approves → paired confirmation and first sync.

No address or port input, no separate enable-sharing prerequisite, and no raw JSON in the normal desktop path. Discover eligible interfaces when pairing starts, prefer a physical private LAN, include Tailscale/private VPN, avoid loopback and container bridges as defaults. If necessary, Connection options exposes friendly network choices such as Wi-Fi, Ethernet and Tailscale; never make users type an address. A QR contains the chosen endpoint and existing secret. Network reachability is not guaranteed merely by discovering an interface; explain same-network/private-VPN requirements and provide Retry/network switching. If there is no eligible network, show a clear recovery state rather than a loopback QR. Keep existing wire format and cryptographic checks.

Render QR at roughly 280 points/pixels or larger with its white quiet zone intact. Desktop states are preparing, scan, compare, paired, expired and failed. Comparison replaces the QR as the dominant action when a request arrives. Approved-response retries must continue working after the UI changes state. Expired codes must be visibly unusable with Generate new code. Devices remain manageable independently, with revocation confirmation. Sync availability is secondary information, not the pairing entry point.

Android's primary onboarding action is Scan QR code, which opens the scanner immediately. Keep camera permission/scan errors actionable. Paste invitation is a secondary fallback sheet, never the default large form. Keep comparison and waiting for approval visually cohesive. Maintain lock cancellation and secure storage. Paired hosts use readable grouped rows, clear search, sync recency, a Sync action, and an obvious route to active sessions. Terminal chrome should make session status and Ctrl selection readable without consuming the terminal.

## Plan review and verification

Rejected an initial generic dashboard approach: the user needs a working SSH library, not status cards or invented metrics. Keep native controls and existing libraries, with small shared styling helpers only where they remove repetition. Preserve secure behavior and data compatibility. Application code is still written by Sol high agents without authored comments.

Before delivery inspect real captures of desktop empty library, saved-host state, host editor and QR pairing; Android onboarding, scanner/fallback, comparison and hosts. Verify small-window scrolling, keyboard focus and existing pairing/SSH regression checks. Add meaningful checks for first-save selection, interface filtering/ranking and the changed pairing states. Do not mistake screenshots for a physical-phone camera scan test.
