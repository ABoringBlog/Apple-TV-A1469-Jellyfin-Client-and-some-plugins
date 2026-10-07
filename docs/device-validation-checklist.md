# Device validation checklist — Pre-Device Freeze

此清单只将执行过的检查列为 VERIFIED OFFLINE；不得把 mock、签名存在、成功构建或 Python TLS 测试改写成真机通过。

## VERIFIED OFFLINE

| 范围 | 证据 |
| --- | --- |
| API/导航/遥控模型/图片缓存 | make test：184 断言；原 HTTP fixture 同样通过 |
| session 生命周期 | 177 断言，取消/注销/重入/关闭 |
| 宿主模型边界 | 49 断言 |
| UI + 注入 mock 播放流程 | 182 断言 + 4 个独立 ABI 拒绝场景 |
| playback/subtitle 模型和状态机 | 179 断言：setup、决策、ticks、URL、上报、暂停/继续/seek/stop、回调竞态、401、坏数据、字幕策略 |
| playback 真实 loopback HTTP | 18 断言；超大 JSON/图片、坏图、慢请求、断连、401 |
| Python 合同 | integration 6、package 8、deployment 7、TLS 4，共 25 个用例；package 对旧/新候选分别执行 |
| 集成链路 | fixture 与 loopback：server info→登录→库→两页→详情→poster/backdrop→远端 logout→旧 token 拒绝 |
| TLS | Foundation 自签名拒绝；隔离 CA 下 Python 可信成功/hostname mismatch/不可信 CA/握手失败；Foundation 错误分支注入 |
| ASan | playback 179、UI 182、session 177；未发现地址错误，未运行 leak detector |
| ARMv7 | 全新目录严格链接，无编译 warning/error，lipo armv7；第二次全新构建字节一致 |
| deb | root:wheel、modes、路径、元数据、ARMv7、签名存在及 Mac strict codesign；两次 deb 字节一致 |
| 部署工具 | dry-run/显式门槛/参数校验/脚本语法；没有远程执行 |

计数口径：771 条离线 Objective-C 断言 + 18 条新增 HTTP 播放断言 = 789；HTTP 重跑基础 184 和 ASan 重跑不重复计入。Python 25 是用例定义数，重复执行/子测试不重复计入；ABI 场景另列。

## PROVISIONAL

- ATV3 DeviceProfile：H.264 8-bit SDR、≤1080p/30 fps/level 4.0、AAC≤2ch/48kHz，保守限制而非设备能力证明。
- MP4/M4V/MOV 直放、HLS direct stream/transcode，以及 header 鉴权、StartTimeTicks/seek 对真实设备 adapter 的要求。
- 字幕选择与转换/burn-in 策略，不代表设备格式支持。
- 编译最低 iOS 8.0 字段与 SDK 假设、ad-hoc 签名在设备上的适用性。
- BackRow 已有 UI 接线的 selector/ABI 依据为历史源码与 runtime mocks，非 8163 实测。
- AC3 **不声明支持**；HEVC、AV1、HDR、Dolby Vision **不声明支持**。

## NOT RUN / REQUIRES DEVICE

以下每项保持 NOT RUN，设备到达后填写时间、结果、脱敏证据与设备 build：

| 设备阻塞项 | 结果 |
| --- | --- |
| USB 识别、Blackb0x 越狱、恢复入口 | NOT RUN |
| SSH 连接、设备权限/空间、安装/回滚/卸载 | NOT RUN |
| 8163 BackRow/FRAppliance selector/ABI | NOT RUN |
| appliance 加载、菜单入口、signature trust、loader 行为 | NOT RUN |
| 真机键盘、密码隐藏、遥控器焦点/短按/长按 | NOT RUN |
| 私有播放器 API、实际 media URL/header/HLS/seek adapter | NOT RUN |
| H.264/AAC/AC3 实际解码、声音、输出与兼容性 | NOT RUN |
| 字幕 renderer、字符/字体/同步/外挂或 burn-in 画面 | NOT RUN |
| 性能、峰值内存、泄漏、长时间运行 | NOT RUN |
| 真机 crash/syslog 与生命周期线程 | NOT RUN |
| 必须从设备提取的 framework/symbol/header | NOT RUN |

## NOT RUN / REQUIRES SERVER CONFIGURATION

真实 Jellyfin、其受信任 HTTPS 成功、真实媒体 PlaybackInfo/转码/字幕/会话上报互操作尚未执行：未提供 JF_URL 与外部凭据/媒体 ID。runner 明确 exit 77 / NOT RUN。这是外部验证条件，不是尚未实现的 runner；即使所有离线项已通过，也不能声称真实服务器通过。

Phase 4E 原验收表继续保留在 `docs/phase4e-device-validation.md`，不得回填成 PASS。

## 2026-10-02 首次部署预检尝试

候选 0.5.1-deviceabi1 SHA256 与指定值一致，包及 stage 校验 VERIFIED STATIC。当前会话 SSH 认证被拒绝，设备预检、备份、安装、loader、principal class、symlink 动态解析、crash/syslog 均 NOT RUN；UI/Remote/生命周期/键盘均 NOT REACHED。真实服务器 NOT RUN。没有设备修改或代码修复，不把静态验证计为 PASS ON DEVICE。详见 [首次部署记录](device-first-deployment-12H1006.md)。

## 2026-10-02 SSH 恢复后首次真机预检 r1

PASS ON DEVICE：atv3 root SSH、AppleTV3,2 / iOS 8.4.4 / 12H1006、宿主 7.9 / 8163、apt-get check、空间和宿主进程；四个支持包安装状态正常（patcyh 正确 ID 为 com.saurik.patcyh）。FAIL ON DEVICE（安装前门槛）：dpkg --audit 非空，多个包缺少 md5sums；AppleTV.app/Appliances 不存在。按要求停止，未上传安装、未改系统包或加载器、未重启。loader/principal class/symlink 解析 NOT RUN；UI/六键/生命周期/键盘各项 NOT REACHED；真实服务器 NOT RUN；Ready for real playback device validation=否。候选 SHA256 未变。原始预检与 dpkg 参考归档保存在 device-evidence/12H1006/pre-first-deploy，仅本地保存；审阅摘要和散列纳入 recovery.git。详见 device-first-deployment-12H1006.md 最新节。
