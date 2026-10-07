# AppleTV 12H1006 / source 8163 真机静态 ABI 审计

当前状态：本地 ABI 修正和候选验证已完成，**Ready for first Jellyfin device deployment**。本文 `VERIFIED ON DEVICE` 均指 **VERIFIED ON DEVICE STATIC EVIDENCE**；实机运行仍 **NOT RUN ON DEVICE**。最终结果见末尾封存段。

日期：2026-10-02。输入为用户提供的 AppleTV3,2 / iOS 8.4.4 / build 12H1006 设备提取物；四份文件自身不能独立证明设备型号与 OS build。Info.plist 确认 com.apple.lowtide、source 8163、MinimumOSVersion 8.4；两份 Mach-O 均为 arm_v7。没有连接、安装或重启设备。

## 证据与判定边界

`VERIFIED ON DEVICE` 在本文表示设备提取物中的类定义/继承指针或具体类方法表/协议方法表已确认，包括方法编码；不是已在设备执行成功。`PRESENT BUT ABI NOT YET VERIFIED` 表示只有引用、字符串或缺少接收者/依赖实现；`NOT FOUND` 仅限这四份证据的搜索范围。字符串不用于推定签名。Foundation/libobjc 通用调用不冒充 BackRow 自有方法。

原始文件 SHA-256：
```
7fdd41ded47a510a0482585822d5633fb4dd464d3a6ad927bb37ce9d93036dfc  AppleTV
f2fb496226afdd8733b16f9880a3315110ad6b68dc57b32994d098b34ec3482b  Info.plist
9027b7b5135abd255308d639fd4ac411ed99b30c2eebbf2018ceef190ad1da22  beigelist7.dylib
b23d29a26771e044ab3a3fd16af1a63bfd00474ccb87335483880779f457c3ae  beigelist7.plist
```

复现：在 device-evidence/12H1006 中运行 `otool -ov AppleTV`、`otool -ov beigelist7.dylib`、`otool -tvV beigelist7.dylib`、`otool -l AppleTV`、`otool -L AppleTV`、`nm -nm`、`strings -a`；完整输出保存在 analysis/。`extract_metadata.py` 仅提取 classlist 中的直接方法和 metaclass，继承按 class 地址解析；不把其他同名 selector 当成本类方法。以下 L 为 analysis/AppleTV.objc.txt 行号；IMP 为未滑移地址（Thumb bit 保留）。

## Phase 4D 类及协议

| 类 | 直接父类 | 状态 |
|---|---|---|
| BRApplianceInfo `0xcdc1c0` | _OBJC_CLASS_$_NSObject | VERIFIED ON DEVICE |
| BRBaseAppliance `0xcdc1e8` | _OBJC_CLASS_$_NSObject | VERIFIED ON DEVICE |
| BRApplianceCategory `0xcdc198` | _OBJC_CLASS_$_NSObject | VERIFIED ON DEVICE |
| BRController `0xcdc38c` | BRControl | VERIFIED ON DEVICE |
| BRControl `0xcdc030` | _OBJC_CLASS_$_UIView | VERIFIED ON DEVICE |
| BRMediaMenuController `0xcdc3f0` | BRMenuController | VERIFIED ON DEVICE |
| BRMenuController `0xcdc490` | BRController | VERIFIED ON DEVICE |
| BRMenuItem `0xcdefb0` | BRControl | VERIFIED ON DEVICE |
| BRThemeInfo `0xcdcaf8` | _OBJC_CLASS_$_NSObject | VERIFIED ON DEVICE |
| BRTextEntryController `0xcdebc8` | BRMenuController | VERIFIED ON DEVICE |
| BRTextEntryControl `0xcde290` | BRControl | VERIFIED ON DEVICE |
| BRTextFieldControl `0xcde5d8` | BRControl | VERIFIED ON DEVICE |
| BRListControl `0xcdd6b0` | BRControl | VERIFIED ON DEVICE |
| BRControllerStack `0xcdc3a0` | BRControl | VERIFIED ON DEVICE |
| BREvent `0xcdca30` | _OBJC_CLASS_$_NSObject | VERIFIED ON DEVICE |
| BRApplianceManager `0xcdf8c0` | BRSingleton | VERIFIED ON DEVICE |

