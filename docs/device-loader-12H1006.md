# 12H1006 Jellyfin loader / candidate contract

分级：**VERIFIED ON DEVICE STATIC EVIDENCE** 为所提供 Mach-O 的静态读键、方法或控制流；**VERIFIED OFFLINE** 为本机测试；**PROVISIONAL** 为待设备确认的行为；本轮所有真实加载/卸载均 **NOT RUN ON DEVICE**。

beigelist7 2.2.6 注入 com.apple.lowtide，BLAppManager -_loadAppliances 从 `NSBundle.mainBundle.bundlePath` 追加 `Appliances`，枚举 `.frappliance`，调用 `NSBundle load` 后获取 `principalClass`，保存 legacy appliance class。实例化使用 `initWithApplianceInfo:nil`，不是 -init；后者在真机 BRBaseAppliance 中直接返回 nil。证据 VM 地址、字段逐项分级见 [ABI 审计](device-abi-12H1006.md)。

双路径保持：

```
payload: /Applications/Jellyfin.frappliance
loader entry: /Applications/AppleTV.app/Appliances/Jellyfin.frappliance
              -> /Applications/Jellyfin.frappliance
```

搜索规则为 VERIFIED ON DEVICE STATIC EVIDENCE；绝对 mainBundle 路径、设备符号链接解析、权限和加载成功均 NOT RUN ON DEVICE。本地包校验检查两个路径、链接目标、root:wheel 0:0、目录/二进制 0755、plist/资源 0644、ARMv7 MH_BUNDLE、iOS 8.0 build baseline、签名存在与 stage 字节一致。

候选 0.5.1-deviceabi1：CFBundleExecutable=Jellyfin，CFBundleIdentifier=org.jellyfin.atv3，NSPrincipalClass=JellyfinAppliance，CFBundlePackageType=BNDL，CFBundleSupportedPlatforms=[iPhoneOS]。principal class 由 constructor 动态注册为 BRBaseAppliance 子类；runtime gate 必须通过，不能仅凭 plist 判断会成功加载。

beigelist 直接以 CFBundleIdentifier 设置 identifier；名称由 localizedInfoDictionary 的 CFBundleName 提供。旧 bundle 在本机 NSBundle 检查中 localized name 为 null；现补入 English.lproj/InfoPlist.strings 和 CFBundleDevelopmentRegion=English，修正后本机返回 Jellyfin。这个资源包含 CFBundleName 与 FRApplianceName；包验证要求新版本包含该资源。**VERIFIED OFFLINE** 不等于设备 Foundation 已执行成功。

FRAppliancePreferedOrderValue 的值保持数字 5，loader 调 floatValue；分类 factory 的 float ABI 是另一个接口，已在 adapter 修复。FRApplianceIdentifier、FRApplianceCategoryDescriptors、FRApplianceSupportedMediaTypes、FRApplianceRequiredRemoteMediaTypes 的原生 BRApplianceInfo 读键/转换已证实，但没有证据要求把它们加入这个 beigelist 插件的 plist。LegacyApplianceClass 是 associated-object key。历史 FRApplianceDataSourceType/FRRemoteAppliance 未找到消费证据，保留但不依赖其语义。

卸载/首次安装回滚由 dpkg --remove 移除 package 所有的 bundle 和 discovery symlink；新脚本进一步检查二者不再存在，残余文件会报失败而不会擅自删除。升级回滚核验原 deb SHA/version 后 dpkg -i，并检查版本、链接和可执行文件。Tests/deployment_test.py 在临时目录以假 dpkg 执行生成的 shell 验证上述三条路径；没有调用设备 dpkg。历史冻结包与套件均保留。

当前不执行 install/rollback/uninstall。首次设备验证仍需用户启动下一阶段，保留 SSH 恢复入口，核对设备目录、宿主路径与候选签名/依赖可加载性。没有播放器 backend，不将浏览 UI 候选描述为可播放版本。
