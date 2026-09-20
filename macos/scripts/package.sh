#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo 'Usage: macos/scripts/package.sh VERSION BUILD_NUMBER OUTPUT_DIRECTORY' >&2
  exit 2
fi

version=$1
build_number=$2
output_directory=$3
if [[ ! $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'VERSION must be a release SemVer such as 1.2.3.' >&2
  exit 2
fi
if [[ ! $build_number =~ ^[1-9][0-9]*$ ]]; then
  echo 'BUILD_NUMBER must be a positive integer.' >&2
  exit 2
fi

for tool in xcodebuild codesign lipo hdiutil ditto /usr/libexec/PlistBuddy; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required macOS tool is missing: $tool" >&2
    exit 1
  fi
done

macos_directory=$(cd "$(dirname "$0")/.." && pwd -P)
repository_directory=$(cd "$macos_directory/.." && pwd -P)
if [[ ! -f "$macos_directory/Harbor.xcodeproj/project.pbxproj" ]]; then
  echo 'The checked-in Harbor.xcodeproj is missing.' >&2
  exit 1
fi
mkdir -p "$output_directory" "$repository_directory/.work"
output_directory=$(cd "$output_directory" && pwd -P)
work=$(mktemp -d "$repository_directory/.work/harbor-package.XXXXXX")
trap 'rm -rf "$work"' EXIT

xcodebuild \
  -project "$macos_directory/Harbor.xcodeproj" \
  -scheme Harbor \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$work/derived" \
  -clonedSourcePackagesDirPath "$work/packages" \
  -skipPackagePluginValidation \
  "MARKETING_VERSION=$version" \
  "CURRENT_PROJECT_VERSION=$build_number" \
  'ARCHS=arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

app="$work/derived/Build/Products/Release/Harbor.app"
helper="$app/Contents/Helpers/HarborAskPass"
binary="$app/Contents/MacOS/Harbor"
plist="$app/Contents/Info.plist"
if [[ ! -f $binary || ! -f $helper || ! -s "$app/Contents/Resources/Harbor.icns" ]]; then
  echo 'The built app is missing its executable, credential helper, or icon.' >&2
  exit 1
fi
if [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") != "$version" ||
      $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist") != "$build_number" ]]; then
  echo 'The built app has an unexpected bundle version.' >&2
  exit 1
fi
codesign --force --sign - --options runtime --timestamp=none "$helper"
codesign --force --sign - --options runtime --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$helper"
codesign --verify --strict --verbose=2 "$app"
for executable in "$binary" "$helper"; do
  architectures=$(lipo -archs "$executable")
  if [[ " $architectures " != *' arm64 '* || " $architectures " != *' x86_64 '* ]]; then
    echo "The built executable is not universal: $executable ($architectures)" >&2
    exit 1
  fi
done

stage="$work/stage"
mkdir -p "$stage"
ditto "$app" "$stage/Harbor.app"
ln -s /Applications "$stage/Applications"
disk_image="$work/harbor-$version-macos-universal.dmg"
hdiutil create -volname "Harbor $version" -srcfolder "$stage" -format UDZO "$disk_image"
hdiutil verify "$disk_image"
mv "$disk_image" "$output_directory/harbor-$version-macos-universal.dmg"
echo "$output_directory/harbor-$version-macos-universal.dmg"
