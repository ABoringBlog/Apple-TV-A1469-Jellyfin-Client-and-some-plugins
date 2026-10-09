#!/bin/sh
set -eu
if [ "$#" -ne 3 ]; then
    echo "Usage: Radio/Scripts/package.sh LANGUAGE BUILT_BUNDLE OUTPUT_DIRECTORY" >&2
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
[ -f "$bundle/InternetRadio" ] && [ -f "$bundle/Info.plist" ]
package=org.atv3.internetradio
base_version=0.3.1
version="$base_version-public2-$lang"
arch=iphoneos-arm
if [ "$lang" = en ]; then display="Internet Radio for Apple TV 3 (English)"; else display="Internet Radio for Apple TV 3 (Chinese)"; fi
mkdir -p "$out/stage/DEBIAN" "$out/stage/Applications/AppleTV.app/Appliances"
cat > "$out/stage/DEBIAN/control" <<EOF
Package: $package
Name: $display
Version: $version
Architecture: $arch
Description: Native Apple TV 3 Internet Radio appliance; requires ATV3Bridge running continuously on a Mac
Maintainer: ABoringBlog
Section: Multimedia
EOF
cp -R "$bundle" "$out/stage/Applications/"
app="$out/stage/Applications/Radio.frappliance"
find "$out/stage" -type d -exec chmod 755 {} +
find "$app" -type f -exec chmod 644 {} +
chmod 755 "$app/InternetRadio"
chmod 644 "$out/stage/DEBIAN/control"
plutil -lint "$app/Info.plist"
python3 - "$app/Info.plist" <<'PYMETA'
import plistlib,sys
with open(sys.argv[1],"rb") as f: info=plistlib.load(f)
expected={"CFBundleExecutable":"InternetRadio","CFBundleIdentifier":"org.atv3.internetradio","CFBundleName":"Internet Radio","FRApplianceIdentifier":"internetradio","FRApplianceName":"Internet Radio","CFBundleVersion":"0.3.1"}
for key,value in expected.items():
    assert info.get(key)==value,(key,info.get(key),value)
PYMETA
xcrun lipo "$app/InternetRadio" -verify_arch armv7
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
ln -s /Applications/Radio.frappliance "$out/stage/Applications/AppleTV.app/Appliances/Radio.frappliance"
deb="$out/${package}_${version}_${arch}.deb"
python3 Scripts/build-deb.py "$out/stage" "$deb"
python3 Radio/Tests/verify_package.py "$lang" "$deb" "$app"
shasum -a 256 "$deb"
