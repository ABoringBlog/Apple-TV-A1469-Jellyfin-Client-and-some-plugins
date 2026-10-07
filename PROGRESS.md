# 开发进度

## 2026-09-27 第一阶段核实与恢复点

已阅读 phase1-report、README、全部源码、测试和四份原始日志。仓库此前无提交。
已完成：Objective-C appliance 入口、运行时 BackRow 适配和 ABI 检查、遥控器解析、独立 Jellyfin 登录/媒体库 API、NSURLProtocol 与 loopback 测试设施。真实 UI、播放、设备兼容性均未验证。

验证：`make test > logs/phase1-recheck.log 2>&1`：69 个断言通过。
历史 ARMv7：4 个源文件成功编译为对象；9.3 SDK 链接缺 liblaunch，10.3 链接缺 `_objc_msgSend_stret`，均伴平台警告。尚无完整 bundle。
历史 `make test-http`：sandbox bind EPERM，未完成网络测试。历史 plist lint 通过。

保留原始 armv7_test* 探针及日志，不删除已有产物。build 和探针二进制只在工作区保留，源代码纳入版本控制。

下一步：检查本地 Kodi 14.2 构建参数、SDK stub 的架构及符号；修复可证实的链接原因；成功后验证 Mach-O、依赖、签名、plist，并尝试 dm.pl 离线打包；增加无 BackRow 的登录/列表/导航模型与测试。每个验证阶段单独提交。无部署或固件操作。

保存限制：主仓库 `git add` / `git commit` 均因 `.git/index.lock: Operation not permitted` 失败（环境将 .git 设为只读）。在项目内使用独立 `recovery.git` 保存提交，不改主仓库；后续可在允许写 .git 的终端 fetch 恢复提交。

## 阶段 2：严格 ARMv7 链接成功

恢复点：`c67601c`（recovery.git；提交身份 Codex checkpoint <codex@localhost>，未修改用户配置）。
`make shell > logs/armv7-sdk11.4.log 2>&1`：退出 0，无警告。完整 11.4 SDK 正确提供 ARMv7 stret 导出，4 个源码重新编译，未删除功能、伪造符号或使用 dynamic_lookup。详见 docs/link-investigation.md。
Makefile 默认 11.4；输出按 SDK/最低版本隔离，保留所有原始产物。下一步验证 bundle 和离线包。

## 阶段 3：产物验证和离线打包

`Scripts/package.sh` 首次失败：lipo 参数顺序错误，记录 logs/package-phase2.log，原输出保留。
修正后 `Scripts/package.sh build/iPhoneOS11.4.sdk-ios8.0/Jellyfin.frappliance build/package-phase2-r2 > logs/package-phase2-r2.log 2>&1` 退出 0。
验证 armv7、MH_BUNDLE、最低 8.0/SDK 11.4、plist lint；依赖 Foundation/CoreFoundation/libobjc/libSystem。原 bundle 未签名；副本 ad-hoc 签名，codesign strict verify 通过。nm 保留系统动态导入，未放宽未定义符号检查。
现有 dm.pl 成功生成 deb；仅有 Perl locale 回退警告。`ar -p build/package-phase2-r2/org.jellyfin.atv3_0.2.0-test1_iphoneos-arm.deb data.tar.gz | tar -tzvf -` 检查包内容，见 logs/package-contents.log。包含 Applications bundle 与 appliance 链接，无设备脚本。SHA256 已记入构建日志。
这不是设备签名信任或安装兼容性验证。未安装、部署、重启或接触设备。下一步独立工作流模型。

## 阶段 4：独立登录与导航模型

新增 JFBrowser：串行工作线程上的登录/刷新、媒体库快照、焦点边界、按下/重复/长按移动、选择与 Menu 返回、刷新按 ID 保留焦点、失败清空过期列表、会话失效回登录。库详情仅表示选中状态，不包含媒体内容或播放。未接入真实 BackRow。
`make test > logs/phase2-tests.log 2>&1` 首次编译失败：CHECK 宏误解析字典字面量逗号；改为可变参数宏。
`make test > logs/phase2-tests-r2.log 2>&1`：97 个断言通过（原 69 + 新增 28），无编译警告。
`make test-http > logs/phase2-http.log 2>&1`：仍因 bind EPERM 阻塞，未执行网络断言。
`make shell > logs/phase2-build.log 2>&1` 与 r2：新增模块 ARMv7 编译成功；尝试明确 SDK 元数据分别出现重复 platform_version、sdk_version 不兼容警告。已撤回这两种参数，保留默认严格链接。
更正阶段 3：实际 LC_VERSION_MIN_IPHONEOS 的 version 和 sdk 均为 8.0（详见原始日志），使用的头文件/stubs 是 11.4。clang 14 对本地旧 SDK 的版本识别回退，并非实际用了 8.0 SDK。不会为改善元数据修改外部 SDK。后续可评估项目内标准 SDK 元数据副本。

真实 UI 阻塞：缺少固件 8163 验证过的列表、焦点、文本输入、controller 生命周期接口及加载顺序。现有事件通知没有连接此模型；不宣称用户可在电视上登录/浏览。

## 最终保存与继续起点

阶段提交（均在 recovery.git）：c67601c 第一阶段；95018cb 严格链接；32757e6 签名和打包；a9fb2f3 导航模型与 97 断言。

最终验证：
- `make shell > logs/phase2-final-build.log 2>&1`：退出 0，无警告，包含 5 个模块的 ARMv7 bundle。
- `Scripts/package.sh build/iPhoneOS11.4.sdk-ios8.0/Jellyfin.frappliance build/package-phase2-final > logs/phase2-final-package.log 2>&1`：退出 0；plist、armv7、Mach-O、依赖和 ad-hoc strict signature 检查通过，dm.pl 成功；仅 Perl locale 回退警告。
- `python3 Scripts/verify-package.py build/package-phase2-final/org.jellyfin.atv3_0.2.0-test1_iphoneos-arm.deb > logs/phase2-package-inspection.log 2>&1`：退出 0；验证 Debian 成员、control、plist、可执行权限、签名资源、软链接；无维护脚本。
- `git --git-dir=recovery.git --work-tree=. diff --check`：通过。
- `git status --short`：主仓库仍全部未跟踪，原因是 .git 只读；不要误认为恢复仓库提交已进入主 main。