BRMenuListItemProvider、BRTextFieldDelegate、BRAppliance 均为 **VERIFIED ON DEVICE 协议**。BRAppliance 作为类为 **NOT FOUND**；不得据同名协议声称存在类。自定义 JellyfinAppliance/JellyfinController 由插件 constructor 注册，不应在宿主二进制出现。

## 全部 BackRow 调用与覆盖方法

| 使用接收者 / selector | 实际声明类 | 方法编码 | 证据 | 状态 |
|---|---|---|---|---|
| BRBaseAppliance `applianceCategories` | BRBaseAppliance | `@8@0:4` | L159940, 0x3671f1 | VERIFIED ON DEVICE |
| BRBaseAppliance `controllerForIdentifier:args:` | BRBaseAppliance | `@16@0:4@8@12` | L159949, 0x3672e9 | VERIFIED ON DEVICE |
| BRBaseAppliance `initWithApplianceInfo:` | BRBaseAppliance | `@12@0:4@8` | L159916, 0x366e99 | VERIFIED ON DEVICE |
| BRMediaMenuController `init` | BRMediaMenuController | `@8@0:4` | L162587, 0x374235 | VERIFIED ON DEVICE |
| BRMediaMenuController `dealloc` | BRMediaMenuController | `v8@0:4` | L162590, 0x3743c5 | VERIFIED ON DEVICE |
| BRMediaMenuController `brEventAction:` | BRMediaMenuController | `c12@0:4@8` | L162605, 0x3749e5 | VERIFIED ON DEVICE |
| BRMediaMenuController `controlWasActivated` | BRMediaMenuController | `v8@0:4` | L162638, 0x374df5 | VERIFIED ON DEVICE |
| BRMediaMenuController `controlWasDeactivated` | BRMediaMenuController | `v8@0:4` | L162641, 0x374f39 | VERIFIED ON DEVICE |
| BRMediaMenuController `wasPopped` | BRController | `v8@0:4` | L161264, 0x36e6e5 | VERIFIED ON DEVICE |
| BRMediaMenuController `itemSelected:` | BRMenuController | `v12@0:4l8` | L164882, 0x3845a5 | VERIFIED ON DEVICE |
| BRMediaMenuController `previewControlForItem:` | BRMediaMenuController | `@12@0:4l8` | L162584, 0x37505d | VERIFIED ON DEVICE |
| BRMediaMenuController `list` | BRMenuController | `@8@0:4` | L164990, 0x3833f9 | VERIFIED ON DEVICE |
| BRMediaMenuController `setListTitle:` | BRMenuController | `v12@0:4@8` | L164906, 0x384219 | VERIFIED ON DEVICE |
| BRMediaMenuController `stack` | BRController | `@8@0:4` | L161324, 0x36e1bd | VERIFIED ON DEVICE |
| BRController `init` | BRController | `@8@0:4` | L161306, 0x36ddf5 | VERIFIED ON DEVICE |
| BRController `brEventAction:` | BRController | `c12@0:4@8` | L161315, 0x36e069 | VERIFIED ON DEVICE |
| BRController `stack` | BRController | `@8@0:4` | L161324, 0x36e1bd | VERIFIED ON DEVICE |
| BRControllerStack `pushController:` | BRControllerStack | `v12@0:4@8` | L161799, 0x36ec61 | VERIFIED ON DEVICE |
| BRControllerStack `popController` | BRControllerStack | `v8@0:4` | L161802, 0x36ece5 | VERIFIED ON DEVICE |
| BREvent `originator` | BREvent | `I8@0:4` | L173610, 0x396b7d | VERIFIED ON DEVICE |
| BREvent `remoteAction` | BREvent | `i8@0:4` | L173598, 0x396b09 | VERIFIED ON DEVICE |
| BREvent `value` | BREvent | `i8@0:4` | L173601, 0x396b19 | VERIFIED ON DEVICE |
| BRApplianceCategory `+categoryWithName:identifier:preferredOrder:` | BRApplianceCategory | `@20@0:4@8@12f16` | L159720, 0x365ab5 | VERIFIED ON DEVICE |
| BRThemeInfo `+sharedTheme` | BRThemeInfo | `@8@0:4` | L175211, 0x39b8e1 | VERIFIED ON DEVICE |
| BRThemeInfo `menuTitleTextAttributes` | BRThemeInfo | `@8@0:4` | L174899, 0x39dd4d | VERIFIED ON DEVICE |
| BRMenuItem `init` | BRMenuItem | `@8@0:4` | L219509, 0x45d921 | VERIFIED ON DEVICE |
| BRMenuItem `setText:withAttributes:` | BRMenuItem | `v16@0:4@8@12` | L219563, 0x45e08d | VERIFIED ON DEVICE |
| BRListControl `setDatasource:` | BRListControl | `v12@0:4@8` | L191574, 0x3db5f9 | VERIFIED ON DEVICE |
| BRListControl `reload` | BRListControl | `v8@0:4` | L191571, 0x3db4c9 | VERIFIED ON DEVICE |
| BRListControl `setSelection:` | BRListControl | `v12@0:4l8` | L191637, 0x3da599 | VERIFIED ON DEVICE |
| BRTextEntryController `init` | BRTextEntryController | `@8@0:4` | L213239, 0x441c21 | VERIFIED ON DEVICE |
| BRTextEntryController `setTextFieldDelegate:` | BRTextEntryController | `v12@0:4@8` | L213281, 0x442fdd | VERIFIED ON DEVICE |
| BRTextEntryController `setInitialTextEntryText:` | BRTextEntryController | `v12@0:4@8` | L213284, 0x442ffd | VERIFIED ON DEVICE |
| BRTextEntryController `setTextEntryTextFieldLabel:` | BRTextEntryController | `v12@0:4@8` | L213278, 0x442e95 | VERIFIED ON DEVICE |
| BRTextEntryController `editor` | BRTextEntryController | `@8@0:4` | L213257, 0x44228d | VERIFIED ON DEVICE |
| BRTextEntryController `setShowUserEnteredText:` | BRTextEntryController | `v12@0:4c8` | L213290, 0x4430b9 | VERIFIED ON DEVICE |
| BRTextEntryControl `textField` | BRTextEntryControl | `@8@0:4` | L202862, 0x410441 | VERIFIED ON DEVICE |
| BRTextFieldControl `stringValue` | BRTextFieldControl | `@8@0:4` | L205571, 0x41c901 | VERIFIED ON DEVICE |

