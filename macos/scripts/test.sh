#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Harbor.xcodeproj -scheme Harbor -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
