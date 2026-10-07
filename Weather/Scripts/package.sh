#!/bin/sh
set -eu
if [ "$#" -ne 3 ]; then
    echo "Usage: Weather/Scripts/package.sh LANGUAGE BUILT_BUNDLE OUTPUT_DIRECTORY" >&2
    echo "LANGUAGE: en or zh" >&2
    exit 2
fi
lang=$1
bundle=$2
out=$3
case "$lang" in en|zh) ;; *) echo "LANGUAGE must be en or zh" >&2; exit 2 ;; esac
repo=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$repo"
[ ! -e "$out" ] || { echo "Output already exists: $out" >&2; exit 1; }
[ -f "$bundle/Weather" ] && [ -f "$bundle/Info.plist" ]
package=org.atv3.weather
base_version=1.0.0
version="$base_version-public1-$lang"
arch=iphoneos-arm
if [ "$lang" = en ]; then display="Weather for Apple TV 3 (English)"; else display="Weather for Apple TV 3 (Chinese)"; fi
mkdir -p "$out/stage/DEBIAN" "$out/stage/Applications/AppleTV.app/Appliances"
cat > "$out/stage/DEBIAN/control" <<EOF
Package: $package
Name: $display
Version: $version
Architecture: $arch
Description: Native Apple TV 3 Weather appliance; requires ATV3Bridge running continuously on a Mac
Maintainer: ABoringBlog
Section: Utilities
EOF
cp -R "$bundle" "$out/stage/Applications/"
app="$out/stage/Applications/Weather.frappliance"
find "$out/stage" -type d -exec chmod 755 {} +
find "$app" -type f -exec chmod 644 {} +
chmod 755 "$app/Weather"
chmod 644 "$out/stage/DEBIAN/control"
plutil -lint "$app/Info.plist"
python3 - "$app/Info.plist" <<'PYMETA'
import plistlib,sys
with open(sys.argv[1],"rb") as stream:
    info=plistlib.load(stream)
expected={"CFBundleExecutable":"Weather","CFBundleIdentifier":"org.atv3.weather","CFBundleName":"Weather","FRApplianceName":"Weather","NSPrincipalClass":"WeatherAppliance","MinimumOSVersion":"8.0","CFBundleVersion":"1.0.0"}
for key,value in expected.items():
    assert info.get(key)==value,(key,info.get(key),value)
PYMETA
xcrun lipo "$app/Weather" -verify_arch armv7
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
ln -s /Applications/Weather.frappliance "$out/stage/Applications/AppleTV.app/Appliances/Weather.frappliance"
deb="$out/${package}_${version}_${arch}.deb"
python3 Scripts/build-deb.py "$out/stage" "$deb"
python3 Weather/Tests/verify_package.py "$lang" "$deb" "$app"
shasum -a 256 "$deb"
