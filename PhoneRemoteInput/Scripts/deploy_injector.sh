#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo "Usage: $0 APPLE_TV_IP" >&2; exit 2; }
ATV_IP=$1
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
STATE=${ATV3_PHONE_STATE_DIR:-"$HOME/.config/atv3-phone-remote"}
TOKEN="$STATE/injector-token"
mkdir -p "$STATE"
chmod 700 "$STATE"
if [ ! -s "$TOKEN" ]; then
  umask 077
  openssl rand -hex 32 > "$TOKEN"
fi
chmod 600 "$TOKEN"

"$ROOT/Scripts/build_injector.sh"
DYLIB="$ROOT/build/org.atv3.remoteinjector.dylib"
PLIST="$ROOT/ATV3Injector/org.atv3.remoteinjector.plist"

scp "$DYLIB" root@"$ATV_IP":/var/root/org.atv3.remoteinjector.dylib.new
scp "$PLIST" root@"$ATV_IP":/var/root/org.atv3.remoteinjector.plist.new
scp "$TOKEN" root@"$ATV_IP":/var/root/org.atv3.remoteinput.token.new

ssh root@"$ATV_IP" '
set -e
D=/Library/MobileSubstrate/DynamicLibraries
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p /var/root/atv3-remoteinput-backup-$STAMP
[ ! -f "$D/org.atv3.remoteinjector.dylib" ] || cp "$D/org.atv3.remoteinjector.dylib" /var/root/atv3-remoteinput-backup-$STAMP/
[ ! -f "$D/org.atv3.remoteinjector.plist" ] || cp "$D/org.atv3.remoteinjector.plist" /var/root/atv3-remoteinput-backup-$STAMP/
mv /var/root/org.atv3.remoteinjector.dylib.new "$D/org.atv3.remoteinjector.dylib"
mv /var/root/org.atv3.remoteinjector.plist.new "$D/org.atv3.remoteinjector.plist"
mv /var/root/org.atv3.remoteinput.token.new /var/mobile/Library/Preferences/org.atv3.remoteinput.token
chown root:wheel "$D/org.atv3.remoteinjector.dylib" "$D/org.atv3.remoteinjector.plist"
chmod 755 "$D/org.atv3.remoteinjector.dylib"
chmod 644 "$D/org.atv3.remoteinjector.plist"
chown mobile:staff /var/mobile/Library/Preferences/org.atv3.remoteinput.token
chmod 600 /var/mobile/Library/Preferences/org.atv3.remoteinput.token
ldid -S "$D/org.atv3.remoteinjector.dylib"
launchctl stop com.apple.frontrow || true
sleep 1
launchctl start com.apple.frontrow
'
echo "ATV3 injector deployed. Verify /var/tmp/atv3-ir-injector.log and loopback port 49154."
