#!/bin/sh
set -eu
LABEL=org.atv3.bridge.weather
DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PYTHON=$(command -v python3)
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$DIR/bridge.log"
mkdir -p "$HOME/Library/LaunchAgents"
if [ ! -f "$DIR/weather_config.json" ]; then
    cp "$DIR/weather_config.example.json" "$DIR/weather_config.json"
fi
"$PYTHON" - "$PLIST" "$PYTHON" "$DIR/weather_server.py" "$DIR/weather_config.json" "$DIR/weather_cache.json" "$LOG" <<'PY'
import plistlib,sys
plist,python,server,config,cache,log=sys.argv[1:]
payload={
    "Label":"org.atv3.bridge.weather",
    "ProgramArguments":[python,server,"--bind","0.0.0.0","--port","8099","--config",config,"--cache",cache],
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
echo "ATV3Bridge Weather installed and kept alive by launchd."
echo "Health check: http://127.0.0.1:8099/health"
echo "Weather endpoint: http://MAC_LAN_IP:8099/v1/weather"
