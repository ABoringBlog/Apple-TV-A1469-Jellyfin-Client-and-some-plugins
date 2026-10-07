# Native playback 60% device checkpoint — 2026-10-04

The handoff was stale: actual clean HEAD was `f2537ea` (0.5.48-playprobe6,
tag `native-playback-0.5.48-60-probe6`), and the device had 0.5.47-playprobe5.
Existing Probe4/5/6 commits, tags, packages and evidence were preserved. No
playback source changes were needed in this continuation.

## Crash attribution

Probe3 crash at 12:08:31 has Jellyfin UUID
`90872A2B-36D1-3A02-89FD-2CDFCE6459B9`, matching the archived Probe3 binary.
With load address `0x532e000`, frame `0x53517ce` resolves to
`-[JFATV3PlaybackBackend prepareRequest:positionTicks:error:] +1024`.
The matched AppleTV image UUID is `7B6481A8-B289-3EF8-A4D1-814283905F8D`.
Its exception frames identify `BRMediaPlayerManager playerForMediaAsset:error:`
and `playerForMediaAssetAtIndex:inTrackList:error:`, then
`LTAVPlayer setMediaAtIndex:inTrackList:error:`, the BRStateMachine path,
and `LTAVPlayer _setMediaAtIndex:inTrackList: +302`.
One internal frame (`0x519ec4` unslid) remains unnamed.
This proves the exception occurred inside the manager call, before controller
creation. No custom getter frame appears. The crash does not contain the
original exception reason, so it cannot alone establish that reason.
The existing Probe4 try/catch encloses this call and controller creation.

Probe5 crash at 12:35:10 has UUID `493F5B07-5478-39BA-B9F9-FCF994B5A7F7`,
matching its archived binary. Frame `0x542e460`, load `0x540a000`, resolves to
`+[JFATV3PlaybackProbeRunner run] +2096`. Disassembly identifies the
`absoluteString` message (selector reference `0x34a28`) in probe diagnostics.
The pre-reload log already reported successful asset/player/controller creation.
Probe6's existing NSString/NSURL type handling fixes this diagnostic failure.

Raw crashes, UUID/symbolication output and validation logs are retained locally
under `device-evidence/12H1006/playprobe6-r2/` (private evidence, git-ignored).

## Verification and deployment

- `git diff --check`, `make test-playback`, `make test-offline`, `make test-asan`
  passed: Core 252, Session 438, Host 46, UI 394, Playback 193, Integration 6/6.
- Fresh build: `build/iPhoneOS11.4.sdk-ios8.0-playprobe6-r2`.
- Fresh package: `build/package-playprobe6-12H1006-r2/`.
- Candidate-specific package tests: 12/12; deployment tests: 8/8; ARMv7 ABI: 4/4.
  Package validation and strict codesign verification passed; thin ARMv7,
  ad-hoc signature, no private BackRow class link dependency.
- Package version: `0.5.48-playprobe6`; bundle version: `0.5.48`.
- DEB SHA256: `af0a33f0dbf4afd657643c37b62699bf602b262bf58bfece008df032751b0cc1`.
- Installed binary SHA256: `7c933eb4c4fbe4d0b69913f0835d8984e3709a9c86b496fa5933b2162ab4e262`.
  Fresh r2 artifacts match the existing r1 hashes.
- `device-deploy.py backup/upload/install/inspect` succeeded with run ID
  `playprobe6_20261004b`. Rollback is the verified installed-version Probe5 r1 DEB.
  Logs are in `logs/device/playprobe6_20261004b-*`.

At device time 13:27:37 ADT, created the enable marker and issued only
`launchctl stop com.apple.frontrow`. Two subsequent SSH attempts timed out
during banner exchange; later read-only checks recovered successfully.
The final probe reported:

```text
PROBE_BEGIN main=1 compatible=1
PROBE_LTAV streamingType=<BRMediaType: Streaming video> listed=1 handlesStreaming=1
PROBE_PREPARE prepared=1 asset=1 player=1 controller=1 errorDomain= errorCode=0 exceptionName= exceptionReason=
PROBE_ASSET loopback=1 tokenInURL=0 stringURL=1
PROBE_END preparedAfterDiscard=0
```

FrontRow PID was 16889, LastExitStatus 15 following the intentional stop.
The enable marker remained after execution; it was explicitly removed after
the successful probe and `PROBE_DISABLED` was verified in `marker-cleanup.log`.
Future marker creation must give the FrontRow user permission to remove it;
the current runner ignores removal failure, so automatic one-shot consumption
must not be assumed merely from successful probe completion.
Both active and Retired crash listings showed no new crash; the latest remains
Probe5's 12:35:10 crash. This demonstrates one complete successful preparation
and discard cycle, not real playback or long-term stability.

## 80% design gates (not enabled)

1. Preserve strict 12H1006 ABI checks and the native streaming BRMediaType.
   Extend asset construction only for a demonstrated required contract.
2. Establish a supported way to attach Authorization to AVURLAsset requests,
   then separately prove propagation to HLS playlists, segments and keys on
   device using an isolated controlled endpoint and synthetic credentials.
   Verify redirect/cross-origin handling and absence of credentials in URLs/logs.
   Preparation alone supplies no evidence of header propagation.
3. Any network/media-loading experiment needs a separately reviewed scope;
   this checkpoint does not authorize cue, setState, present or real media flow.
4. Keep `startRequest:` fail-closed and the real Play button disconnected until
   header propagation and presentation are proven. Retain existing PlaybackInfo
   planning, DirectPlay/DirectStream/Transcode selection, reporting state machine
   and URL checks in JFPlaybackModel/JFPlaybackController.

No cue, setState, present, real Jellyfin media request, reboot, system/cache
modification, or unrelated UI/transcoding work was performed in this continuation.
