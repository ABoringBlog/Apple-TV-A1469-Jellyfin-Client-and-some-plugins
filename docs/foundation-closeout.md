# FRAppliance foundation closeout — 0.5.13-foundation1

Baseline: recovery `076cd37`, stable rollback `0.5.12-logoonly1`.
Target: AppleTV3,2 / A1469 / Apple TV 7.9 / 12H1006.

## Scope

Removed IconDiagnostics, its delayed selector, all four BRApplianceIconManager
probe hooks, runtime UI trace calls and the /tmp/JellyfinATV3.log writer.
Preserved synthetic BRApplianceInfo, BLForceLegacyNav=false, logo resources,
720/1080 string and NSNumber dictionary keys, and the merchant KVC bridge.
Only Jellyfin merchant menu-icon-url and menu-icon-url-version are intercepted;
all other keys/merchants call the saved superclass implementation.
No Beigelist, Substrate, bootstrap, Apple system file or cache manipulation.

Synthetic info now owns alloc until init returns, releases on rejected init ABI,
and autoreleases the returned object (including replacement/nil init semantics).

## Ownership review

- Controller retains menu/remote via associated objects; menu controller pointer
  is non-owning. Deallocation closes menu and clears both associations.
- Pop closes UI/session; deactivate clears list datasource and observers while
  retaining navigation state for a return from native text input.
- Editor close clears delegate and input text before release. End-edit callback
  retains UI across reentrant native stack pop.
- UI/session observers are removed before owned objects are released.
- Session/playback delivery holders do not retain owners; close nils owner,
  cancels tasks and invalidates generations. Blocks retain task inputs and copied
  callbacks; completed work/delivery blocks are released. Worker logout cleanup
  uses a temporary cycle broken when its work finishes.
- Existing UI tests cover direct controller deallocation, repeated pop/close,
  editor cancellation and callbacks after close. New tests cover superclass KVC
  fallback and synthetic init returning self, nil, or a replacement object.
- AddressSanitizer is an address-error check, not a device leak measurement.

## Validation and deployment

Local validation passed: make test-offline (184 core, 177 session, 49 host,
238 UI, 179 playback assertions; 13 ABI rejection processes; integration fixture
and 6 Python integration tests), 8 deployment tests. Historical package tests
passed with one legacy-resource skip; the new candidate passed all 12 tests
without skips. ARMv7 target ABI tests: 4 passed. ARMv7 build and adhoc codesign
strict verification passed. ASan playback/UI/session passed (detect_leaks=0).
Two new test fixture compiler warnings were corrected; UI and UI ASan reran
successfully, with unchanged production package bytes.

Candidate: build/package-freeze-foundation1-12H1006-r1/
org.jellyfin.atv3_0.5.13-foundation1_iphoneos-arm.deb
SHA256: 9da8635223a6d56ccb9fa1cbbc943128b74f58ea486cd38595d1ec8c48e9ac69
Rollback SHA256: 6a59d750212df2216bdc254d664b60b7e7292b8dd505c226baca888be9511974
Evidence: logs/foundation1-offline.log, foundation1-asan.log,
foundation1-ui-r2.log and logs/freeze-foundation1-12H1006-r1/.

Offline source checkpoint: 2cde99d / foundation-0.5.13-offline.
Controlled deployment run: foundation1-20261003-r1. Backup archive and rollback
package hashes were verified before upload/install. Package ownership, modes,
symlink and installed binary SHA256 passed inspection:
b974ff3f2b6cfd6d89b007a9e2350937c61ccf91cc7d6a1de62fba4f06abb661.

Only launchctl stop com.apple.frontrow was issued; KeepAlive relaunched FrontRow.
PID changed 19458 -> 19793 and remained 19793 in subsequent sampling at about
02:16 ADT. No whole-device reboot was performed. Existing bootstrap md5sums audit
warnings remain unchanged; the existing deployment script gates passed.
Apple regenerated org.jellyfin.atv3@1080.png at 02:14. Its SHA256 equals AppIcon.png:
5236d4c4475054799cf23262b96ebd850651534260c28f4188cd2b0736c98c65.
MainMenuImageCache reports merchant.org.jellyfin.atv3_version@1080 = 0.5.13.
The old diagnostic log hash stayed unchanged across the restart. Crash directory
listing showed no new entry; historical 01:15 crash links remain and are not
attributed to this candidate. Raw evidence: device-evidence/12H1006/foundation1-r1/.

