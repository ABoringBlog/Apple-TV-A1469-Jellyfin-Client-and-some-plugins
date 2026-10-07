#!/bin/sh
set -eu
LABEL=org.atv3.bridge.radio
DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PYTHON=$(command -v python3)
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$DIR/radio_server.log"

mkdir -p "$HOME/Library/LaunchAgents"
"$PYTHON" - "$PLIST" "$PYTHON" "$DIR/radio_server.py" "$LOG" <<'PY'
import plistlib,sys
plist,python,server,log=sys.argv[1:]
payload={
    "Label":"org.atv3.bridge.radio",
    "ProgramArguments":[python,server],
    "EnvironmentVariables":{"ATV3_RADIO_PORT":"8100"},
    "RunAtLoad":True,
    "KeepAlive":True,
    "WorkingDirectory":str(__import__("pathlib").Path(server).parent),
    "StandardOutPath":log,
    "StandardErrorPath":log,
}
with open(plist,"wb") as f: plistlib.dump(payload,f)
PY

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "ATV3Bridge Radio installed and kept alive by launchd."
echo "Health: http://127.0.0.1:8100/health"
echo "ATV3 bridge base URL: http://MAC_LAN_IP:8100"
