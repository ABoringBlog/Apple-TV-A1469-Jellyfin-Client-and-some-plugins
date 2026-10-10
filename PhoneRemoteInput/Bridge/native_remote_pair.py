#!/usr/bin/env python3
"""Controlled, five-minute pairing window for iPhone's built-in TV Remote."""
from pathlib import Path
import os
import sys
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/"upstream-atvr4samsung"/"src"))
from atvr4samsung.companion.protocol.server_identity import load_persisted_identity
from atvr4samsung.pairing_window import PairingWindowStore

def main():
    state=Path(os.environ.get("ATV3_PHONE_STATE_DIR",str(Path.home()/".config"/"atv3-phone-remote"))).expanduser()/"native_remote_state"
    state.mkdir(mode=0o700,parents=True,exist_ok=True)
    os.chmod(state,0o700)
    identity=load_persisted_identity(state)
    store=PairingWindowStore(state)
    mode=sys.argv[1] if len(sys.argv)>1 else "status"
    if mode=="open":
        window=store.open(server_identifier=identity.identifier,
                          server_generation=identity.generation,duration_seconds=300)
        print("PAIR_WINDOW_ACTIVE_5_MIN")
        print("NATIVE_IPHONE_REMOTE_PIN="+window.pin)
    elif mode=="status":
        window=store.active()
        print("ACTIVE_PAIR_WINDOW="+str(window is not None))
        if window:
            print("EXPIRES_IN_SECONDS="+str(int(window.expires_at-__import__('time').time())))
    elif mode=="close":
        PairingWindowStore.clear_state(state)
        print("PAIR_WINDOW_CLOSED")
    else:
        raise SystemExit("usage: native_remote_pair.py [open|status|close]")

if __name__=="__main__":
    main()
