# 12H1006 native playback investigation

Evidence target: AppleTV3,2 / 12H1006 AppleTV UUID
`7B6481A8-B289-3EF8-A4D1-814283905F8D`. Addresses below are unslid.
All work uses the existing local executable; no system files are modified.
Annotated disassemblies are in `device-evidence/12H1006/playprobe7-r1/`.
The annotation script is a linear constant aid, not a control-flow emulator;
conclusions below also follow the actual load/store and call instructions.

## STATIC VERIFIED — HTTP headers

`LTAVPlayer -_playerItemForAsset:isLookaheadItem:` starts at `0x500e4c`.

- `0x500f46`: sends `playbackMetadata` to the media asset, retaining the result.
- `0x501a56..0x501a5e`: loads key via `0xb75fec -> 0xce5fbc`, a CFString
  containing `BRMediaAssetMetadataHTTPHeaders`, and calls `objectForKey:`
  on the metadata dictionary. Selector is saved in stack slot `sp+60`.
- `0x501a7c..0x501a86`: loads imported `AVURLAssetHTTPHeaderFieldsKey`
  through `0xb760f8` and reads any existing dictionary from the options.
- `0x501a9e..0x501ad6`: mutable-copies it or creates a mutable dictionary.
- `0x501aec`: `addEntriesFromDictionary:` with the asset's header dictionary.
- `0x501b02`: writes merged headers back under `AVURLAssetHTTPHeaderFieldsKey`.
- `0x501d6a`: `+[AVURLAsset URLAssetWithURL:options:]`, URL from `sp+72`,
  options from r11. `0x50242c` constructs `AVPlayerItem` with `playerItemWithAsset:`.
- `0x501d12..0x501d4a`: separately maps `kBRMediaAssetReferenceRestrictions`
  to imported `AVURLAssetReferenceRestrictionsKey`. Its redirect enforcement
  is NOT yet verified and must not be inferred from the key name.

A complete aligned data-pointer scan finds one pointer to the header key
storage, at `0xb75fec`. A full __text Thumb MOVW/MOVT/ADD-PC scan identifies five references:
`0x268ee0` (ATVVideoAsset initWithFeedElement:), `0x275f58`
(ATVVideoCacheManager _startCachingURL:orItem:withElapsedTime:),
`0x38fd0a` (BRStreamingMediaAsset playbackMetadata), `0x447430`
(ATVAppAVAsset playbackMetadata), and `0x501a56` (LTAVPlayer consumer).
Each surrounding range is saved separately. This enumerates this compiler
reference form; it is not a claim that all possible indirect paths were excluded.

`BRBaseMediaAsset playbackMetadata` ABI is `@8@0:4`; its setter is
`v16@0:4@8@12`. Base implementations at `0x385284/0x385288` are stubs.
The Jellyfin subclass supplies an immutable dictionary getter and copies the
original request. Only Authorization, Accept, Accept-Language and User-Agent
are admitted; no Host, cookies, framing or hop-by-hop fields. No values are logged.

`LTAVPlayer _setMediaAtIndex:inTrackList:` at `0x50a830` calls `mediaURL`
at `0x50a936`, then `NSURL URLWithString:` at `0x50a95e`. This further
identifies the Probe3 failure site and validates retaining string media URLs.

## STATIC VERIFIED — command states (not an observed state sequence)

`BRMediaPlayer setState:error:` (`0x4afbe0`) is an inert base implementation.
Actual LTAVPlayer dispatch is `0x4f98e4`, bounds-checking 0..15 and using the
Thumb halfword jump table at `0x4f992c`.

| Command | Target | Posted event |
|---|---|---|
| 0 | 0x4f994c | Stop and reset event |
| 1 | 0x4f9978 | Pause event |
| 3 | 0x4f999e | Play event |
| 4..6 | 0x4f99c4..0x4f9a10 | FFW1..3 |
| 7..9 | 0x4f9a36..0x4f9a82 | Rewind 1..3 |

