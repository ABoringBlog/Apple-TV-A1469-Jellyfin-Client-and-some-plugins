# Phase 4E：Apple TV 3 部署操作手册

当前停点：等待设备连接。候选包离线验证通过；未执行 SSH、安装或重启。本流程仅验证现有 UI，不开展播放器开发。面向项目目标 A1469 / 软件 7.9（8163），具体设备 dpkg、签名信任、加载服务均待采样。

## 1. Mac 离线 deb 检查

在项目根目录运行：

```sh
python3 Tests/package_test.py
python3 Scripts/verify-package.py build/package-phase4e-final/org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb build/package-phase4e-final/stage/Applications/Jellyfin.frappliance
codesign --verify --strict --verbose=2 build/package-phase4e-final/stage/Applications/Jellyfin.frappliance
shasum -a 256 build/package-phase4e-final/org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb
```

固定候选 SHA256：`94fde77a0b2d04680dc999cb0c5e92657e4a008fb958da269b981da0b2314738`。
二进制 SHA256：`7a439c840e7c0c9f1d472f457c57a19b4bfd76a9b02521a0da7b0e40bf6b7e08`。
包 ID `org.jellyfin.atv3`，deb 版本 `0.4.0-test1`，bundle `0.4.0`，架构 `iphoneos-arm` / thin ARMv7，最低系统字段 iOS 8.0。无 maintainer scripts，无自动重启。ad-hoc 签名仅有 Mac 校验证据。

离线套件 `build/deployment-phase4e/` 含候选、检查脚本、预检脚本和文档。在套件根目录执行 `shasum -a 256 -c SHA256SUMS` 和 `python3 Scripts/verify-package.py org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb`。Mac 需要 Python 3、ar；严格签名检查使用项目中的签名 stage。

## 2. 设备连接后只读预检

配置专用 SSH 别名 `atv3-test`，HostName/端口/User root 使用实际设备信息。密码由 SSH 交互输入或使用已有密钥，不放入命令或文档。首次连接核对主机指纹；不要禁用主机密钥检查。旧算法协商失败时记录原始错误，按设备实际支持情况处理该别名，不全局开启旧算法。

```sh
mkdir -p logs/device
ssh -o ConnectTimeout=10 atv3-test 'sh -s' < Scripts/device-preflight.sh > logs/device/preflight.txt 2>&1
```

报告脚本只读取配置和状态；退出 0 只表示采样完成。检查缺失项，确认 root UID、设备型号/固件、dpkg 架构 `iphoneos-arm`、包数据库无异常、Appliances 路径、可写挂载和可用空间。预留包及解压文件、备份空间（建议至少 20 MiB，旧 bundle 大于此值时另算）。在电视设置中人工核对软件 7.9（8163），不将 plist 的 OS 版本直接当作软件版本。

必须确认现有越狱支持 appliance 加载，以及可在加载失败时保留 SSH 恢复入口。根据 `launchctl list` 和实际 plist 确认宿主服务与重启方法；当前不预设服务标签。路径已存在但无 dpkg 所属、属于其他包、存在异常链接、非目标固件或挂载只读时停止安装，先解决冲突。不要强制覆盖、重挂载或修改加载器。

## 3. 安装前备份

以下为设备连接并完成预检后的手工步骤，逐段执行并检查退出码。先在 Mac 为本次尝试创建唯一记录目录，避免覆盖前一次：

```sh
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
LOCAL_RUN="logs/device/$RUN_ID"
mkdir "$LOCAL_RUN"
ssh atv3-test 'umask 077; mkdir /var/root/jellyfin-phase4e'
```

设备目录若已存在，停止并为新尝试选择新目录，下文路径同步替换。备份前读取 `dpkg-query -W org.jellyfin.atv3`：首次安装记录 ABSENT；已安装则记录原版本，并备妥该**原版本**可重装 deb（校验和、控制信息与内容）。历史离线包未经设备验证，不能直接称为已知可用回滚包。没有旧 deb 时不升级。

```sh
ssh atv3-test 'sh -s' <<'REMOTE'
set -eu
cd /var/root/jellyfin-phase4e
umask 077
set --
for p in Applications/Jellyfin.frappliance Applications/AppleTV.app/Appliances/Jellyfin.frappliance; do
    if [ -e "/$p" ] || [ -L "/$p" ]; then set -- "$@" "$p"; fi
done
if [ "$#" -gt 0 ]; then
    tar -czpf before-files.tar.gz -C / "$@"
    tar -tzf before-files.tar.gz
else
    printf '%s\n' 'Both deployment paths absent' > before-absent.txt
fi
cp -p /var/lib/dpkg/status dpkg-status.reference
REMOTE
scp -r atv3-test:/var/root/jellyfin-phase4e "$LOCAL_RUN/backup"
```

