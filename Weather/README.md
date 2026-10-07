# Weather for Apple TV 3 / Apple TV 3 原生天气

[English-only README](README_EN.md)

![Weather icon](Weather.frappliance/AppIcon.png)

适用于已越狱 **Apple TV 3（A1469 / AppleTV3,2）** 的原生天气应用，提供 **中文** 和 **English** 两个安装包。

> **重要：当前 Weather 不是完全独立运行的应用。实时天气功能依赖一台 Mac 24 小时运行 `ATV3Bridge`。Mac 关机、休眠、断网或 Bridge 停止后，Apple TV 不能获取新的实时天气；已有缓存可能暂时继续显示。**

## 当前架构

`Apple TV 3 Weather → 局域网 HTTP → Mac ATV3Bridge → HTTPS → IP location / Open-Meteo`

- Apple TV 3 负责原生 BackRow UI、天气图标和缓存。
- Mac 上的 ATV3Bridge 负责现代 HTTPS、定位和天气 API。
- Weather 不包含 API Key，也不直接依赖 Jellyfin。
- Bridge URL 不再硬编码；每个用户需要在 ATV3 上写入自己的 Mac 地址。

## 功能

- 当前温度、天气状况、体感温度、湿度和风速
- 日出 / 日落
- 逐小时天气预报
- 7 天天气预报
- 白天 / 夜间及多种天气图标
- ATV3 首页 Weather 图标
- 异步更新与本地缓存
- 中文版和英文版功能一致

## 已验证状态

- 目标设备：Apple TV 3 A1469 / AppleTV3,2
- 系统：Apple TV Software 7.9 / build 12H1006
- 当前中文 1.0 真机基线与设备上正在运行的二进制完全一致。
- 历史 English 0.5.5 真机基线也已核对保存。
- 原始真机开发版本曾硬编码开发者私人 Mac IP，因此 **不会原样公开**。
- GitHub 公共版改为 `/var/root/.atv3-weather-bridge-url` 配置，并重新构建英文 / 中文安装包。

## 下载

Release：

https://github.com/ABoringBlog/Apple-TV-A1469-Jellyfin-Client-and-some-plugins/releases/tag/weather-v1.0.0-public1

请选择其中一个：

- `org.atv3.weather_1.0.0-public1-zh_iphoneos-arm.deb` — 中文
- `org.atv3.weather_1.0.0-public1-en_iphoneos-arm.deb` — English

两个版本包 ID 相同，**只能二选一安装**。安装另一个语言版本相当于替换当前 Weather。

## 1. 在 Mac 上安装 ATV3Bridge

Mac 需要安装 Python 3。进入仓库的 `Weather/Bridge`：

```sh
cd Weather/Bridge
./install_launch_agent.sh
```

脚本会创建一个 macOS LaunchAgent，让 Weather Bridge 登录后自动启动并保持运行。

测试：

```sh
curl http://127.0.0.1:8099/health
curl http://127.0.0.1:8099/v1/weather
```

默认 `weather_config.example.json` 使用自动定位。首次安装会复制为未纳入 Git 的 `weather_config.json`，可以自行修改。

### 手动位置配置

如果不想自动定位，把配置改成类似：

```json
{
  "auto_location": false,
  "location": "My City",
  "latitude": 0.0,
  "longitude": 0.0,
  "timezone": "UTC"
}
```

## 2. 告诉 Apple TV 你的 Mac Bridge 地址

先找到 Mac 在同一局域网中的 IP，然后在 ATV3 上执行：

```sh
echo 'http://MAC_LAN_IP:8099/v1/weather' > /var/root/.atv3-weather-bridge-url
```

把 `MAC_LAN_IP` 替换成你的 Mac 局域网地址。建议给 Mac 设置固定 DHCP 租约或固定局域网 IP，否则地址变化后 Weather 会失去 Bridge。

## 3. 安装 Weather

在电脑下载并校验 SHA256，然后：

```sh
scp org.atv3.weather_1.0.0-public1-zh_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.atv3.weather_1.0.0-public1-zh_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'
```

英文版只需把文件名换成 `...public1-en...deb`。

## Mac 24/7 依赖

当前版本的架构本身就要求 Bridge：

- Mac 必须处于开机状态。
- Mac 不能长期休眠。
- Mac 和 ATV3 必须能在局域网互相访问。
- `org.atv3.bridge.weather` LaunchAgent 必须正常运行。
- Mac 必须能访问互联网，才能更新实时天气。

如果 Bridge 停止，ATV3 不会获得新的天气数据。这不是可选辅助组件，而是当前 Weather 实现的一部分。

## 网络与隐私说明

- Bridge 默认监听 `0.0.0.0:8099`，没有身份验证；建议只在可信家庭局域网中使用，并不要把 8099 端口暴露到公网。
- `auto_location: true` 时，Bridge 会请求 `ipwho.is` 获取粗略网络位置。
- Bridge 会向 Open-Meteo 发送经纬度以取得天气数据。
- 本仓库不包含开发者的私人 IP、缓存天气数据、个人位置配置或 API 密钥。

## 从源码构建

在仓库根目录执行中文：

```sh
make -C Weather LANGUAGE=zh BUILD=build/weather-zh weather
Weather/Scripts/package.sh zh Weather/build/weather-zh/Weather.frappliance Weather/build/package-zh
```

英文：

```sh
make -C Weather LANGUAGE=en BUILD=build/weather-en weather
Weather/Scripts/package.sh en Weather/build/weather-en/Weather.frappliance Weather/build/package-en
```

需要 macOS、Xcode Command Line Tools、Python 3 和兼容的 Theos/iPhoneOS SDK。Apple 专有 SDK 不包含在仓库中。

## License

原创 Weather / ATV3Bridge 代码及文档采用仓库根目录的 [MIT License](../LICENSE)。本项目不是 Apple 官方项目。
