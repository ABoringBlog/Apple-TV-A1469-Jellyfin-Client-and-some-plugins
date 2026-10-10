# Physical-device verification

Target hardware:

- Apple TV 3 A1469
- AppleTV3,2
- Apple TV Software 7.9 / build 12H1006
- iOS 8.4.4 base system

Verified on physical hardware on 2026-10-10:

- iPhone Control Center Apple TV Remote completed authenticated pair verification with the Mac Companion bridge.
- Native iPhone Select press/release reached the ATV3.
- Directional navigation reached the ATV3 IR-equivalent event injector.
- Menu events reached the ATV3.
- Play-button short/long handling was observed reaching mapped next/previous actions.
- The ATV3 loopback injector was loaded in the AppleTV process and listening only on `127.0.0.1:49154`.
- Injected BackRow events were queued on the real ATV3.
- Text focus hooks observed real `BRTextEntryController` pushes.
- Phone text produced repeated `TEXT_UPDATED` events on the real ATV3.
- Phone submit produced repeated `TEXT_SUBMITTED` events on the real ATV3.

The deployed development injector exactly matched the local `RemoteInjector-skip-final.dylib` baseline by MD5 before public sanitization.

## Public-build boundary

The public source changes one security detail from the tested development build: instead of embedding a fixed injector token in the dylib, the public version reads a per-install token from:

`/var/mobile/Library/Preferences/org.atv3.remoteinput.token`

The public sanitized injector compiles successfully as ARMv7, but that **sanitized token-file build has not yet received a separate physical-device installation acceptance test**.

The functional remote/text-input architecture itself is device-verified; the public packaging/deployment hardening is separately identified above.
