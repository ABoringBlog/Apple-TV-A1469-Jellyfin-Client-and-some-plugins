#!/bin/sh
set -eu

LABEL=org.atv3.bridge.cloudtune
DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PYTHON=$(command -v python3)
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$DIR/cloudtune_bridge.log"
PORT="${CLOUDTUNE_PORT:-8101}"
BIND="${CLOUDTUNE_BIND:-0.0.0.0}"
UPSTREAM="${CLOUDTUNE_UPSTREAM:-http://127.0.0.1:18300}"

mkdir -p "$HOME/Library/LaunchAgents"

"$PYTHON" - "$PLIST" "$PYTHON" "$DIR/cloudtune_bridge.py" "$LOG" "$PORT" "$BIND" "$UPSTREAM" <<'PY'
import plistlib,sys
plist,python,server,log,port,bind,upstream=sys.argv[1:]
payload={
    "Label":"org.atv3.bridge.cloudtune",
    "ProgramArguments":[python,server],
    "EnvironmentVariables":{
        "CLOUDTUNE_PORT":port,
        "CLOUDTUNE_BIND":bind,
        "CLOUDTUNE_UPSTREAM":upstream,
    },
    "RunAtLoad":True,
    "KeepAlive":True,
    "WorkingDirectory":str(__import__("pathlib").Path(server).parent),
    "StandardOutPath":log,
    "StandardErrorPath":log,
}
with open(plist,"wb") as f:
    plistlib.dump(payload,f)
PY

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "CloudTune Bridge installed and kept alive by launchd."
echo "Health: http://127.0.0.1:$PORT/health"
echo "ATV3 bridge base URL: http://MAC_LAN_IP:$PORT"
echo "Upstream API: $UPSTREAM"