最终测试包：build/package-phase2-final/org.jellyfin.atv3_0.2.0-test1_iphoneos-arm.deb，SHA256 44bd88815352272d1c9b354e18d96b2d72260d808d29f73be5668e383c5eedf8。
没有清理任何旧备份、构建产物或 Git 历史。最终恢复提交另导出 checkpoints/phase2.bundle，便于中断恢复。

下次明确起点：先读取本文件和 recovery.git 日志，在可写 Git 环境导入恢复分支；扩展独立模型的取消/异步生命周期与媒体内容 API，并在允许 loopback 的环境执行 make test-http。核实真实 SDK 元数据识别；取得固件 8163 可验证的 BackRow 接口证据后再接真实 UI。真实 Jellyfin/TLS、设备加载/签名信任和播放仍未验证，本轮不进行设备部署。

## 第三阶段 A：恢复资料和网络环境复核

主 .git 普通 mode/flags 无异常，但本会话文件权限明确将 .git 设为只读；不尝试改权限或写锁。recovery.git HEAD = de9048daca3fccd46bb11aef8e4ac57b293cd413；`git --git-dir=recovery.git fsck --full` 退出 0；phase2.bundle verify 退出 0，包含 HEAD/master 和完整历史。未删除恢复资料。
基线 `make test` 97 断言通过，见 logs/phase3-baseline.log。`make test-http` 在 127.0.0.1:0 bind 时 EPERM，尚未启动客户端，属于环境阻止，不是代码失败。runner 现为权限阻止明确输出 BLOCKED 并退出 77（make 会转为 2）。不绕过沙箱；用户可在普通终端执行 `cd $HOME/Projects/Jellyfin-ATV3 && make test-http`。
后续主仓库迁移：在允许写 .git 的终端 `git fetch ./recovery.git master:refs/heads/recovery-phase3`；先保留工作区再选用导入分支，禁止强制 reset/clean。bundle 也可作为 fetch 来源。恢复仓库保留阶段二标签 phase2-offline-verified，指向 de9048d，仅代表离线验证。

## 第三阶段 B：异步执行、超时和取消

前一小阶段提交 8d4653a。新增 JFWorker/JFTask 串行异步执行器，可包裹 client 或 browser 操作；主线程交付结果。任务 block 持有使用对象直到完成；UI 关闭必须取消任务并避免回调强持有自身。取消轮询最多约 50ms，取消底层连接、抑制交付；超时可设置 0.05..300 秒，使用单调时钟总期限。禁止同时从外部线程访问同一 client/model。
首次测试发现 NSOperation 完成后 cancel 不保证取消标记，导致已排队回调仍触发（logs/phase3-async-tests.log）。补充独立取消标记后 `make test` 102 断言通过（logs/phase3-async-tests-r2.log）；覆盖主线程交付、超时、运行中取消和完成后交付前取消。`make shell` 退出 0，无警告（logs/phase3-async-build-r2.log）。真实 socket 超时/取消仍待允许 loopback 的终端运行。

## 第三阶段 C：媒体 API 与请求描述

异步阶段提交 eccde37。新增电影/电视剧分页列表（start/limit）、季、集、按用户取详情、PlaybackInfo。校验媒体 ID、结果形状和 HTTP 错误，401 清会话。海报/静态直传返回带 X-Emby-Token 的 NSURLRequest，URL 不含 token；没有下载/解码海报或启动播放，不声称设备支持返回的媒体。调用方必须拒绝跨域重定向，且不能记录请求头。
Tests/media.json 为 NSURLProtocol 和 HTTP runner 共用的精确路径/query/认证 fixtures；测试分页、各层列表、详情、错误数据、越界参数、路径注入和过期会话。`make test` 130 断言通过，`make shell` 退出 0，无警告（logs/phase3-media-*）。HTTP fixture 具备同样用例，当前仍受 bind 沙箱限制。
API 参考官方客户端源码 https://github.com/jellyfin/jellyfin-apiclient-python/blob/master/jellyfin_apiclient_python/api.py 与官方生成 SDK https://github.com/jellyfin/jellyfin-sdk-typescript/blob/master/src/generated-client/api/library-api.ts 。未验证真实服务器版本差异。

## 第三阶段 D：独立媒体导航

媒体 API 提交 f9fcc23。JFBrowser 新增电影详情、电视剧→季→集→详情、逐层返回和焦点恢复；媒体页支持每页 100 项加载更多。列表/详情成功后才切页；失败保持可用页面，401 清导航和会话。新增 snapshot 可通过 JFWorker 在主线程交付；遥控选择的网络操作需显式排入 worker，事件处理本身不发网络请求。真实 BackRow 接线仍未实现。
`make test` 148 断言通过；`make shell` 退出 0，无警告（logs/phase3-navigation-*）。新增导航测试涵盖电影/电视剧全链路、返回、快照保留、越界选择、注销清历史。本阶段之后继续补生命周期、分页和异常边界测试，再做最终离线包验证。

## 第三阶段 E：生命周期和边界验证

导航阶段提交 af0d216。修正 cancelAll 对“已完成但主线程尚未交付”任务的管理；工作 block 结束后及时释放捕获对象，先保留结果/错误再释放 work。新增调用者立即释放 client、排队前取消、cancelAll 延迟交付、超过 8 MiB、100+1 项分页、失败保留焦点/列表、401 清整个导航的测试。
`make test` 162 断言通过；`make shell` 退出 0，无警告（logs/phase3-boundary-*）。`make test-http` 再次 BLOCKED，runner 77、make 2，未执行真实 HTTP 断言（logs/phase3-http-final.log）。没有把环境阻止记录为代码失败。HTTP runner 同步增加慢响应、超大响应和媒体 fixtures，用户允许监听的终端可运行完整测试。

## 第三阶段 F：0.3.0 离线版本验证

边界阶段提交 a71d223。版本统一为 bundle/API 0.3.0、Debian 0.3.0-test1。源码、独立导航和异步使用契约已更新 README。

