# Phase 4C 宿主与会话契约

本文件保留 4C 时的独立边界记录。Phase 4D 已实现 controller 直接事件路由与 UI 生命周期，现状见 [Phase 4D UI](phase4d-ui.md)；下文“当前 shell 未接线”描述仅适用于 4C。

`JFSessionHost` 是可独立测试的主线程事件/关闭适配器，不注册私有 selector，不创建 BackRow 列表或输入控件。当前 `JFBackRow.m` 保持原有外壳行为；8163 上的真实接线须等待列表、输入、事件线程和 controller 生命周期证据。

## 事件所有权

宿主先用已验证的事件解码路径获得 JFRemote 的 button/phase 字典，再且仅再调用一次 `handleRemoteEvent:`。

| 条件 | 结果 | 宿主责任 |
| --- | --- | --- |
| 非法/未知事件、已关闭、非主线程调用 | Unhandled | 交给已有宿主处理；非主线程须另行确认事件线程契约 |
| busy 时的已知事件 | Consumed | 丢弃，不排队，不 pop |
| 登录页/库列表根页 Menu press | ExitRequested | 宿主决定是否退出；适配器自身不 pop 或 close |
| 更深层 Menu press | Consumed | 会话排队返回一级，保留焦点；宿主不得再次 pop |
| Menu release/hold/repeat | Consumed | 不重复返回或退出 |
| 上/下 press/hold/repeat | Consumed | 会话更新焦点；busy 时拒绝重复命令 |
| 库列表 Select press | Consumed | 进入独立模型的库页；类型选择由未来 UI 显式调用 openLibraryWithType: |
| 媒体列表 Select press | Consumed | 按快照焦点打开电影/剧集/季/集，网络在 worker 上执行 |
| 详情 Select、左右、其它已知 release | Consumed | 暂无播放或额外导航行为 |

`ExitRequested` 是意图，不等于成功移除 controller。宿主可拒绝退出，此时会话保持可用。确认执行移除时，先解除 UI 观察者，再 close，再执行已验证的宿主移除操作。禁止把 busy 时 session 的 NO 返回值解释为根页退出。

**当前 shell 的 `JFRemoteEvent` 通知不是此适配器的可取消事件入口。** 原 shell 会在通知之后自行处理 Menu/pop；直接订阅通知并调用适配器会造成双重处理。因此本阶段不自动订阅该通知。未来接线时须在原 Event 路径中先依据适配器结果决定消费/退出/回退，并增加 runtime mock 回归；不能只加一个 notification observer。

## 生命周期与线程

1. 宿主在主线程创建 JFSession（服务器 URL、稳定 deviceID、显式 allowHTTP），再创建 JFSessionHost。两者不暴露 worker/client/browser。
2. UI 仅观察对应 session 的 JFSessionChanged 并读取 snapshot、busy、errorKind；不要跨线程读这些属性。通知可同步重入，完成时 busy 已为 NO。
3. 普通动作 busy 时返回 NO，login 替换旧工作，logout 串行清模型。没有自动重试、隐式凭据保存或无限动作队列。
4. 注销仍允许再次登录。关闭是终态：解除观察者、adapter close、主线程 release adapter/session。外部直接 session close 时 adapter 也拒绝事件。
5. adapter 析构会 close session；session 析构也有清理兜底。交付对象不保留宿主/session，关闭立即切断旧交付；后台 logout 在同一 worker 上等待在途请求结束，取消不能回滚已经发生的服务端行为。
6. 不强捕获宿主/session 到 notification block；宿主负责移除自己的 observer。session close 不发送通知，宿主自行关闭界面。已关闭的 session 不复用，重新进入须创建新实例。

`Tests/host.m` 用 mock 宿主和真实 session + NSURLProtocol fixture 验证 49 个断言，包含逐层 Menu、根退出意图、busy 丢弃、press/release 区分、Select 网络导航及宿主释放；`Tests/main.m` 原 runtime mocks 继续验证现有 BackRow 外壳。它们均不构成 8163 ABI/加载顺序/可见 UI 的证据。
