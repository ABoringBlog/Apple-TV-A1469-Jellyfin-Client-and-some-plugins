# ARMv7 链接诊断（2026-09-27）

只读检查本地 theos-sdks 和 Kodi-Helix：

- 9.3 的 usr/lib/libSystem.tbd 重导出 liblaunch.dylib，但 SDK 无对应 stub。不是项目直接调用 launch API。
- 10.3 的 libobjc.A.tbd 将 armv7/armv7s/arm64/i386/x86_64 放在同一导出组，缺 objc_msgSend_stret。JFClient 的 rangeOfCharacterFromSet: 返回 NSRange，在 ARMv7 上需要结构体返回消息入口，不能用普通 objc_msgSend 替代。
- 9.3、10.3 的混合设备/模拟器 v2 stubs 伴平台警告；11.4 v3 stubs 仅列设备架构，且为 armv7/armv7s 单独导出 stret。使用完整 11.4 SDK 重新编译、链接，未修改任何 SDK、未补造符号，警告和错误均消失。
- Kodi tools/darwin/Configurations/App-iOS.xcconfig 使用 armv7、iphoneos SDK、最低 4.2；App-ATV2.xcconfig 使用 undefined dynamic_lookup。这里仅沿用设备架构和 bundle 形式，不沿用放宽未定义符号的选项。本项目使用 clang 默认现代 iOS ObjC ABI、手动引用计数、最低 iOS 8.0。最低版本仍需目标固件验证。

命令：`make shell > logs/armv7-sdk11.4.log 2>&1`，退出 0。完整 4 个源文件重新编译，严格链接成功。对象按 SDK 名和最低版本隔离，原 build/armv7 仍保留。

这证明工具链能产出 ARMv7 bundle，不证明 8163 上的加载、系统符号、BackRow、TLS 或 UI 兼容性。