实际通过：
- `make test > logs/phase3-final-tests.log 2>&1`：162 断言，退出 0。
- AddressSanitizer 独立编译 build/tests-asan，并运行 `./build/tests-asan http://fixture.invalid > logs/phase3-asan.log 2>&1`：162 断言，退出 0，无 ASan 诊断；不等同于泄漏检测或设备验证。
- `make shell BUILD=build/phase3-ios8.0 > logs/phase3-final-build.log 2>&1`：全新目录编译全部 6 个模块，严格 ARMv7 链接退出 0，无警告。
- `Scripts/package.sh build/phase3-ios8.0/Jellyfin.frappliance build/package-phase3-final > logs/phase3-final-package.log 2>&1`：退出 0；armv7、Mach-O、plist、依赖、ad-hoc strict signature 通过，dm.pl 生成包。仅 Perl locale 回退警告。
- `python3 Scripts/verify-package.py build/package-phase3-final/org.jellyfin.atv3_0.3.0-test1_iphoneos-arm.deb > logs/phase3-package-inspection.log 2>&1`：退出 0；包成员、control、权限、签名资源、appliance 链接正确，无维护脚本。
- recovery.git `diff --check` 通过。主 .git 未修改。

包 SHA256：52bbddc4493b5d30ecfdb68437ac777ae715c80f1666b5c8b3a26c83a35151fb。
原 phase2.bundle SHA256：dc228e27f2585482a791d8e2ae9f6f71de02acdea037b83021a1f70c95acf10b。

未通过/未执行范围：真实 HTTP 因沙箱 EPERM 未启动客户端；真实 Jellyfin/TLS、8.0/8163 兼容性、SDK 版本字段回退、BackRow 界面与加载顺序、播放/字幕和设备信任仍未验证。海报和静态播放仅请求描述；暂无图片下载缓存、DeviceProfile/转码选择、播放进度上报。季/集暂不分页，结果受 8 MiB 上限。取消不回滚已完成的模型变化，UI 需主线程取消并使用快照，禁止并发直接访问模型。

下一轮起点：先读本记录和 recovery.git log；在允许监听的普通终端执行 `cd $HOME/Projects/Jellyfin-ATV3 && make test-http`，把实际网络结果保存新日志；补真实 Jellyfin/TLS 兼容验证与资源下载，再依固件 8163 接口证据接 BackRow。不要把离线标签当成设备可用版本。保留 phase2-offline-verified 与所有历史包；本轮无备份删除、部署、越狱或固件修改。


## 第三阶段提交索引与恢复交接

以 recovery.git 最终 log/reflog 复核的编号为准：8d4653a 环境核实；eccde37 异步；f9fcc23 媒体 API；af0d216 导航；a71d223 生命周期边界；fd461f0 最终离线版本与包验证。早先导航阶段短编号记录有误，此处已更正。
标签 v0.3.0-offline → fd461f0；上一版本 phase2-offline-verified → de9048d。交接文档提交在版本标签之后，不改变已验证源码。最终历史导出 checkpoints/phase3.bundle（含 master、HEAD 和标签），保留 phase2.bundle。恢复日志可通过 `git --git-dir=recovery.git log --oneline --decorate` 读取。

迁移时普通终端先执行 `git fetch ./recovery.git master:refs/heads/recovery-phase3`，需要标签时再执行 `git fetch ./recovery.git refs/tags/v0.3.0-offline:refs/tags/v0.3.0-offline refs/tags/phase2-offline-verified:refs/tags/phase2-offline-verified`。先保留未跟踪工作区再切换分支；当前主 main 仍无这些提交。恢复 Git 不可用时把 fetch 来源换为 ./checkpoints/phase3.bundle。没有强制改主仓库权限。

## 第四阶段 A：基线复核

确认 recovery.git HEAD f550e74，v0.3.0-offline 指向 fd461f0。阅读现有源码、README、测试及第三阶段构建/测试记录；不重复已完成的分页、取消和严格链接实现。
实际执行 `make test > logs/phase4-baseline.log 2>&1`：162 断言通过。
`make test-http > logs/phase4-http.log 2>&1`：bind EPERM，runner 77 / make 2，客户端未运行，属于权限阻塞而非代码缺陷。外部命令：`cd $HOME/Projects/Jellyfin-ATV3 && make test-http > logs/phase4-http-external.log 2>&1`。
下一步：共用受限传输实现图片下载/缓存；增加无敏感输出的真实服务器入口、TLS 测试条件和 BackRow 模型接线。未修改外部目录；保留第二、第三阶段恢复资料。

## 第四阶段 B：图片下载与缓存

新增 Sources/API/JFImageCache.{h,m}；JFClient 抽取 JSON/图片共用的受限传输，增加 Primary 与 Backdrop/0 下载。ImageIO 验证可解码且 <=16M 像素，传输 <=8MiB。内存 <=8MiB，磁盘 <=32MiB，TTL/显式失效，文件名 SHA256、不保存请求头或 URL。每次登录随机命名空间；logout/401 清除本 client 使用过的缓存。磁盘可跨内存清空复用，不跨登录复用。缓存写入失败不使成功下载失败。不自动重试认证，失败图片不缓存，调用方可重新请求恢复。
修改 Makefile 链接 ImageIO/CoreGraphics；Tests/main.m、JFFixtureProtocol.m、run.py 和 pixel.png 覆盖真实 ImageIO 解码、内存/磁盘读回、TTL、损坏文件、海报/背景、503 后恢复、401 注销及缓存清除。
`make test > logs/phase4-images-tests.log 2>&1`：184 断言通过；`make shell BUILD=build/phase4-images > logs/phase4-images-build.log 2>&1`：全部模块 ARMv7 严格链接成功、无警告。HTTP fixture 已同步，但 socket 测试仍受沙箱限制。图片尚未显示到 BackRow。
下一步：真实服务器/TLS 入口和独立 UI 会话适配、缓存容量与接线边界测试。

## 第四阶段 C.0：恢复核对、结构分析与网络基线

按要求首先执行 recovery.git log，确认 HEAD 为 5567ea1，工作区干净。该提交已保存
Tests/integration.{py,m}、TLS runner 和 Makefile 集成入口；补记这一尚未写入进度的恢复状态。
未重新初始化 Git，未修改主 .git，未改生产源码。结构与逐文件修改计划见
docs/phase4c-plan.md；后续按入口收口、独立 UI session、宿主边界分阶段测试并提交。

实际验证：make test 184 断言通过；make test-integration-fixture 登录/库/详情/图片/
注销通过，分页因未配置 library 明确 SKIP；make shell BUILD=build/phase4c-baseline
全量严格链接成功、无警告，lipo 确认 armv7。日志为 logs/phase4c-baseline.log、
phase4c-integration-fixture.log、phase4c-baseline-build.log。