tar 不使用 `-h`，保留链接本身。比较设备备份与下载副本 SHA256，并确认 tar 可列出。设备可用 `shasum -a 256 FILE`、`sha256sum FILE` 或 `openssl dgst -sha256 FILE`，以预检实际存在的工具为准。`dpkg-status.reference` 仅供诊断，不能整体覆盖活动数据库；文件备份也不替代旧版本 deb。备份下载或校验失败时不安装。

## 4. SSH 上传与安装

```sh
scp build/package-phase4e-final/org.jellyfin.atv3_0.4.0-test1_iphoneos-arm.deb atv3-test:/var/root/jellyfin-phase4e/candidate.deb
ssh atv3-test 'openssl dgst -sha256 /var/root/jellyfin-phase4e/candidate.deb'
ssh atv3-test 'dpkg --info /var/root/jellyfin-phase4e/candidate.deb'
ssh atv3-test 'dpkg --contents /var/root/jellyfin-phase4e/candidate.deb'
```

上例摘要命令仅在预检确认 openssl 可用时使用，否则替换为另一已确认的 SHA256 工具。必须与固定候选散列逐字一致，设备 dpkg 能读取 gzip/ustar 内容。scp 默认传输方式若因设备没有 SFTP 失败，且本机 `scp` 支持 `-O`，可用 `scp -O` 走旧协议；继续保留主机校验。

核对备份与回滚路径后执行安装，立即保存退出码，不能用 tee 掩盖 SSH/dpkg 失败：

```sh
ssh atv3-test 'dpkg -i /var/root/jellyfin-phase4e/candidate.deb' > "$LOCAL_RUN/install.txt" 2>&1
INSTALL_RC=$?
printf 'install exit=%s\n' "$INSTALL_RC"
cat "$LOCAL_RUN/install.txt"
```

非零时停止，记录 `dpkg --audit`，不要继续重启或强制安装。成功后：

```sh
ssh atv3-test 'dpkg-query -W -f="\${Status} \${Version} \${Architecture}\n" org.jellyfin.atv3; dpkg --audit'
ssh atv3-test 'ls -ldn /Applications/Jellyfin.frappliance /Applications/Jellyfin.frappliance/_CodeSignature; ls -ln /Applications/Jellyfin.frappliance/Info.plist /Applications/Jellyfin.frappliance/Jellyfin /Applications/Jellyfin.frappliance/_CodeSignature/CodeResources; readlink /Applications/AppleTV.app/Appliances/Jellyfin.frappliance'
ssh atv3-test 'openssl dgst -sha256 /Applications/Jellyfin.frappliance/Jellyfin'
```

核对 `install ok installed 0.4.0-test1 iphoneos-arm`、UID/GID 0:0、目录与二进制 755、资源 644，链接指向 `/Applications/Jellyfin.frappliance`，二进制散列与第 1 节一致。所有命令输出均需检查，最后一个命令的成功不能代替前面的成功。

## 5. 加载与验收

先保持第二个 SSH 会话可用。仅按预检确认的宿主服务操作，在维护窗口重启宿主一次；将确切命令与服务标签记入验证记录。尚未取得该证据，因此本手册不提供猜测的 killall/launchctl 命令，也不自动 reboot。

按 [真机验收表](phase4e-device-validation.md) 逐项记录。没有入口、只能进 shell、密码未隐藏或出现 crash loop 均为失败，先停止登录测试并收集本次时间范围内的崩溃报告。真实服务器地址/测试账号在设备 UI 输入，使用受信任 HTTPS；不绕过证书错误。不要将完整凭据、token 或未脱敏系统日志写入仓库。

## 6. 回滚

保持 SSH 可连接，并按已确认方法停用/停止宿主后操作，防止重载。首次安装且之前两个目标路径均不存在时：

```sh
ssh atv3-test 'dpkg --remove org.jellyfin.atv3'
```

检查退出码、`dpkg --audit`、包状态与两个路径，随后按已确认的方法恢复宿主，验证原主菜单和 SSH。无需 purge，也不删除用户数据或修改系统目录。移除失败或有残留先调查，不用递归 rm。

升级场景：将已校验的原版本 deb 上传到本次目录 `rollback.deb`，执行 `dpkg -i /var/root/jellyfin-phase4e/rollback.deb`；检查原版本/状态、文件和链接，恢复宿主并验收。不要使用强制降级/覆盖选项；若 dpkg 拒绝，停止并保留诊断。文件备份仅作人工恢复参考，不能仅解压旧文件后宣称包数据库已回滚。

SSH 不可达时使用该设备越狱方案已有的恢复入口；当前尚未获知该入口，必须在安装前补齐。不要盲目恢复固件。每次尝试保留原包、候选、备份、安装日志和验收记录。
