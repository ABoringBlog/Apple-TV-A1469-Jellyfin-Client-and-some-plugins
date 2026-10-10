#!/usr/bin/env python3
"""ATV3 Bridge: make the iPhone's built-in Control Center Remote see a modern Apple TV.

Client side: open-source Companion Link server (atvr4samsung, MIT), real pairing
with authenticated session and persistent identity. Back-end: paired DMAP
protocol to the actual Apple TV 3. No web UI or iPhone app is required.
"""
import asyncio
import base64
from contextlib import AsyncExitStack
import json
import logging
import os
from pathlib import Path
import signal
import sys
import time

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT/"upstream-atvr4samsung"/"src"))
from zeroconf import Zeroconf
from pyatv import const
import pyatv
from atvr4samsung.bridge.gestures import GestureConfig
from atvr4samsung.bridge.keymap import Action
from atvr4samsung.companion.discovery import advertise_companion
from atvr4samsung.companion.relay import DirectionalHoldConfig
from atvr4samsung.companion.server import close_server, serve
from atvr4samsung.companion.protocol.server_identity import load_or_create_server_identity
from atvr4samsung.companion.protocol.paired_clients import PairedClients
from atvr4samsung.companion.protocol.enums import KeyboardFocusState
from atvr4samsung.pairing_window import PairingWindowStore

LOG=logging.getLogger("atv3.native_remote")
STATE_ROOT=Path(os.environ.get("ATV3_PHONE_STATE_DIR",str(Path.home()/".config"/"atv3-phone-remote"))).expanduser()
STATE_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
os.chmod(STATE_ROOT,0o700)
PRIVATE=STATE_ROOT/"native_remote_state"
PRIVATE.mkdir(mode=0o700, exist_ok=True)
os.chmod(PRIVATE,0o700)
ATV_HOST=os.environ.get("ATV3_PHONE_ATV","").strip()
MAC_HOST=os.environ.get("ATV3_PHONE_BIND","").strip()
if not ATV_HOST or not MAC_HOST:
    raise RuntimeError("ATV3_PHONE_ATV and ATV3_PHONE_BIND must be configured")
PORT=int(os.environ.get("ATV3_NATIVE_REMOTE_PORT","49152"))
NAME=os.environ.get("ATV3_NATIVE_REMOTE_NAME","ATV3 Bridge")
BACKEND_CREDENTIALS=STATE_ROOT/"private_state.json"
IR_KEYFILE=Path(os.environ.get("ATV3_IR_KEYFILE",str(STATE_ROOT/"injector-token"))).expanduser()
IR_ENABLED=os.environ.get("ATV3_IR_INJECT","0")=="1"
IR_ACTION={"KEY_NEXT_TRACK":12,"KEY_PREVIOUS_TRACK":9,"KEY_UP":3,"KEY_DOWN":4,"KEY_LEFT":6,"KEY_RIGHT":7,
           "KEY_ENTER":5,"KEY_RETURN":1}

KEYMAP={
    "KEY_UP":"up", "KEY_DOWN":"down", "KEY_LEFT":"left",
    "KEY_RIGHT":"right", "KEY_ENTER":"select", "KEY_RETURN":"menu",
    "KEY_HOME":"top_menu", "KEY_PLAY_BACK":"play_pause",
    "KEY_PLAY":"play", "KEY_PAUSE":"pause",
    "KEY_POWER":"suspend",
    "KEY_NEXT_TRACK":"next", "KEY_PREVIOUS_TRACK":"previous",
}
# Keep volume and power disabled until separately verified on this ATV3 path.
UNSAFE={"KEY_POWER","KEY_VOLUP","KEY_VOLDOWN","KEY_MUTE"}