HTTP/TLS 首次在沙箱内 bind EPERM，runner 77 / make 2（logs/phase4c-http.log、
phase4c-tls-negative.log）。按权限流程在获准的沙箱外重新运行，make test-http
184 断言通过，make test-tls-negative 自签名证书拒绝通过（logs/phase4c-http-permitted.log、
phase4c-tls-negative-permitted.log）。历史“socket 测试尚未完成”的限制本次已部分解除；
这仅代表 Mac loopback HTTP 与 TLS 负例，不代表真实 Jellyfin 或设备兼容性。

当前未提供真实服务器地址/账号；真实 Jellyfin、可信 HTTPS 成功路径和 BackRow 可见 UI
仍未验证。下一步为 4C.1：完善现有集成入口参数校验、TLS 错误 domain/code 判断、
fixture 分页覆盖与使用说明；随后实现 JFSession，保留现有 ARMv7/手动引用计数约束。

## 第四阶段 C.1：集成入口收口

以 9bcc7fd 为基点，保留既有生产模块。Python 与 Objective-C 双层校验配置类型、模式、URL、ID 和 HTTP 显式选择；凭据仅经匿名管道，固定输出白名单不转发诊断。TLS 拒绝改为 domain + 明确证书错误码，timeout 同时校验 domain。fixture 配置 lib1，并断言第一页 movie1、第二页为空。

验证：`make test-integration-entry` 4 个测试通过（含类型矩阵、退出码、完整 fixture 分页、输出脱敏、启动/期限失败），logs/phase4c1-entry.log。HTTP/TLS 沙箱 bind 仍返回 77；获准重跑 `make test-http test-tls-negative` 退出 0，184 断言及证书拒绝通过，logs/phase4c1-network-permitted.log。真实服务器和可信 HTTPS 成功路径未提供，未执行。

## 第四阶段 C.2：独立 JFSession

C.1 提交 0d1d402。新增 JFSession.{h,m}，不改 JFClient/JFWorker/JFBrowser/BackRow。主线程命令/快照通知、busy 拒绝普通重复操作、登录代次替换、有限错误类别；关闭和注销在原 worker 串行清理，交付对象不持有 session，close 后后台清理自行保持存活至完成。HTTP 初始化须显式允许，UI 不获得 client/browser 或 token。

新增 Tests/session.m 的可控 client 覆盖主线程交付、401、认证后取库失败、超时分类、焦点/返回、快速重复操作、新旧登录竞争、注销/关闭期间请求、立即释放及后台清理完成。测试首轮 mock 在 super dealloc 再次调用 logout 时访问已释放 gate，修正 mock 指针置空；随后修正释放断言等待 autoreleasepool 排空，保留失败日志。不涉及原生产模块缺陷。

验证：`make test test-session test-integration-entry` 退出 0，184 原回归断言、177 session 断言、4 入口测试通过，logs/phase4c2-regression.log。session AddressSanitizer 177 断言通过，无 ASan 诊断，logs/phase4c2-session-asan-r2.log；非泄漏检测。`make shell BUILD=build/phase4c2` ARMv7 全量严格链接成功、无警告，logs/phase4c2-armv7.log。尚未绑定真实宿主生命周期。

## 第四阶段 C.3：宿主边界与验收

C.2 提交 4b36b10。新增 JFSessionHost.{h,m}：规范化事件返回 Unhandled/Consumed/ExitRequested；busy 已知事件消费并丢弃，深层 Menu 由模型返回、根 Menu 仅请求宿主退出，媒体 Select 走 session worker。close/析构使 session 终态关闭。未改 JFBackRow.m 或其它原有生产模块，没有引入固件 selector；真实 controller 接线、输入、可见列表仍待 8163 证据。明确现有 JFRemoteEvent 通知不能取消 shell 的 Menu pop，不能直接据此接线。完整契约见 docs/phase4c-host-boundary.md。

新增 Tests/host.m 49 断言，以 mock 宿主 + 真实 session/fixture 覆盖事件和关闭。新增 test-integration-http，使用 socket 跑集成入口的登录、两页、图片、清会话、401/500 退出码、断连和超时。该测试证实入口 timeout 原先只识别 NSURLErrorDomain，漏掉既有 client 的 Jellyfin/-1001 总期限错误；仅修正入口判定为两个已知 domain + 同一码，保留原传输实现。首次失败见 logs/phase4c3-entry-http-permitted.log，修正后六个场景通过，logs/phase4c3-entry-http-r2.log。401/500 的 FAIL 行为预期负例，最终 contracts PASS / exit 0。

最终验证：
- `make test-phase4c` 退出 0：184 原回归 + 177 session + 49 host 断言，4 个入口测试，logs/phase4c3-regression.log。
- 获准沙箱外 `make test-integration-http` 退出 0；`make test-http test-tls-negative` 退出 0，184 HTTP 断言与证书拒绝通过，logs/phase4c3-network-final.log。沙箱 bind 阻止仍保留 logs/phase4c3-entry-http.log，未当作成功。
- `make shell BUILD=build/phase4c-final` 全量严格链接成功、无警告；lipo 确認 armv7，logs/phase4c3-armv7.log。
- 原 JFClient/JFWorker/JFImageCache/JFBrowser/JFBackRow/JFRemote 与 9bcc7fd 无差异；未修改主 .git、未部署或接触设备。

Phase 4C 计划内三个实现阶段完成。真实 Jellyfin 地址/测试账号未提供，可信 HTTPS 成功与服务版本兼容未验证；BackRow 实机生命周期、列表、输入和播放未实现，不视作可用电视 UI。下一步需真实服务器/账号验证与 8163 接口证据，再做宿主接线。全部阶段提交仍保存在 recovery.git。

## 第四阶段 D.1：BackRow 列表桥接与生命周期

起点 c82238a，先完成 UI 结构/接口分析并输出方案，详见 docs/phase4d-plan.md。只读下载 nitoTV 源码至 build/evidence-nitotv（commit c0c030b64bea586aed1ae3772f89c12bc2ebc60a），不复制实现或引入其依赖。

