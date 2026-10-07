#!/bin/sh
# Rebuild into never-before-used directories. Does not contact any device or server.
set -eu
cd "$(dirname "$0")/.."
label=${1:-}
case "$label" in ''|*[!a-zA-Z0-9_-]*) echo 'Usage: freeze-build.sh UNIQUE_LABEL' >&2; exit 2;; esac
build="build/freeze-$label"
package="build/package-freeze-$label"
log="logs/freeze-$label"
if [ -e "$build" ] || [ -e "$package" ] || [ -e "$log" ]; then echo 'Checkpoint already exists; choose a new label' >&2; exit 1; fi
mkdir "$log"
xcrun clang --version > "$log/toolchain.txt"
git --git-dir=recovery.git rev-parse HEAD > "$log/source-commit.txt"
git --git-dir=recovery.git --work-tree=. status --short > "$log/source-status.txt"
make shell BUILD="$build" > "$log/armv7.log" 2>&1
JF_ARM_BUNDLE="$build/Jellyfin.frappliance/Jellyfin" python3 Tests/armv7_abi_test.py > "$log/target-abi-tests.log" 2>&1
Scripts/package.sh "$build/Jellyfin.frappliance" "$package" > "$log/package.log" 2>&1
candidate=$(find "$package" -maxdepth 1 -name '*.deb' -type f)
[ -n "$candidate" ]
JF_PACKAGE="$candidate" python3 Tests/package_test.py > "$log/package-tests.log" 2>&1
shasum -a 256 "$candidate" > "$log/SHA256SUMS"
printf 'Built %s; records: %s\n' "$candidate" "$log"