class ATV3DMAP:
    def __init__(self):
        self.device=None
        self.connect_lock=asyncio.Lock()
        self.send_lock=asyncio.Lock()
        self._missing_logged=False
        self._play_held_at=None
        self._text_focus=False
        self._ir_hold_key=None
        self._ir_release_task=None

    def credential(self):
        try:
            return json.loads(BACKEND_CREDENTIALS.read_text())["dmap_credentials"]
        except (ValueError,KeyError,FileNotFoundError):
            return None

    async def connect(self):
        async with self.connect_lock:
            if self.device:
                return self.device
            creds=self.credential()
            if not creds:
                if not self._missing_logged:
                    LOG.warning("ATV3 DMAP still unpaired. iPhone emulator can pair, but TV keys remain disabled.")
                    self._missing_logged=True
                return None
            scanned=await pyatv.scan(asyncio.get_running_loop(),hosts=[ATV_HOST],
                                      protocol=const.Protocol.DMAP,timeout=4)
            cfg=next((c for c in scanned if str(c.address)==ATV_HOST),None)
            if cfg is None:
                raise RuntimeError("Real ATV3 not discoverable")
            if not cfg.set_credentials(const.Protocol.DMAP,creds):
                raise RuntimeError("Invalid ATV3 DMAP credential")
            self.device=await asyncio.wait_for(pyatv.connect(
                cfg,asyncio.get_running_loop(),protocol=const.Protocol.DMAP),timeout=10)
            LOG.info("Connected to real ATV3 via paired DMAP")
            return self.device

    async def send(self,command):
        async with self.send_lock:
            if command.action is Action.SEND_TEXT:
                if command.text is not None:
                    if '\n' in command.text or '\r' in command.text:
                        clean=command.text.rstrip('\r\n')
                        if clean: await self._send_text(clean)
                        await self._submit_text()
                    else:
                        await self._send_text(command.text)
                return
            if command.action is not Action.SEND_KEY:
                LOG.debug("Skipped unsupported input action %s", command.action.name)
                return
            key=command.samsung_key
            if key in UNSAFE:
                LOG.debug("Skipped unsupported/unsafe hardware control %s",key)
                return
            target=KEYMAP.get(key)
            if target is None:
                LOG.debug("No ATV3 mapping for %s",key)
                return
            if key=="KEY_PLAY_BACK" and command.cmd in ("Press", "Release"):
                if command.cmd=="Press":
                    if self._play_held_at is None:
                        self._play_held_at=time.monotonic()
                        LOG.info("iPhone play key down")
                else:
                    held=self._play_held_at
                    self._play_held_at=None
                    if held is not None:
                        duration=time.monotonic()-held
                        action_id=9 if duration>=0.45 else 12
                        await self._inject_ir(action_id,1)
                        await self._inject_ir(action_id,0)
                        LOG.info("iPhone play key %s -> ATV3 action=%d (hold_ms=%d)",
                                 "long-previous" if action_id==9 else "short-next",action_id,int(duration*1000))
                    else:
                        LOG.warning("iPhone play release without matching down")
                return
            if key=="KEY_ENTER" and command.cmd=="Press" and self._text_focus:
                await self._submit_text()
                return
            if key=="KEY_ENTER" and command.cmd=="Release" and self._text_focus:
                return
            if IR_ENABLED and key in IR_ACTION:
                try:
                    action_id=IR_ACTION[key]
                    if key=="KEY_ENTER" and command.cmd in ("Press","Release"):
                        await self._inject_ir(action_id,1 if command.cmd=="Press" else 0)
                        LOG.info("iPhone Select edge forwarded %s",command.cmd)
                        return
                    directional=key in {"KEY_UP","KEY_DOWN","KEY_LEFT","KEY_RIGHT"}
                    if self._ir_release_task:
                        self._ir_release_task.cancel()
                        self._ir_release_task=None
                    if self._ir_hold_key is not None and (not directional or self._ir_hold_key!=action_id):
                        await self._inject_ir(self._ir_hold_key,0)
                        self._ir_hold_key=None
                    if directional:
                        phase=2 if self._ir_hold_key==action_id else 1
                        await self._inject_ir(action_id,phase)
                        self._ir_hold_key=action_id
                        self._ir_release_task=asyncio.create_task(self._release_ir_after_pause(action_id))
                    else:
                        await self._inject_ir(action_id,1)
                        await self._inject_ir(action_id,0)
                    LOG.info("Forwarded native iPhone button %s -> ATV3 IR action=%d phase=%d",key,action_id,phase if directional else 1)
                    return
                except (OSError,TimeoutError,ValueError,RuntimeError) as exc:
                    LOG.warning("System IR injection unavailable, falling back to DMAP (%s)",type(exc).__name__)
            device=await self.connect()
            if device is None:
                return
            try:
                await asyncio.wait_for(getattr(device.remote_control,target)(),timeout=8)
                LOG.info("Forwarded native iPhone button %s -> ATV3 %s",key,target)
            except Exception as exc:
                LOG.warning("ATV3 DMAP send failed (%s)",type(exc).__name__)
                self.device.close()
                self.device=None

    async def _submit_text(self):
        token=IR_KEYFILE.read_text().strip()
        reader,writer=await asyncio.wait_for(asyncio.open_connection('127.0.0.1',49154),timeout=3)
        try:
            writer.write(('ATV3SUBMIT '+token+'\n').encode())
            await writer.drain()
            response=await asyncio.wait_for(reader.readline(),timeout=3)
            LOG.info('Phone Input submit result: %s',response.strip().decode('ascii','replace'))
        finally:
            writer.close()
            await writer.wait_closed()

    async def _send_text(self,text):
        if len(text)>512 or any(ord(c)<32 and c not in '\t' for c in text):
            return
        token=IR_KEYFILE.read_text().strip()
        LOG.info('Phone Input outgoing: non_ascii=%s',any(ord(c)>127 for c in text))
        encoded=base64.b64encode(text.encode('utf-8')).decode('ascii')
        if not encoded: return
        reader,writer=await asyncio.wait_for(asyncio.open_connection('127.0.0.1',49154),timeout=3)
        try:
            writer.write(('ATV3TEXT '+token+' '+encoded+'\n').encode('ascii'))
            await writer.drain()
            response=await asyncio.wait_for(reader.readline(),timeout=3)
            LOG.info('Phone Input delivery result: %s',response.strip().decode('ascii','replace'))
        finally:
            writer.close()
            await writer.wait_closed()

    async def _inject_ir(self,action_id,phase):
        token=IR_KEYFILE.read_text().strip()
        reader,writer=await asyncio.wait_for(asyncio.open_connection("127.0.0.1",49154),timeout=3)
        try:
            writer.write(f"ATV3KEY {token} {action_id} {phase}\n".encode())
            await writer.drain()
            reply=await asyncio.wait_for(reader.readline(),timeout=3)
            if reply!=b"QUEUED\n":
                raise RuntimeError("ATV3 injector rejected event")
        finally:
            writer.close()
            await writer.wait_closed()

    async def _release_ir_after_pause(self,action_id):
        try:
            await asyncio.sleep(0.55)
            async with self.send_lock:
                if self._ir_hold_key==action_id:
                    await self._inject_ir(action_id,0)
                    self._ir_hold_key=None
                    self._ir_release_task=None
        except asyncio.CancelledError:
            return
        except (OSError,TimeoutError,ValueError,RuntimeError) as exc:
            LOG.warning("IR release failed: %s",type(exc).__name__)
            self._ir_hold_key=None
            self._ir_release_task=None

    async def close(self):
        if self._ir_release_task:
            self._ir_release_task.cancel()
            self._ir_release_task=None
        if self._ir_hold_key is not None:
            try: await self._inject_ir(self._ir_hold_key,0)
            except (OSError,TimeoutError,ValueError,RuntimeError): pass
            self._ir_hold_key=None
        if self.device:
            self.device.close()
            self.device=None

