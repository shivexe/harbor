from pathlib import Path
from textwrap import wrap
from xml.etree import ElementTree
from xml.sax.saxutils import escape


WIDTH = 1860
LANES = {"desktop": 70, "android": 710, "result": 1350}
NODE_WIDTH = 440
COLORS = {
    "background": "#17191c",
    "panel": "#222529",
    "text": "#f2f3f3",
    "muted": "#bdc3c6",
    "line": "#8d969b",
    "success": "#81a991",
    "check": "#c6a470",
    "failure": "#ba7f7b",
}


def e(value):
    return escape(str(value), {'"': "&quot;"})


def node_height(node):
    limit = 26 if node.get("kind") == "check" else 43
    lines = wrap(node["body"], limit, break_long_words=False, break_on_hyphens=False)
    if node.get("kind") == "check":
        return max(200, 130 + 28 * len(lines))
    return 76 + 25 * max(1, len(lines))


def layout(section):
    rows = sorted({node["row"] for node in section["nodes"]})
    y = 218
    row_y = {}
    for row in rows:
        row_y[row] = y
        y += max(node_height(node) for node in section["nodes"] if node["row"] == row) + 82
    row_bottom = {row: row_y[row] + max(node_height(node) for node in section["nodes"] if node["row"] == row) for row in rows}
    nodes = {node["id"]: {**node, "x": LANES[node["lane"]], "y": row_y[node["row"]], "h": node_height(node), "row_bottom": row_bottom[node["row"]]} for node in section["nodes"]}
    for edge in section["edges"]:
        assert edge[0] in nodes and edge[1] in nodes, (section["slug"], edge)
        assert nodes[edge[0]]["row"] <= nodes[edge[1]]["row"], (section["slug"], edge)
    assert len(nodes) == len(section["nodes"]), section["slug"]
    return nodes, y + 16


def edge_svg(a, b, label):
    if a["row"] == b["row"]:
        assert abs(a["x"] - b["x"]) in (640, 1280)
        left_to_right = a["x"] < b["x"]
        x1 = a["x"] + (NODE_WIDTH if left_to_right else 0)
        x2 = b["x"] + (0 if left_to_right else NODE_WIDTH)
        y1 = a["y"] + a["h"] / 2
        y2 = b["y"] + b["h"] / 2
        d = f"M{x1},{y1:.1f} L{x2},{y2:.1f}"
        lx = (x1 + x2) / 2
        ly = min(y1, y2) - 9
    else:
        x1 = a["x"] + NODE_WIDTH / 2
        x2 = b["x"] + NODE_WIDTH / 2
        y1 = a["y"] + a["h"]
        y2 = b["y"]
        if x1 == x2:
            d = f"M{x1:.1f},{y1:.1f} L{x2:.1f},{y2:.1f}"
            lx = x1 + 12
            ly = (y1 + y2) / 2 + 5
        else:
            middle = a["row_bottom"] + (25 if abs(x1 - x2) > 640 else 55)
            d = f"M{x1:.1f},{y1:.1f} L{x1:.1f},{middle:.1f} L{x2:.1f},{middle:.1f} L{x2:.1f},{y2:.1f}"
            lx = x1 + (x2 - x1) * (0.35 if abs(x1 - x2) > 640 else 0.5)
            ly = middle - 9
    line = f'<path d="{d}" fill="none" stroke="{COLORS["line"]}" stroke-width="2" marker-end="url(#arrow)"/>'
    if not label:
        return line
    width = max(38, len(label) * 8.7 + 12)
    box = f'<rect x="{lx - width / 2:.1f}" y="{ly - 17:.1f}" width="{width:.1f}" height="23" fill="{COLORS["background"]}"/>'
    text = f'<text x="{lx:.1f}" y="{ly:.1f}" text-anchor="middle" class="edge">{e(label)}</text>'
    return line + box + text


def node_svg(node):
    accent = COLORS.get(node.get("kind", ""), COLORS["line"])
    x, y, h = node["x"], node["y"], node["h"]
    if node.get("kind") == "check":
        shape = f'<path d="M{x + NODE_WIDTH / 2},{y} L{x + NODE_WIDTH},{y + h / 2} L{x + NODE_WIDTH / 2},{y + h} L{x},{y + h / 2} Z" fill="{COLORS["panel"]}" stroke="{accent}" stroke-width="2"/>'
        title = f'<text x="{x + NODE_WIDTH / 2}" y="{y + 69}" text-anchor="middle" class="node-title">{e(node["title"])}</text>'
        body = "".join(
            f'<text x="{x + NODE_WIDTH / 2}" y="{y + 99 + 24 * i}" text-anchor="middle" class="node-body">{e(line)}</text>'
            for i, line in enumerate(wrap(node["body"], 26, break_long_words=False, break_on_hyphens=False))
        )
        return shape + title + body
    title = f'<text x="{x + 22}" y="{y + 36}" class="node-title">{e(node["title"])}</text>'
    body = "".join(
        f'<text x="{x + 22}" y="{y + 69 + 25 * i}" class="node-body">{e(line)}</text>'
        for i, line in enumerate(wrap(node["body"], 43, break_long_words=False, break_on_hyphens=False))
    )
    return f'<rect x="{x}" y="{y}" width="{NODE_WIDTH}" height="{h}" rx="3" fill="{COLORS["panel"]}" stroke="{accent}" stroke-width="2"/>' + title + body


