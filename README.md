# Apple TV 3 Modernization

[English-only README](README_EN.md)

Independent open-source applications for **jailbroken Apple TV 3 (A1469 / AppleTV3,2)**. Each app is independently installable, has its own version and release, and shares the same voluntary [GitHub Sponsors](https://github.com/sponsors/ABoringBlog) entry point.

面向已越狱 Apple TV 3 的独立开源应用集合。各应用分别构建、安装与发布，共享自愿赞助入口。

## Available applications / 已发布应用

| App | Description / 功能 | Release |
| --- | --- | --- |
| **[RetroReel3](#retroreel3-jellyfin-client)** | Independent, unofficial native client for Jellyfin / 非官方 Jellyfin 原生客户端 | [v0.5.85-brand1](https://github.com/ABoringBlog/Apple-TV-A1469-/releases/tag/v0.5.85-brand1) |
| **[Clock](Clock/)** | Native standalone clock / 原生独立时钟 | [clock-v0.1.5](https://github.com/ABoringBlog/Apple-TV-A1469-/releases/tag/clock-v0.1.5) |

**Both apps are free and do not require sponsorship. / 所有应用免费，赞助完全自愿。**

---

## RetroReel3 (Jellyfin client)

![RetroReel3 original app icon](Jellyfin.frappliance/AppIcon.png)

**An unofficial native Jellyfin client for jailbroken Apple TV 3 (A1469).**

**适用于已越狱 Apple TV 3（A1469）的独立第三方 Jellyfin 原生客户端。**

*Independent community project; not affiliated with or endorsed by Jellyfin or Apple.*

Native Jellyfin appliance for jailbroken **Apple TV 3 (A1469 / AppleTV3,2)**. Not an AirPlay receiver, browser wrapper, or tvOS application.

适用于已越狱 **Apple TV 3（A1469 / AppleTV3,2）** 的原生 Jellyfin 客户端，不依赖 AirPlay 或网页封装。

### Compatibility / 兼容性

- Tested hardware and firmware: **AppleTV3,2 / A1469, Apple TV Software 7.9, build 12H1006 (iOS 8.4.4)**.
- The native playback baseline was tested on physical hardware. The rebranded 0.5.85-brand1 package is independently built and tested offline; **real-device acceptance for this release remains pending**.
- Other models, firmware builds and jailbreak environments are not validated.

已在上述设备型号和系统版本完成原生播放基础版真机验证。当前品牌版本已完成构建和离线测试；不保证其他型号或固件兼容。

### Install / 安装

Download the `.deb` file and `SHA256SUMS` from the [RetroReel3 v0.5.85 Release](https://github.com/ABoringBlog/Apple-TV-A1469-/releases/tag/v0.5.85-brand1). On your Mac/Linux computer, verify the SHA256 listed in `SHA256SUMS`, then run:

从 RetroReel3 v0.5.85 Release 下载 `.deb` 和 `SHA256SUMS`，先校验哈希，再在 Mac/Linux 终端执行：

```sh
scp org.jellyfin.atv3_0.5.85-brand1_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.jellyfin.atv3_0.5.85-brand1_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'
```

Replace `APPLE_TV_IP` with the target Apple TV's local address. Requires jailbreak, root SSH and `dpkg`. Restart only the FrontRow host, not the entire device.

把 `APPLE_TV_IP` 换成 Apple TV 的局域网地址。需要已越狱、SSH root 权限及 `dpkg`。只重启 FrontRow，不重启整机。

> The legacy Apple TV 3 curl/SSL stack may not connect to modern GitHub HTTPS. Download on a computer and transfer by SCP instead.
>
> ATV3 内置的旧版 curl/SSL 可能无法连接 GitHub HTTPS，建议电脑下载后通过 SCP 传入。

**Upgrade safety / 升级兼容：** Package ID (org.jellyfin.atv3), internal bundle path, principal class and saved session keys remain unchanged for existing installations. Only the visible app name and artwork change. / 为保留升级兼容性，程序路径、包标识和登录数据保持不变，只改变对外名称与图标。

### Features / 功能

- Jellyfin server login and media-library navigation / 登录、浏览电影与电视剧
- Native Apple TV player with DirectPlay, DirectStream/remux and server transcoding / 原生播放及三种播放协商
- Playback controls, progress reporting and resume / 播放控制、进度上报、断点续播
- Audio track selection and server-rendered subtitles / 音轨切换与服务器字幕处理

The current client may require server video transcoding when subtitles are selected. See [playback architecture](docs/playback-architecture.md) and [subtitle architecture](docs/subtitle-architecture.md).

当前选择字幕时可能需要服务器烧录字幕，详见播放与字幕架构说明。

### Build / 编译

Requires macOS, Xcode Command Line Tools, a compatible Theos/iPhoneOS SDK and Python 3.

```sh
make shell
Scripts/package.sh build/iPhoneOS11.4.sdk-ios8.0/Jellyfin.frappliance build/package-local
JF_PACKAGE=build/package-local/org.jellyfin.atv3_0.5.85-brand1_iphoneos-arm.deb make test-offline test-asan
```

Use a fresh output directory for each `Scripts/package.sh` invocation. The project has no dependency on redistributing Apple system binaries or proprietary SDKs.

`Scripts/package.sh` 每次应指定不存在的新输出目录。不要将 Apple 系统二进制或专有 SDK 上传到公开仓库。

### Optional developer probes / 可选开发诊断

The legacy network/presentation probes are **disabled unless explicitly enabled**. They do not contain a personal LAN address. For those specialized experiments, the developer must provide the origin in the root-owned device file `/var/root/.jellyfin-atv3-probe-origin` (example format: `http://PROBE_SERVER_IP:18780`). The standalone synthetic server accepts `--bind`; it defaults to loopback. Normal Jellyfin playback does not use this setting.

开发诊断探针默认不启动；要运行专门的实验，需自行指定诊断服务器地址。普通播放不需要此配置。

### License and third-party rights / 许可证与第三方权利

The original RetroReel3 and Clock source code and project documentation authored by ABoringBlog are released under the [MIT License](LICENSE). Third-party assets, logos, trademarks, Apple system frameworks and the Jellyfin name or logo are not relicensed by this repository. This is an independent community client, not an official Jellyfin project. Check the rights to any included third-party graphics before reuse or redistribution.

ABoringBlog 原创的 RetroReel3、Clock 源码及项目文档采用 [MIT License](LICENSE)。MIT 授权不涵盖第三方素材、商标、Apple 系统框架及 Jellyfin 名称/标志。本项目为独立社区客户端，并非 Jellyfin 官方项目。复用或重新分发第三方图像前请确认授权。

### Project notes / 项目文档

The historical [PROGRESS.md](PROGRESS.md) and [docs](docs/) record development stages; older passages may describe pre-device prototypes and should not be interpreted as the current release status. See the [Releases](https://github.com/ABoringBlog/Apple-TV-A1469-/releases) page for published versions.

历史开发记录可能描述早期尚未真机验证的状态，请以最新 Release 为准。