新增 JFBRMenu：受检 runtime 调用、BRMenuListItemProvider 数据源、标题/列表/选择重绘。扩展 JFBackRow 动态子类：有完整菜单接口时继承 BRMediaMenuController；没有菜单类时保留 shell，类存在但生命周期/选择 ABI 不匹配则拒绝注册。activate 重绘，deactivate 解绑，wasPopped/dealloc 关闭；数据源不反向持有 controller。网络与会话模块无改动。

Tests/ui.m 的 20 个 runtime 断言验证主入口、列表、边界行、ABI 拒绝、生命周期及释放。`make test-phase4d` 原 410 断言 + 20 UI 断言及 4 Python 测试通过；`make shell BUILD=build/phase4d1` ARMv7 严格链接通过，无警告。日志 logs/phase4d1-final-tests.log、phase4d1-armv7.log；首轮编译警告已修正，历史日志保留。UI 尚处于 renderer 阶段，下一阶段接主界面与 JFSession；未做实机验证。

## 第四阶段 D.2：主界面、登录与列表

D.1 提交 d8eff55。新增 JFUIController presentation，动态 JellyfinController 持有它：主界面包含 Server address、Username、Sign in、Allow HTTP；文本输入仅使用有证据且运行时签名匹配的 BRTextEntryController 接口，密码要求 setShowUserEnteredText:NO 可用。输入完成/取消解除 delegate 并清空文本，密码不成为 UI ivar。稳定 JFDeviceID 是唯一写入 defaults 的配置，服务器/用户名只在当前 UI 内存；现有网络/会话模块不改。

登录通过原 JFSession，渲染库名、媒体类型选择、电影/剧集列表、详情、加载、空库、有限错误；提供刷新、注销与返回。输入覆盖时停用 UI 观察，返回重读快照，不关闭会话。关闭先清输入/观察，再关闭会话。当前阶段通过 itemSelected: 验证行为，完整遥控所有权在 D.3 收口。

`make test-phase4d` 原 410 断言、UI 扩展测试和 4 Python 测试通过，logs/phase4d2-regression.log；`make shell BUILD=build/phase4d2` ARMv7 严格链接通过、无警告，logs/phase4d2-armv7.log。UI 测试使用真实 session/fixture 覆盖输入、HTTP 显式选择、登录→库→电影→详情→返回→注销、认证失败、空库与取消输入。首轮 mock 方法声明警告已修正。实际 BackRow 控件显示、输入掩码和真实认证仍需实机验证。

## 第四阶段 D.3：Apple Remote 接线与最终验收

D.2 提交 0519eed。JFUIController 从实际动态 controller 的 brEventAction: 接收 JFRemote 规范化事件，上/下同步模型焦点或 UI 操作行，Select 短按执行，Menu 深层返回/根页退出，busy 事件丢弃。UI 不订阅 JFRemoteEvent；仅 shell fallback 继续旧通知路径，避免二次 pop。补 runtime provider ABI 校验及列表实例预检，不兼容时拒绝创建 controller；关闭清空列表行、输入和观察者。

Tests/ui.m 扩展至 153 个 UI 主流程断言：原始遥控事件进入运行时 override，多库焦点/操作行恢复，电视剧→季→集→详情，全层返回，busy Menu，无效输入来源，关闭中的请求和保留输入控件时宿主释放。另四个独立进程检查菜单 superclass、数据源 protocol、密码隐藏方法、list 实例 ABI 不兼容的拒绝路径。mock 基于固定源码接口证据，不等于固件运行结果。

最终验证：
- `make test-phase4d` 退出 0，原 410 + UI 153 = 563 个主流程 Objective-C 断言，4 个 ABI 拒绝场景，以及 4 个 Python 测试通过；logs/phase4d3-final-tests.log。
- UI AddressSanitizer 编译并运行，153 断言通过，无 ASan 诊断；logs/phase4d3-final-asan.log。非泄漏检测。
- `make shell BUILD=build/phase4d-final` 全量构建后对最终改动增量重链均退出 0、无警告；logs/phase4d3-armv7.log、phase4d3-final-armv7.log。lipo 确认 armv7。
- 对比 c82238a，Sources/API、Sources/Navigation、Sources/Input 和 JFSessionHost 完全无差异；主 .git 未写入，没有部署或设备操作。网络实现未变，本阶段未重复 socket/TLS 测试，沿用 4C 已记录的网络基线。

使用和生命周期文档见 docs/phase4d-ui.md，README 已更新；nitoTV 固定来源链接记录于 docs/references.md。实现范围完成：FRAppliance 分类入口、原生菜单、输入、session/API 接入、库列表及遥控生命周期接线。产物 build/phase4d-final/Jellyfin.frappliance 未签名。未提供实机/服务器，因此 8163 加载、实际界面、键盘/密码隐藏、生命周期线程及真实认证/可信 HTTPS 成功尚未验证；没有声称电视上运行成功。下一步为有环境时的真机 UI 验证，播放/海报显示/登录持久化仍不在本阶段范围。

## 第四阶段 E.1 / E.2：冻结候选与真机部署准备

2026-09-29 接续已通过的 Phase 4E package final。候选 deb 为
`build/package-phase4e-final/org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb`，
SHA256 `94fde77a0b2d04680dc999cb0c5e92657e4a008fb958da269b981da0b2314738`。
保留既有 E.1 bundle 0.4.0 / deb 0.4.0-test1、项目内 build-deb.py 与包拒绝测试改动；本轮未重建或改变该候选，未修改 Sources。

新增只读 `Scripts/device-preflight.sh`，采样型号/固件、dpkg、挂载、空间、目标路径与服务；采样完成不等于兼容性通过。新增 `docs/phase4e-deployment.md` 和 `docs/phase4e-device-validation.md`，覆盖 SSH、主机校验、备份、上传散列、安装状态、UID/GID/modes、首次安装/升级回滚与 UI 验收。宿主服务与恢复入口待设备采样，不预设重启命令。

新增 `Scripts/prepare-deployment-kit.py`：固定候选摘要、拒绝覆盖目录、打包文档和校验脚本、生成 SHA256SUMS。套件 `build/deployment-phase4e/` 已生成。脚本默认项目根目录下 build 输出，也可传入新的输出目录；无设备操作。

