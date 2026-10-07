# Task 2 — server configuration / native input

Base: clean recovery 1bb2537, source/package 0.5.18-directroot2. User reports
Menu issue resolved. Preserve the native root Menu handling and Jellyfin-only
BLAppLegacyMerchant root-controller bridge from that baseline; no further Menu
investigation. Icon bridge/dictionary/resources and bootstrap remain unchanged.

Candidate: 0.5.19-config1.

- Native BRTextEntryController for Server address, Username and Password, with
  required protocol/selector/ABI guards and secure password masking.
- Separate Password and Sign in rows; Password: Entered reveals no secret/length.
  Password stays in memory, clears after submission, server/user changes and close;
  cancellation detaches delegate and clears the native field.
- Server address, username, Allow HTTP saved under ServerConfiguration in the
  org.jellyfin.atv3 defaults suite, reloaded on each new controller. No password or
  token is written by configuration persistence.
- Shared URL normalization for UI and JFClient: HTTPS default for omitted scheme,
  lowercase scheme/host, validated explicit ports, IPv4/IPv6, preserved base path,
  no trailing slash, default ports removed. Reject unsupported schemes, userinfo,
  queries/fragments, malformed escapes, bad host/port and traversal path segments.
- HTTP addresses can be configured while disabled, but sign-in sends no request
  until Allow HTTP is enabled. Turning HTTP off clears an HTTP session.
- Server/user changes close and release the old session/host, cancel callbacks and
  clear password; existing worker cleanup clears client token and tracked image
  caches. No token persistence exists yet (task 3); none is claimed here.
- TLS/certificate errors have a dedicated message; network reachability and timeout
  remain separate. System certificate validation is unchanged.

Validation passed: make test-offline (211 core, 177 session, 49 host, 319 UI,
179 playback assertions; 13 ABI rejection processes), fixture integration and
6 Python integration tests, 8 deployment tests; ASan playback/UI/session passed
(detect_leaks=0). Fresh ARMv7 build, 4 target ABI tests, adhoc signing and strict
verification, and all 12 new candidate package tests passed. No compiler warnings.
Evidence: logs/config1-offline-asan.log and logs/freeze-config1-12H1006-r1/.

Candidate SHA256:
7d288a3e09bc72e3c864af4ff0a2e04858540d6ba7f88ddb1ecff1069ba6f905
0.5.18 rollback SHA256:
db2ab1118521087332c4e082d348058e6cdf47278ce643a63e85b5d9544973ec
Preflight confirmed installed 0.5.18-directroot2, FrontRow PID 86.
Native device input and persistence acceptance remains pending deployment.

Recoverable full backup prior to task 2:
$HOME/Backups/Jellyfin-ATV3/20261004-032004-FULL-BACKUP/
Tar fully read (5168 members), bundle verified, SHA256 verified. HANDOFF corrected
to identify the actual 0.5.18 source snapshot and user-solved Menu issue; current
0.5.18 package is separately included under current-candidate/.

Rollback packages retained: 0.5.12-logoonly1 and 0.5.18-directroot2, plus every
intermediate candidate. Device version/PID must be freshly sampled before deploy;
older 0.5.14/PID 20053 observations are historical.

## Deployment status

Source checkpoint 266431f / server-config-0.5.19-offline. Upgrade run
config1-20261004-r1 backed up installed 0.5.18 and verified its rollback archive/deb,
then uploaded/installed 0.5.19 with SHA256 verification. Post-install inspect passed.
Only launchctl stop com.apple.frontrow was issued; old PID 86.
Two subsequent read-only SSH diagnostics attempts timed out during banner exchange.
New PID, post-restart crash status and native input/config persistence are not yet
verified. Do not mark task 2 device acceptance complete or advance to task 3 yet.
The user has been asked whether the app opens with the five configuration rows.
No second install/restart or whole-device reboot was issued.