数据源与 delegate 回调：

| 协议 / selector | 编码 | 证据 | 状态 |
|---|---|---|---|
| itemCount | `l8@0:4` | L301145 | VERIFIED ON DEVICE |
| heightForRow: | `f12@0:4l8` | L301148 | VERIFIED ON DEVICE |
| rowSelectable: | `c12@0:4l8` | L301151 | VERIFIED ON DEVICE |
| titleForRow: | `@12@0:4l8` | L301154 | VERIFIED ON DEVICE |
| itemForRow: | `@12@0:4l8` | L301157 | VERIFIED ON DEVICE |
| textDidEndEditing: | `v12@0:4@8` | L296914 | VERIFIED ON DEVICE |
| textDidChange: | `v12@0:4@8` | L296911 | VERIFIED ON DEVICE |

`textDidChange:` 是真机 BRTextFieldDelegate 的 required 方法，审计基线 JFUIController 只实现 textDidEndEditing:；现已补齐并通过离线回归，设备调用路径仍待验。通用 alloc/retain/release/autorelease、methodSignatureForSelector:、instanceMethodSignatureForSelector: 等依赖 Foundation/libobjc（未提供库实现），完整接收者 ABI 标记 **PRESENT BUT ABI NOT YET VERIFIED**。NSObject 协议有部分声明不等于类实现。

## 已确定的问题与待验证项

1. **必须修正 Categories 的 order 类型。** 真机是 `@20@0:4@8@12f16`，审计基线仅允许 i/q/I/Q，返回空数组；现已为 f 使用真实 float 存储，继续严格拒绝不支持类型。不能直接把整数零地址当作浮点参数设计。
2. 菜单协议 long/float/BOOL 的设备编码分别 l/f/c；当前原型相符。保留运行时签名检查，不据静态证明移除门禁。
3. textDidEndEditing: 的签名已证实，但 sender 身份、输入提交顺序、掩码表现、取消/弹栈重入与生命周期语义未运行验证。
4. originator/remoteAction/value 的整数 ABI 已证实，originator==1 和遥控动作枚举语义尚未据这次审计确认。
5. 对象返回 @ 不编码具体动态类：list→BRListControl、editor→BRTextEntryControl、textField→BRTextFieldControl、stack→BRControllerStack 是代码使用契约；本表验证这些类的方法，不能替代真实对象链验证。
6. 原静态审计阶段没有修改生产代码；后续 ABI C/D 已执行证据驱动修正，冻结旧包不变。


