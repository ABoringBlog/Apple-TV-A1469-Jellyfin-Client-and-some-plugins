# Phone Remote & Text Input for Apple TV 3

[English-only README](README_EN.md)

这是 Apple TV 3 Modernization 项目的**手机遥控器 + 手机文字输入**模块。

目标是让 iPhone 自带的 **控制中心 → Apple TV Remote** 直接控制已越狱 Apple TV 3，而不需要安装第三方 iPhone App。

## 当前状态

**v1.0 / public1：真机功能已验证。**

已在 Apple TV 3 A1469 / AppleTV3,2 / 7.9 / 12H1006 上实际验证：

- iPhone 控制中心 Apple TV Remote 成功完成 authenticated pair verification
- Select 按下/松开能够到达 ATV3
- 上下左右方向键能够到达 ATV3
- Menu 能够到达 ATV3
- Play 键短按 / 长按映射到下一首 / 上一首链路
- ATV3 injector 在 AppleTV 进程内运行并监听 `127.0.0.1:49154`
- BackRow IR-equivalent 事件能够真实进入 ATV3
- `BRTextEntryController` focus hook 真机触发
- iPhone 输入文字产生真实 `TEXT_UPDATED`
- iPhone 提交文字产生真实 `TEXT_SUBMITTED`

因此**手机遥控和手机输入都不是模拟功能，已经有真机事件证据**。

完整验证边界见 [VERIFICATION.md](VERIFICATION.md)。

## 下载 / Release

当前公开版本：`phone-remote-input-v1.0.0-public1`

https://github.com/ABoringBlog/Apple-TV-A1469-Jellyfin-Client-and-some-plugins/releases/tag/phone-remote-input-v1.0.0-public1

Release 资产包括：

- `org.atv3.remoteinjector_1.0.0-public1_armv7.dylib` — 已清理固定 token 的公开 ARMv7 injector
- `ATV3-PhoneRemoteInput-v1.0.0-public1-source.tar.gz` — 本模块公开源码
- `atvr4samsung-atv3.patch` — 固定 upstream commit 上的 ATV3 专用补丁
- `SHA256SUMS`

建议优先按下面的脚本从源码部署；预编译 dylib 主要用于校验和高级手动安装。

## 架构

手机遥控：

`iPhone Control Center Remote → Companion Link → Mac Bridge → IR-equivalent injector / DMAP → Apple TV 3`

手机文字输入：

`iPhone Remote keyboard / RTI → Mac Bridge → SSH loopback tunnel → ATV3 injector → BRTextEntryController`

主要端口：

- `49152`：Mac 上的 Companion Link 服务，供 iPhone 连接
- `49154`：ATV3 本机 loopback injector，仅通过 SSH tunnel 从 Mac 访问
- `49156`：Mac 本机 focus 协调端口，仅监听 `127.0.0.1`

## 安全设计

公开版不会保存或分发开发机上的真实配对状态。

以下内容都放在用户自己的私有状态目录：

`~/.config/atv3-phone-remote/`

包括：

- iPhone Companion 配对身份
- paired clients
- DMAP credential
- injector token
- pairing GUID
- 运行日志

公开版 injector 也不再把 token 写死进源码。安装时随机生成 token，并在 ATV3 保存到：

`/var/mobile/Library/Preferences/org.atv3.remoteinput.token`

ATV3 injector 本身只监听 `127.0.0.1:49154`，不会直接开放到局域网。

## 第三方基础

iPhone Companion Link 服务基于 MIT 开源项目 `atvr4samsung`，固定到 upstream commit：

`7673178729a12b20c7d7a0bc968fc1786cbf2567`

本仓库**不复制整个 upstream Git 仓库**。安装脚本会 clone 固定 commit，然后应用：

`Patches/atvr4samsung-atv3.patch`

该 patch 包含本项目需要的 ATV3 改动，包括：Select press/release、方向 hold、Play 短/长按、Next/Previous、中文/日文 IME 的 `textToCommit`。

Mac → ATV3 的 legacy DMAP 使用 `pyatv==0.18.0`。

详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 安装顺序

### 1. 准备 Mac

Mac 和 Apple TV 3 必须在同一个可信局域网，并且 Mac 能 SSH 登录 ATV3。

建议先配置 SSH key，因为持久化 tunnel 使用 `BatchMode=yes`。

运行：

```sh
cd PhoneRemoteInput
./Scripts/setup_mac.sh MAC_LAN_IP APPLE_TV_IP
```

这一步会：

- clone 固定版本 atvr4samsung
- 应用 ATV3 patch
- 创建 Python venv
- 安装 pyatv 和 upstream 依赖
- 创建私有 state/token
- 安装 Mac Companion Bridge launchd
- 安装 Mac → ATV3 SSH loopback tunnel launchd

### 2. 部署 ATV3 injector

需要一个可用于 armv7/iOS 8 的 iPhoneOS SDK：

```sh
export IOS_SDK='/path/to/iPhoneOS.sdk'
./Scripts/deploy_injector.sh APPLE_TV_IP
```

脚本会先备份现有 injector，再部署：

`/Library/MobileSubstrate/DynamicLibraries/org.atv3.remoteinjector.dylib`

以及对应 filter plist 和私有 token。

### 3. 配对 Mac → ATV3 DMAP

```sh
export ATV3_PHONE_BIND='MAC_LAN_IP'
export ATV3_PHONE_ATV='APPLE_TV_IP'
export ATV3_PHONE_STATE_DIR="$HOME/.config/atv3-phone-remote"
.venv/bin/python Bridge/dmap_pair_atv3.py
```

按照终端提示，在 ATV3 的 Remote App 配对界面完成配对。

### 4. 配对 iPhone → Mac Companion

```sh
export ATV3_PHONE_STATE_DIR="$HOME/.config/atv3-phone-remote"
.venv/bin/python Bridge/native_remote_pair.py open
```

然后在 iPhone：

`控制中心 → Apple TV Remote → ATV3 Bridge`

输入终端显示的临时 PIN。

## 与 CloudTune 的手机搜索输入

CloudTune 1.1 public2 使用真正的 `BRTextEntryController` 搜索界面。

当搜索编辑器获得 focus 时，本模块会把 iPhone Remote 键盘输入发送到 ATV3；中文 IME 提交使用 `textToCommit`，真机已经观察到 `TEXT_UPDATED` 和 `TEXT_SUBMITTED`。

## 公共版验证边界

当前真机运行的是功能上对应的最终开发版 injector/Bridge，并已完成真实遥控和文字输入验证。

为了避免把真实 token 上传 GitHub，public1 改成了**运行时私有 token 文件**。这个公开安全版已经成功编译成 ARMv7 dylib，但这个经过安全改造的 public injector 还没有单独重新安装到真机做一次 acceptance test。

也就是说：**功能架构已真机验证；公开版 token-hardening 部署流程是新整理的。**

## License

本项目自写的 Bridge glue、ATV3 injector、部署脚本和文档按仓库根目录 MIT License 发布。