2 goes to the fallback branch at `0x4f9b90`; it is not assigned a guessed name.
`cueMediaWithError:` at `0x4f97c8` posts `Cue media event` and tests the
state machine for `Remote media loading error state`. Success is not proof
of asynchronous network success. Loading/failure observed state values remain
PROVISIONAL until their producers and runtime behavior are established.

## STATIC VERIFIED — lifecycle entry points

- `BRMediaPlayerManager presentPlayer:options:`: `v16@0:4@8@12`, `0x499cc0`;
  owns the native presentation path, reaching `_addPlayerWindowForController:`.
- `endPresentation`: `v8@0:4`, `0x49a5d0`; resolves the presented controller/stack.
- `_playerControllerWasPopped:` at `0x49e888` clears external controller state,
  updates auto-presentation and removes its player window.
- `LTAVPlayer _playerItemDidPlayToEnd:` at `0x507f84` posts
  `BRMediaPlayerPlaylistAssetPlayedToEndTime` and enters the internal event path.
- `_playerItemFailedToPlayToEnd:` at `0x5080cc` forwards an error into that path.
- `_playerItemPlaybackStalled:` at `0x5081cc` posts
  `BRMediaAssetStalledDuringPlaybackNotification` with the media object.

The final callback mapping and ownership adapter remain PROVISIONAL. A stalled
notification alone must not mark media watched or naturally ended.

## DEVICE VERIFIED

Only Probe6 preparation/discard is verified so far; see the 60% closeout.
Probe7 is a fixed-origin, synthetic-only, non-presenting cue probe. It consumes
its marker before running and fails closed if deletion fails. The controlled
server logs header names/presence, synthetic match booleans, paths and origins,
never values. Real session credentials are not accessible to this runner.

Additional STATIC VERIFIED notifications: `_setExternalPlayerState:reason:`
at `0x50d414` posts `BRMPStateChanged` with player object and optional
`BRMediaPlayerStateChangeReason`. `_postErrorNotificationImmediately:` posts
`BRMediaPlayerPlaybackError`, with error under `BRMediaPlayerPlaybackErrorErrorKey`.
`BRMediaPlayerController wasPopped` posts `BRMediaPlayerControllerWasPopped`
at `0x376b40` and calls `setState:error:` on the player when its
`alwaysStopPlaybackWhenPopped` policy applies. These are candidates for scoped
observers; observers must be removed before releasing their player/controller.

## Probe7 DEVICE VERIFIED network results (recovered after explicit stop)

Source `e155776`, device 0.5.49-playprobe7, binary SHA256
`638c36b4bcce0baa5110d2a4f10de439043215e4a8596dbbbc1fc4763e96187b`.
`playprobe7-r1/requests-r2.jsonl` records requests from APPLE_TV_IP.
Plain master/media playlists and all six segments carried synthetic Authorization.
Same-origin redirect target master did NOT carry it, but child playlist/segments did.
Cross-origin redirect target master did NOT carry it, but its child playlist and
segments DID. Direct cross-origin segment references also carried it. Redirected
segments themselves did not carry Authorization at the secondary origin.
**This is a credential isolation failure, not an 80% pass.** Production remains closed.
The explicit STOP interrupted the runner before its final stop/end lines; later
FrontRow reload terminated it. No additional AppleTV crash appeared in active or
Retired lists at resume. Probe7 full offline finished; ASan compilation was explicitly
terminated and is not counted as passed.

## Probe8 PROVISIONAL experiment

Retain the same native header channel, add `kBRMediaAssetReferenceRestrictions=5`
(remote-to-local | cross-site). The enum values are from the local iPhoneOS11.4 SDK
AVAsset.h; availability predates iOS 8, but **actual 12H1006 enforcement is unverified**.
Use existing encrypted 12-second fixture, add ordinary MP4 and AES key requests.
No user credentials, real media, fullscreen, or production start are enabled.