def section_svg(section):
    nodes, height = layout(section)
    title = f'<text x="70" y="72" class="section-title">{e(section["title"])}</text>'
    summary = f'<text x="70" y="110" class="summary">{e(section["summary"])}</text>'
    lane_names = section.get("lanes", {"desktop": "DESKTOP", "android": "ANDROID", "result": "CHECK / RESULT"})
    lanes = "".join(
        f'<text x="{x}" y="172" class="lane">{e(lane_names[lane])}</text><path d="M{x},185 h440" stroke="{COLORS["line"]}" stroke-width="1"/>'
        for lane, x in LANES.items()
    )
    connectors = "".join(edge_svg(nodes[source], nodes[target], label) for source, target, label in section["edges"])
    boxes = "".join(node_svg(node) for node in nodes.values())
    return title + summary + lanes + connectors + boxes, height


def document(title, description, content, height):
    css = """
    text{font-family:Arial,DejaVu Sans,sans-serif;fill:#f2f3f3}
    .page-title{font-size:34px;font-weight:700}
    .section-title{font-size:30px;font-weight:700}
    .summary{font-size:19px;fill:#bdc3c6}
    .lane{font-size:18px;font-weight:700;letter-spacing:1px;fill:#bdc3c6}
    .node-title{font-size:21px;font-weight:700}
    .node-body{font-size:18px}
    .edge{font-size:16px;font-weight:700;fill:#f2f3f3}
    """
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{height}" viewBox="0 0 {WIDTH} {height}" role="img" aria-labelledby="title desc">
<title id="title">{e(title)}</title><desc id="desc">{e(description)}</desc>
<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0,0 L10,5 L0,10 Z" fill="{COLORS["line"]}"/></marker></defs>
<style>{css}</style><rect width="{WIDTH}" height="{height}" fill="{COLORS["background"]}"/>{content}</svg>'''


def n(id, row, lane, title, body, kind=""):
    return {"id": id, "row": row, "lane": lane, "title": title, "body": body, "kind": kind}


SECTIONS = [
    {
        "slug": "01-ownership",
        "title": "01 / Who owns each copy",
        "summary": "The desktop is the master address book. The phone carries a sealed copy; the SSH server is the destination.",
        "lanes": {"desktop": "DESKTOP OWNER", "android": "ANDROID PHONE", "result": "BOUNDARY / SERVER"},
        "nodes": [
            n("owner", 0, "desktop", "One desktop owns hosts", "Mac uses SwiftUI, SwiftTerm and OpenSSH. Linux uses Qt, QTermWidget and OpenSSH with its own vault identity."),
            n("no_merge", 0, "result", "No desktop merge", "Mac and Linux do not copy or combine their vaults. Harbor has no hosted account or cloud relay."),
            n("copy", 1, "android", "Phone receives a copy", "Flutter, xterm and dartssh2 run the phone. Manual sync copies hosts and credentials; phone cannot edit host settings."),
            n("desk_ssh", 2, "desktop", "Desktop can open SSH", "Mac and Linux use system OpenSSH to connect to the chosen server. Sharing is not needed for this."),
            n("phone_ssh", 2, "android", "Phone can open SSH", "The saved copy works offline from the desktop if the phone can still reach the SSH server."),
            n("server", 3, "result", "SSH server", "Both clients connect here directly. The server account controls what commands may change." , "success"),
        ],
        "edges": [
            ("owner", "no_merge", "ownership limit"),
            ("owner", "copy", "signed, encrypted HTTP sync"),
            ("owner", "desk_ssh", "saved host"),
            ("copy", "phone_ssh", "saved host"),
            ("desk_ssh", "server", "SSH commands"),
            ("phone_ssh", "server", "SSH commands"),
        ],
    },
    {
        "slug": "02-save-vault",
        "title": "02 / Save a host in the desktop vault",
        "summary": "Only an unlocked desktop edits host records. A failed check leaves the previous saved record in place.",
        "lanes": {"desktop": "DESKTOP ACTION", "android": "DATA / CHECK", "result": "FAILURE OR RESULT"},
        "nodes": [
            n("unlock", 0, "desktop", "Open the vault", "Mac confirms the device owner, then gets its AES-256 key from Keychain. Linux derives one from a passphrase."),
            n("unlock_ok", 1, "android", "Vault opens?", "Decrypt the whole library and check its records. Each new vault gets its own identity and signing key.", "check"),
            n("unlock_fail", 1, "result", "Stay locked", "Denied unlock, wrong passphrase, missing Mac key, corrupt data, or a second owner stops the operation.", "failure"),
            n("edit", 2, "desktop", "Enter host settings", "Set address, port, SSH user, name, group, notes, and password, private key, or no saved credential."),
            n("key", 3, "desktop", "Import a private key", "File and paste accept up to 256 KiB. Keep encrypted text. Linux bounds PBKDF2 to 2m rounds; Mac checks PEM within 3 seconds."),
            n("other_login", 3, "android", "Password or none", "Password needs a value. None saves no password, key, or passphrase; server policy must authorize login."),
            n("valid", 4, "android", "Record valid?", "Check address, port 1–65535, username, selected login method, size, and private-key format before Save.", "check"),
            n("draft", 4, "result", "Keep the draft", "A rejected key, size limit, cancel, or lock leaves the saved host. Mac OpenSSH passphrase failure may appear at SSH.", "failure"),
            n("save", 5, "desktop", "Encrypt and replace", "Discard unused credential fields. Increase revision inside the library, encrypt it, then atomically replace the owner-only file."),
            n("save_fail", 5, "result", "Old file remains", "A disk or permission failure stops the save; the previous persisted host remains." , "failure"),
            n("revision", 6, "desktop", "New version is saved", "Host add, edit, delete, or trusted-key change raises the revision, a version counter, in that encrypted save." , "success"),
            n("lock_life", 6, "result", "Lock ends active work", "Mac locks on screen lock or 15 idle minutes. Linux locks when asked. Both stop sharing and SSH sessions."),
            n("trust", 7, "android", "Trust server key?", "A scan shows a fingerprint: a short identifier for the server key. The person compares it elsewhere and approves.", "check"),
            n("no_pin", 7, "result", "No automatic trust", "A scan alone never proves identity. An unverified host may sync, but Android will refuse its SSH connection.", "failure"),
            n("pin", 8, "desktop", "Save approved key", "Store the full server public key. Address or port changes clear trust and require another check." , "success"),
        ],
        "edges": [
            ("unlock", "unlock_ok", "decrypt + validate"),
            ("unlock_ok", "unlock_fail", "No"),
            ("unlock_ok", "edit", "Yes"),
            ("edit", "key", "key login"),
            ("edit", "other_login", "password / none"),
            ("key", "valid", "host draft"),
            ("other_login", "valid", "host draft"),
            ("valid", "draft", "No"),
            ("valid", "save", "Yes"),
            ("save", "save_fail", "write fails"),
            ("save", "revision", "write succeeds"),
            ("revision", "lock_life", "later lock"),
            ("revision", "trust", "before SSH"),
            ("trust", "no_pin", "No"),
            ("trust", "pin", "Yes"),
        ],
    },
    {
        "slug": "03-pair",
        "title": "03 / Pair one Android phone",
        "summary": "A short-lived QR secret starts the exchange. The person approves only after comparing both displayed codes.",
        "nodes": [
            n("listen", 0, "desktop", "Unlock and share", "Start the opt-in HTTP listener on port 45873. The selected private IP is the QR address; the listener binds all interfaces."),
            n("listen_fail", 0, "result", "No invitation", "Try another reachable network. Both current UIs use port 45873; an occupied port stops sharing.", "failure"),
            n("invite", 1, "desktop", "Make a five-minute QR", "Include desktop URL, vault ID, one-use pair ID, random 32-byte secret, signing public key, and expiry."),
            n("scan", 2, "android", "Scan or paste QR", "Camera permission can be denied; paste is the fallback. The QR is secret and is copied only by explicit action."),
            n("qr_check", 3, "android", "Invitation valid?", "Check version, expiry, sizes, IDs, key and literal local IP URL. No DNS, public IP, or redirect.", "check"),
            n("qr_fail", 3, "result", "Stop pairing", "Bad QR, cancellation, or unreachable desktop leaves the existing phone vault alone.", "failure"),
            n("request", 4, "android", "Make encrypted request", "Create device ID and random nonce. Make a six-digit check number from them and the QR secret (SHA-256). Seal with a pair-request label."),
            n("bind", 5, "desktop", "Bind first requester", "Decrypt and check the request. The first valid device ID and nonce own this invitation; rate and socket limits apply."),
            n("busy", 5, "result", "Reject other claimant", "Another device, malformed message, or expired invitation cannot take over the pending approval.", "failure"),
            n("wait", 6, "android", "Wait with same request", "Pending 202 or network timeout retries the exact encrypted request every two seconds until decision or QR expiry."),
            n("compare", 6, "desktop", "Codes match?", "Compare the two screens. Approve on the desktop only when they match.", "check"),
            n("deny", 7, "result", "Deny or expire", "Code mismatch: deny. Denied 403 or expired/canceled 410 ends pairing; dismissing desktop QR cancels it.", "failure"),
            n("approve", 7, "desktop", "Save this phone's sync key", "Create a new random 32-byte key for this phone. Save the pairing in the encrypted desktop vault first."),
            n("reply", 8, "android", "Check encrypted reply", "Open with the QR secret and pair-response label. Check IDs, desktop name, and sync key; pin signing public key from QR."),
            n("reply_fail", 8, "result", "Reject bad reply", "Bad success reply stops pairing; scan a new QR. A lost network response can retry the same bound request until expiry.", "failure"),
            n("already", 9, "android", "Already paired?", "Choose the first-pair or replacement path before saving phone state.", "check"),
            n("stage", 9, "result", "Stage replacement", "Keep the approved new pairing in memory. Old saved pairing and hosts stay until the new snapshot passes."),
            n("first", 10, "android", "Save first pairing", "Save identity with an empty host copy. If first sync fails, this pairing remains for a retry."),
            n("stage_sync", 10, "result", "Use staged key", "Request the new snapshot with the approved key still held only in phone memory."),
            n("first_sync", 11, "android", "Fetch first snapshot", "Use the new sync key to request, decrypt, and verify a full signed host snapshot."),
            n("sync_pass", 12, "android", "First sync valid?", "Check signature, IDs, revision, and every host before replacing a saved copy.", "check"),
            n("sync_fail", 12, "result", "Keep saved state", "First pair keeps its empty copy for retry. Replacement keeps the old pairing and hosts; pending memory can be lost.", "failure"),
            n("commit", 13, "android", "Save verified snapshot", "Replace the full host list. For a desktop switch, save new pairing and snapshot together in one value.", "success"),
        ],
        "edges": [
            ("listen", "listen_fail", "start fails"),
            ("listen", "invite", "listener ready"),
            ("invite", "scan", "QR JSON"),
            ("scan", "qr_check", "invitation"),
            ("qr_check", "qr_fail", "No"),
            ("qr_check", "request", "Yes"),
            ("request", "bind", "POST /v1/pair/{pairId}"),
            ("bind", "busy", "invalid / claimed"),
            ("bind", "wait", "202 pending"),
            ("wait", "compare", "user compares"),
            ("compare", "deny", "No"),
            ("compare", "approve", "Yes"),
            ("approve", "reply", "sealed sync key"),
            ("reply", "reply_fail", "invalid"),
            ("reply", "already", "accepted"),
            ("already", "stage", "Yes"),
            ("already", "first", "No"),
            ("stage", "stage_sync", "no saved change"),
            ("stage_sync", "first_sync", "new pairing in RAM"),
            ("first", "first_sync", "saved identity"),
            ("first_sync", "sync_pass", "signed snapshot"),
            ("sync_pass", "sync_fail", "No"),
            ("sync_pass", "commit", "Yes"),
        ],
    },
    {
        "slug": "04-sync",
        "title": "04 / Manually sync the full host list",
        "summary": "The phone asks for a fresh copy. Every check passes before it replaces the saved list, including deletions.",
        "nodes": [
            n("tap", 0, "android", "Tap Sync", "Use the saved desktop URL. The desktop must be reachable, unlocked, and sharing. There is no auto-discovery."),
            n("offline", 0, "result", "Keep existing copy", "Offline, stopped sharing, timeout, or network error leaves the previous phone hosts available.", "failure"),
            n("ask", 1, "android", "Seal a fresh request", "Make a random 32-byte request ID. Encrypt vault ID and request ID with this phone's sync key and sync-request label."),
            n("metadata", 1, "result", "HTTP reveals metadata", "IP, port, path, device ID, size, and timing remain visible. Host data and credentials stay inside encrypted bodies."),
            n("authorize", 2, "desktop", "Authorized phone?", "Use visible device ID to find its key. Check the sealed request, purpose label, vault ID, and version.", "check"),
            n("revoke", 2, "result", "Reject request", "Unknown or revoked device: 403. Bad sealed request: 400. Bad version or vault: Mac 400, Linux 403. Phone keeps its copy.", "failure"),
            n("snapshot", 3, "desktop", "Build full snapshot", "Copy all hosts, credentials, vault ID, revision, time, and echoed request ID; bound the total size."),
            n("bounds", 3, "result", "Bound time and size", "At most 10,000 hosts, 256 KiB/key, 1 MiB/host, 8 MiB snapshot, 16 MiB reply. Request: 16 KiB header, 512 KiB body, 10 s."),
            n("sign", 4, "desktop", "Sign, then encrypt", "Ed25519 signature proves which desktop issued the bytes. AES-256-GCM hides and seals them for this phone."),
            n("open", 5, "android", "Open response seal", "AES-GCM checks the response using this phone's sync key and sync-response label."),
            n("badseal", 5, "result", "Reject bad seal", "Wrong key, purpose label, or changed ciphertext stops processing and keeps the prior host copy.", "failure"),
            n("verify", 6, "android", "Signature valid?", "Verify exact signed bytes with the desktop public key pinned from the pairing QR.", "check"),
            n("bad", 6, "result", "Reject entire response", "Bad signature, malformed JSON, wrong vault or request ID, or invalid host stops replacement.", "failure"),
            n("check", 7, "android", "Snapshot valid?", "Check version, vault ID, echoed request ID, numeric time, revision, and every host with unique IDs.", "check"),
            n("old", 7, "result", "Keep prior state", "Old revision or invalid host is rejected. Equal revision is allowed with a fresh request ID; time is not an expiry.", "failure"),
            n("write", 8, "android", "Replace one saved value", "Store pairing, revision, and the entire host snapshot together. The phone host list is read-only."),
            n("write_fail", 8, "result", "Immediate error shown", "One logical value avoids split pairing/host updates. Later disk-write failure may not be reported; crash durability is unproven.", "failure"),
            n("done", 9, "android", "Show new host list", "The new full copy includes removals. There is no phone-to-desktop host edit endpoint.", "success"),
        ],
        "edges": [
            ("tap", "offline", "no connection"),
            ("tap", "ask", "paired"),
            ("ask", "metadata", "HTTP request"),
            ("ask", "authorize", "POST /v1/sync"),
            ("authorize", "revoke", "No"),
            ("authorize", "snapshot", "Yes"),
            ("snapshot", "bounds", "limits"),
            ("snapshot", "sign", "snapshot bytes"),
            ("sign", "open", "encrypted signed reply"),
            ("open", "badseal", "seal fails"),
            ("open", "verify", "authenticated bytes"),
            ("verify", "bad", "No"),
            ("verify", "check", "Yes"),
            ("check", "old", "No"),
            ("check", "write", "Yes"),
            ("write", "write_fail", "write fails"),
            ("write", "done", "write succeeds"),
        ],
    },
    {
        "slug": "05-ssh",
        "title": "05 / Open a direct SSH terminal",
        "summary": "Harbor checks the server before giving login proof. A terminal appears only after the remote shell opens.",
        "lanes": {"desktop": "HARBOR CLIENT", "android": "SSH SERVER", "result": "STOP / RESULT"},
        "nodes": [
            n("pick", 0, "desktop", "Choose a saved host", "Desktop uses its editable record; phone uses its read-only copy. Both need a network route to the server."),
            n("pin_missing", 0, "result", "No trusted server key", "Desktop must scan, compare, and approve the server key. Android needs a later sync of that key.", "failure"),
            n("prepare", 1, "desktop", "Prepare login material", "Phone parses a saved encrypted key in memory before the socket. Desktop stages its original key for OpenSSH to unlock during login."),
            n("key_fail", 1, "result", "Keep encrypted original", "Phone rejects a wrong or unsupported key before network login. Key work runs off the UI: PBKDF2 ≤2m, bcrypt ≤1024 rounds." , "failure"),
            n("open", 2, "desktop", "Open SSH transport", "Phone dartssh2 opens TCP. Desktop OpenSSH uses safe arguments, a private known-hosts file, and no inherited user config or agent keys."),
            n("network_fail", 2, "result", "Timeout or disconnect", "Phone socket and handshake each have 15-second limits. Report an error; the saved host remains.", "failure"),
            n("server_key", 3, "android", "Present server key", "SSH setup returns the server's public key before Harbor supplies user login proof."),
            n("compare", 4, "desktop", "Server key matches?", "Compare its full key or SHA-256 fingerprint with the saved trusted key. Reject a changed identity.", "check"),
            n("mismatch", 4, "result", "Stop before login", "A mismatch needs explicit desktop re-verification and sync. Harbor does not accept it on sight.", "failure"),
            n("auth", 5, "desktop", "Prove user access", "Password travels inside SSH; key signs proof. None uses server policy without fallback. Mac Keychain or Linux socket helper gives desktop secrets here, never in arguments or environment."),
            n("server_auth", 5, "android", "Check user proof", "The remote account accepts or denies the login. Its permissions control what commands can change."),
            n("auth_fail", 5, "result", "Login rejected", "Wrong secret, denied account, or the phone's 30-second login timeout ends the attempt before any shell opens.", "failure"),
            n("shell", 6, "desktop", "Request remote shell", "Ask for a PTY: a remote terminal window. Phone waits up to 15 seconds for the shell."),
            n("shell_check", 6, "android", "Shell accepted?", "Only successful SSH authentication and an opened shell make the terminal ready.", "check"),
            n("shell_fail", 6, "result", "Show error", "Refusal or timeout keeps the terminal out of the connected state.", "failure"),
            n("input", 7, "desktop", "Send typed input", "Keystrokes and terminal size updates travel inside the SSH encrypted channel. No sync server relays them."),
            n("run", 7, "android", "Run command", "The SSH server interprets the text under that account's permissions; read-only host settings do not limit shell power."),
            n("output", 8, "desktop", "Render returned output", "Display bounded server text. No automatic link or OSC52 clipboard action; explicit terminal Copy is still available."),
            n("subshell", 8, "result", "Nested shell exits", "This is ordinary terminal output. Harbor stays connected while the main SSH shell runs; Back may keep it open."),
            n("end_check", 9, "desktop", "What event arrived?", "The main SSH session finishes, or the transport reports a failure?", "check"),
            n("main_exit", 10, "android", "Main shell exits", "Remove only the ended session. Other active terminals remain available."),
            n("lost", 10, "result", "Transport fails", "Close this session and offer Retry or Edit. Phone Edit means desktop change, Sync, then Retry.", "failure"),
            n("cleanup", 11, "android", "Release session material", "Manual Close or lock closes SSH. Desktop removes temporary 0600 key files from private 0700 directories."),
        ],
        "edges": [
            ("pick", "pin_missing", "no pin"),
            ("pick", "prepare", "trusted pin saved"),
            ("prepare", "key_fail", "key fails"),
            ("prepare", "open", "login material ready"),
            ("open", "network_fail", "connect fails"),
            ("open", "server_key", "SSH handshake"),
            ("server_key", "compare", "server public key"),
            ("compare", "mismatch", "No"),
            ("compare", "auth", "Yes"),
            ("auth", "server_auth", "login proof"),
            ("server_auth", "auth_fail", "denied"),
            ("server_auth", "shell", "accepted"),
            ("shell", "shell_check", "PTY + shell"),
            ("shell_check", "shell_fail", "No"),
            ("shell_check", "input", "Yes"),
            ("input", "run", "SSH input"),
            ("run", "output", "SSH output"),
            ("output", "subshell", "nested shell output"),
            ("output", "end_check", "session event"),
            ("end_check", "main_exit", "session done"),
            ("end_check", "lost", "transport error"),
            ("main_exit", "cleanup", "ended session"),
            ("lost", "cleanup", "close resources"),
        ],
    },
    {
        "slug": "06-android-local",
        "title": "06 / Android local protection and limits",
        "summary": "Follow the saved copy from the lock screen to disk, memory, SSH, and removal.",
        "lanes": {"desktop": "USER / PHONE APP", "android": "STORAGE / DESKTOP", "result": "OUTCOME / LIMIT"},
        "nodes": [
            n("screen", 0, "desktop", "Protect the window", "Android FLAG_SECURE blocks ordinary screenshots and recent-app previews of Harbor."),
            n("unlock", 1, "desktop", "Device unlock succeeds?", "Android asks for its configured PIN, pattern, or password. This is a screen gate, not a separate Harbor PIN.", "check"),
            n("locked", 1, "result", "Remain locked", "No device credential or canceled confirmation leaves hosts hidden and SSH closed.", "failure"),
            n("read", 2, "android", "Read one saved value", "Pairing and hosts share one private app setting. Android's app sandbox keeps ordinary other apps out; a read error does not reset data."),
            n("cipher", 3, "android", "Decrypt local storage", "AES-128-GCM locks and checks saved data. Android Keystore's RSA key locks the random AES data key (RSA-OAEP)."),
            n("keystore_limit", 3, "result", "Separate gate and key", "The storage key does not require every screen unlock. Hardware backing and secure RAM erasure are unproven."),
            n("memory", 4, "desktop", "Use records in memory", "After unlock, decrypted hosts and a selected SSH credential enter app memory. No host editor or credential-reveal action is offered."),
            n("compromise", 4, "result", "Device limit", "A rooted or compromised phone may inspect process memory. The interactive SSH shell can still change remote data.", "failure"),
            n("pause", 5, "desktop", "Pause or wait five minutes", "Background pause or tracked inactivity closes all SSH sessions, clears visible hosts, and returns to the locked first screen."),
            n("persist", 5, "android", "Encrypted copy persists", "Unlock reloads the saved copy. Backup and device transfer are disabled for this app."),
            n("unpair", 5, "result", "Confirm Unpair?", "While unlocked, Cancel keeps data. Confirm deletes local saved entries, closes SSH, and clears the UI.", "check"),
            n("cancel", 6, "desktop", "Cancel keeps data", "The phone stays paired. Saved hosts and existing sessions are unchanged.", "success"),
            n("disk_limit", 6, "android", "Newest save may be lost", "Android saves this setting in the background. A sudden crash may lose the newest update (SharedPreferences.apply)."),
            n("unpair_limit", 6, "result", "Local removal only", "Unpair does not revoke the desktop or delete the plugin's Keystore RSA alias. A detected deletion error is shown.", "failure"),
            n("revoke_action", 7, "desktop", "Separately: Revoke", "On the desktop, choose a paired phone and remove its registration."),
            n("revoke", 7, "android", "Block future sync", "Desktop deletes that phone's sync key. Later sync gets 403, but old offline hosts stay on the phone."),
            n("rotate", 7, "result", "Stop SSH at server", "Revocation cannot remotely wipe copied credentials or open SSH. Rotate passwords, keys, or server policy there.", "failure"),
        ],
        "edges": [
            ("screen", "unlock", "launch"),
            ("unlock", "locked", "No"),
            ("unlock", "read", "Yes"),
            ("read", "cipher", "encrypted bytes"),
            ("cipher", "keystore_limit", "key design"),
            ("cipher", "memory", "decrypted records"),
            ("memory", "compromise", "process limit"),
            ("memory", "pause", "leave / idle"),
            ("memory", "unpair", "choose Unpair"),
            ("pause", "persist", "disk retained"),
            ("unpair", "cancel", "Cancel"),
            ("unpair", "unpair_limit", "confirmed"),
            ("persist", "disk_limit", "storage limit"),
            ("revoke_action", "revoke", "device ID"),
            ("revoke", "rotate", "access already copied"),
        ],
    },
    {
        "slug": "07-key-map",
        "title": "07 / Which key does which job",
        "summary": "Read each row across. These keys serve different jobs; the rows are not a sequence.",
        "lanes": {"desktop": "OWNER / SOURCE", "android": "JOB", "result": "HOLDER / LIMIT"},
        "nodes": [
            n("mac", 0, "desktop", "Mac vault key", "Random AES-256 key kept by macOS Keychain."),
            n("mac_job", 0, "android", "Seal Mac's file", "AES-GCM encrypts the local library and detects changes to its sealed bytes."),
            n("mac_limit", 0, "result", "Stays on Mac", "Phone never receives this vault key."),
            n("linux", 1, "desktop", "Linux vault key", "A user passphrase and random salt make an AES-256 key using 600,000 PBKDF2 rounds."),
            n("linux_job", 1, "android", "Seal Linux's file", "This key encrypts the independent Linux vault."),
            n("linux_limit", 1, "result", "Stays on Linux", "It is not the Mac key or a cross-desktop sync key."),
            n("phone", 2, "desktop", "Phone storage keys", "The phone plugin makes a random AES-128 data key; Android Keystore keeps the RSA wrapping key."),
            n("phone_job", 2, "android", "Seal the phone copy", "The wrapped AES key opens encrypted pairing and snapshot data on local disk."),
            n("phone_limit", 2, "result", "Stays on phone", "These keys are not carried in the QR. Screen unlock is a separate app gate."),
            n("signing", 3, "desktop", "Desktop signing key", "Ed25519 private key stays with that desktop. Its public half travels in the pairing QR."),
            n("signing_job", 3, "android", "Prove snapshot issuer", "A signature proves the exact snapshot bytes came from the paired desktop; it does not hide them."),
            n("signing_limit", 3, "result", "Phone pins public half", "The phone checks signatures against the key from the QR, never a new key sent by HTTP."),
            n("invite", 4, "desktop", "Invitation secret", "The QR carries a random 32-byte secret for one invitation lasting five minutes."),
            n("invite_job", 4, "android", "Seal first pair messages", "Both sides use it for the pair request and reply. The six-digit comparison code is not a key."),
            n("invite_limit", 4, "result", "Temporary, both sides", "Keep QR private. An approved reply can be retried only by its bound request until expiry."),
            n("sync_key", 5, "desktop", "Per-phone sync key", "Desktop makes a different random 32-byte key after approving each phone."),
            n("sync_job", 5, "android", "Seal later sync bodies", "AES-256-GCM encrypts and checks request and response bodies for that phone."),
            n("sync_limit", 5, "result", "Desktop and phone", "Revoking deletes the desktop's copy, blocking new sync, not old offline credentials."),
            n("server_pin", 6, "desktop", "SSH server public key", "Desktop scans, person verifies its fingerprint, then desktop saves the approved key."),
            n("pin_job", 6, "android", "Check destination", "The synced pin identifies the SSH server before Harbor gives user login proof."),
            n("pin_limit", 6, "result", "Desktop and phone", "This is the server's key, separate from the desktop signing key."),
            n("login", 7, "desktop", "SSH login secret", "Password or original private key and passphrase are saved in the encrypted host record."),
            n("login_job", 7, "android", "Prove user access", "Both clients may use it for SSH. A private key signs proof; it is not uploaded to the server."),
            n("login_limit", 7, "result", "Copied to phone", "Server account policy decides permissions. Rotation at the server removes copied access."),
            n("session", 8, "desktop", "SSH session keys", "SSH negotiates new live channel keys between client and server."),
            n("session_job", 8, "android", "Encrypt terminal traffic", "These keys protect interactive commands and output while that SSH connection lasts."),
            n("session_limit", 8, "result", "Only this SSH link", "They are separate from the vault, invitation, and sync keys."),
            n("nonce", 9, "desktop", "Nonce", "A fresh number for each AES-GCM seal."),
            n("tag", 9, "android", "Tag and purpose label", "Tag detects tampering; the visible AAD label ties a sealed message to its intended use."),
            n("revision", 9, "result", "Revision", "A rising host version counter. 'Atomic' means replace the complete saved value in one logical step."),
        ],
        "edges": [
            ("mac", "mac_job", "encrypts"), ("mac_job", "mac_limit", "holder"),
            ("linux", "linux_job", "encrypts"), ("linux_job", "linux_limit", "holder"),
            ("phone", "phone_job", "opens"), ("phone_job", "phone_limit", "holder"),
            ("signing", "signing_job", "signs"), ("signing_job", "signing_limit", "public key"),
            ("invite", "invite_job", "seals"), ("invite_job", "invite_limit", "lifetime"),
            ("sync_key", "sync_job", "seals"), ("sync_job", "sync_limit", "holders"),
            ("server_pin", "pin_job", "compared"), ("pin_job", "pin_limit", "holders"),
            ("login", "login_job", "authenticates"), ("login_job", "login_limit", "holders"),
            ("session", "session_job", "encrypts"), ("session_job", "session_limit", "lifetime"),
        ],
    },
    {
        "slug": "08-draw-architecture",
        "title": "08 / How to draw a system from a brief",
        "summary": "Repeat this trace for each user action. Draw owners, moving data, checks, and what survives a failure.",
        "lanes": {"desktop": "ASK", "android": "TRACE", "result": "DRAW / VERIFY"},
        "nodes": [
            n("verbs", 0, "desktop", "1. Name user actions", "Write verb and object: save host, pair phone, sync, connect, revoke."),
            n("actors", 1, "android", "2. Name each owner", "Person, desktop, phone, and SSH server. Mark who may write each record; Harbor hosts have one desktop owner."),
            n("rest", 2, "result", "3. Place stored data", "Locate host records, credentials, pairing keys, and revision. Mark disk or temporary memory."),
            n("boundary", 3, "desktop", "4. Draw boundaries", "Draw device, process, and network edges. Ask what still works when a device is offline."),
            n("success", 4, "android", "5. Trace one success", "Number each send, check, write, and reply. Put the moved data on every arrow."),
            n("security", 5, "result", "6. Check each crossing", "Ask: who is sending, who may act, and can someone read or alter it? Draw separate checks."),
            n("failure", 6, "desktop", "7. Draw failure branches", "Wrong key, timeout, cancel, duplicate, old reply, or failed write: say which saved state remains."),
            n("life", 7, "android", "8. Follow its lifetime", "Include creation, unlock, background, exit, revocation, and deletion for each secret and session."),
            n("code", 8, "result", "9. Match code to boxes", "Find the real module and library for each step. Add limits. Do not invent a server when direct links suffice."),
            n("walk", 9, "desktop", "10. Walk real cases", "Phone SSH with desktop offline; changed server key; failed sync; revoked phone; ended shell."),
            n("complete", 10, "result", "Final check", "Every arrow names data; every write names owner; every secret has holder and lifetime; every failure says what stays."),
        ],
        "edges": [
            ("verbs", "actors", "actions"),
            ("actors", "rest", "ownership"),
            ("rest", "boundary", "data locations"),
            ("boundary", "success", "crossings"),
            ("success", "security", "request path"),
            ("security", "failure", "checks"),
            ("failure", "life", "state left"),
            ("life", "code", "lifecycle"),
            ("code", "walk", "evidence"),
            ("walk", "complete", "scenarios"),
        ],
    },
]


def main():
    here = Path(__file__).parent
    master_parts = ['<text x="70" y="72" class="page-title">HARBOR / Architecture and data flow</text>',
                    '<text x="70" y="109" class="summary">Follow the arrows. Each box says what happens and where the information goes.</text>']
    y = 150
    for section in SECTIONS:
        content, height = section_svg(section)
        standalone = document(section["title"], section["summary"], content, height)
        path = here / f'{section["slug"]}.svg'
        path.write_text(standalone, encoding="utf-8")
        ElementTree.fromstring(standalone)
        master_parts.append(f'<path d="M70,{y} H1790" stroke="{COLORS["line"]}" stroke-width="1"/>')
        master_parts.append(f'<g transform="translate(0,{y + 20})">{content}</g>')
        y += height + 60
    master = document("Harbor architecture and data flow", "Complete map of Harbor ownership, saving, pairing, synchronization, SSH, Android protection, key map, and architecture reading method.", "".join(master_parts), y)
    (here / "harbor-architecture.svg").write_text(master, encoding="utf-8")
    ElementTree.fromstring(master)


if __name__ == "__main__":
    main()