## beigelist7 loader、路径与 bundle 要求

beigelist7.plist 的 Filter.Bundles 为 com.apple.lowtide，CoreFoundationVersion 下界为 847.27；dylib 日志版本 2.2.6。nm 确认导入 MSHookMessageEx；反汇编 0x7cb4/0x7cb8 是 _loadApplianceWithInfo: 的 hook 安装。加载器自身 BLAppManager 方法编码来自 beigelist7.objc.txt，不能用 AppleTV 中的同名 selector 替代。

| 接收者 / selector | 编码 | 状态 |
|---|---|---|
| BRApplianceManager loadAppliances | `v8@0:4` | VERIFIED ON DEVICE |
| BRApplianceManager _loadApplianceWithInfo: | `@12@0:4@8` | VERIFIED ON DEVICE |
| BRApplianceManager _applianceForInfo: | `@12@0:4@8` | VERIFIED ON DEVICE |
| BLAppManager loadAppliances / _loadAppliances / reloadAppliances | `v8@0:4` | VERIFIED ON DEVICE |
| BLAppManager applianceWithIdentifier: | `@12@0:4@8` | VERIFIED ON DEVICE |
| BLAppManager +sharedAppManager | `@8@0:4` | VERIFIED ON DEVICE |

**loader 发现路径是 `<NSBundle.mainBundle.bundlePath>/Appliances/Jellyfin.frappliance`。** 不是直接扫描 /Applications。对于位于 /Applications/AppleTV.app 的宿主，对应 `/Applications/AppleTV.app/Appliances/Jellyfin.frappliance`。AppleTV 自身也包含 /Applications/AppleTV.app 字符串，但绝对 mainBundle 路径仍须运行时只读核对；这次没有文件系统采样，不能把字符串当作安装位置测量。

具体控制流（analysis/loader-disassembly.txt，按 VM 地址）：

- 0xa924 mainBundle → 0xa934 bundlePath → 0xa950 stringByAppendingPathComponent:@"Appliances"。
- 0xa970 defaultManager → 0xa982 enumeratorAtPath: → nextObject；0xab30 pathExtension → 0xab40 isEqualToString:@"frappliance"，不匹配跳至下一项。
- 0xab54 拼完整路径 → 0xab6a bundleWithPath: → 0xab8c load；失败分支到 0xacb6，记录失败。
- 成功后 0xab9c principalClass，0xaba8 infoDictionary；0xabda setLegacyApplianceClass: 保存得到的类；0xabe2 localizedInfoDictionary 用于名称；0xac02 从 infoDictionary 取 identifier。
- 0x9f0c legacyApplianceClass → 0x9f1e alloc → 0x9f30 initWithApplianceInfo:nil（r2 在 0x9f26 明确置零）。BRBaseAppliance 提供该初始化方法；不能假定 loader 一定调用插件的 init。

常量解析脚本 resolve_loader.py 按 Mach-O segment 映射解析 Thumb PC 相对引用，输出 beigelist7.constants.txt；它不是完整控制流模拟器。这里的调用/分支结论另对原始反汇编核对，外部未绑定指针不解释成运行时对象。

现有 Scripts/package.sh:39 **已经**创建：

```
/Applications/AppleTV.app/Appliances/Jellyfin.frappliance
  -> /Applications/Jellyfin.frappliance
```

所以 `/Applications/Jellyfin.frappliance` 可作为 payload 存放位置，Appliances 下的入口才是 loader 发现位置。现有方案静态上符合发现规则，不能声称必须把 payload 搬进宿主。Foundation 对该设备链接的实际解析、权限、代码加载仍 NOT RUN；不删除旧入口、不改包、不部署。部署工具/文档需明确区分 payload 与 discovery path，保留二者存在和链接目标检查。

