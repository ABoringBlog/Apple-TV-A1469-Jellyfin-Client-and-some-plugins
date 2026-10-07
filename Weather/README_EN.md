# Weather for Apple TV 3

[← Bilingual README](README.md)

![Weather icon](Weather.frappliance/AppIcon.png)

A native Weather appliance for **jailbroken Apple TV 3 (A1469 / AppleTV3,2)**. Both **English** and **Chinese** packages are provided.

> **Important: the current Weather implementation is not standalone. Live weather depends on a Mac running `ATV3Bridge` continuously, 24/7. If the Mac is shut down, asleep, offline, or the bridge stops, the Apple TV cannot retrieve new live weather data. A previously cached snapshot may remain visible temporarily.**

## Architecture

`Apple TV 3 Weather → LAN HTTP → Mac ATV3Bridge → HTTPS → IP location / Open-Meteo`

- The Apple TV renders the native BackRow UI, icons, and local snapshot cache.
- ATV3Bridge on the Mac handles modern HTTPS, location discovery, and weather APIs.
- No API key is embedded or required.
- The bridge endpoint is user-configurable and is not hardcoded to the developer's LAN.

## Features

- Current temperature and condition
- Feels-like temperature, humidity, and wind
- Sunrise and sunset
- Hourly forecast
- 7-day forecast
- Day/night and weather-condition graphics
- Apple TV 3 home-screen Weather icon
- Asynchronous refresh and local caching
- Equivalent English and Chinese editions

## Verified status

- Target: Apple TV 3 A1469 / AppleTV3,2
- Apple TV Software 7.9 / build 12H1006
- The Chinese 1.0 development baseline matches the binary currently running on the physical device.
- A historical English 0.5.5 baseline was also physically verified and preserved.
- Those development binaries embedded a private Mac LAN address and are therefore **not published unchanged**.
- Public packages use `/var/root/.atv3-weather-bridge-url` and are rebuilt from the sanitized public source.

## Download

Release:

https://github.com/ABoringBlog/Apple-TV-A1469-Jellyfin-Client-and-some-plugins/releases/tag/weather-v1.0.0-public1

Choose one package:

- `org.atv3.weather_1.0.0-public1-en_iphoneos-arm.deb` — English
- `org.atv3.weather_1.0.0-public1-zh_iphoneos-arm.deb` — Chinese

Both use the same package ID (`org.atv3.weather`), so they are alternatives and cannot be installed side by side.

## 1. Run ATV3Bridge on the Mac

Python 3 is required. From `Weather/Bridge`:

```sh
cd Weather/Bridge
./install_launch_agent.sh
```

This installs a macOS LaunchAgent that starts the bridge at login and keeps it running.

Test it:

```sh
curl http://127.0.0.1:8099/health
curl http://127.0.0.1:8099/v1/weather
```

The example configuration uses automatic location discovery. The installer copies it to an untracked `weather_config.json`, which can be edited locally.

### Manual location

To disable automatic location discovery, use a configuration such as:

```json
{
  "auto_location": false,
  "location": "My City",
  "latitude": 0.0,
  "longitude": 0.0,
  "timezone": "UTC"
}
```

## 2. Configure the bridge URL on the Apple TV

Find the Mac's LAN IP address, then run on the ATV3:

```sh
echo 'http://MAC_LAN_IP:8099/v1/weather' > /var/root/.atv3-weather-bridge-url
```

Replace `MAC_LAN_IP` with the Mac's address. A DHCP reservation or static LAN address is recommended so this URL does not change.

## 3. Install Weather

Download the desired `.deb` and verify `SHA256SUMS`, then transfer and install it. English example:

```sh
scp org.atv3.weather_1.0.0-public1-en_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.atv3.weather_1.0.0-public1-en_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'
```

Use the `-zh` package name for Chinese.

## 24/7 Mac requirement

This is a core architectural requirement of the current release:

- The Mac must remain powered on.
- It must not stay asleep while Weather is expected to update.
- The Mac and ATV3 must be mutually reachable on the LAN.
- The `org.atv3.bridge.weather` LaunchAgent must remain running.
- The Mac needs internet access for fresh weather data.

ATV3Bridge is therefore not an optional helper in this release; it is part of the Weather runtime.

## Network and privacy notes

- The bridge listens on `0.0.0.0:8099` by default and has no authentication. Use it only on a trusted LAN and do not expose port 8099 to the public internet.
- With `auto_location: true`, ATV3Bridge requests `ipwho.is` to obtain an approximate network location.
- It sends latitude/longitude to Open-Meteo to retrieve forecasts.
- The repository does not publish the developer's private LAN IP, weather cache, personal location configuration, or API credentials.

## Build from source

English:

```sh
make -C Weather LANGUAGE=en BUILD=build/weather-en weather
Weather/Scripts/package.sh en Weather/build/weather-en/Weather.frappliance Weather/build/package-en
```

Chinese:

```sh
make -C Weather LANGUAGE=zh BUILD=build/weather-zh weather
Weather/Scripts/package.sh zh Weather/build/weather-zh/Weather.frappliance Weather/build/package-zh
```

Requires macOS, Xcode Command Line Tools, Python 3, and a compatible Theos/iPhoneOS SDK. Proprietary Apple SDKs are not included.

## License

Original Weather / ATV3Bridge source and project documentation are released under the repository's [MIT License](../LICENSE). This is an independent, unofficial project and is not affiliated with Apple.
