#!/bin/bash
set -euo pipefail
harbor_macos_dir="$(cd "$(dirname "$0")/.." && pwd)"
harbor_check_dir="$(mktemp -d)"
trap 'rm -rf "$harbor_check_dir"' EXIT
cat > "$harbor_check_dir/main.swift" <<'SWIFT'
import Foundation

func rejected(_ host: Host) -> Bool {
    do { try host.validate(); return false }
    catch { return true }
}

var host = Host(name: "Work", address: "192.168.1.2", username: "operator", secret: "secret")
try host.validate()
assert(Library().revision == 1)
let valid = host
host.address = "-oProxyCommand=malicious"
assert(rejected(host))
host = valid
host.username = "-luser"
assert(rejected(host))
host = valid
host.address = "host\nsecond"
assert(rejected(host))
host = valid
host.secret = "password\nsecond"
assert(rejected(host))
host = valid
host.port = 65536
assert(rejected(host))
host = valid
host.auth = .key
host.privateKey = "PRIVATE KEY" + String(repeating: "x", count: 256 * 1024)
assert(rejected(host))
print("Portable Swift host validation passed")
SWIFT
"${SWIFTC:-swiftc}" "$harbor_macos_dir/Harbor/Models.swift" "$harbor_check_dir/main.swift" -o "$harbor_check_dir/model-check"
"$harbor_check_dir/model-check"
