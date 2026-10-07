# Internet Radio for Apple TV 3 / Apple TV 3 网络电台

[English-only README](README_EN.md)

![Internet Radio icon](Radio.frappliance/AppIcon.png)

适用于已越狱 **Apple TV 3（A1469 / AppleTV3,2）** 的原生 Internet Radio / 网络电台应用。发布包提供 **中文** 与 **English** 两个版本。

> **重要：当前 Radio 依赖一台 Mac 持续运行 ATV3Bridge Radio。Mac 关机、休眠、断网或 bridge 停止后，Radio 无法正常加载电台目录、搜索、收藏和最近播放等数据。已经开始播放的电台流可能暂时继续，因为选中电台后 ATV3 会直接连接该电台的音频流。**

## 当前架构

**Apple TV 3 Radio → 局域网 HTTP → Mac ATV3Bridge Radio → HTTPS → Radio Browser**

选择电台后：

**Apple TV 3 AVPlayer → 电台自己的 HTTP/HTTPS 音频流**

因此 ATV3Bridge 是当前版本正常浏览和选择电台所必需的运行组件，但它不代理最终音频数据。

## 功能

- 全球网络电台目录
- 按国家 / 地区浏览
- 按类型 / 标签浏览
- A-Z 电台名称搜索
- 收藏
- 最近播放
- 电台播放、暂停 / 恢复
- 播放失败自动重试
- 中文与英文 UI
- Mac bridge 持久保存收藏和最近播放状态

## 已验证状态

目标环境：

- Apple TV 3 A1469
- AppleTV3,2
- Apple TV Software 7.9 / build 12H1006
- iOS 8.4.4 基础系统

当前 ATV3 上手工部署的中文 **Radio 0.3.1** 与 Mac 最新开发构建的可执行文件 MD5 完全一致：

`bbcd705fbfbb497be4e304ce62044ebf`

开发版曾硬编码开发者 Mac 的私人局域网地址，因此不会原样公开。GitHub 公共版改成读取：

`/var/root/.atv3-radio-bridge-url`

公开的中文 / 英文 `.deb` 由清理后的同一套最终源码构建，并经过离线包结构、ARMv7、签名、隐私和可重复构建检查。**这两个公共 .deb 本身尚未在真机重新安装验收。**

## 下载

Release：

https://github.com/ABoringBlog/Apple-TV-A1469-Jellyfin-Client-and-some-plugins/releases/tag/radio-v0.3.1-public1

请选择一个版本：

- `org.atv3.internetradio_0.3.1-public1-zh_iphoneos-arm.deb` — 中文
- `org.atv3.internetradio_0.3.1-public1-en_iphoneos-arm.deb` — English

两个版本使用相同的包 ID `org.atv3.internetradio`，**只能二选一安装**。

## 1. 在 Mac 上运行 ATV3Bridge Radio

需要 macOS 和 Python 3。

在仓库根目录：

```sh
cd Radio/Bridge
./install_launch_agent.sh
```

脚本会创建 `org.atv3.bridge.radio` LaunchAgent，让 Radio bridge 登录后自动启动并保持运行。

检查：

```sh
curl http://127.0.0.1:8100/health
```

正常时应返回 `ATV3Bridge Internet Radio` 的健康状态。

### Mac 必须持续在线

当前版本中，Mac bridge **不是可选组件**：

- Mac 必须保持开机。
- Mac 不能长期休眠。
- Mac 与 ATV3 必须可以在同一局域网互相访问。
- `org.atv3.bridge.radio` 必须持续运行。
- Mac 需要联网才能从 Radio Browser 获取新目录数据。

如果 bridge 离线，已经开始播放的流可能继续，但新的目录、搜索、收藏与最近播放请求会失败。

## 2. 在 ATV3 配置 Bridge 地址

找到 Mac 的局域网 IP，然后在 ATV3 执行：

```sh
echo 'http://MAC_LAN_IP:8100' > /var/root/.atv3-radio-bridge-url
```

把 `MAC_LAN_IP` 换成你的 Mac 地址。建议在路由器中给 Mac 设置 DHCP Reservation / 固定局域网 IP。

## 3. 安装 Radio

中文示例：

```sh
scp org.atv3.internetradio_0.3.1-public1-zh_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.atv3.internetradio_0.3.1-public1-zh_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'
```

英文版把文件名换成 `...public1-en...deb`。

如果此前是手工部署的 Radio，请先备份：

```text
/Applications/Radio.frappliance
/Applications/AppleTV.app/Appliances/Radio.frappliance
```

公共 `.deb` 覆盖手工部署版本的迁移流程尚未单独进行真机验收。

## Bridge、网络与隐私

- Radio bridge 默认监听 `0.0.0.0:8100`，目前没有身份验证。
- **只建议在可信家庭局域网中使用，不要把 8100 暴露到公网。**
- bridge 会访问 Radio Browser 的公开目录 API。
- 选中电台后，ATV3 会直接访问第三方电台提供的音频 URL。
- 收藏和最近播放保存在 Mac 上的 `Radio/Bridge/radio_state.json`；该文件被 Git 忽略，不会上传。
- 仓库不包含开发者私人 IP、收藏历史、最近播放记录、账号密码或 API Key。

## 从源码构建

中文：

```sh
make -C Radio LANGUAGE=zh BUILD=build/radio-zh radio
Radio/Scripts/package.sh zh Radio/build/radio-zh/Radio.frappliance Radio/build/package-zh
```

English：

```sh
make -C Radio LANGUAGE=en BUILD=build/radio-en radio
Radio/Scripts/package.sh en Radio/build/radio-en/Radio.frappliance Radio/build/package-en
```

需要 macOS、Xcode Command Line Tools 和兼容的 Theos/iPhoneOS SDK。Apple 专有 SDK 不包含在仓库中。

## License

原创 Radio / ATV3Bridge Radio 源码与项目文档采用仓库根目录的 [MIT License](../LICENSE)。

Radio Browser、电台名称、图标、音频流及其他第三方内容仍归各自所有者所有。本项目不是 Apple 官方项目。
