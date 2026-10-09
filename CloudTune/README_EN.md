# CloudTune for Apple TV 3

[← Chinese / bilingual project README](README.md)

![CloudTune icon](CloudTune.frappliance/AppIcon.png)

**CloudTune v1** is an independent native music client for a jailbroken **Apple TV 3 (A1469 / AppleTV3,2)**.

> **This is the first public version. The main goal for the next release is a redesigned / updated UI.**

> **Branding note:** the public name **CloudTune / 云律音乐** and the cloud + music-note + sound-wave icon were deliberately **invented with ChatGPT at the user's request** to replace the official name/logo used during development. They are not official NetEase Cloud Music names, logos, or artwork. This reduces direct copying and brand confusion, but does not guarantee that there is no API, service-terms, trademark, or other legal risk. CloudTune is independent and is not affiliated with or endorsed by NetEase.

## v1 features

- Native Apple TV 3 BackRow UI
- QR-code account login
- User playlists and playlist tracks
- Recommended music
- Recently played
- Synced lyrics and translated lyrics
- Album artwork
- Play / pause
- Repeat queue, repeat one, shuffle
- Playback queue
- Like / unlike
- Playback-URL prefetching and local metadata caching
- English and Chinese builds

The search-input UI is still transitional in v1 and is planned to integrate with phone input later.

## Version status and next goal

This release is explicitly **CloudTune v1 / the first public version**.

The first priority for the next version is: **redesign and update the UI**. The existing playback/account logic will remain, while layout, visuals, interaction feedback, and the overall Apple TV experience become the main focus.

## Architecture and Mac Bridge requirement

> **CloudTune currently requires a Mac running CloudTune Bridge continuously.**

Architecture:

**Apple TV 3 CloudTune → LAN HTTP → Mac CloudTune Bridge → local compatible API service → third-party music service**

Defaults:

- CloudTune Bridge: `8101`
- External compatible API: `127.0.0.1:18300`

CloudTune Bridge handles QR login, local storage of the user's own authenticated session, playlists/tracks/recommendations/recent history, lyrics, likes, artwork proxying, and resolving playback URLs that the account is authorized to receive.

After a playback URL is resolved, ATV3 AVPlayer plays that URL directly. **If the upstream service does not authorize a playback URL for the account, CloudTune returns the item as unavailable instead of bypassing that restriction.**

If the Mac shuts down, sleeps, loses internet access, CloudTune Bridge stops, or the external compatible API stops, new data and playback requests will fail.

## External API dependency

This repository **does not include or redistribute** NeteaseCloudMusicApi source code or the legacy `.tgz` package.

Development was tested against Binaryify **NeteaseCloudMusicApi 4.32.0**, released under the MIT License. The upstream project later stopped active maintenance. This repository publishes only the CloudTune client and CloudTune Bridge.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution.

Users must provide their own compatible local API service, normally at:

```text
http://127.0.0.1:18300
```

Or configure another endpoint before installing the Bridge:

```sh
export CLOUDTUNE_UPSTREAM='http://127.0.0.1:18300'
```

## Download

Release:

https://github.com/ABoringBlog/Apple-TV-A1469-Jellyfin-Client-and-some-plugins/releases/tag/cloudtune-v1.0.0-public1

Choose one package:

- `org.atv3.cloudtune_1.0.0-public1-en_iphoneos-arm.deb` — English
- `org.atv3.cloudtune_1.0.0-public1-zh_iphoneos-arm.deb` — Chinese

Both use package ID `org.atv3.cloudtune`, so install only one language edition.

The public build uses a different bundle/package ID, merchant identifier, and runtime class name from the development build `org.atv3.neteasemusic`, so it does not directly overwrite that development package.

## 1. Run a compatible local API on the Mac

Confirm your compatible API service is reachable locally, for example:

```sh
curl http://127.0.0.1:18300
```

CloudTune does not install or redistribute that third-party service.

## 2. Install CloudTune Bridge

Python 3 is required.

```sh
cd CloudTune/Bridge
./install_launch_agent.sh
```

This creates the macOS LaunchAgent `org.atv3.bridge.cloudtune`.

Check it with:

```sh
curl http://127.0.0.1:8101/health
```

## 3. Configure the bridge URL on the ATV3

Find the Mac's LAN IP, then run on the Apple TV:

```sh
echo 'http://MAC_LAN_IP:8101' > /var/root/.atv3-cloudtune-bridge-url
```

A DHCP reservation or static LAN address for the Mac is recommended.

## 4. Install CloudTune

English example:

```sh
scp org.atv3.cloudtune_1.0.0-public1-en_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.atv3.cloudtune_1.0.0-public1-en_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'
```

Use the `-zh` package for Chinese.

## Login and privacy

After QR authorization, CloudTune Bridge stores the user's own authenticated session in:

```text
~/.config/cloudtune-atv3/session.json
```

The directory is private and the session file is written with `0600` permissions. It is outside the Git repository, is not included in the `.deb`, is not uploaded to GitHub, and should not be shared manually.

CloudTune Bridge listens on `0.0.0.0:8101` by default and does not add separate LAN authentication. **Use it only on a trusted LAN and do not expose port 8101 to the public internet.**

## Device and public-package verification

The development ATV3 client is version `0.3.3`. The latest Mac development executable and the executable currently running on the physical ATV3 match exactly by MD5:

```text
86e67afca8c592ef3a355b2d25b89848
```

The public build is rebranded and privacy-sanitized, so it is not a byte-for-byte copy of the development binary.

The public English and Chinese `.deb` packages pass ARMv7 build validation, ad-hoc signature validation, strict package-payload checks, private-IP/local-path scanning, and two independent byte-for-byte reproducible builds.

**The sanitized public v1 `.deb` packages have not yet received a separate physical-device installation acceptance test.**

## Build from source

English:

```sh
make -C CloudTune LANGUAGE=en BUILD=build/cloudtune-en cloudtune
CloudTune/Scripts/package.sh en CloudTune/build/cloudtune-en/CloudTune.frappliance CloudTune/build/package-en
```

Chinese:

```sh
make -C CloudTune LANGUAGE=zh BUILD=build/cloudtune-zh cloudtune
CloudTune/Scripts/package.sh zh CloudTune/build/cloudtune-zh/CloudTune.frappliance CloudTune/build/package-zh
```

Requires macOS, Xcode Command Line Tools, and a compatible Theos/iPhoneOS SDK. Proprietary Apple SDKs are not included in the repository.

## Branding provenance

See [BRANDING.md](BRANDING.md). The public name and icon were invented with ChatGPT at the user's request for this open-source release and are **not official NetEase Cloud Music branding assets**.

## License

CloudTune's own client source, Bridge glue code, build scripts, branding, and project documentation are released under the repository's root [MIT License](../LICENSE).

Third-party APIs, music services, account systems, songs, lyrics, artwork, and audio streams are not part of this repository.