实际检查：package_test.py 8 tests OK；verify-package ARMv7、ownership/modes、signature presence、metadata 与签名 stage 字节一致；codesign --verify --strict 通过；预检脚本 sh -n 通过；套件 7 项 SHA256 全部 OK，套件内候选独立校验通过。日志 `logs/phase4e2-package-check.log`、`logs/phase4e2-kit-check.log`。没有因文档/部署准备改动重复 UI 或网络回归。

当前状态 **WAITING FOR DEVICE**。未获得设备 SSH 地址/别名、实际固件/加载环境、恢复入口与真实服务器配置。没有执行 SSH、安装、重启或加载器修改；全部真机验收保持 NOT RUN。设备连接后从只读预检开始。本轮不进入播放器开发。主 .git 保持不变，阶段记录保存于 recovery.git。

## Pre-Device Freeze A：真实服务器入口

保留 fixture，增加 JF_URL/JF_USERNAME/JF_PASSWORD 或 JF_TOKEN、JF_LIBRARY/JF_ITEM 与外部 JSON 配置；凭据经匿名 stdin 传入 Objective-C，输出白名单不记录 URL、凭据、响应或 headers。新增 Users/Me token 登录、Sessions/Logout、旧 token 401 验证，支持 POST 204。HTTPS 继续系统信任；另备隔离 CA 的 TLS 成功/hostname mismatch/不可信 CA/握手失败测试，无系统信任修改。真实服务器未配置，NOT RUN。后续最终验收统一运行 HTTP/TLS 与全回归。

## Pre-Device Freeze B：播放与字幕独立逻辑

新增 JFPlaybackModel、JFPlaybackController 与 JFSubtitle：POST PlaybackInfo、provisional H.264/AAC 1080p DeviceProfile、DirectPlay/DirectStream/Transcode 保守决策、同源且保留服务器 base path 的播放请求、认证 header、resume ticks、Playing/Progress/Stopped、setup cancel、pause/resume/seek/stop、迟到回调代次隔离。新增外挂 SRT/UTF-8/时间戳验证及 ASS/SSA 转换或保样式 burn-in、PGS burn-in 策略。没有原生字幕或播放器实现，没有声明 AC3/HEVC/AV1/HDR/Dolby Vision 支持。

模型首轮发现 reverse-proxy base path 尾部斜杠差异，已修复并保留失败日志；播放/字幕断言从 147 扩展至 162，通过，含 seek 前旧回调、上报 401 和 session logout during setup。日志 pre-device-playback-*.log。真正的媒体解码、转码服务兼容性和设备字幕呈现不属于这些 mock 结果。

## Pre-Device Freeze C：UI 播放器抽象接线

JFUIController 支持显式注入 JFPlaybackBackend；JFSession 独占现有 client/worker 并管理播放注销/关闭。默认无 backend，不显示可播放入口；测试注入 inert mock 后验证点击影片→详情 Play→PlaybackInfo→playing→pause/resume/seek/stop/error→详情。真机代码未调用任何新私有播放器 selector。UI 主流程 182 断言及 4 个 ABI 拒绝场景通过；原导航行为保留。

## Pre-Device Freeze D：分步部署工具

新增 device-deploy.py，覆盖 connect/preflight/disk/backup/upload/install/inspect/rollback/uninstall/diagnostics/crashes。默认 dry-run，执行需 --execute，写入需 --device-confirmed；严格主机校验，无重启/固件/越狱操作。备份下载核验、原版本 deb、候选散列、磁盘空间与安装前状态为安装门槛。日志私有写盘，原始 crash/syslog 单独 opt-in。7 个 Python 测试通过，首次测试的 argparse 负例输入方式已纠正，失败记录保留。设备操作全部 NOT RUN。

## Pre-Device Freeze E：HTTP/TLS 与最终验收准备

新增 playback HTTP runner，真实 loopback 覆盖 PlaybackInfo/上报/字幕、空源/坏结构、超大 JSON/图片、损坏图片、断连、超时与 401，18 断言通过。TLS 隔离 CA 初轮因 Python/OpenSSL 严格校验要求 CA keyUsage 扩展失败；补齐 CA/leaf 扩展后 4 项（可信成功、hostname mismatch、不可信 CA、TLS 握手失败）全部通过，不修改系统信任。Foundation 自签名拒绝另行保留，Foundation hostname/TLS 错误状态使用 NSURLProtocol 注入验证；这些证据不等于设备 TLS 或真实 Jellyfin 成功。

增加 test-offline/test-asan、参数化 package_test.py，下一候选使用 0.5.0-predevice1；保留所有 0.4.0 历史包与 deployment-phase4e。当前开始最终回归、ASan、全新目录 ARMv7 构建与打包。

## Pre-Device Freeze F：最终离线验收与候选

完整实现包含原 API/session/artwork/UI、外部配置 integration runner、provisional playback/subtitle 层、mock backend UI 接线及部署工具。没有真机播放器实现，也没有新增未经验证的播放器 selector。

最终结果：184 基础 + 177 session + 49 host + 182 UI + 179 playback/subtitle = 771 离线 Objective-C 断言；另 18 playback HTTP 断言，共 789（HTTP 基础复跑与 ASan 不重复计数）。Python 6 integration + 8 package + 7 deployment + 4 TLS = 25 用例定义；package 对原 0.4.0 与最终 0.5.0 各运行通过；4 独立 ABI 拒绝场景通过。loopback integration 全链路、Foundation 自签名拒绝、隔离 CA TLS 4 项全部通过。ASan playback 179 / UI 182 / session 177 通过，无地址错误；非 leak detector。

补充字幕/失败回调边界测试时首次 CHECK 宏不支持表达式内逗号而编译失败，修正可变参数宏；最终日志 pre-device-playback-boundaries-r2.log 为新编译普通/ASan 各 177 通过，保留前次失败日志。生产源码没有因该测试修正改变。

全新目录 build/pre-device-armv7 严格 ARMv7 链接成功，无编译 warning/error。Scripts/freeze-build.sh repeat1 第二次干净构建与第一次原始 Mach-O 字节一致；签名、打包后的 deb 也字节一致。未执行旧 make clean；已将 clean 改为拒绝删除历史产物。新增可重复构建脚本输出独立目录/日志，拒绝覆盖。

最终 deb：build/package-pre-device-final/org.jellyfin.atv3_0.5.0-predevice1_iphoneos-arm.deb
SHA256：214fe2607b19293dea4dba64c6bc066b6bf17a6a1253e54cf03eab8d812bcae9
包内签名二进制 SHA256：eabdd305beeb67dbe8e4c368923f59a983e5dc5f81fc5cc8e7d6d1412d1956be
包内容/ownership/modes/ARMv7/signature presence、strict Mac codesign 均通过。

