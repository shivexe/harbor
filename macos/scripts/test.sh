#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d Harbor.xcodeproj ]]; then echo 'Harbor.xcodeproj is missing.' >&2; exit 1; fi
mkdir -p ../.work
test_filter=()
if [[ ${CI:-} == true ]]; then
  for name in \
    testSharedProtocolVectors \
    testApprovedReplyCachePreservesBindingAcrossNewInvitations \
    testSSHDiagnosticMilestonesRequireOrderedLocalEvidence \
    testEncryptedMessageAuthenticatesContext \
    testComparisonMatchesSHA256BigEndian \
    testHostRejectsArgumentAndCredentialInjection \
    testVaultDoesNotPersistPlaintextAndRejectsTampering \
    testHTTPFramingRejectsConflictingLengthsAndChunkedUploads \
    testPairingAddressRejectsPublicAndDNSOrigins \
    testAutomaticPairingNetworkChoicesAvoidLoopbackAndBridges \
    testNoPasswordHostClearsInactiveCredentialsAndExportsNone; do
    test_filter+=("-only-testing:HarborTests/HarborTests/$name")
  done
fi
xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath ../.work/derived -clonedSourcePackagesDirPath ../.work/packages -skipPackagePluginValidation CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= "${test_filter[@]}" test