## Probe8 DEVICE VERIFIED — native restriction insufficient

Source `7f023ae`, version 0.5.50-playprobe8, binary SHA256
`5f389500845d58196059a7fb7ed5385653bd73d4e3fc5f19a0fc5b088f7c3131`.
Plain MP4, HLS master/media/all six segments, and encrypted HLS key/segments
received synthetic Authorization. With reference restrictions 5, cross-origin
child requests STILL received it. Thus this metadata option is not a sufficient
scheme/host/port credential boundary. All seven cases completed cue/stop,
`NETWORK_END` was recorded, FrontRow PID 25326 and no new AppleTV crash.
Full offline and ASan passed (Core 252, Session 438, Host 46, UI 394,
Playback 204, Integration 6/6); ABI 4/4, candidate Package 12/12, Deployment 8/8.
`playprobe8-r1/requests-r1.jsonl` later also contains Mac loopback-gateway tests;
filter `peer=APPLE_TV_IP` to identify the native Probe8 requests.

## Probe9 PROVISIONAL — per-request origin boundary

Since native header propagation leaks credentials across origins, the native
player will receive only a loopback URL and a non-secret local header marker.
An appliance-owned `JFMediaGateway` holds the original Authorization in memory,
streams allowed same-origin responses, rejects every redirect, rewrites HLS URI
references to local routes, and rejects external scheme/host/port references.
Known credential query fields are stripped from HLS references before an upstream
request is created. Cookies, caching and compression are disabled. No session
credentials are written to URLs, files or diagnostic output. Binary media data
streams with backpressure; playlists have a 1 MiB cap and route count is bounded.
Only loopback binds are allowed; no external listening service is added to ATV.

This retains BackRow/AVFoundation rendering and the existing playback planner and
reporting. It does not claim native reference restrictions became safe. Same-origin
redirects are deliberately rejected too: configure the final server URL.
Offline policy assertions and a real Mac loopback HTTP test exercise ordinary MP4,
nested HLS, six segments, AES key, same/cross-origin redirects and external children.
The first Mac HTTP run passed 47 assertions; device proof is still pending.

## 2026-10-05 recovery and Probe9 device verification

Recovery HEAD was clean `62a4dbe`, tagged `native-playback-0.5.51-80-probe9`.
`e155776` matches the requested Probe7 tag; Probe8 had already been committed
as `7f023ae`. No uncommitted Probe8 work remained. Main `.git` is an unborn
main branch and is not the project history. Recovery fsck passed (only dangling
objects reported); no reset, clean, stash or history migration was performed.

Installed version was already 0.5.51-playprobe9, binary SHA256
`d77e27100acc0fe99b05639ca9f1ab0356b550d64cbb9eb4d24c89a9593bdfb0`.
The running FrontRow had not yet executed Probe9. A new isolated server capture
and one-shot FrontRow reload completed all seven Probe9 cue/stop cases.
`playprobe9-r1/requests-resume-20261005-r2.jsonl` contains 30 ATV requests,
all to the primary origin with correct synthetic Authorization; zero secondary
requests. MP4, plain and AES HLS master/media playlists, all six segments and
AES key were fetched. Same/cross-origin redirects, external child references,
and redirected segments were exercised and blocked. `NETWORK_END` appears in
`completed-resume-20261005.log`. `Scripts/verify-network-probe.py` verifies
positive coverage as well as absence of external requests; all checks passed.
Two SSH banner timeouts during the run recovered without intervention.

This proves the tested native loader plus gateway network boundary, not complete
Task 8 playback. Probe10 adds a separately enabled synthetic full-screen experiment
with numeric elapsed-time samples and scoped notification names, never userInfo.
Real playback, transport controls, completion, resume and server reporting still
require implementation and device acceptance. The user authorizes using the saved
device session, without exposing credentials, and will assist with TV acceptance.
