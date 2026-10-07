# Pre-Device Freeze

状态：离线实现及验收完成；实际 ATV3 与真实 Jellyfin 验证未执行。默认候选仍是浏览 UI，必须显式注入经过验证的 backend 才能播放。此 freeze 不包含未知播放器私有 API，也不伪装电视上已成功播放。

## 产物

- 版本：bundle 0.5.0 / deb 0.5.0-predevice1。
- deb：`build/package-pre-device-final/org.jellyfin.atv3_0.5.0-predevice1_iphoneos-arm.deb`。
- SHA256：`214fe2607b19293dea4dba64c6bc066b6bf17a6a1253e54cf03eab8d812bcae9`。
- 包内已签名二进制 SHA256：`eabdd305beeb67dbe8e4c368923f59a983e5dc5f81fc5cc8e7d6d1412d1956be`。
- ARMv7 原始 bundle：`build/pre-device-armv7/Jellyfin.frappliance`。
- 重复构建：`build/freeze-repeat1`、`build/package-freeze-repeat1`，二进制与 deb 均字节一致。
- 新部署套件：`build/deployment-pre-device-final`，自带 SHA256SUMS。
- 恢复仓库：`recovery.git`；最终 tag `pre-device-freeze-v0.5.0`。主 `.git` 不写入。
- Phase 4E `build/deployment-phase4e`、0.4.0 deb、历史日志和 checkpoints 均保留。

## 已实现

现有 API/session/artwork/UI model 全部保留；增加真实服务环境/配置 runner、服务器注销与 token invalidation、独立播放模型/DeviceProfile/三种协商决策/URL/resume/上报/状态机/取消、字幕 metadata/选择/UTF-8/转换与 burn-in 策略、播放器 backend 抽象及 UI mock 接线、错误与生命周期 fixture，以及默认 dry-run 的部署工具。

详见 [播放架构](playback-architecture.md)、[字幕架构](subtitle-architecture.md)、[部署工具](deployment-tooling.md) 和 [证据分级清单](device-validation-checklist.md)。

## 真实 Jellyfin runner

仅使用测试用户：runner 会执行服务端 logout，验证本次 session/token 失效。支持用户登录或已存在的用户 access token（二选一；管理员 API key 未必能提供 Users/Me/注销语义，不属于此入口）。参数来自环境或外部 JSON，绝不把真实凭据提交仓库。

环境：`JF_URL`、`JF_USERNAME`、`JF_PASSWORD`，或 `JF_URL`、`JF_TOKEN`；可加 `JF_LIBRARY`、`JF_ITEM`。默认 https；明文 HTTP 需显式 `--allow-http`。不要在聊天/日志中粘贴凭据。

```sh
make build/integration
python3 Tests/integration.py --config /private/path/jellyfin-test.json
# 或预先由安全的外部方式设置环境：
python3 Tests/integration.py
# 只测公开信息及系统可信 HTTPS 连接：
python3 Tests/integration.py --mode probe
# fixture 保留，不使用真实环境凭据：
python3 Tests/integration.py --fixture
```

外部 JSON 字段为 url、username/password 或 token、library、item，均为字符串。library/item 需预先选择有内容、有海报与背景图的测试媒体；未配置会 SKIP 对应步骤，不能当作完整真实服务验收。URL 禁止内嵌凭据、query/fragment。原有 `--url`/`--library`/`--item` 与交互输入也兼容。

凭据经匿名 stdin 到 Objective-C，stdout 严格阶段白名单，stderr 不转发，错误不回显 response/header/配置。没有真实参数返回 77 / NOT RUN；目前实际记录见 `logs/pre-device-real-server.log`。默认系统信任，不关闭证书/hostname 验证；Python 隔离 CA 成功不替代 Foundation 真实 HTTPS 成功。

## 可重复验收

```sh
make test-offline
make test-asan
# 需要允许本地 socket 监听；只使用 Mac loopback：
make test-http test-integration-http test-tls-negative test-playback-http test-tls-contracts
# 全新目录重建；标签必须未使用：
Scripts/freeze-build.sh YOUR_NEW_LABEL
# 当前最终包检查：
JF_PACKAGE=build/package-pre-device-final/org.jellyfin.atv3_0.5.0-predevice1_iphoneos-arm.deb python3 Tests/package_test.py
python3 Scripts/verify-package.py build/package-pre-device-final/org.jellyfin.atv3_0.5.0-predevice1_iphoneos-arm.deb build/package-pre-device-final/stage/Applications/Jellyfin.frappliance
codesign --verify --strict --verbose=2 build/package-pre-device-final/stage/Applications/Jellyfin.frappliance
git --git-dir=recovery.git --work-tree=. diff --check
```

`make clean` 已禁用删除历史产物，clean build 使用新目录。freeze-build.sh 记录工具链、source commit/status、ARMv7/打包日志与 SHA256；失败不删除目录，改用新标签。源码和工具链相同才期待字节复现，不承诺跨 Xcode/SDK 版本二进制相同。

最终证据：`logs/pre-device-offline-final.log`、`pre-device-network-final.log`、`pre-device-playback-boundaries-r2.log`、`pre-device-armv7.log`、`pre-device-package.log`、`pre-device-package-tests.log`、`pre-device-reproducibility.log`。最后扩展字幕/回调边界测试时修正 CHECK 宏的逗号参数处理，旧失败日志保留，不用旧 ASan 二进制输出覆盖这次失败；最终 r2 正常测试和新编译 ASan 都为 177 断言通过。

## 后续边界

无需设备的实现工作已完成。剩余设备工作为 USB/Blackb0x/SSH、8163 selectors/ABI、签名/加载器、键盘/遥控、真实播放器 adapter/解码/字幕/性能和设备证据采集。另有未提供真实服务器配置所导致的外部集成验证 NOT RUN，必须如实保留。部署时从只读 preflight 开始，确认恢复入口后再选用新候选；绝不自动重启、越狱或修改固件。

最后追加真实在途 setup cancel/logout 与 token 登录/注销入口验收，见 `logs/pre-device-boundary-final.log`：playback/subtitle 普通及 ASan 各 179 断言，integration 6 Python 用例。仅扩展测试，不改变上述候选二进制或 SHA256。
