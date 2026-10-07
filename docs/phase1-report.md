# 第一阶段实际结果

日期：2026-09-27。所有写入限定当前仓库，保留原有 armv7_test* 文件。没有越狱、部署、设备连接、固件修改、系统修改或签名动作。

## 创建文件

- `.gitignore`：排除 build 和 Python 缓存。
- `Makefile`：Mac 测试、真实 HTTP 测试、ARMv7 编译及 bundle 链接目标。
- `Jellyfin.frappliance/Info.plist`：bundle 元数据和动态 principal class 名称。
- `Sources/JFAppliance.m`：constructor 入口和真实 bundle anchor 类。
- `Sources/BackRow/JFBackRow.h`、`.m`：独立适配层、运行时子类注册、方法 ABI 检查、事件读取和 Menu 栈返回。
- `Sources/Input/JFRemote.h`、`.m`：按下、释放、重复、长按状态解析。
- `Sources/API/JFClient.h`、`.m`：连接探测、认证、获取媒体库、内存会话和错误处理。
- `Tests/main.m`：断言测试及明确命名的 BackRow doubles。
- `Tests/JFFixtureProtocol.m`：通过实际 NSURLConnection 的 NSURLProtocol 测试替身。
- `Tests/run.py`：临时端口 loopback HTTP 服务，测试完成后关闭。
- `README.md`、`docs/references.md`、本报告。
- `logs/mac-tests.log`、`logs/http-test-blocked.log`、`logs/armv7-build.log`、`logs/armv7-link-sdk10.3.log`：原始测试与编译诊断。

## 验证结果

- Mac clang 14.0.0，ld 820.1；所有 Objective-C 源和测试编译成功，无编译警告。
- `make test`：69 个断言通过。覆盖无 BackRow 时安全退出、使用测试类注册、重复注册、Menu press 返回且 release 不重复返回、未知/错误事件回退、六个按键、释放与长按、URL/设备 ID 校验、Unicode 和引号密码序列化、认证令牌传递、401 清除会话、坏 JSON、错误顶层类型、500、断连、重定向拒绝、空媒体库和损坏的条目。
- `make test-http` 所使用的 HTTP runner 在首次执行时遭沙箱 `bind` 拒绝：`PermissionError: [Errno 1] Operation not permitted`。真实 socket 测试未通过/未执行到客户端；不能用 NSURLProtocol 结果代替真实网络、TLS 或服务器兼容性验证。普通 Mac 终端可运行该目标。
- `plutil -lint Jellyfin.frappliance/Info.plist` 通过。
- 4 个源文件编译为 Mach-O arm_v7 对象成功，位于 build/armv7。没有可运行的 ARMv7 bundle。

## 编译阻断与诊断

第一次 `make shell` 使用 iPhoneOS9.3.sdk：所有源文件编译成功，链接器报告多条 `.tbd ... built for iOS Simulator` 警告，最终缺失 `/usr/lib/system/liblaunch.dylib for architecture armv7`。本地 SDK 中也不存在对应 liblaunch.tbd。

第二次只用 iPhoneOS10.3.sdk 对同一批对象进行替代链接诊断：仍有平台标记警告，最终 `_objc_msgSend_stret` 未定义（来自 JFClient 中返回 NSRange 的消息调用）。没有通过删除正确调用或伪造符号来掩盖 ABI 问题。完整原始诊断见两个 armv7 日志。需要完整且平台标记正确、包含 ARMv7 Objective-C runtime 导出符号的匹配 SDK/link stubs；不是缺少一个随便实现的函数。

没有依赖 BackRow.framework、Substrate 或 Theos 可执行工具。设备上的 BackRow 类、实际 Beigelist 加载行为、签名要求仍属于运行环境依赖。

## 未解决兼容性与边界

1. A1469 / 7.9（8163）尚无真机验证。仅根据旧 Kodi 的接口名称探测，不声明私有类头文件；参数数目、返回和参数编码不匹配时拒绝注册或回退。类别工厂只接受实际运行时报告的整数类型。
2. constructor 只尝试一次自动注册；公开的 JFRegisterBackRowClasses 可重试，但尚无已证实的 Beigelist 延迟加载回调。若加载时 BRBaseAppliance/BRController 尚不存在，不会显示 appliance。不能假设 Beigelist 一定按所需顺序加载。
3. 继承 BRBaseAppliance 原始初始化和 applianceInfo 行为；没有移植 Kodi 的旧版 applianceInfo hack、UIKit workaround 或全局 popup hook。是否需要 BRApplianceInfo 子类、topShelfController、菜单图标和 first-responder 设置，均等待 8163 的运行时采样，当前未实现。这可能阻止菜单显示或事件投递。
4. 遥控器编号、originator=1、value=0/1 源于旧 Kodi，7.9 的重复节奏、长按 Menu 系统行为及中心键编号待验证。方向长按识别依赖重复事件。Mac doubles 只能验证本项目逻辑。
5. UI 目前是 BRController 外壳和事件通知；未实现服务器输入、登录页面、焦点列表、媒体浏览画面或播放。API 已独立完成，但尚未与设备 UI 工作流连接。
6. MinimumOSVersion / 编译最低版本 8.0 为可配置假设，需核对 8163 的 Foundation/Objective-C runtime ABI。旧设备 TLS/根证书能否连接目标 Jellyfin 服务器、API 版本差异需要实际测试。
7. API 采用工作线程上的同步调用，未实现用户取消、重试或页面销毁后的任务管理。无账号/token 持久化，无任意认证挑战或证书绕过。测试尚未覆盖真实 TLS、超时边界及 8 MiB 限制边界。
