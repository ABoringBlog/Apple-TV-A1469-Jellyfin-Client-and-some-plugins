# 12H1006 首次部署记录

2026-10-02 最新状态：SSH 已恢复，真机预检因 dpkg audit 非空和 Appliances 目录缺失而停止；尚未上传或安装。以下保留首次认证失败历史，最新结果见末节。

设备目标为用户确认的 AppleTV3,2 / A1469、软件 7.9 / SourceVersion 8163、iOS 8.4.4 / 12H1006、APPLE_TV_IP。本轮尚不能独立核实设备状态。

## 本轮证据

- recovery.git 起点 `add254a`，预检开始时工作区干净；主 .git 未修改。
- 候选 `build/package-freeze-deviceabi-12H1006-r1/org.jellyfin.atv3_0.5.1-deviceabi1_iphoneos-arm.deb`。
- SHA256 `f204d818df94235278a020f7ee7f9d7e1a06638b5d2d0ec63faccd8a238d7a0e`：VERIFIED STATIC，与用户指定值一致。
- 项目 verify-package.py 对候选及签名 stage 检查通过：VERIFIED STATIC。包含路径、owner/modes、元数据、ARMv7、签名存在和无维护脚本；不等于真机通过。
- SSH 使用 HostKeyAlgorithms=+ssh-rsa、StrictHostKeyChecking=yes、BatchMode=yes。沙箱首次阻止连接；经权限升级后到达 SSH 认证，返回 `Permission denied (publickey,password,keyboard-interactive).`。远端 id/uname 未执行。
- 当前默认身份文件不存在，未发现该设备专用 SSH 别名；未尝试无关服务的私钥。等待可用 alias/key/agent，不收集明文密码。
- 本地证据：`device-evidence/12H1006/pre-first-deploy/`。尚无设备备份，不能视为备份完成。

## 结果

| 项目 | 状态 |
| --- | --- |
| 当前会话 SSH 认证 | FAIL ON DEVICE：SSH 认证被拒绝；不是 appliance 运行失败 |
| uname / SystemVersion / df / dpkg audit / apt check | NOT RUN |
| MobileSubstrate / Beigelist / 主进程 / 目标路径 | NOT RUN |
| 覆盖位置备份、上传、dpkg 安装及安装后检查 | NOT RUN |
| loader / principal class / 实际 symlink 解析 | NOT RUN |
| 图标/分类、进入、主列表 | NOT REACHED |
| Remote Up / Down / Left / Right / Select / Menu | 各项 NOT REACHED |
| controller push/pop、生命周期 callback | NOT REACHED |
| 登录界面、真实键盘、输入/删除/提交、返回 | 各项 NOT REACHED |
| crash / syslog 采集 | NOT RUN；没有证据宣称无 crash |
| 真实 Server connection/login/session/libraries/item list/detail/poster/backdrop/logout | 各项 NOT RUN；未提供服务器配置 |
| 播放器 | NOT RUN；不进入本次范围 |

未修改设备，未触发 reload、kill 或 reboot；未修改代码或打包逻辑，未发现真机代码 blocker。恢复 SSH 认证后，继续已有 device-deploy.py 流程，先完成全项预检和备份再安装。当前不能宣布 appliance 已加载，也不能宣布已具备进入真实播放器阶段的验收条件。

## SSH 恢复后的真机预检（2026-10-02，r1）

起点 recovery.git `5cb18b4`，工作区干净。首条设备命令严格使用 `ssh atv3 'echo ATV3_SSH_OK; id; uname -a'`；沙箱网络权限获准后返回 ATV3_SSH_OK、uid=0(root)、AppleTV3,2 / arm / J33iAP。此前认证阻塞已解除。

使用既有 `Scripts/device-deploy.py preflight --host atv3 --run-id first-20261002-r1 --output device-evidence/12H1006/pre-first-deploy --execute` 采样，随后只读复核关键门槛。脚本退出 0 仅代表采样完成。

### 已确认事实与阻塞

- PASS ON DEVICE：SSH root；SystemVersion 的 ProductVersion=8.4.4、ProductBuildVersion=12H1006；宿主 CFBundleVersion=7.9、CFBundleSourceVersion=8163、identifier=com.apple.lowtide。
- PASS ON DEVICE：`apt-get check` 退出 0；根卷可用 488568 KiB、数据卷 5843892 KiB。
- PASS ON DEVICE（仅安装状态）：mobilesubstrate 0.9.6301、beigelist 2.2.6-30、com.saurik.patcyh 1.2.0-1、uikittools 1.1.12-1 均 install ok installed。初次以 patcyh 查询失败属包名错误，后续已用准确包名确认；不代表加载注入已验证。
- PASS ON DEVICE（仅进程存在）：PID 86 `/Applications/AppleTV.app/AppleTV`。实际 launchd Label 为 com.apple.frontrow，UserName=mobile、KeepAlive=true；com.apple.lowtide 为 bundle identifier，不能直接假设是 launchd Label。未重启服务。
- FAIL ON DEVICE（预检）：两次 `dpkg --audit` 均输出大量包缺少 md5sums，包括 mobilesubstrate、dpkg 和基础包。虽然 audit exit=0，仍不满足部署工具 `test -z "$(dpkg --audit)"` 门槛。参考备份也确认 mobilesubstrate.md5sums 缺失。未伪造校验文件或重装系统包。
- FAIL ON DEVICE（预检）：`/Applications/AppleTV.app/Appliances` 不存在，不满足既有工具 `test -d` 门槛。`/Applications` 实际指向 `/var/stash/Applications`；两处 Jellyfin 目标均 ABSENT。未创建目录、未放宽门禁。
- VERIFIED STATIC：设备 AppleTV/Info.plist/beigelist7.dylib/beigelist7.plist SHA256 与既有 ABI 证据逐一相同；这不证明进程已注入或 appliance 已加载。
- VERIFIED STATIC：本地候选 SHA256 再次与指定值一致，候选未变。