文档更新 README、playback-architecture、subtitle-architecture、pre-device-freeze、device-validation-checklist。新套件将保存为 build/deployment-pre-device-final；原 deployment-phase4e、checkpoints、recovery.git、日志和所有历史 deb 保留。恢复点及最终 tag 保存在 recovery.git。

没有真实服务器配置，实际 runner exit 77 / NOT RUN（pre-device-real-server.log）；没有连接 Apple TV、SSH、安装、重启、固件或越狱操作。设备项目全部 NOT RUN；profile/解码/字幕策略为 PROVISIONAL。后续仅设备特定实现/验证与外部服务器配置后的集成验收，详见分级清单。

封存前补充等待 PlaybackInfo 真正进入请求后再 stop/logout，以及 user token 认证→注销→失效入口用例；最终 logs/pre-device-boundary-final.log 为 playback/subtitle 179、integration 6、playback ASan 179 通过。仅测试改动，冻结包字节未变。

最终套件 build/deployment-pre-device-final 已生成并通过 14 项 SHA256 校验，套件内候选再次独立检查通过；原 build/deployment-phase4e 的 7 项 SHA256 再次通过，证明历史套件未变。新工具 install dry-run 已执行，明确未运行 SSH。recovery.git diff --check 通过。最后恢复提交将以 pre-device-freeze-v0.5.0 tag 标识。

## 真机 ABI A：12H1006 / source 8163 静态 UI 审计

读取四份设备提取物并保存 SHA256、otool/nm/strings、Objective-C 类/继承/方法编码。详见 docs/device-abi-12H1006.md；VERIFIED ON DEVICE 限静态设备元数据，不代表实际运行成功。BRMediaMenuController → BRMenuController → BRController → BRControl；BRAppliance 为协议而非已证实的类。发现 categoryWithName:identifier:preferredOrder: 的 order 为 float，现有整数门禁返回空分类；BRTextFieldDelegate required textDidChange: 未实现。菜单 long 行号与 float 高度编码相符。生产代码与冻结包保持原样，未部署、安装、重启；仅使用 recovery.git 保存阶段。

## 真机 ABI B：loader / plist / 播放器静态清单

第一阶段 recovery.git 18eb7e2。第二阶段反汇编确认 beigelist7 BLAppManager 在 mainBundle.bundlePath/Appliances 枚举 frappliance，load 后取 principalClass，实例化走 initWithApplianceInfo:nil。发现入口为 /Applications/AppleTV.app/Appliances/Jellyfin.frappliance（绝对宿主路径仍需运行时确认），现有 package.sh 已建立到 /Applications/Jellyfin.frappliance payload 的符号链接，不能误判为只装顶层路径。CFBundleIdentifier/CFBundleName 为该加载路径使用的键；LegacyApplianceClass 是 associated-object key，不是必需 plist 字段。

docs/device-abi-12H1006.md 完成逐项 UI ABI、继承、loader、字段与后续修改清单。analysis/player-api.md 保存四个 BR player 类的完整直接方法表。BR 播放时间 double、起播位置/音量 float 等有元数据；AVPlayer/AVPlayerItem/AVPlayerLayer 仅外部类引用，ABI 和播放能力仍未验证。未实现播放器，未改生产源码/冻结包，未 SSH/安装/重启。源码必须后续修复 float 分类 order 和 required textDidChange:；真实 UI、遥控语义、链接加载、解码与字幕仍 NOT RUN。所有阶段只提交 recovery.git。

续跑从 recovery status/log 确认只有 18eb7e2，未提交内容均为上述分析成果，没有代码改动。补齐 BRApplianceInfo 字段读写反汇编：identifier/name/categoryDescriptors/supportedMediaTypes/requiredRemoteMediaTypes 与 float order；不把原生描述字典要求套到 beigelist bundle。BRBaseAppliance -init 直接 nil，loader 使用 initWithApplianceInfo:nil，fixture 后续据此修正。新增 docs/device-player-api-12H1006.md，区分 VERIFIED METHOD + ABI、METHOD NAME PRESENT ONLY、CLASS REFERENCE ONLY、NOT FOUND。静态审计完成，下一阶段执行本地修正与测试。

## 真机 ABI C：证据驱动 runtime 修正

修正 category factory 为精确 float 参数（f），不再接受未经本固件证明的整数 order；class/selector/编码不匹配则拒绝注册。BREvent 只接受真机 int32 action/value 与 uint32 originator，避免 unsigned 值按 signed 解读；列表 selection 精确匹配 long。补齐 required textDidChange: no-op，缺少或不匹配菜单/文本协议时拒绝使用。新增 init 签名门禁，保留动态类查找与 objc/runtime 架构。测试按 initWithApplianceInfo:nil 初始化 appliance，并证明 BRAppliance 是 protocol 而非 class。

首轮 make test-ui test 全部通过：221 UI 主流程断言、13 独立拒绝场景（原 4 + 新 9），184 基础断言。新场景含 float 分类成功、整数错误编码/缺失 factory/class、缺失协议/selector、init 错误编码、long/int 差异、事件错误返回编码；日志 device-evidence/12H1006/analysis/abi-first-tests.log。未运行设备。前一提交 diff --check 指出 player-api.md 末尾额外空行，本阶段已修正；不将此前检查记为通过。全量回归、ASan、ARMv7/包验证待下一阶段。

## 真机 ABI D：打包契约与离线回归

ABI 修正恢复点 3db0932。make test-offline test-asan 完成：184 基础 + 177 session + 49 host + 221 UI + 179 playback/subtitle = 810 主流程断言，另 13 ABI 拒绝场景。ASan playback/UI/session 各 179/221/177 全部通过（不含 leak detector）。HTTP 基础 184 复跑、integration loopback 全链路/退出码负例、playback HTTP 18、Foundation 自签名拒绝、TLS 4 均通过；HTTP integration 日志里的预期 FAIL 是负例输出，runner 总体退出 0。