PENDING: visual logo, direct login navigation, remote/Menu, five repeated entry/
exit cycles, longer PID stability, and whole-device reboot acceptance. User was
asked for native screen/remote validation; no remote UI automation is established.
This candidate is not yet promoted to stable rollback. Task 2 has not started.
Raw evidence stays outside source commits; reviewed results will be added here.
Do not start task 2 until foundation device acceptance is complete.

## Rollback

Preserve build/package-logoonly1-12H1006-r1/
org.jellyfin.atv3_0.5.12-logoonly1_iphoneos-arm.deb.
Use Scripts/device-deploy.py backup with that rollback package before upgrade.
Use the matching run-id rollback action, inspect, then restart only
com.apple.frontrow. Never manufacture or delete Apple MainMenu cache entries.

## Recovery policy

Create a recoverable checkpoint at each major stage. Usage quota is not exposed
by available tools; the user supplies the low-quota signal. FULL BACKUP NOW stops
new development immediately and triggers a verified full recovery backup under
$HOME/Backups/Jellyfin-ATV3/<timestamp>/ including source, recovery.git,
git bundle, stable/candidate/rollback packages, SHA256SUMS and HANDOFF.md.

Exact rollback command for this deployment:

```sh
python3 Scripts/device-deploy.py rollback --host atv3 --run-id foundation1-20261003-r1 --output device-evidence/12H1006/foundation1-r1 --execute --device-confirmed
python3 Scripts/device-deploy.py inspect --host atv3 --run-id foundation1-20261003-r1 --output device-evidence/12H1006/foundation1-r1 --execute
ssh atv3 'launchctl stop com.apple.frontrow'
```

## User acceptance update

User reported an anomaly after deployment; exact reproduction details are pending.
Foundation acceptance has NOT passed. Do not promote 0.5.13 to stable or start
task 2. Read-only anomaly sampling at about 02:17 ADT still shows PID 19793
and no new crash directory entry. Preserve the candidate and the verified
0.5.12 rollback while waiting for the affected interaction to be described.

## Reproduction and navigation investigation

User clarified: entering/exiting without moving selection works. After Up/Down
movement, first Menu leaves a Jellyfin title with no rows; second leaves Jellyfin
in a box; third returns to main menu. Repeated entry/exit alone is fine.
No crash/PID change was found. This is an unresolved navigation/render lifecycle
failure; root cause is not yet established. It may predate diagnostic cleanup.

Full project recovery backup was verified at:
$HOME/Backups/Jellyfin-ATV3/20261003-021922-foundation-anomaly/
All tar members were read, recovery.bundle verify passed, 683 SHA256 entries
were recomputed. Includes source/recovery.git/history, all builds and raw evidence,
separate stable/candidate/rollback debs, uncommitted patch and HANDOFF.md.
That snapshot predates the detailed reproduction and navigation probe below.

Temporary candidate 0.5.14-navtrace1 adds only a bounded, exception-contained
navigation probe in Jellyfin's own callbacks, to /tmp/JellyfinNavigation.log.
Records numeric events, controller pointers/class names and verified stack
selectors (controllers / peekController); no input, credentials, tokens or row
text. No Apple/Beigelist method replacement. Remove this probe after diagnosis.
Stable rollback remains 0.5.12-logoonly1; previous candidate is 0.5.13-foundation1.


## Navigation root cause and final fix candidate

0.5.14-navtrace1 reproduced the focus-dependent Menu failure on device. The
trace proved the failing stack contained exactly one JellyfinController. Menu
issued BRControllerStack popController, but Jellyfin had already closed its menu
datasource before BackRow finished the pop transition, exposing an empty
Jellyfin controller. The diagnostic probe itself is removed in the next
candidate.

