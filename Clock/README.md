# Clock for Apple TV 3 / Apple TV 3 原生时钟

[English-only README](README_EN.md)

![Clock appliance icon](Clock.frappliance/AppIcon.png)

An independently installable native clock appliance for a **jailbroken Apple TV 3 (A1469 / AppleTV3,2)**. Built for Apple TV Software **7.9 / 12H1006** with BackRow, not AirPlay, a webpage or tvOS.

适用于已越狱的 **Apple TV 3（A1469 / AppleTV3,2）** 的独立原生时钟。使用 BackRow 原生界面，不是 AirPlay、网页或 tvOS 移植。

## What it does / 功能

- Shows local time with seconds and a formatted date / 显示本地时间、秒数及日期
- Renders the clock view and refreshes while active / 原生时钟画面与刷新
- Integrates with the ATV3 home menu; contains experimental home-icon refresh support / 主菜单集成及首页图标刷新实验
- Requires no Jellyfin server, online account or API key / 不需要 Jellyfin、外部账户或 API 密钥

**Compatibility:** The original Mac executable and artwork matched the Clock **0.1.5** appliance observed on the physical A1469. The new public package passed offline checks, but installing this separately packaged **.deb** has not yet been tested on the device.

**兼容性：** Mac 原始构建文件与 A1469 上安装的 Clock 0.1.5 一致。公开安装包通过离线检查，但新 **.deb** 尚未单独在真机安装。

## Download / 下载

The independent Clock v0.1.5 installer and SHA256SUMS are available at:

https://github.com/ABoringBlog/Apple-TV-A1469-/releases/tag/clock-v0.1.5

Do not use the RetroReel3 package to install Clock. The two projects have separate package IDs.

## Installation / 安装

Requires jailbreak, root SSH access and dpkg. Download the Clock .deb on a modern Mac or Linux PC, verify its checksum, and transfer it:

    scp org.atv3.clock_0.1.5_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
    ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.atv3.clock_0.1.5_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'

Replace APPLE_TV_IP with the device's LAN IP. If Clock was deployed manually before, **back up the existing /Applications/Clock.frappliance and its symlink first**; the managed .deb upgrade over a manually deployed app has not yet been validated.

请把 APPLE_TV_IP 换成自己的设备 IP。若此前手动部署 Clock，请在使用 .deb 安装前备份原应用和主菜单软链接；目前尚未验证手动安装原位转托管安装包的流程。

## Build from source / 源码编译

Requires macOS, Xcode Command Line Tools, Python 3, and a compatible Theos/iPhoneOS SDK (not distributed here). Run from the **repository root**:

    make -C Clock BUILD=build/clock-public clock
    Clock/Scripts/package.sh Clock/build/clock-public/Clock.frappliance Clock/build/package-public

Output: Clock/build/package-public/org.atv3.clock_0.1.5_iphoneos-arm.deb

Override the default SDK path with IOS_SDK=/your/sdk/path if needed. The packager is offline, signs ad-hoc, and refuses to overwrite an existing output directory.

## Layout / 目录

- Sources/Clock/: ARMv7 BackRow source
- Clock.frappliance/: plist, localized display name, shipped icons
- Makefile: independent ARMv7 build
- Packaging/control and Scripts/package.sh: Debian package generation
- Tests/verify_package.py: offline payload and metadata validation

## License and independence / 许可及独立性

Original Clock source code is available under the [repository MIT License](../LICENSE). No Apple system binaries, firmware, proprietary frameworks or SDKs are distributed. Third-party rights are not relicensed. This is an independent, unofficial project not endorsed by Apple.

Clock 原创源码遵循根目录 MIT 许可证。仓库不分发 Apple 系统二进制、固件或私有 SDK。本项目与 Apple 无隶属或官方合作关系。