当前 Jellyfin.frappliance/Info.plist 审计：

| 字段 | 当前值 / 证据 | 结论 |
|---|---|---|
| CFBundleExecutable | Jellyfin；loader 调 NSBundle load | 名称匹配；真机签名/依赖加载未运行验证 |
| NSPrincipalClass | JellyfinAppliance；loader 在 load 后取 principalClass | 结构符合；constructor 必须成功注册类，否则无法获得可用 principal class |
| CFBundleIdentifier | org.jellyfin.atv3；0xac02 读取 kCFBundleIdentifierKey 并设置 merchant identifier | 已提供；不是要求额外 FRApplianceIdentifier 的证据 |
| CFBundleName | Jellyfin；localizedInfoDictionary 的 kCFBundleNameKey 用于 title | 已补本地化资源；本机读取为 Jellyfin，设备标题仍 NOT RUN |
| FRAppliancePreferedOrderValue | integer 5；0xace2 fallback 读取，0xacf8 floatValue | NSNumber 整数可供 floatValue 转换；拼写 Prefered 与 loader 一致 |
| FRApplianceName | Jellyfin；AppleTV 字符串/信息对象相关证据 | 存在不等于 beigelist 直接读取此字段；不可代替 CFBundleName |
| FRHideIfNoCategories | false；AppleTV 相关证据 | 不可用此字段掩盖 Categories 的 float ABI 问题 |
| FRApplianceDataSourceType / FRRemoteAppliance | All / true | NOT FOUND（本次两份二进制字符串）；无依据宣称必需或有效 |
| FRApplianceIdentifier / FRApplianceCategoryDescriptors | 当前未提供；AppleTV 中存在键名 | 不据字符串强加 plist 要求；beigelist 路径使用 CFBundleIdentifier 和 principal class，分类由 applianceCategories 提供 |
| LegacyApplianceClass | 当前未提供 | 0x9ec4–0x9ef0 用作 associated-object key；class 从 principalClass 写入，不应误加为必需 plist 字段 |
| BLMerchantPreferedOrderValue | 未提供 | 优先于 FRAppliancePreferedOrderValue；可选 |
| BLForceLegacyNav / BLShowInFirstRow | 未提供 | 读取后 boolValue；可选，未据静态分析保证导航/首排实际效果 |
| AppIcon.png | loader 0xac54 pathForResource:ofType: | 图标资源可选分支；无图标时的视觉行为待验收 |
| MinimumOSVersion / platform / package type | 8.0 / iPhoneOS / BNDL | 不与宿主最低 8.4 冲突；不证明实际依赖支持，也不要求与宿主值相等 |

## 播放器 API 证据（仅清单，无实现）

完整直接方法表（包括 class methods、私有 helpers、编码、IMP 与元数据行号）见 [player-api.md](../device-evidence/12H1006/analysis/player-api.md)。BRMediaPlayer → NSObject；BRMediaPlayerController → BRController；BRMediaPlayerWaitControl → BRControl；BRMediaPlayerManager → BRSingleton，均 VERIFIED ON DEVICE（静态）。

| 接收者 / API | 编码 | 状态 |
|---|---|---|
| BRMediaPlayer setMediaAtIndex:inTrackList:error: | `c20@0:4l8@12^@16` | VERIFIED ON DEVICE |
| BRMediaPlayer cueMediaWithError: | `c12@0:4^@8` | VERIFIED ON DEVICE |
| BRMediaPlayer setState:error: | `c16@0:4i8^@12` | VERIFIED ON DEVICE |
| BRMediaPlayer playerState | `i8@0:4` | VERIFIED ON DEVICE |
| BRMediaPlayer rate / duration / elapsedTime | `d8@0:4` | VERIFIED ON DEVICE |
| BRMediaPlayer setElapsedTime: | `v16@0:4d8` | VERIFIED ON DEVICE |
| BRMediaPlayer setStartPosition: / setVolume: | `v12@0:4f8` | VERIFIED ON DEVICE |
| BRMediaPlayer bufferedRange | `{BRTimeRange=dd}8@0:4` | VERIFIED ON DEVICE |
| BRMediaPlayer subtitleOptions / audioOptions | `@8@0:4` | VERIFIED ON DEVICE |
| BRMediaPlayer setSelectedSubtitleOption: / setSelectedAudioOption: | `v12@0:4@8` | VERIFIED ON DEVICE |
| BRMediaPlayerController initWithPlayer: | `@12@0:4@8` | VERIFIED ON DEVICE |
| BRMediaPlayerController setAlwaysStopPlaybackWhenPopped: | `v12@0:4c8` | VERIFIED ON DEVICE |
| BRMediaPlayerWaitControl initWithAsset: / initWithOffer: | `@12@0:4@8` | VERIFIED ON DEVICE |
| BRMediaPlayerWaitControl setReadyToPlay / setAuthorizing | `v8@0:4` | VERIFIED ON DEVICE |
| AVPlayer / AVPlayerItem / AVPlayerLayer / AVURLAsset | nm 外部类引用 + AVFoundation load dependency | PRESENT BUT ABI NOT YET VERIFIED |

