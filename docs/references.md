# 参考与接口证据

以下本地文件只读查看，没有复制 Kodi 实现代码或改动外部目录：

- `~/Downloads/AppleTV3/Kodi-Helix/xbmc/osx/atv2/KodiAppliance.mm`：`initApplianceRuntimeClasses` 使用 objc_allocateClassPair / objc_registerClassPair；BRBaseAppliance、BRApplianceCategory；categoryWithName:identifier:preferredOrder:、applianceCategories、controllerForIdentifier:args:。Kodi 注释描述旧系统将类移入 AppleTV.app，不能据此认定 8163 完全相同。
- 同目录 `KodiAppliance.h`：原继承关系，仅作证据，不用该私有头文件构建。
- 同目录 `KodiController.mm`：约 143–166 行事件编号，435 行起 remoteAction / originator / value；311 行 stack / popController；1352 行 BRController 运行时子类。8/9 对应左右持续操作，22/23/24 对应中心键长按；没有使用 0xfeed0001 等 Kodi 自定义事件冒充固件事件。
- 同目录 `XBMCATV2-Info.plist.in`：BNDL、NSPrincipalClass、FRApplianceName、FRApplianceDataSourceType、FRRemoteAppliance 和历史拼写 FRAppliancePreferedOrderValue。
- `~/Downloads/AppleTV3/Kodi-Helix/tools/darwin/packaging/atv2/mkdeb-atv2.sh.in`：Applications 下 frappliance 与 AppleTV.app/Appliances 的软链接关系。未执行脚本，也未生成其设备修改行为。
- `~/Downloads/AppleTV3/Blackb0x-source/Blackb0x/Files/setup.sh`：69/79 行移动并安装 beigelist_2.2.6-30_iphoneos-arm.deb；94–105 行涉及 appliance 目录。当前本地材料没有 Beigelist 加载器源代码或该 deb，不能确认扫描、过滤、初始化调用顺序。项目按 appliance bundle + constructor 注册组织，加载时机待验证。

公开 Jellyfin 接口依据（查询日期 2026-09-27）：

- [Jellyfin UserController](https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/UserController.cs)：用户名认证入口。
- [Jellyfin UserViewsController](https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/UserViewsController.cs)：当前 UserViews 路由；Users/{userId}/Views 保留为兼容路由。本阶段选用后者以兼容旧服务器。
- [官方 SDK 认证指南](https://kotlin-sdk.jellyfin.org/guide/authentication.html)：认证后持有访问令牌。

公开接口与本地模拟测试不是实际 Jellyfin 服务器版本的端到端认证证据。

第三阶段媒体 API 参考（2026-09-27）：

- [官方 Python 客户端 API](https://github.com/jellyfin/jellyfin-apiclient-python/blob/master/jellyfin_apiclient_python/api.py)：媒体查询、季/集、详情及播放信息接口。
- [官方 TypeScript 生成的媒体接口](https://github.com/jellyfin/jellyfin-sdk-typescript/blob/master/src/generated-client/api/library-api.ts)：Items 的用户、类型、父级和分页参数。
- [官方 SDK GetEpisodes 参数](https://typescript-sdk.jellyfin.org/interfaces/generated-client.ShowApiGetEpisodesRequest.html)：Series/Season 筛选。

这些是路由和参数依据，自动 fixtures 仅验证客户端构造与处理；真实服务和设备兼容性仍未验证。

Phase 4D BackRow UI 接口依据（2026-09-28，固定提交，不代表 8163 验证）：

- [nitoTV c0c030b 的原生菜单实现](https://github.com/lechium/nitoTV/blob/c0c030b64bea586aed1ae3772f89c12bc2ebc60a/Classes/nitoFilesController.m)：BRMediaMenuController、setListTitle:、list/setDatasource:、menu item/theme 和 provider callbacks。
- [BRController 接口](https://github.com/lechium/nitoTV/blob/c0c030b64bea586aed1ae3772f89c12bc2ebc60a/iosDefaults/theos/include/BackRow/BRController.h)：wasPopped、stack；同目录 BRMediaMenuController.h 为激活/停用和 preview 回调，BRListControl.h 为 reload/selection，BRTextEntryController.h 为输入 delegate/文本/显示控制。
- [文本输入使用](https://github.com/lechium/nitoTV/blob/c0c030b64bea586aed1ae3772f89c12bc2ebc60a/Classes/nitoRssController.xm)：BRTextEntryController、textDidEndEditing:、sender stringValue、push/pop。
- [数据源协议](https://github.com/lechium/nitoTV/blob/c0c030b64bea586aed1ae3772f89c12bc2ebc60a/Lowtide/BRMenuListItemProvider.h)：native long 行号/数量、float height、BOOL selectable。

仅分析接口及调用关系，没有复制第三方实现代码或使用私有头文件参与编译。只读源码副本位于 build/evidence-nitotv；运行时还会验证实际 signature，四种不兼容条件已有独立 mock 测试。真实密码显示、键盘行为、生命周期线程与加载顺序仍待设备验证。
