#!/usr/bin/env python3
"""One-time DMAP pairing of the Mac Bridge with the real Apple TV 3.

This is independent of iPhone Control Center pairing to the emulated
Companion server. It does not require a custom iPhone app or browser.
"""
import asyncio
import json
import os
from pathlib import Path
import secrets
import sys
import time

import pyatv
from pyatv import const

STATE_ROOT=Path(os.environ.get("ATV3_PHONE_STATE_DIR",str(Path.home()/".config"/"atv3-phone-remote"))).expanduser()
STATE_ROOT.mkdir(mode=0o700,parents=True,exist_ok=True)
os.chmod(STATE_ROOT,0o700)
PRIVATE=STATE_ROOT/"private_state.json"
ATV_IP=os.environ.get("ATV3_PHONE_ATV","").strip()
MAC_IP=os.environ.get("ATV3_PHONE_BIND","").strip()
if not ATV_IP or not MAC_IP:
    raise RuntimeError("ATV3_PHONE_ATV and ATV3_PHONE_BIND must be configured")
OUT=STATE_ROOT/"dmap_pairing_status.json"
GUID_FILE=STATE_ROOT/"dmap_pairing_guid.private"

def stable_guid():
    if GUID_FILE.exists():
        value=GUID_FILE.read_text().strip().upper()
        if len(value)!=16 or any(c not in "0123456789ABCDEF" for c in value):
            raise RuntimeError("Invalid stored pairing GUID")
        return "0x"+value
    value=secrets.token_hex(8).upper()
    fd=os.open(str(GUID_FILE), os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
    with os.fdopen(fd,"w") as f:f.write(value+"\n")
    return "0x"+value

def save(data):
    fd=os.open(str(OUT),os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,"w") as f:json.dump(data,f)

async def main():
    print("DMAP_PAIRING_DISCOVERY_STARTED",flush=True)
    configs=await pyatv.scan(asyncio.get_running_loop(),timeout=5,hosts=[ATV_IP],protocol=const.Protocol.DMAP)
    cfg=next((c for c in configs if str(c.address)==ATV_IP),None)
    if cfg is None:raise RuntimeError("ATV3 DMAP not found")
    pairing=await pyatv.pair(cfg,const.Protocol.DMAP,asyncio.get_running_loop(),
                              name="ATV3 Native Remote Bridge",addresses=[MAC_IP],
                              pairing_guid=stable_guid())
    # Log only HTTP outcome; never log pairing PIN, hash, or URL query.
    from aiohttp import web
    @web.middleware
    async def safe_pair_diagnostics(request, handler):
        try:
            if request.remote != ATV_IP:
                print("DMAP_PAIR_REJECT_NON_ATV3", flush=True)
                return web.Response(status=403)
            # Diagnose hashed pairing proof without logging the PIN or proof itself.
            import hashlib
            proof=request.rel_url.query.get("pairingcode", "").lower()
            guid=pairing._pairing_guid
            matches=[]
            if len(proof)==32 and all(ch in "0123456789abcdef" for ch in proof):
                for test_pin in range(10000):
                    encoded=guid+"".join(ch+"\x00" for ch in f"{test_pin:04d}")
                    if hashlib.md5(encoded.encode()).hexdigest()==proof:
                        matches.append(test_pin)
                        break
            print(f"DMAP_PROOF_DIAGNOSTIC valid_md5={len(proof)==32} recognized_pin={bool(matches)} matches_current_pin={bool(pin is not None and matches and matches[0]==pin)}", flush=True)
            response=await handler(request)
            print(f"DMAP_PAIR_REQUEST remote={request.remote} result_http={response.status}",flush=True)
            return response
        except Exception as exc:
            print(f"DMAP_PAIR_REQUEST_ERROR type={type(exc).__name__}",flush=True)
            raise
    pairing.app.middlewares.append(safe_pair_diagnostics)
    pin=None
    pairing.pin(None)  # Short-lived ATV3-only compatibility enrollment
    try:
        await pairing.begin()
        save({"status":"waiting-any-pin-atv3-only","started":int(time.time())})
        print("ATV3_PAIRING_COMPATIBILITY_WINDOW=ATV3_ONLY_ANY_FOUR_DIGITS",flush=True)
        print("On Apple TV 3 select Settings > General > Remotes > Remote App and choose ATV3 Native Remote Bridge, then enter PIN.",flush=True)
        for i in range(120):
            if pairing.has_paired:
                await pairing.finish()
                creds=pairing.service.credentials
                if not creds:raise RuntimeError("Paired without credentials")
                private=json.loads(PRIVATE.read_text()) if PRIVATE.exists() else {}
                private["dmap_credentials"]=creds
                fd=os.open(str(PRIVATE),os.O_WRONLY|os.O_TRUNC,0o600)
                with os.fdopen(fd,"w") as f:json.dump(private,f)
                save({"status":"paired","time":int(time.time())})
                print("ATV3_DMAP_PAIRING_SUCCESS",flush=True)
                return
            await asyncio.sleep(1)
        save({"status":"timeout","time":int(time.time())})
        print("ATV3_DMAP_PAIRING_TIMED_OUT",flush=True)
    finally:
        await pairing.close()

if __name__=="__main__":
    asyncio.run(main())
