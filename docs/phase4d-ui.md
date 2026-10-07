# Phase 4D UI 与验收

## 用户流程

FRAppliance 的 Jellyfin 分类通过 `controllerForIdentifier:args:` 创建 JellyfinController。菜单接口完整时，它动态继承 BRMediaMenuController；不依赖私有头文件、Substrate、UIKit 或第三方运行库。

进入后显示 Server address、Username、Sign in、Allow HTTP。先输入最终服务器地址（可带 /jellyfin 部署路径）和用户名，再选择 Sign in 输入密码。HTTPS 保持系统证书验证；HTTP 必须主动打开 Allow HTTP。密码字段要求运行时具有 `setShowUserEnteredText:` 并设置 NO，否则禁用该输入；实际掩码/隐藏效果仍待设备确认。

认证成功后显示媒体库名字，以及 Refresh libraries、Sign out。选择库后选择 Movies 或 TV shows；电影打开详情，电视剧依次打开季、集和详情。列表为空时显示提示；请求期间标题显示 Loading，暂时丢弃遥控操作；失败显示有限错误类别。媒体分页通过 Load more 触发。详情目前只显示说明和返回，没有播放入口。

Apple Remote 上/下移动可选行，Select 短按选中。Select hold/repeat 不重复提交。Menu 在详情/媒体/类型页返回一级，在登录或媒体库根页退出；Menu hold/repeat/release 不重复退出，busy 时不退出。返回媒体/库列表恢复模型焦点；从底部操作行回到列表时恢复上次模型焦点。

服务器和用户名仅在当前 UI 内存；退出后需重新输入。密码仅在输入控件和当次登录任务内短暂持有，完成/取消/关闭时清空控件并解除 delegate，不写 defaults/文件。仅 `JFDeviceID` 保存至当前进程 defaults，提供稳定设备标识。未新增 token 持久化或 Keychain。

## 分层与生命周期

- `JFBackRow`：动态创建 appliance/controller，受检调用 superclass；直接解码并路由 Apple Remote，拥有唯一 pop 决策。UI 路径不再发布 JFRemoteEvent 让其它观察者驱动同一次导航。
- `JFBRMenu`：runtime 调用验证、列表数据源、标题与选择。列表持有 data source，data source 不持有 controller；界面关闭清空行。
- `JFUIController`：presentation 和文本输入 delegate；持有现有 JFSession/JFSessionHost，只用主线程命令和快照。没有访问 client/browser/worker。
- 现有 Sources/API、Sources/Navigation、Sources/Input、JFSessionHost 与 c82238a 完全一致。

`controlWasActivated` 先调用原方法，再绑定观察者和渲染当前快照。`controlWasDeactivated` 先暂停观察和解除 list datasource，再调用原方法；会话继续存在，所以打开输入页不会注销。`wasPopped` 与 dealloc 关闭输入、移除观察者、关闭会话、解除 controller 引用，再调用原方法。根页 Menu 在确认 popController ABI 后先 close，再 pop。正常 UI/生命周期及释放要求主线程；非主线程遥控返回 NO。

输入 editor 由 UI 保留，delegate 只接受该 editor 当前 textField 的完成回调。完成时先复制文本、清空 editor/解除 delegate，再 pop，避免重新激活时误判为取消。用户直接取消输入时，重新激活主界面会清 editor，且不提交登录。出栈后旧请求的交付不能重附列表。`JFSession` 原有代次和串行关闭规则不变。

## 能力检查与证据

接口来源固定为 [nitoTV c0c030b](https://github.com/lechium/nitoTV/tree/c0c030b64bea586aed1ae3772f89c12bc2ebc60a)，本地只读副本在忽略目录 build/evidence-nitotv；结合本地 Kodi Helix 生命周期代码，见 docs/references.md。代码没有复制这些项目的实现。

注册时检查菜单 superclass 的 list、setListTitle:、itemSelected:、激活/停用/出栈等 ABI；存在 BRMenuListItemProvider runtime protocol 时还比对其回调签名。创建 controller 时检查 list 对象的数据源、reload、selection 和 menu item/theme 接口；不兼容则返回 nil。文本输入还单独验证 delegate、field、stack push/pop 和隐藏密码方法。整数 setter 按 runtime 的有符号 32/64 位编码调用，回调使用证据中的 native long；ARMv7 保持 MRC、blocks、iOS 8.0 工具链基线。

缺少 BRMediaMenuController 时保留旧 shell；该 fallback 不提供列表 UI。菜单类存在但 ABI 不兼容时不注册 UI，不以猜测接口继续调用。未解决缺少 BackRow 类时 constructor 的加载顺序问题；仍需真实 loader 确认。

## 实际验收与限制

`make test-phase4d`：原 410 Objective-C 断言、153 UI 主流程断言、4 个独立 ABI 拒绝场景，以及 4 个 Python 入口测试通过。UI mocks 用原 JFSession 和 NSURLProtocol fixture，覆盖真实主入口/生命周期回调、输入、登录/空库/错误、媒体层级、原始 remote 事件、焦点、busy、取消和释放。没有在这轮重新跑 socket/TLS；网络代码未变，保留 Phase 4C 的网络验证记录。

`build/ui-asan`：153 UI 断言通过，无 ASan 诊断，不等于泄漏检测。`make shell BUILD=build/phase4d-final`：ARMv7 严格链接通过、无警告，lipo 确认 armv7。产物 `build/phase4d-final/Jellyfin.frappliance` 未签名、未部署。

未提供设备与真实服务器：8163 实际加载/显示/输入键盘/密码隐藏/生命周期线程、真实 Jellyfin 登录及可信 HTTPS 成功仍未验证。列表代码和 mock 验收已经实现，不能把它们表述为电视上已成功运行。下一步应在已确认兼容的设备测试入口和输入→登录→库列表→返回；播放、海报视图和持久化登录不属于本阶段。
