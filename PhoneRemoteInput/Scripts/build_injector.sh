#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IOS_SDK=${IOS_SDK:-}
[ -n "$IOS_SDK" ] && [ -d "$IOS_SDK" ] || {
  echo "Set IOS_SDK to a compatible iPhoneOS SDK path." >&2
  exit 2
}
OUT="$ROOT/build"
mkdir -p "$OUT"
/usr/bin/clang \
  -arch armv7 \
  -isysroot "$IOS_SDK" \
  -miphoneos-version-min=8.0 \
  -fno-objc-arc -fblocks \
  -dynamiclib \
  -Wl,-no_uuid \
  -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/org.atv3.remoteinjector.dylib \
  "$ROOT/ATV3Injector/RemoteInjector.m" \
  -framework Foundation -lobjc \
  -o "$OUT/org.atv3.remoteinjector.dylib"
xcrun lipo "$OUT/org.atv3.remoteinjector.dylib" -verify_arch armv7
file "$OUT/org.atv3.remoteinjector.dylib"
echo "$OUT/org.atv3.remoteinjector.dylib"
