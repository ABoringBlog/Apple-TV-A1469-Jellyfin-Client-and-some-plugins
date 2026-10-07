# Clock for Apple TV 3

[← Bilingual Clock README](README.md) · [Project English README](../README_EN.md)

![Clock appliance icon](Clock.frappliance/AppIcon.png)

An independently installable native clock appliance for a **jailbroken Apple TV 3 (A1469 / AppleTV3,2)**.

It targets Apple TV Software **7.9 / build 12H1006** and uses the legacy BackRow runtime. It is not an AirPlay app, web wrapper, or tvOS application.

## Features

- Displays local time with seconds
- Displays a formatted local date
- Native clock screen rendered on the Apple TV
- Automatic refresh while the clock is active
- Integration with the legacy Apple TV 3 home menu
- Experimental home-icon refresh support
- No Jellyfin server required
- No online account required
- No API key required

## Compatibility and verification

Target environment:

- Apple TV 3 A1469
- AppleTV3,2
- Apple TV Software 7.9
- Build 12H1006

The original Mac build of Clock **0.1.5** was compared with the executable installed on the physical Apple TV 3, and the executable matched exactly by MD5.

The public source snapshot also matches the source used for that build.

The separately generated public package passed:

- ARMv7 architecture checks
- Bundle metadata checks
- Ad-hoc signature validation
- Strict package payload validation
- Symlink validation
- Two independent reproducible builds

The managed .deb itself has **not yet been separately installed and accepted on the physical device**. The currently running device copy was deployed manually during development.

## Download

Download Clock v0.1.5 and SHA256SUMS here:

**[Clock v0.1.5 Release](https://github.com/ABoringBlog/Apple-TV-A1469-/releases/tag/clock-v0.1.5)**

Clock is independent from RetroReel3. Do not use the RetroReel3 package to install Clock.

Package ID:

    org.atv3.clock

## Installation

Requirements:

- Jailbroken Apple TV 3
- Root SSH access
- dpkg
- Mac or Linux computer

Download the package to your computer, verify the SHA256 checksum, then transfer it:

    scp org.atv3.clock_0.1.5_iphoneos-arm.deb root@APPLE_TV_IP:/var/root/
    ssh root@APPLE_TV_IP 'dpkg -i /var/root/org.atv3.clock_0.1.5_iphoneos-arm.deb && launchctl stop com.apple.frontrow && launchctl start com.apple.frontrow'

Replace APPLE_TV_IP with your Apple TV's local IP address.

### Important for existing manual installations

If Clock was previously installed manually, back up:

    /Applications/Clock.frappliance
    /Applications/AppleTV.app/Appliances/Clock.frappliance

before installing the managed .deb.

An in-place migration from a manually deployed Clock appliance to the public .deb has not yet been validated.

## Build from source

Requires:

- macOS
- Xcode Command Line Tools
- Python 3
- Compatible Theos/iPhoneOS SDK

The SDK is not distributed in this repository.

Run from the repository root:

    make -C Clock BUILD=build/clock-public clock
    Clock/Scripts/package.sh Clock/build/clock-public/Clock.frappliance Clock/build/package-public

Output:

    Clock/build/package-public/org.atv3.clock_0.1.5_iphoneos-arm.deb

If your SDK is stored elsewhere, override the default path:

    make -C Clock IOS_SDK=/path/to/your/sdk BUILD=build/clock-public clock

The package script works entirely offline, uses ad-hoc signing, and refuses to overwrite an existing output directory.

## Project layout

    Clock/
    ├── Clock.frappliance/       Application plist, localized name, and shipped icons
    ├── Packaging/               Debian package metadata
    ├── Scripts/                 Offline packaging tools
    ├── Sources/Clock/           Native ARMv7 BackRow source
    ├── Tests/                   Package validation
    └── Makefile                 Independent Clock build

## Independence

Clock is a standalone application.

It does not require or modify RetroReel3, Jellyfin Server, RetroReel3 login data, or RetroReel3 package files.

RetroReel3 package ID:

    org.jellyfin.atv3

Clock package ID:

    org.atv3.clock

They can coexist on the same Apple TV 3.

## License

Original Clock source code and project documentation authored by **ABoringBlog** are released under the repository's [MIT License](../LICENSE).

No Apple system binary, firmware, proprietary framework, or proprietary SDK is distributed in this repository.

This is an independent, unofficial project and is not affiliated with or endorsed by Apple.

## Sponsorship

Clock is free and open source. Sponsorship is entirely optional and does not unlock paid features or guaranteed development work.

[Support ABoringBlog on GitHub Sponsors](https://github.com/sponsors/ABoringBlog)
