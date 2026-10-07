# Phase 4D：BackRow UI 接线

起点 c82238a，recovery.git 工作区干净。网络、worker、browser、JFSession 和 JFSessionHost 保持不变；只扩展 BackRow/UI 边界及测试。

## 接口证据与设计

本地 KodiController.mm 的 controlWasActivated/controlWasDeactivated 支持激活/停用回调；从 nitoTV 原仓库只读下载 build/evidence-nitotv，固定提交 c0c030b64bea586aed1ae3772f89c12bc2ebc60a。参考 Classes/nitoFilesController.{h,m} 的 BRMediaMenuController/list/setDatasource:/setListTitle:/itemCount/itemForRow:/rowSelectable:/titleForRow:/heightForRow:/itemSelected:，以及 iosDefaults/theos/include/BackRow 的 BRController、BRListControl、BRMenuItem、BRThemeInfo、BRTextEntryController 头文件。Classes/nitoRssController.xm 提供文本输入 delegate、stringValue 和 push/pop 用法。

这些是旧 BackRow 源码/接口证据，不是 8163 实机 ABI 证明。不引入私有头文件、复制第三方实现、Substrate 或外部库。使用运行时签名验证和动态子类，保留 ARMv7、MRC、严格链接。

## 子阶段

1. 4D.1：新增受检 runtime 调用和菜单 renderer/data source；JellyfinController 在完整菜单能力存在时继承 BRMediaMenuController，缺失时保留原 shell。接入 activate/deactivate/wasPopped/dealloc。停用仅解绑，出栈关闭；构造/异常路径拒绝不兼容 ABI。补 runtime mock 后提交。
2. 4D.2：新增 UI presentation 层，主界面配置服务器/用户名，密码编辑完成后直接调用现有 JFSession。显示 libraries/media/type/detail/busy/empty/error；密码不保存。运行 UI 测试后提交。
3. 4D.3：从 brEventAction 直接路由规范化遥控事件（不通过通知接线），统一焦点和 Menu；输入子页由系统处理。验证逐层返回、刷新/注销、重入、宿主释放、错误和 ABI 拒绝。更新文档，回归/ARMv7 后提交。

每阶段更新 PROGRESS.md，提交 recovery.git；不修改主 .git，不部署。实机可见 UI、输入掩码效果、固件生命周期、真实服务器认证需单独验证。

## 执行结果

D.1 已提交 d8eff55；D.2 已提交 0519eed；D.3 提交以 recovery.git log 为准。
三个实现阶段完成，验收与实际限制见 phase4d-ui.md 和 PROGRESS.md。