包版本升为 0.5.1-deviceabi1、bundle 0.5.1，双路径不变。按 beigelist localizedInfoDictionary 读名逻辑补 English.lproj/InfoPlist.strings 与 development region；本机名称从 null 变为 Jellyfin。严格包验证新增字段/资源和 loader entry 检查；卸载/回滚加入双路径后置条件。Python integration 6、历史 package 12（1 个新资源测试对旧版本跳过）、deployment 8 全部通过。deployment 模拟首轮函数名含横线不被 sh 接受，次轮 /var 与 /private/var 路径比较失败，第三轮均修正通过；保留全部失败日志。

新候选 ARMv7 产物将额外运行 4 个 target ABI 测试，直接比较编译输出的 long/float/BOOL callback 编码与设备元数据，确认无 BR private class 链接依赖。下一步新目录干净构建、签名打包、候选 package 12 全部测试与 SHA256 封存。未部署或访问设备，主 .git 保持未写入。

## 最终封存：Ready for first Jellyfin device deployment

这是首次设备部署的**本地准备完成**状态，不是已安装/已加载/可播放声明。所有 Apple TV 运行项目仍 NOT RUN ON DEVICE；没有 SSH、安装、重启、kill、Substrate/Beigelist/系统文件修改。

候选来源：recovery.git `44290d3`，其后仅封存文档/验证记录，无生产源代码改动。版本 0.5.1-deviceabi1，bundle 0.5.1。

- deb：`build/package-freeze-deviceabi-12H1006-r1/org.jellyfin.atv3_0.5.1-deviceabi1_iphoneos-arm.deb`
- SHA256：`f204d818df94235278a020f7ee7f9d7e1a06638b5d2d0ec63faccd8a238d7a0e`
- 包内签名二进制 SHA256：`326922b54788f775eca85378280a0e9263b56ecdf2761ba74cca4aed0052b0e1`
- 新构建：`build/freeze-deviceabi-12H1006-r1`；证据：`logs/freeze-deviceabi-12H1006-r1/`。

VERIFIED OFFLINE：

| 验证 | 结果 |
|---|---|
| make test / session / host / UI / playback | 184 + 177 + 49 + 221 + 179 = 810 断言通过 |
| ABI negative/rejection | 13 独立进程场景通过（额外计数，不与主流程混算） |
| playback HTTP | 18 断言通过；与上项主流程共 828 条断言 |
| HTTP 基础 / integration | 基础 184 复跑通过；loopback 全流程与 401/500/超时/离线退出码契约通过，不重复计入 828 |
| Python | integration 6 + 新候选 package 12 + deployment 8 + TLS 4 + ARMv7 target ABI 4 = 34 tests，全通过 |
| ASan | playback 179 / UI 221 / session 177 通过，detect_leaks=0；重复执行不重复计数 |
| 干净 ARMv7 build | 新目录完整编译/严格链接成功；无编译 warning/error；目标 callback 编码 l/f/c 与设备一致 |
| 包 | 双路径链接、owner/modes、plist/本地化字段、ARMv7、签名存在、stage 字节一致、无 maintainer script、archive 可重复生成均通过 |
| codesign | --verify --strict 通过（Mac 验证，不代表设备 trust） |
| 部署工具 | 新候选 install dry-run 通过；未执行 SSH |
| 保留检查 | 主 .git 17 文件字节/文件集合未变；16 个历史 deb SHA256 未变 |
| diff | recovery.git diff --check 完成；仅末尾文档提交在此之后 |

原始日志：device-evidence/12H1006/analysis/abi-full-offline.log、abi-http-tls-final.log、abi-deployment-r3.log；候选 package-tests.log / target-abi-tests.log / armv7.log / package.log 位于新 freeze 日志目录。旧包资源用例跳过不计作新候选成功；最终新候选 12 tests 无跳过。早期两个 deployment fixture 失败已修正并保存日志，不掩盖为首次全部通过。工具链只有 Perl locale fallback 提示，无 ARMv7 编译警告。

剩余设备验收：确认实际 mainBundle 路径及符号链接解析、代码签名信任/依赖解析、constructor 注册和 principalClass、分类显示、菜单生命周期、遥控枚举/原点、输入提交/掩码/取消，以及真实 Jellyfin 服务与 TLS。用户提供的设备 bootstrap/SSH 状态不重复处理。当前没有已知未修复的静态 ABI 阻塞；上述动态结果都未执行。

播放器后续仍独立：BR 方法 ABI 清单已建立，但 state 枚举、asset 构造、factory、回调语义、解码/profile、字幕与 HTTP 认证传播尚未确认；AVPlayer 系列是 class reference / selector name evidence。**没有真实播放器 backend，首次部署只验收 appliance/UI。**

18eb7e2 之后的逻辑阶段提交：c13801f（loader/player 审计）、3db0932（runtime ABI 修复与拒绝回归）、44290d3（loader 名称资源/打包契约）。最终封存提交见 recovery.git HEAD。

## 2026-10-02 首次部署预检尝试

候选 0.5.1-deviceabi1 SHA256 与指定值一致，包及 stage 校验 VERIFIED STATIC。当前会话 SSH 认证被拒绝，设备预检、备份、安装、loader、principal class、symlink 动态解析、crash/syslog 均 NOT RUN；UI/Remote/生命周期/键盘均 NOT REACHED。真实服务器 NOT RUN。没有设备修改或代码修复，不把静态验证计为 PASS ON DEVICE。详见 [首次部署记录](docs/device-first-deployment-12H1006.md)。

## 2026-10-02 SSH 恢复后首次真机预检 r1

PASS ON DEVICE：atv3 root SSH、AppleTV3,2 / iOS 8.4.4 / 12H1006、宿主 7.9 / 8163、apt-get check、空间和宿主进程；四个支持包安装状态正常（patcyh 正确 ID 为 com.saurik.patcyh）。FAIL ON DEVICE（安装前门槛）：dpkg --audit 非空，多个包缺少 md5sums；AppleTV.app/Appliances 不存在。按要求停止，未上传安装、未改系统包或加载器、未重启。loader/principal class/symlink 解析 NOT RUN；UI/六键/生命周期/键盘各项 NOT REACHED；真实服务器 NOT RUN；Ready for real playback device validation=否。候选 SHA256 未变。原始预检与 dpkg 参考归档保存在 device-evidence/12H1006/pre-first-deploy，仅本地保存；审阅摘要和散列纳入 recovery.git。详见 device-first-deployment-12H1006.md 最新节。
