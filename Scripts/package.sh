#!/bin/sh
# Offline only: no device commands or maintainer scripts.
set -eu
bundle=${1:-build/iPhoneOS11.4.sdk-ios8.0/Jellyfin.frappliance}
out=${2:-build/package-phase4e}
# Refuse overwriting a previous package checkpoint.
if [ -e "$out" ]; then echo "Output already exists: $out" >&2; exit 1; fi
package=$(awk '/^Package: / {print $2}' Packaging/control)
version=$(awk '/^Version: / {print $2}' Packaging/control)
arch=$(awk '/^Architecture: / {print $2}' Packaging/control)
case "$package:$version:$arch" in *[!a-zA-Z0-9.+:~_-]*|'') echo 'Invalid package metadata' >&2; exit 1;; esac
[ -n "$package" ] && [ -n "$version" ] && [ "$arch" = iphoneos-arm ]
[ -f "$bundle/Jellyfin" ] && [ -f "$bundle/Info.plist" ]
mkdir -p "$out/stage/DEBIAN" "$out/stage/Applications" "$out/stage/Applications/AppleTV.app/Appliances"
cp Packaging/control "$out/stage/DEBIAN/control"
cp -R "$bundle" "$out/stage/Applications/"
app="$out/stage/Applications/Jellyfin.frappliance"
find "$out/stage" -type d -exec chmod 755 {} +
find "$app" -type f -exec chmod 644 {} +
chmod 755 "$app/Jellyfin"
chmod 644 "$out/stage/DEBIAN/control"
plutil -lint "$app/Info.plist"
python3 - "$app/Info.plist" "$version" <<'PYMETA'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    metadata = plistlib.load(source)
if metadata['CFBundleVersion'] != sys.argv[2].split('-')[0]:
    raise SystemExit('Bundle/package versions differ; rebuild before packaging')
PYMETA
file "$app/Jellyfin"
xcrun lipo "$app/Jellyfin" -verify_arch armv7
xcrun otool -hv "$app/Jellyfin"
xcrun otool -L "$app/Jellyfin"
xcrun otool -l "$app/Jellyfin"
xcrun nm -u "$app/Jellyfin"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
codesign -dvv "$app"
ln -s /Applications/Jellyfin.frappliance "$out/stage/Applications/AppleTV.app/Appliances/Jellyfin.frappliance"
python3 Scripts/build-deb.py "$out/stage" "$out/${package}_${version}_${arch}.deb"
ar -t "$out/${package}_${version}_${arch}.deb"
shasum -a 256 "$app/Jellyfin" "$out/"*.deb

python3 Scripts/verify-package.py "$out/${package}_${version}_${arch}.deb" "$app"