### 证据保存与备份边界

`device-evidence/12H1006/pre-first-deploy/` 保存原始 preflight、extended-preflight、confirmed-gate-failure、package-status 日志，以及 `preflight-reference-r1.tar.gz`。参考归档通过 SSH 只读流式下载，含 dpkg status/info 和 system/host/frontrow plist，共 110 个成员，已在 Mac 完整读取和解析。归档 SHA256：`7d692548619aca7b45124942100f30df8d1875d8bccaf8c249d68aacbaf335ef`。未在设备创建临时部署目录。

这是诊断参考备份，不是部署工具的 backup/BACKUP_VERIFIED，未进行设备端归档摘要比对；不能用来声称安装门槛已全部通过，不能整体覆盖活动 dpkg 数据库。原始证据与归档仅保留本地、不提交 Git；reviewed-summary 和 evidence-sha256 保存可审阅事实及文件散列。

`/var/log/syslog` 不存在，已知 crash 目录列表已保存，尚未采集 ASL 日志或执行 loader 测试；不能宣称没有 crash。

### 本轮最终结果

| 项目 | 结果 |
| --- | --- |
| 安装、上传、安装后 audit/apt 检查 | NOT RUN：关键预检失败 |
| loader / principal class 注册 | NOT RUN |
| symlink 实际解析 | NOT RUN：目标均未安装 |
| Jellyfin 出现、进入、主列表 | 各项 NOT REACHED |
| Up / Down / Left / Right / Select / Menu | 六项各为 NOT REACHED |
| controller push/pop、lifecycle callbacks | 各项 NOT REACHED |
| 登录 UI、键盘、输入、删除、提交、返回 | 六项各为 NOT REACHED |
| crash/syslog | 仅预安装目录基线；加载期间采集 NOT RUN |
| 真实 Jellyfin Server | NOT RUN：未配置 |
| Jellyfin 代码 blocker / 修复 | 未发现 / 无；本轮是部署前环境门槛失败 |
| Ready for real playback device validation | 否 |

未执行 apt upgrade、重越狱、Beigelist/MobileSubstrate 修改、dpkg install、reload、kill 或 reboot。未改变候选，不需要新 ARMv7 build。遵守“任何关键预检失败则停止，不安装”的先决条件；本轮未达到运行验收 A，也未到达代码 blocker B。

后续需先处理设备包数据库状态与缺失 discovery 目录，再重新执行全部预检。该修复可能涉及此前明确禁止修改的 bootstrap/系统包，因此没有擅自扩展本轮范围或绕过安装门槛。

## 2026-10-02 device UI diagnostic candidate 0.5.2-deviceui1

User-visible 0.5.1 result: Jellyfin appeared in the Apple TV main menu without an icon; selecting it pushed a controller whose visible content was only the title `Jellyfin`. This is the first direct evidence that the Beigelist discovery path, bundle load, principal class registration, appliance category, and controller creation path are at least partially functional on 12H1006.

Beigelist 2.2.6 static evidence shows its legacy loader requests `AppIcon.png` from the frappliance bundle. Candidate 0.5.1 did not contain that resource. Candidate 0.5.2-deviceui1 adds a 188x108 `AppIcon.png`, adds file-backed runtime diagnostics at `/tmp/JellyfinATV3.log`, and does not modify jailbreak/bootstrap packages. The candidate SHA256 is `5e4c2d0b51b4fa160820b2a4ec9da8c4e2b86295ea5771d6a5a314fbbeb8edc5`; executable SHA256 is `0946ac7cdad48a1cda7074de14705e1f6b4304c77714b2d0f373673270218c02`.

Offline regression tests and ARMv7 packaging verification passed. Before upgrade, 0.5.1 was backed up with an explicit rollback deb in run `deviceui-20261002-r1`. Upgrade to 0.5.2-deviceui1 succeeded and post-install inspection passed. `com.apple.frontrow` was then restarted only; PID changed from 1137 to 1653 and remained running. No AppleTV/Lowtide/Jellyfin crash report was found. The fresh runtime log confirms `BRBaseAppliance`, `BRController`, and `BRMediaMenuController` are present, the menu ABI gate passes, and `JellyfinAppliance` / `JellyfinController` registration completes with menu support enabled.

Visual confirmation of the new icon and a fresh selection of Jellyfin are still required. Menu-row rendering remains unresolved until the user opens the new candidate and the resulting runtime log is collected; no claim is made yet that login rows render correctly.
