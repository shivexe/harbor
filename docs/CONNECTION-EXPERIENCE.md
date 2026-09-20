# Connection experience

Harbor 1.1.2 addresses the reported strict host-key failure and replaces the prematurely visible terminal with connection progress and recovery actions.

## Research and behavior

[OpenSSH configuration](https://man.openbsd.org/ssh_config) treats `UserKnownHostsFile` as a list of filenames. Each filename containing spaces needs quotes inside the option value, even when the process receives arguments as an array. The native Mac vault is under `Library/Application Support/Harbor`; development tests previously used paths without spaces. The fix must preserve the approved server key and strict checking.

[OpenSSH's diagnostic output](https://man.openbsd.org/ssh) can be directed to a separate local file with `-E`. Desktop progress uses this local output, not strings printed by a remote shell, to determine connection milestones. Android uses the SSH library's socket, verification, authentication and shell callbacks. Starting a process or receiving arbitrary output does not prove a shell is connected.

[Apple's progress guidance](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) supports an indeterminate indicator when completion cannot be estimated. Harbor shows meaningful steps without an invented percentage or timed animation between stages.

## Presentation

Retain the existing graphite canvas `#17191F`, raised surfaces `#272B35`, primary text `#F1F2F6`, secondary text `#ABB1C0`, and periwinkle action color `#A8B8FA`. Use the platform's native font and the existing heading, body and button styles. A single left-aligned progress panel occupies the connection workspace; a host name and endpoint identify the attempt above the steps.

The sequence is reaching the server, verifying its identity, signing in, and opening the shell. Completed steps have checkmarks, the active step has an indeterminate indicator, and pending steps remain muted. First-use server identity approval remains explicit. The terminal and its keyboard/input controls appear only after successful authentication and shell acceptance.

[Tailscale SSH check mode](https://tailscale.com/docs/features/tailscale-ssh#configure-tailscale-ssh-with-check-mode) can require browser sign-in before authentication succeeds. A bounded, selectable server message remains visible in the progress panel so the user can follow those instructions. Server-supplied text never advances the connection steps or triggers automatic navigation.

A failure remains in this panel with a specific explanation and **Retry** and **Edit Config** actions. Recovery actions remain visible in a footer while lengthy details and server messages scroll. Retry creates a new attempt using the latest saved host. Edit Config opens the existing desktop editor. Android preserves its read-only model: **Edit on desktop** explains where to change the host and offers syncing the updated configuration. Active attempts support cancellation. Canceling, locking or dismissing an attempt prevents its later callbacks from opening a session.

## Acceptance

- A real connection succeeds when session paths contain spaces, with strict host-key checking still enabled.
- A wrong server key fails before a terminal is displayed; no silent replacement or trust bypass occurs.
- Bad credentials, refusal, missing trust and shell rejection remain in the connection UI with useful recovery actions.
- All existing password, private-key, encrypted-private-key and SSH `none` methods remain supported.
- Terminal visibility depends on actual shell acceptance. Remote text resembling diagnostic output cannot advance progress.
- Local diagnostic files are private, bounded and removed with the session; passwords, keys and terminal input are never added to diagnostics.
- Retry uses updated configuration and does not revive canceled or locked attempts.

Executed checks and release artifacts are recorded separately in the release validation notes.
