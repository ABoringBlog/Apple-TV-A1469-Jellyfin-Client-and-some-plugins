#!/bin/sh
# Offline Clock packaging. Does not contact or modify a physical device.
set -eu
if [ "$#" -ne 2 ]; then echo 'Usage: Clock/Scripts/package.sh BUILT_BUNDLE OUTPUT_DIRECTORY' >&2; exit 2; fi
repo=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$repo"
bundle=$1
out=$2
[ ! -e "$out" ] || { echo "Output already exists: $out" >&2; exit 1; }
[ -f "$bundle/Clock" ] && [ -f "$bundle/Info.plist" ]
package=$(awk '/^Package: / {print $2}' Clock/Packaging/control)
version=$(awk '/^Version: / {print $2}' Clock/Packaging/control)
arch=$(awk '/^Architecture: / {print $2}' Clock/Packaging/control)
[ "$package" = org.atv3.clock ] && [ "$arch" = iphoneos-arm ]
case "$version" in *[!a-zA-Z0-9.+:~_-]*|'') echo "Bad package version" >&2; exit 1 ;; esac
mkdir -p "$out/stage/DEBIAN" "$out/stage/Applications/AppleTV.app/Appliances"
cp Clock/Packaging/control "$out/stage/DEBIAN/control"
cp -R "$bundle" "$out/stage/Applications/"
app="$out/stage/Applications/Clock.frappliance"
find "$out/stage" -type d -exec chmod 755 {} +
find "$app" -type f -exec chmod 644 {} +
chmod 755 "$app/Clock"
chmod 644 "$out/stage/DEBIAN/control"
plutil -lint "$app/Info.plist"
python3 - "$app/Info.plist" "$version" <<'PYMETA'
import plistlib,sys
with open(sys.argv[1],"rb") as stream: info=plistlib.load(stream)
required={
    "CFBundleExecutable":"Clock",
    "CFBundleIdentifier":"org.atv3.clock",
    "CFBundleName":"Clock",
    "FRApplianceName":"Clock",
    "NSPrincipalClass":"ClockAppliance",
    "MinimumOSVersion":"8.0",
    "CFBundleVersion":sys.argv[2].split("-")[0],
}
for key,value in required.items():
    assert info.get(key)==value,(key,info.get(key),value)
PYMETA
xcrun lipo "$app/Clock" -verify_arch armv7
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
ln -s /Applications/Clock.frappliance "$out/stage/Applications/AppleTV.app/Appliances/Clock.frappliance"
deb="$out/$package"_"$version"_"$arch".deb
python3 Scripts/build-deb.py "$out/stage" "$deb"
python3 Clock/Tests/verify_package.py "$deb" "$app"
shasum -a 256 "$deb"
