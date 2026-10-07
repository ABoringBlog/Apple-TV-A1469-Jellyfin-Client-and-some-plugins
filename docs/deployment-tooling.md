# Pre-Device 部署工具

`Scripts/device-deploy.py` 不扫描或自动连接设备。所有 action 默认 dry-run；即使只读 SSH 也需 `--execute`。写入还需 `--device-confirmed`，表示操作者已核对型号/固件、越狱加载环境与 SSH 恢复入口。脚本不重启、不 remount、不修改固件、不 jailbreak。严格主机密钥校验要求先通过已知渠道确认并配置 SSH known_hosts。

设备到达后顺序执行（示例省略 `--execute`，默认均只预览）：

```sh
python3 Scripts/device-deploy.py connect --host atv3-test
python3 Scripts/device-deploy.py preflight --host atv3-test
python3 Scripts/device-deploy.py disk --host atv3-test
python3 Scripts/device-deploy.py backup --host atv3-test --run-id attempt01
python3 Scripts/device-deploy.py upload --host atv3-test --run-id attempt01 --package PATH_TO_DEB --sha256 EXPECTED_SHA256
python3 Scripts/device-deploy.py install --host atv3-test --run-id attempt01 --package PATH_TO_DEB --sha256 EXPECTED_SHA256
python3 Scripts/device-deploy.py inspect --host atv3-test --run-id attempt01
python3 Scripts/device-deploy.py diagnostics --host atv3-test --run-id attempt01
python3 Scripts/device-deploy.py crashes --host atv3-test --run-id attempt01
python3 Scripts/device-deploy.py rollback --host atv3-test --run-id attempt01
python3 Scripts/device-deploy.py uninstall --host atv3-test --run-id attempt01
```

实际执行时，只读 action 添加 `--execute`；backup/upload/install/rollback/uninstall 同时添加 `--execute --device-confirmed`。每次部署选新的 run-id，不覆盖旧备份或候选。端口可用 `--port`，IPv6 用 SSH 别名。密码只由 SSH 输入或已有密钥处理。

首次安装要求两个目标路径原本均不存在。升级 backup 必须带 `--rollback-package ORIGINAL_DEB`，脚本验证旧 deb 与实际已安装版本一致，并保留其 SHA256。backup 包含 bundle、链接和 dpkg status 参考副本，下载 Mac 并核对 SHA256 后才写 BACKUP_VERIFIED。不要将 status 参考副本整体覆盖活动数据库。已有未被 dpkg 正确管理的文件会阻止备份/安装。

upload 使用 SSH stdin，不依赖设备 SFTP；安装前再次比对候选摘要、包元数据、安装前包状态、dpkg audit 与空间。目录已存在或上传中断则保留现场，使用新 run-id，不能盲目重试覆盖。inspect 要求设备 BSD stat，检查 UID/GID 0:0、755/644 及 appliance 链接，并输出二进制 SHA256供比对部署清单；命令缺失记为 BLOCKED，不声称检查通过。

首次安装 rollback 执行 dpkg remove；升级 rollback 重装原 deb。dpkg audit 异常不会阻止回滚命令本身，但结果仍须人工检查。uninstall 只做 remove，不 purge 用户数据。失败时停止后续步骤，保持原日志与备份；不使用强制覆盖/降级选项。宿主停止与恢复命令仍需设备服务证据，参见 Phase 4E 手册。

输出默认保存 `logs/device/`，目录/文件通过 umask 077 创建。crashes 默认仅列出已知 crash 目录；`--include-sensitive-logs` 才读取有界 syslog 与 AppleTV/Lowtide crash 尾部，原始内容写本地文件而不打印。分享前必须脱敏。设备命令兼容性、crash 路径、安装与回滚全部 NOT RUN；离线测试只验证 dry-run、参数防注入、脚本语法、校验门槛和本地包检查。