async def run():
    stop=asyncio.Event()
    loop=asyncio.get_running_loop()
    for sig in (signal.SIGINT,signal.SIGTERM):
        try:loop.add_signal_handler(sig,stop.set)
        except NotImplementedError:pass

    # Bind one stable per-household identity, not the upstream's default shared identity.
    identity=load_or_create_server_identity(PRIVATE)
    paired=PairedClients(PRIVATE/"paired-clients.json")
    window=PairingWindowStore(PRIVATE)
    backend=ATV3DMAP()
    listener=None
    unpublish=None
    zconf=None
    try:
        listener,_=await serve(
            backend.send,host=MAC_HOST,port=PORT,device_name=NAME,
            gesture_config=GestureConfig(repeat_every=350),
            hold_config=DirectionalHoldConfig(enabled=True, activate_ms=450.0, initial_delay=0.40, interval=0.30, max_hold=8.0),
            unique_id=identity.identifier,private_key=identity.private_key,
            server_identity_generation=identity.generation,
            paired_clients=paired,require_paired=True,pairing_window=window
        )
        # Local-only diagnostic and later ATV3 focus notification endpoint.
        # No external LAN access; active phone pairing remains mandatory.
        async def focus_control(reader,writer):
            try:
                line=await asyncio.wait_for(reader.readline(),timeout=3)
                if line in (b"FOCUS 1\n",b"FOCUS 0\n"):
                    focus=line==b"FOCUS 1\n"
                    for session in listener._atvr4samsung_services:
                        rti=getattr(session,"session",None)
                        if rti is not None and getattr(rti,"rti_registered",False):
                            rti.rti_text=""
                            rti.rti_focus_state=KeyboardFocusState.Focused if focus else KeyboardFocusState.Unfocused
                    writer.write(b"OK\n")
                else:
                    writer.write(b"ERR\n")
                await writer.drain()
            finally:
                writer.close()
                await writer.wait_closed()
        focus_server=await asyncio.start_server(focus_control,"127.0.0.1",49156)
        LOG.info("Phone Input focus endpoint on 127.0.0.1:49156; RTI text forwarding enabled when ATV3 text focus is active")
        async def poll_atv3_text_focus():
            previous=None
            while not stop.is_set():
                try:
                    token=IR_KEYFILE.read_text().strip()
                    reader,writer=await asyncio.wait_for(asyncio.open_connection('127.0.0.1',49154),timeout=2)
                    try:
                        writer.write(('ATV3FOCUS '+token+'\n').encode())
                        await writer.drain()
                        result=await asyncio.wait_for(reader.readline(),timeout=2)
                    finally:
                        writer.close()
                        await writer.wait_closed()
                    if result in (b'FOCUS 1\n',b'FOCUS 0\n'):
                        current=result==b'FOCUS 1\n'
                        backend._text_focus=current
                        if current!=previous:
                            for service in listener._atvr4samsung_services:
                                session=getattr(service,'session',None)
                                if session is not None and getattr(session,'rti_registered',False):
                                    session.rti_text=''
                                    session.rti_focus_state=KeyboardFocusState.Focused if current else KeyboardFocusState.Unfocused
                            LOG.info('ATV3 text focus %s', 'active' if current else 'inactive')
                        previous=current
                    else:
                        previous=None
                except (OSError,TimeoutError,ValueError) as exc:
                    if previous is not None:
                        LOG.warning('Text focus polling unavailable: %s',type(exc).__name__)
                    previous=None
                await asyncio.sleep(0.65)
        focus_poll_task=asyncio.create_task(poll_atv3_text_focus())
        zconf=Zeroconf()
        unpublish=await advertise_companion(
            loop,zconf,MAC_HOST,PORT,device_name=NAME,
            identity_identifier=identity.identifier,
            model="AppleTV14,1"
        )
        LOG.info("iPhone native Apple TV Remote discovery ready: %s on %s:%d",
                 NAME,MAC_HOST,PORT)
        LOG.info("Open a 5-minute enrollment window using native_remote_pair.py")
        await stop.wait()
    finally:
        if 'focus_poll_task' in locals():
            focus_poll_task.cancel()
            try: await focus_poll_task
            except asyncio.CancelledError: pass
        if 'focus_server' in locals():
            focus_server.close()
            await focus_server.wait_closed()
        # Advertise goodbye, drain dispatch, and close paired-client state.
        if unpublish:
            try:await unpublish()
            except Exception:LOG.exception("mDNS shutdown")
        if listener:
            await close_server(listener)
        else:
            paired.close()
        if zconf:
            await loop.run_in_executor(None,zconf.close)
        await backend.close()

if __name__=="__main__":
    logging.basicConfig(level=logging.INFO,format="%(asctime)s %(levelname)s %(name)s %(message)s")
    asyncio.run(run())