Next: confirm native screen, regain read-only SSH sampling, test native field
entry/cancel/password masking, HTTP gate, valid/invalid URLs and persisted
server/username/Allow HTTP after exit/reentry. Password should be empty on reentry.

Rollback if needed (restore 0.5.18, preserve older 0.5.12 too):

```sh
python3 Scripts/device-deploy.py rollback --host atv3 --run-id config1-20261004-r1 --output device-evidence/12H1006/config1-r1 --execute --device-confirmed
python3 Scripts/device-deploy.py inspect --host atv3 --run-id config1-20261004-r1 --output device-evidence/12H1006/config1-r1 --execute
ssh atv3 'launchctl stop com.apple.frontrow'
```


## 0.5.21 native text-entry correction and device acceptance

Device validation of 0.5.19-config1 found that Server address, Username and
Password all fell back to "Text input is unavailable". Allow HTTP still toggled
normally and navigation remained stable, isolating the failure to native text
entry rather than the menu/controller foundation.

12H1006 static analysis and a bounded temporary runtime probe established the
cause: BRTextEntryController -init is present with the expected object-return ABI
but its ARM implementation is a nil-return stub. The real initializer is
initWithTextEntryStyle: with encoding @12@0:4i8. Apple code on the same firmware
uses style 4. Runtime validation on the device confirmed that style 4 creates a
BRTextEntryController whose editor is BRTextEntryControl and whose textField is
BRTextFieldControl. The delegate protocol, initial-text setter, field label,
password masking, stringValue getter and current/global controller stack push/pop
gates all matched and passed.

0.5.21-textinput1 therefore uses initWithTextEntryStyle:4 only on the ARM device
path after exact return/argument ABI checks. Host tests keep their ordinary mock
initializer. The temporary JFTextEntryProbe source and runtime log were removed
from the production candidate.

Validation for 0.5.21-textinput1 passed: 211 core, 177 session, 49 host, 319 UI,
179 playback/subtitle assertions, 6 integration tests, 8 deployment tests and all
three ASan suites. Fresh ARMv7/iOS 8.0 build, strict adhoc codesign verification
and 12 candidate package tests passed. No compiler warning/error was found in
logs/textinput1-full-verify.log.

Recovery commit: 89f2bcd.
Candidate tag: server-config-0.5.21-textinput1.
Package:
build/package-textinput1-12H1006-r1/
org.jellyfin.atv3_0.5.21-textinput1_iphoneos-arm.deb
Package SHA256:
01930529e20b8258b023124bf03a5db6fc2df17d26b69d4557eee5f281ff60dd
Binary SHA256:
0984cfeafa566d005367a4d2340b90f9857cfd6ae8a68472a30f56942df3b85c
AppIcon SHA256:
5236d4c4475054799cf23262b96ebd850651534260c28f4188cd2b0736c98c65

Controlled deployment run textinput1-20261004-r1 backed up the installed
0.5.20-textprobe1 before installing 0.5.21-textinput1. Only FrontRow was restarted;
no whole-device reboot was performed. FrontRow changed from PID 1519 to PID 2176.
Repeated post-deploy sampling kept PID 2176 and the installed binary hash matched
the packaged candidate. LatestCrash-AppleTV.ips still points to the historical
AppleTV_2026-10-03-011539_Apple-TV.ips; no new AppleTV crash was observed.

For physical acceptance the user was instructed to reply "继续" only if all listed
checks were normal. The user then replied "继续", confirming: direct Jellyfin entry
remained free of the old black wrapper; Server address, Username and Password each
opened native text entry instead of the unavailable fallback; password input was
masked and returned as "Password: Entered"; Sign in became selectable once all
required fields were present; Allow HTTP still toggled; remote Up/Down and one-Menu
exit remained normal.

Task 2 server configuration / native input is therefore accepted on the current
FrontRow session. Task 3 token persistence has not started. Whole-device reboot
acceptance remains deliberately deferred and must not be inferred from this
Task 2 acceptance.