AVFoundation 未提供实现或 dyld cache，因此不借用本机 SDK 方法声明冒充 iOS 8.4.4 真机 ABI。AppleTV.nm.txt 还确认 AVPlayerItemDidPlayToEndTimeNotification、AVPlayerItemFailedToPlayToEndTimeNotification、AVPlayerItemPlaybackStalledNotification，以及 AVURLAssetHTTPHeaderFieldsKey、AVURLAssetHTTPCookiesKey、AVURLAssetOutOfBandAlternateTracksKey 的外部引用。这些是依赖/符号证据，不是可用性、HTTP 认证转发或字幕呈现保证。

尚未确认：BR player state 枚举数值、媒体 asset 构造契约、具体 player factory/子类、事件回调与 ownership、seek 精度、HTTP headers 的重定向策略、HLS/直播放协议兼容、音视频 codec/profile 上限、AC3 输出能力、字幕格式与 renderer。即使 setAC3Enabled: 存在，也不能宣布 AC3 可播。不得现在实现或接入播放器。

## 审计时提出的修改清单（完成状态见 ABI C/D）

- JFBackRow.m Categories：增加经精确签名检查的 float order 参数路径，并以 ARMv7 方法编码建立回归；当前入口分类存在确定缺陷。
- JFUIController：补齐 BRTextFieldDelegate required textDidChange:（可按业务选择安全 no-op），继续核对 delegate 调用/取消行为；只有 method encoding 不能确认 sender 语义。
- JFBackRow.h / 注册日志 / Phase 4D 文档：将笼统的“8163 unverified”改为“12H1006 静态 ABI 已审计，运行行为待验”；不要删除运行时门禁。
- Tests/ui.m 的 mock 必须增加真实 float 分类工厂和 BRTextFieldDelegate 契约；原 mock 通过不能抵消真机编码不匹配。
- deployment 文档应明确 Appliances 下发现入口与 /Applications 下 payload；现有符号链接布局已存在，本次没有证据要求迁移。
- 不盲加 FRApplianceIdentifier、FRApplianceCategoryDescriptors、LegacyApplianceClass；不改冻结 deb。下一轮代码修改和签名/打包须产生新候选。

第一阶段恢复提交：`18eb7e2`。第二阶段 loader/player 审计提交由 recovery.git 日志标识；不修改主 .git。

## 续跑补充：逐字段证据分级与原生信息对象

本节的 VERIFIED ON DEVICE STATIC EVIDENCE 仅证明指定读键/消费路径；不声称字段必填或插件运行成功。PRESENT BUT ABI/SEMANTICS NOT FULLY VERIFIED 保留为未完成语义验证。部署/UI/播放均 NOT RUN ON DEVICE。

