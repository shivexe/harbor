#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 VERSION OUTPUT_DIRECTORY" >&2
    exit 2
fi

version=${1#v}
if [[ ! $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Expected a version like 1.2.3 or v1.2.3" >&2
    exit 2
fi

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir="$source_dir/build/package"
cmake -S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DHARBOR_VERSION="$version"
cmake --build "$build_dir" --parallel 2
mkdir -p -- "$2"
cpack --config "$build_dir/CPackConfig.cmake" -G DEB -B "$2"

package="$2/harbor-$version-linux-amd64.deb"
[[ $(dpkg-deb -f "$package" Version) == "$version" ]] || { echo "Incorrect DEB version" >&2; exit 1; }
[[ $(dpkg-deb -f "$package" Architecture) == amd64 ]] || { echo "Incorrect DEB architecture" >&2; exit 1; }
extracted=$(mktemp -d)
trap 'rm -rf -- "$extracted"' EXIT
dpkg-deb -x "$package" "$extracted"
[[ -x "$extracted/usr/bin/harbor" && -x "$extracted/usr/bin/harbor-askpass" ]] || { echo "Missing executable in DEB" >&2; exit 1; }
actual=$(cd "$extracted" && find usr ! -type d | LC_ALL=C sort)
expected=$(cat <<'EOF'
usr/bin/harbor
usr/bin/harbor-askpass
usr/share/applications/harbor.desktop
usr/share/doc/harbor/README.md
usr/share/doc/harbor/THIRD_PARTY_NOTICES.md
usr/share/icons/hicolor/scalable/apps/harbor.svg
EOF
)
if [[ $actual != "$expected" ]]; then
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    exit 1
fi
