# CloudTune / 云律音乐 for Apple TV 3

[English-only README](README_EN.md)

![CloudTune icon](CloudTune.frappliance/AppIcon.png)

**CloudTune / 云律音乐 v1.1 public2** 是一个面向已越狱 **Apple TV 3（A1469 / AppleTV3,2）** 的独立原生音乐客户端。

> **public1 是第一版；当前 public2 是功能更新。v2 的主要目标仍然是重新设计 / 更新 UI。**

> **品牌说明：**「CloudTune / 云律音乐」这个名字，以及公开版使用的云朵 + 音符 + 声波图标，都是用户明确要求 **ChatGPT 临时创作 / 虚构** 的独立品牌，用来替代开发阶段使用的网易云官方名称和官方图标，减少直接复制官方品牌资产带来的版权、商标和用户混淆风险。它们不是网易云音乐官方名称、Logo 或素材，本项目与网易没有隶属、授权或官方合作关系。这个做法只能降低品牌混淆风险，并不保证项目不存在其他 API、服务条款或法律风险。

## v1.1 public2 当前功能

- Apple TV 3 原生 BackRow UI
- 二维码登录
- 我的歌单与歌单歌曲
- 推荐音乐
- 最近播放
- 歌词与翻译歌词
- 封面显示
- 播放 / 暂停
- 列表循环、单曲循环、随机播放
- 播放队列
- 喜欢 / 取消喜欢
- 播放地址预取与本地元数据缓存
- 中文版与 English 版
- 真正的 BackRow `BRTextEntryController` 搜索界面
- iPhone Control Center Remote 键盘输入集成
- 搜索结果直接播放
- 原生 BackRow 播放进度覆盖层
- 手动上一首 / 下一首与单曲循环逻辑修正
- 封面请求统一为约 400×400，降低桥接和解码负担

手机键盘和系统级手机遥控由独立的 [Phone Remote & Text Input](../PhoneRemoteInput/) 模块提供。该模块的遥控事件、文字更新和文字提交均已有 ATV3 真机日志验证。

## 版本状态 / 下一版计划

`cloudtune-v1.0.0-public1` 是第一版。当前 `1.1.0-public2` 在保持原有功能的基础上加入手机输入搜索、搜索结果播放、遥控事件修复、原生进度条和封面请求优化。

**v2 的首要目标仍然是重做并更新 UI。** 功能逻辑会继续保留，但视觉结构、布局、操作反馈和整体 Apple TV 使用体验会作为下一阶段重点。

## 架构与 Mac Bridge 要求

> **CloudTune 当前必须依赖一台 Mac 持续运行 CloudTune Bridge。**

架构：

**Apple TV 3 CloudTune → 局域网 HTTP → Mac CloudTune Bridge → 本机兼容 API 服务 → 第三方音乐服务**

默认：

- CloudTune Bridge：`8101`
- 外部兼容 API：`127.0.0.1:18300`

CloudTune Bridge 负责二维码登录、本地保存用户自己的登录 session、歌单 / 歌曲 / 推荐 / 最近播放、歌词、喜欢状态、封面代理，以及获取经过账号授权的播放 URL。

取得播放 URL 后，ATV3 的 AVPlayer 直接播放该 URL。**如果上游服务没有向该账号授权播放地址，Bridge 会返回不可播放，不会绕过该限制。**

Mac 关机、休眠、断网、CloudTune Bridge 停止，或外部兼容 API 停止后，CloudTune 的新数据请求和新播放请求都会失败。

## 外部 API 依赖

本仓库**不包含也不重新分发** NeteaseCloudMusicApi 源码或旧 `.tgz` 包。

开发阶段测试过 Binaryify 的 **NeteaseCloudMusicApi 4.32.0**。它是 MIT License，但上游后来停止活跃维护。公开仓库仅提供 CloudTune 客户端和 Bridge。

完整 attribution 见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。用户需要自行提供一个兼容的本地 API 服务，默认运行在：

```text
http://127.0.0.1:18300
```

也可以在安装 Bridge 前指定：

```sh
export CLOUDTUNE_UPSTREAM='http://127.0.0.1:18300'
```

## 下载

Release：

https://github.com/ABoringBlog/Apple-TV-A1469-Jellyfin-Client-and-some-plugins/releases/tag/cloudtune-v1.1.0-public2

请选择一个：

- `org.atv3.cloudtune_1.1.0-public2-zh_iphoneos-arm.deb` — 中文
- `org.atv3.cloudtune_1.1.0-public2-en_iphoneos-arm.deb` — English

两个版本包 ID 都是 `org.atv3.cloudtune`，所以只能二选一安装。