| 字段 | 分级 | 方法/反汇编证据与边界 |
|---|---|---|
| NSPrincipalClass | PRESENT BUT ABI/SEMANTICS NOT FULLY VERIFIED | beigelist 在 0xab9c 调 NSBundle principalClass；标准 bundle 字段对应关系在离线包验证，Foundation 实现未提供 |
| CFBundleIdentifier | VERIFIED ON DEVICE STATIC EVIDENCE | beigelist 0xac02 使用导入的 kCFBundleIdentifierKey 取值，0xac10 setIdentifier: |
| CFBundleExecutable | PRESENT BUT ABI/SEMANTICS NOT FULLY VERIFIED | loader 调 NSBundle load；本 bundle 指向 Jellyfin，但设备 Foundation 读键实现未提供 |
| CFBundlePackageType | PRESENT BUT ABI/SEMANTICS NOT FULLY VERIFIED | 候选 BNDL 合乎本地 bundle 构建；未发现 loader 直接检查这个键，不能称为已证必需条件 |
| FRApplianceIdentifier | VERIFIED ON DEVICE STATIC EVIDENCE | BRApplianceInfo key 的 0x366b52 常量与 objectForKey:；infoForApplianceDescription: 0x3669ea 也读取；非证明 beigelist 插件必须提供 |
| FRApplianceName | VERIFIED ON DEVICE STATIC EVIDENCE | BRApplianceInfo name 0x366b7a 取键；工厂 0x366a20 写回本地化名称 |
| FRApplianceCategoryDescriptors | VERIFIED ON DEVICE STATIC EVIDENCE | BRApplianceInfo applianceCategoryDescriptors 0x366cd2 对应读键 |
| FRAppliancePreferedOrderValue | VERIFIED ON DEVICE STATIC EVIDENCE | BRApplianceInfo preferredOrder 0x366bce 取键，0x366bde floatValue；beigelist fallback 0xace2 |
| FRApplianceSupportedMediaTypes | VERIFIED ON DEVICE STATIC EVIDENCE | BRApplianceInfo supportedMediaTypes 0x366c0a；工厂 0x366a36–0x366a72 将 array 转 set |
| FRApplianceRequiredRemoteMediaTypes | VERIFIED ON DEVICE STATIC EVIDENCE | requiredRemoteMediaTypes 0x366c32；工厂 0x366994–0x3669d6 将 array 转 set |
| LegacyApplianceClass | VERIFIED ON DEVICE STATIC EVIDENCE | beigelist 0x9ec4–0x9ef0 与 0xaf58/0xaf64 的 objc_get/setAssociatedObject 路径；不是所需 plist 字段 |
| FRApplianceDataSourceType / FRRemoteAppliance | NOT FOUND | 两个二进制未找到键；保留历史元数据不等于赋予其有效语义 |

原始反汇编与常量解析：analysis/AppleTV.appliance-info.disassembly.txt、AppleTV.appliance-info.constants.txt。还确认 BRBaseAppliance -init (0x366e94) 直接返回 nil；-initWithApplianceInfo: (0x366e98) 调 super init 并 setApplianceInfo:。现有生产插件没有覆盖这两个 initializer，beigelist 已证路径调用后者，因而不用为 -init 增加未经需求的覆盖。回归 fixture 必须按 loader initializer 实例化 appliance，不能用 NSObject -init 的成功假装已覆盖真实初始化。

类型解码：@ 对象，v void，c signed char/ARMv7 BOOL，i int32，I uint32，l ARMv7 long32（不等于 selector 的语义可改成 int），f float32，d double64，^@ 对象输出指针。方法编码中的数字是 ARMv7 参数布局。宿主 macOS 的 long/BOOL 编码可不同，离线测试必须另以 ARMv7 产物核对。

## 修正状态（ABI C）

此前“必须修正/待补齐”清单为审计时状态。现已本地修正：float 分类 factory 与精确编码门禁；int32/uint32 事件读取；long selection；textDidChange:；缺失协议拒绝与 init 编码检查。没有添加新私有 selector，没有将 BRAppliance 当作类，也没有实现播放器。Tests/ui.m 已覆盖上述拒绝情形并按 loader 初始化 appliance。221 UI 断言 + 13 拒绝场景 + 184 基础断言 VERIFIED OFFLINE；设备行为仍 NOT RUN ON DEVICE。

## 修正状态（ABI D）

新增 loader 名称资源 English.lproj/InfoPlist.strings、development region，并在包验证中检查。旧本机 NSBundle localizedInfoDictionary name 为 null，新版为 Jellyfin（VERIFIED OFFLINE）；设备解析仍 NOT RUN ON DEVICE。保留两路径布局，不盲加其他 FRA/Legacy 字段。详见 [loader 契约](device-loader-12H1006.md)。全量离线/ASan/HTTP/TLS 已完成，ARMv7 新候选构建与校验记录将在最终封存段给出。

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
