#!/bin/sh
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 MAC_LAN_IP APPLE_TV_IP" >&2; exit 2; }
MAC_IP=$1
ATV_IP=$2
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
STATE=${ATV3_PHONE_STATE_DIR:-"$HOME/.config/atv3-phone-remote"}
UPSTREAM="$ROOT/upstream-atvr4samsung"
COMMIT=7673178729a12b20c7d7a0bc968fc1786cbf2567

mkdir -p "$STATE" "$HOME/Library/LaunchAgents"
chmod 700 "$STATE"

if [ ! -d "$UPSTREAM/.git" ]; then
  git clone https://github.com/vb3/atvr4samsung.git "$UPSTREAM"
fi
git -C "$UPSTREAM" fetch --all --tags
git -C "$UPSTREAM" checkout --detach "$COMMIT"
if git -C "$UPSTREAM" apply --check "$ROOT/Patches/atvr4samsung-atv3.patch" >/dev/null 2>&1; then
  git -C "$UPSTREAM" apply "$ROOT/Patches/atvr4samsung-atv3.patch"
fi

if [ ! -x "$ROOT/.venv/bin/python" ]; then
  python3 -m venv "$ROOT/.venv"
fi
"$ROOT/.venv/bin/pip" install --upgrade pip
"$ROOT/.venv/bin/pip" install "pyatv==0.18.0"
"$ROOT/.venv/bin/pip" install -e "$UPSTREAM"

TOKEN="$STATE/injector-token"
if [ ! -s "$TOKEN" ]; then
  umask 077
  openssl rand -hex 32 > "$TOKEN"
fi
chmod 600 "$TOKEN"

BRIDGE_PLIST="$HOME/Library/LaunchAgents/org.atv3.bridge.native-iphone-remote.plist"
TUNNEL_PLIST="$HOME/Library/LaunchAgents/org.atv3.ir-event-tunnel.plist"

python3 - "$BRIDGE_PLIST" "$ROOT" "$STATE" "$MAC_IP" "$ATV_IP" <<'PY'
import plistlib,sys
plist,root,state,mac_ip,atv_ip=sys.argv[1:]
payload={
 "Label":"org.atv3.bridge.native-iphone-remote",
 "ProgramArguments":[root+"/.venv/bin/python",root+"/Bridge/native_ios_remote.py"],
 "WorkingDirectory":root+"/Bridge",
 "EnvironmentVariables":{
   "ATV3_PHONE_BIND":mac_ip,
   "ATV3_PHONE_ATV":atv_ip,
   "ATV3_PHONE_STATE_DIR":state,
   "ATV3_IR_KEYFILE":state+"/injector-token",
   "ATV3_NATIVE_REMOTE_PORT":"49152",
   "ATV3_NATIVE_REMOTE_NAME":"ATV3 Bridge",
   "ATV3_IR_INJECT":"1",
 },
 "RunAtLoad":True,
 "KeepAlive":True,
 "StandardOutPath":state+"/native_remote_stdout.log",
 "StandardErrorPath":state+"/native_remote_stderr.log",
}
with open(plist,"wb") as f: plistlib.dump(payload,f)
PY

python3 - "$TUNNEL_PLIST" "$ATV_IP" "$STATE" <<'PY'
import plistlib,sys
plist,atv_ip,state=sys.argv[1:]
payload={
 "Label":"org.atv3.ir-event-tunnel",
 "ProgramArguments":[
   "/usr/bin/ssh","-N",
   "-L","127.0.0.1:49154:127.0.0.1:49154",
   "-o","ExitOnForwardFailure=yes",
   "-o","BatchMode=yes",
   "-o","ServerAliveInterval=15",
   "-o","ServerAliveCountMax=2",
   "-o","ConnectTimeout=12",
   "root@"+atv_ip,
 ],
 "RunAtLoad":True,
 "KeepAlive":True,
 "StandardOutPath":state+"/ir_tunnel_stdout.log",
 "StandardErrorPath":state+"/ir_tunnel_stderr.log",
}
with open(plist,"wb") as f: plistlib.dump(payload,f)
PY

UID_NUM=$(id -u)
launchctl bootout "gui/$UID_NUM" "$BRIDGE_PLIST" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID_NUM" "$TUNNEL_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_NUM" "$TUNNEL_PLIST"
launchctl bootstrap "gui/$UID_NUM" "$BRIDGE_PLIST"
launchctl kickstart -k "gui/$UID_NUM/org.atv3.ir-event-tunnel" || true
launchctl kickstart -k "gui/$UID_NUM/org.atv3.bridge.native-iphone-remote"

echo "Mac services installed."
echo "State directory: $STATE"
echo "Next: deploy the ATV3 injector, pair Mac->ATV3 DMAP, then pair iPhone->Mac Companion."