公开版和开发阶段的 `org.atv3.neteasemusic` 使用不同 bundle/package ID、merchant identifier 和 runtime class name，不会直接覆盖开发版。

## 1. 在 Mac 上启动兼容 API

先确保你自己的兼容 API 服务可以在 Mac 本机访问，例如：

```sh
curl http://127.0.0.1:18300
```

CloudTune 不负责安装或分发该第三方服务。

## 2. 安装 CloudTune Bridge

需要 Python 3。

```sh
cd CloudTune/Bridge
./install_launch_agent.sh
```

它会创建 macOS LaunchAgent：`org.atv3.bridge.cloudtune`。

检查 Bridge：

```sh
curl http://127.0.0.1:8101/health
```

## 3. 配置 ATV3 的 Bridge 地址

找到 Mac 的局域网 IP，然后在 ATV3 写入：

```sh
echo 'http://MAC_LAN_IP:8101' > /var/root/.atv3-cloudtune-bridge-url
```

建议给 Mac 设置 DHCP Reservation / 固定局域网 IP。

## 4. 安装 CloudTune

中文示例：

```sh
scp org.atv3.cloudtune_1.1.0-public2-zh_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.atv3.cloudtune_1.1.0-public2-zh_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'
```

English 版把文件名换成 `...public2-en...deb`。

## iPhone 手机遥控和文字输入

CloudTune 1.1 的搜索页使用真实 `BRTextEntryController`。如需直接使用 iPhone 自带控制中心 Apple TV Remote 进行导航和键盘输入，请安装独立的 [Phone Remote & Text Input](../PhoneRemoteInput/) 模块。

真机已经观察到 `TEXT_ENTRY_PUSH`、`TEXT_UPDATED` 和 `TEXT_SUBMITTED`，并验证 Select、Menu、方向键以及媒体上一首 / 下一首转发。

该模块和 CloudTune Bridge 是**两个不同组件**：CloudTune Bridge 负责音乐账号 / 数据 / 播放 URL；Phone Remote & Text Input 负责 iPhone 遥控和文字输入。

## 登录与隐私

二维码授权成功后，Bridge 会将用户自己的登录 session 保存到：

```text
~/.config/cloudtune-atv3/session.json
```

目录权限为私有，session 文件按 `0600` 保存。该文件不在 Git 仓库中、不会进入 `.deb`、不会上传 GitHub，也不应该手工分享。

CloudTune Bridge 默认监听 `0.0.0.0:8101` 且没有自己的 LAN 身份认证，因此：**只建议在可信家庭局域网使用，不要把 8101 端口暴露到公网。**

## 真机与公开包验证

这次更新后的最终开发基线已经直接在 ATV3 上运行。重新构建前，Mac 最新开发二进制与真机文件 MD5 完全一致：

```text
8fc370961fedbf8959c358c5b64c78ae
```

之后重新执行原始 Makefile 会生成未签名文件，因此 MD5/文件大小变化；但新构建与真机文件的 Mach-O `LC_UUID` 仍完全一致。真机文件是 ad-hoc 签名版本。

公开版进行了重新品牌化和隐私清理，因此不是原开发二进制的直接复制。

公开中文 / English `.deb`：ARMv7 构建通过、ad-hoc 签名验证通过、严格包结构检查通过、私人 IP / 本机路径扫描通过，并连续两次独立构建 byte-for-byte 一致。

**1.1 public2 的重新品牌化 / 清理后 `.deb` 尚未单独在真机安装验收。** 最新开发基线和手机输入链路已在真机验证，public2 包本身完成的是独立构建、签名与离线验证。

## 从源码构建

中文：

```sh
make -C CloudTune LANGUAGE=zh BUILD=build/cloudtune-zh cloudtune
CloudTune/Scripts/package.sh zh CloudTune/build/cloudtune-zh/CloudTune.frappliance CloudTune/build/package-zh
```

English：

```sh
make -C CloudTune LANGUAGE=en BUILD=build/cloudtune-en cloudtune
CloudTune/Scripts/package.sh en CloudTune/build/cloudtune-en/CloudTune.frappliance CloudTune/build/package-en
```

需要 macOS、Xcode Command Line Tools 和兼容的 Theos/iPhoneOS SDK。Apple 专有 SDK 不包含在仓库中。

## Branding / 品牌来源

详见 [BRANDING.md](BRANDING.md)。公开名称和图标是用户让 ChatGPT 为这个开源发布版临时创作的独立身份，**不是官方网易云音乐品牌素材**。

## License

CloudTune 自己的客户端源码、Bridge glue code、构建脚本和项目文档按仓库根目录 [MIT License](../LICENSE) 发布。

第三方 API、第三方音乐服务、账号系统、歌曲、歌词、封面和音频流不属于本仓库。
