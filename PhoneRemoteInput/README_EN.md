# Phone Remote & Text Input for Apple TV 3

[← Chinese README](README.md)

This module lets the iPhone's built-in **Control Center → Apple TV Remote** control a jailbroken Apple TV 3, including phone keyboard text entry, without requiring a third-party iPhone app.

## Status

**v1.0 / public1: core functionality is verified on physical hardware.**

Verified on Apple TV 3 A1469 / AppleTV3,2 / 7.9 / 12H1006:

- authenticated iPhone Control Center Remote pair verification
- Select press/release reaching the real ATV3
- directional navigation reaching the real ATV3
- Menu reaching the real ATV3
- Play short/long behavior reaching mapped next/previous actions
- ATV3 injector running inside the AppleTV process and listening only on `127.0.0.1:49154`
- real BackRow IR-equivalent event injection
- `BRTextEntryController` focus hooks firing on the real ATV3
- phone text producing real `TEXT_UPDATED` events
- phone submit producing real `TEXT_SUBMITTED` events

See [VERIFICATION.md](VERIFICATION.md) for the exact verification boundary.

## Download / Release

Current public release: `phone-remote-input-v1.0.0-public1`

https://github.com/ABoringBlog/Apple-TV-A1469-Jellyfin-Client-and-some-plugins/releases/tag/phone-remote-input-v1.0.0-public1

Release assets include:

- `org.atv3.remoteinjector_1.0.0-public1_armv7.dylib` — token-sanitized public ARMv7 injector
- `ATV3-PhoneRemoteInput-v1.0.0-public1-source.tar.gz` — public module source
- `atvr4samsung-atv3.patch` — ATV3-specific patch against the pinned upstream commit
- `SHA256SUMS`

The scripted source deployment below is recommended; the prebuilt dylib is primarily provided for verification and advanced manual installation.

## Architecture

Remote control:

`iPhone Control Center Remote → Companion Link → Mac Bridge → IR-equivalent injector / DMAP → Apple TV 3`

Text input:

`iPhone Remote keyboard / RTI → Mac Bridge → SSH loopback tunnel → ATV3 injector → BRTextEntryController`

Ports:

- `49152`: Companion Link service on the Mac for the iPhone
- `49154`: loopback-only injector socket on the ATV3, reached from the Mac through SSH tunneling
- `49156`: Mac-local focus coordination endpoint bound to `127.0.0.1`

## Security model

Public source does not include the developer's real pairing state, credentials, private LAN addresses, or injector token.

Per-user private state is stored under:

`~/.config/atv3-phone-remote/`

This includes Companion identity, paired clients, DMAP credentials, injector token, pairing GUID, and logs.

The public injector no longer embeds a fixed token. A random token is created during installation and stored on the ATV3 at:

`/var/mobile/Library/Preferences/org.atv3.remoteinput.token`

The injector itself listens only on ATV3 loopback `127.0.0.1:49154`.

## Third-party foundation

The Companion Link server is based on the MIT-licensed `atvr4samsung` project, pinned to upstream commit:

`7673178729a12b20c7d7a0bc968fc1786cbf2567`

This repository does **not** vendor the upstream Git repository. `Scripts/setup_mac.sh` clones the pinned commit and applies:

`Patches/atvr4samsung-atv3.patch`

The ATV3 patch adds Select press/release edges, directional hold timing, Play short/long handling, media Next/Previous capabilities, and committed CJK IME `textToCommit` support.

Legacy Mac → ATV3 DMAP uses `pyatv==0.18.0`.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Installation

### 1. Prepare the Mac

The Mac and ATV3 must be on the same trusted LAN, and the Mac must be able to SSH to the ATV3. SSH key authentication is recommended because the persistent tunnel uses `BatchMode=yes`.

```sh
cd PhoneRemoteInput
./Scripts/setup_mac.sh MAC_LAN_IP APPLE_TV_IP
```

This clones the pinned upstream, applies the ATV3 patch, creates a Python venv, installs dependencies, creates private state/token files, and installs the Companion Bridge plus SSH tunnel LaunchAgents.

### 2. Deploy the ATV3 injector

Provide a compatible armv7/iOS 8 iPhoneOS SDK:

```sh
export IOS_SDK='/path/to/iPhoneOS.sdk'
./Scripts/deploy_injector.sh APPLE_TV_IP
```

The script backs up any existing injector before deploying:

`/Library/MobileSubstrate/DynamicLibraries/org.atv3.remoteinjector.dylib`

plus its filter plist and private token.

### 3. Pair Mac → ATV3 DMAP

```sh
export ATV3_PHONE_BIND='MAC_LAN_IP'
export ATV3_PHONE_ATV='APPLE_TV_IP'
export ATV3_PHONE_STATE_DIR="$HOME/.config/atv3-phone-remote"
.venv/bin/python Bridge/dmap_pair_atv3.py
```

Follow the terminal instructions and complete pairing from the ATV3 Remote App settings page.

### 4. Pair iPhone → Mac Companion

```sh
export ATV3_PHONE_STATE_DIR="$HOME/.config/atv3-phone-remote"
.venv/bin/python Bridge/native_remote_pair.py open
```

Then on iPhone open:

`Control Center → Apple TV Remote → ATV3 Bridge`

and enter the temporary PIN shown in the terminal.

## CloudTune phone search integration

CloudTune 1.1 public2 uses a real `BRTextEntryController` search editor.

When the editor gains focus, this module forwards iPhone Remote keyboard input to the ATV3. CJK IME commit handling uses `textToCommit`; real `TEXT_UPDATED` and `TEXT_SUBMITTED` events were observed on physical hardware.

## Public-build boundary

The functional remote and text-input architecture is device-verified using the final development injector/bridge baseline.

To avoid publishing a real fixed token, public1 changes the injector to load a per-install private token file at runtime. That sanitized public injector compiles successfully as ARMv7 but has **not yet received a separate physical-device installation acceptance test**.

In short: the functionality is device-verified; the public token-hardening/deployment packaging is newly sanitized.

## License

Project-authored Bridge glue, ATV3 injector code, deployment scripts, and documentation are released under the repository's root MIT License.
