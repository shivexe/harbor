#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 1; }
xcodegen generate
xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
