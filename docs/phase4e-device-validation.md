# Phase 4E 真机验证记录

状态：WAITING FOR DEVICE。以下全部为 NOT RUN；离线通过不能替代真机结果。

记录时间 / 操作者：待填
设备型号（外壳 A1469 与 hw.machine）/ 软件版本 / build：待填
越狱与 appliance 加载环境：待填
SSH 别名（不要填密码）/ 预检日志：待填
候选 deb：org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb
SHA256：94fde77a0b2d04680dc999cb0c5e92657e4a008fb958da269b981da0b2314738
旧版本 / 回滚 deb 校验和 / 备份目录：待填
Jellyfin 服务版本 / HTTPS 证书链 / 测试库：待填（不记录账号密码或 token）

| 项目 | 操作与预期 | 结果 / 证据 |
| --- | --- | --- |
| 设备门槛 | 核对 A1469、7.9（8163）目标；不同版本先评估，dpkg 架构、挂载、空间、加载器均可用 | NOT RUN |
| 备份 | 下载并校验安装前文件/链接备份；升级必须有原版本可重装 deb | NOT RUN |
| 上传 | 设备 SHA256 与上述候选一致；dpkg --info/--contents 可解析 | NOT RUN |
| 安装 | dpkg -i 退出 0；状态 install ok installed、0.4.0-test1；dpkg --audit 无异常 | NOT RUN |
| 文件 | bundle 与链接路径正确，UID/GID 0:0，目录/二进制 755，plist/签名资源 644；二进制散列一致 | NOT RUN |
| 宿主加载 | 按实际 launchd 证据重启宿主后 Jellyfin 入口出现，无 crash loop | NOT RUN |
| 主界面 | 进入显示服务器/用户名/登录/Allow HTTP；不只出现 shell fallback | NOT RUN |
| 输入 | 地址/用户名可编辑、取消可返回；密码输入隐藏，取消不泄漏 | NOT RUN |
| HTTPS | 默认证书校验下真实服务器登录成功；不关闭 TLS 校验 | NOT RUN |
| 错误登录 | 错误密码显示认证错误，可重新登录，无死锁 | NOT RUN |
| 列表 | 库→电影→详情；库→电视剧→季→集→详情；刷新、空库、加载更多均正确 | NOT RUN |
| 遥控 | 上下焦点正确；Select 单次选择；Menu 深层返回、根页退出，无双重 pop | NOT RUN |
| 忙碌/生命周期 | 加载时重复按键被丢弃；反复进出和输入页返回无崩溃，关闭后无旧请求重绘 | NOT RUN |
| 网络错误 | 断网/超时/服务错误显示有限错误并能恢复；失效会话返回登录 | NOT RUN |
| 注销 | 清会话，返回登录；再次进入不自动恢复登录 | NOT RUN |
| 稳定性 | 连续进出 10 次并浏览至少 15 分钟，记录 crash 和内存异常 | NOT RUN |
| 回滚 | 在测试窗口恢复旧包或移除首次安装包；宿主与 SSH 恢复正常 | NOT RUN |

逐项用 PASS / FAIL / BLOCKED / NOT RUN 填写，附时间和脱敏证据路径。加载失败时先保留设备崩溃报告、宿主服务信息和安装日志；不要通过重签、修改加载器或强制 dpkg 覆盖来掩盖失败。日志可能含服务器地址或认证信息，分享前脱敏。

播放、转码、字幕、海报视图及登录持久化不属于本阶段验收。只有完成设备测试才能修改上述状态。
