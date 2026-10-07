# 阶段 4C：代码核对与实施范围

恢复基点为 recovery.git `5567ea1`，工作区原本干净。该提交已加入
Tests/integration.m、integration.py、TLS runner 和 Makefile 入口，属于已保存的
集成测试起点；PROGRESS.md 原来只记到 4B。此次先分析，不改生产源码。

## 现有结构

- JFClient：同步 HTTP/HTTPS、系统默认 TLS 信任、拒绝重定向、超时/取消、
  8 MiB 响应限制、登录与媒体 API；图片共用传输并使用 JFImageCache。
- JFWorker/JFTask：串行后台执行、主线程交付、取消抑制待交付回调。
  取消不能回滚已经发生的模型变更。
- JFBrowser：登录、媒体层级、焦点与返回历史、快照；由同一 worker 独占。
- JFBackRow：运行时 ABI 检查、controller 创建和遥控通知。尚无列表绘制、
  登录输入或 session 生命周期绑定；Menu 当前直接尝试 popController。
- Makefile：手动引用计数、blocks、iOS 8.0 基线、严格 ARMv7 bundle 链接。
  Tests/main.m 使用 Mac runtime mock，不能证明固件 8163 兼容。

## 后续小阶段与文件

1. **4C.1 集成入口收口**：修改 Tests/integration.py、integration.m、run.py、
   Makefile 和 README.md，补入口参数/类型校验、固定脱敏输出及退出码测试。
   fixture 默认未提供 library，分页目前 SKIP；应另设精确 fixture 用例覆盖。
   TLS 错误判定应同时校验错误 domain/code，不能只靠整数范围。
   保持匿名管道输入凭据、HTTP 显式选择、默认系统证书验证及无自动重试。
   已有 JFClient 传输不重写；仅在测试证实问题时局部修改。
2. **4C.2 独立 UI 会话适配**：新增 Sources/Navigation/JFSession.{h,m}，
   在主线程接受登录、刷新、导航、注销与关闭命令，内部独占 browser/worker，
   交付快照、busy 状态和有限错误信息。以会话代次阻止旧回调覆盖新会话；
   明确快速重复操作的排队/拒绝规则。注销和关闭须串行清会话，不能只 cancel。
   不向 UI 暴露可跨线程调用的 client/browser，不保存密码或 token。
   Tests/main.m（或独立 session 测试文件）覆盖主线程交付、401、登录后库请求失败、
   新旧登录竞争、关闭期间请求、注销、焦点/返回和宿主释放。
3. **4C.3 宿主边界与验收**：为 session 定义可 mock 的事件及关闭边界，
   确认 Menu 由模型还是宿主消费；如修改 JFBackRow.m，必须补 runtime mock
   测试。缺少 8163 列表、输入和生命周期接口证据时不猜测 selector 或宣称
   完成真实 UI。更新 README.md、PROGRESS.md，运行回归与 ARMv7 构建。

每个实现小阶段完成测试后单独提交 recovery.git，并更新 PROGRESS.md。
不初始化 Git，不写主 .git，不部署，不假设设备或真实服务器可用。

## 本次实际验证

- make test：184 断言通过，logs/phase4c-baseline.log。
- make test-integration-fixture：登录、库、详情、两类图片、注销通过；分页 SKIP，
  logs/phase4c-integration-fixture.log。
- make shell BUILD=build/phase4c-baseline：全量 ARMv7 严格链接成功、无警告，
  logs/phase4c-baseline-build.log；lipo 确认为 armv7。
- make test-http 和 make test-tls-negative：沙箱内 bind 被禁止，runner 77，
  记录于 phase4c-http.log、phase4c-tls-negative.log。
- 在获准的沙箱外重跑：HTTP 184 断言通过，自签名证书被拒绝，分别见
  logs/phase4c-http-permitted.log、logs/phase4c-tls-negative-permitted.log。

没有提供真实 Jellyfin 地址/测试账号，真实服务认证及可信 HTTPS 成功路径尚未验证。
本地 HTTP fixture 与 TLS 负例不能替代上述验证；本次未接触真实设备。

## 执行结果

三个子阶段已按此范围实现，详见 PROGRESS.md 的 C.1–C.3 和
[宿主契约](phase4c-host-boundary.md)。C.1 提交 0d1d402，C.2 提交 4b36b10，
C.3 提交以 recovery.git log 为准。原有生产模块保持不变；新增会话与宿主适配器。
真实服务器/可信 HTTPS 成功及 8163 UI 接线仍属于待提供环境/接口证据的验证范围。