0.5.15-foundation2 keeps the menu alive while requesting popController. Cleanup
is owned by the existing controlWasDeactivated / wasPopped / dealloc lifecycle.
The UI regression test now requires datasource retention until wasPopped, then
requires it to be detached. No merchant/KVC/icon behavior is changed.


## Native root Menu delegation candidate

0.5.15-foundation2 removed the pre-pop datasource teardown, which eliminated the
empty Jellyfin page, but device validation showed that a synchronous
BRControllerStack popController issued from inside JellyfinController
brEventAction: can remain pending after list focus movement.

12H1006 disassembly confirms BRMediaMenuController brEventAction: does not
special-case remote Menu action 1 in its media-specific branch; it falls through
the native superclass event path. 0.5.16-nativeexit1 therefore removes Jellyfin's
manual root stack pop. Internal Jellyfin back-navigation is unchanged; only a
root ExitRequested Menu press is delegated to the native BRMediaMenuController
brEventAction: implementation. Cleanup remains lifecycle-owned by
controlWasDeactivated / wasPopped / dealloc.


## Direct root category-wrapper candidate

Device validation of 0.5.16-nativeexit1 showed that native Menu handling removed
one manual-pop layer, but an Apple-supplied black title/chrome layer labelled
"Jellyfin" still appears on entry and is revisited on exit after list focus
moves. The appliance currently advertises both a direct applianceController and
a synthetic single applianceCategories entry. 0.5.17-directroot1 keeps the
direct applianceController path and controllerForIdentifier: compatibility
fallback, but returns an empty applianceCategories array so the direct merchant
launch does not also construct a legacy/category wrapper.


## Beigelist legacy root bridge candidate

0.5.17-directroot1 proved that the single-category wrapper is responsible for
the black Jellyfin title/chrome layer, but removing applianceCategories also
removed the Jellyfin menu content. Static analysis of Beigelist 7 then located
its ATVMainMenuController _pushControllerForApplianceOrMerchant: hook: for a
managed legacy appliance it calls BLAppManager applianceWithIdentifier:, asks
that object for rootController, and pushes that result onto
BRApplicationStackManager.stack.

0.5.18-directroot2 restores the verified Jellyfin appliance category as a
compatibility fallback, but installs a Jellyfin-owned runtime bridge on
BLAppLegacyMerchant rootController. Only the Jellyfin merchant returns a direct
JellyfinController. Every other merchant calls the saved Beigelist
rootController IMP unchanged. No Beigelist/Substrate/system file is modified.

## BACKUP NOW and user-directed scope change

0.5.14-navtrace1 passed test-offline, ARMv7 build/signing, target ABI 4 tests,
candidate package 12 tests and deployment 8 tests. Commit 0eb02f8, tag
navigation-trace-0.5.14. SHA256:
0da457392e83ba7a8bc7bb5636ae1ca3f1faf92fbd9f9045b97a7b49aa910ae7.
Deployed through navtrace1-20261003-r1 after verified backup of installed 0.5.13.
FrontRow-only restart produced PID 20053; BACKUP NOW read-only sampling still
shows installed 0.5.14 and PID 20053, with no new crash listing entry.

User then requested BACKUP NOW; full recovery backup takes priority. While backup
was in progress user explicitly requested skipping Menu anomaly work and continuing.
Finish and verify the full backup, then continue task 2. This overrides the earlier
foundation-acceptance gate but does NOT turn the unresolved Menu issue into a pass.
Do not further investigate Menu unless asked. Remove the temporary navigation
probe from the next normal candidate; do not leave diagnostic code in production.
Keep stable 0.5.12 rollback and all intermediate candidate packages.

Task 2 next: inspect existing native text entry / URL validation / defaults,
implement server configuration and persistence with focused tests, then follow
ARMv7/package/checkpoint/controlled-deployment process. Tasks 3–9 remain pending.
No actual Jellyfin server credentials are available in this session.
