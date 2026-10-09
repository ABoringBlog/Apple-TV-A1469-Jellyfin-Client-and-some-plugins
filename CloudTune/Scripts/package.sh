#!/bin/sh
set -eu
if [ "$#" -ne 3 ]; then
    echo "Usage: CloudTune/Scripts/package.sh LANGUAGE BUILT_BUNDLE OUTPUT_DIRECTORY" >&2
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
[ -f "$bundle/CloudTune" ] && [ -f "$bundle/Info.plist" ]
package=org.atv3.cloudtune
base_version=1.0.0
version="$base_version-public1-$lang"
arch=iphoneos-arm
if [ "$lang" = en ]; then display="CloudTune for Apple TV 3 (English)"; else display="云律音乐 for Apple TV 3 (Chinese)"; fi
mkdir -p "$out/stage/DEBIAN" "$out/stage/Applications/AppleTV.app/Appliances"
cat > "$out/stage/DEBIAN/control" <<EOF
Package: $package
Name: $display
Version: $version
Architecture: $arch
Description: CloudTune v1, an independent Apple TV 3 music client; requires a Mac CloudTune Bridge and an external compatible music API service
Maintainer: ABoringBlog
Section: Multimedia
EOF
cp -R "$bundle" "$out/stage/Applications/"
app="$out/stage/Applications/CloudTune.frappliance"
find "$out/stage" -type d -exec chmod 755 {} +
find "$app" -type f -exec chmod 644 {} +
chmod 755 "$app/CloudTune"
chmod 644 "$out/stage/DEBIAN/control"
plutil -lint "$app/Info.plist"
python3 - "$app/Info.plist" <<'PYMETA'
import plistlib,sys
with open(sys.argv[1],"rb") as f: info=plistlib.load(f)
expected={
    "CFBundleExecutable":"CloudTune",
    "CFBundleIdentifier":"org.atv3.cloudtune",
    "CFBundleName":"CloudTune",
    "FRApplianceIdentifier":"cloudtune",
    "FRApplianceName":"CloudTune",
    "CFBundleVersion":"1.0.0",
    "CFBundleShortVersionString":"1.0.0",
    "MinimumOSVersion":"8.0",
}
for key,value in expected.items():
    assert info.get(key)==value,(key,info.get(key),value)
PYMETA
xcrun lipo "$app/CloudTune" -verify_arch armv7
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
ln -s /Applications/CloudTune.frappliance "$out/stage/Applications/AppleTV.app/Appliances/CloudTune.frappliance"
deb="$out/${package}_${version}_${arch}.deb"
python3 Scripts/build-deb.py "$out/stage" "$deb"
python3 CloudTune/Tests/verify_package.py "$lang" "$deb" "$app"
shasum -a 256 "$deb"
