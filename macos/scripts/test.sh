#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v xcodegen >/dev/null 2>&1; then xcodegen generate; fi
if [[ ! -d Harbor.xcodeproj ]]; then echo 'Harbor.xcodeproj is missing; install XcodeGen to generate it.' >&2; exit 1; fi
mkdir -p ../.work
xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath ../.work/derived -clonedSourcePackagesDirPath ../.work/packages -skipPackagePluginValidation CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
