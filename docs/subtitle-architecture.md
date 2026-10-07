# 字幕逻辑层

此模块只解析/选择/请求字幕，不包含 ATV3 renderer，不声明设备支持 SRT、ASS、SSA、PGS 或任何字幕格式。

`JFSubtitleTracks` 从 MediaStreams 读取 Subtitle 类型的 Index、Codec、Language、Title、IsExternal、IsForced、IsDefault。索引必须为唯一非负整数且≤10000，类型错误/重复索引拒绝。保留默认/强制标记供选择，但不暗中自动启用字幕。`JFSubtitleSelection` 接收明确索引，-1 表示 off。

| 数据条件 | 逻辑策略 | 限制 |
| --- | --- | --- |
| 外挂 SRT/SubRip | direct subtitle | 表示无需格式转换；不代表可在 ATV3 显示 |
| 内嵌 SRT/SubRip | server-side conversion | 服务端提取为 SRT |
| ASS/SSA，可接受丢失样式 | server-side conversion | 显式 losesStyling，转 SRT |
| ASS/SSA，保留样式 | burn-in required | 需视频转码 |
| PGS/pgssub/hdmv_pgs_subtitle/DVD bitmap | burn-in required | 不将 bitmap 当 UTF-8 |
| 未知 codec/非法索引 | 拒绝 | 无静默格式猜测 |

请求地址为 `Videos/{item}/{mediaSource}/Subtitles/{index}/Stream.srt`，ID 严格校验，认证仅 header。路径按 [Jellyfin v10.10.7 SubtitleController](https://github.com/jellyfin/jellyfin/blob/v10.10.7/Jellyfin.Api/Controllers/SubtitleController.cs) 构造，不跟随服务器元数据中的任意外部 URL 或文件系统 Path。

UTF-8 解码严格，接受 UTF-8 BOM 和 CRLF，拒绝坏编码、NUL、空内容、超过 2 MiB、缺序号/文本、非法时间戳或结束早于开始的 SRT。通用 HTTP 传输同时有 8 MiB 上限与总 deadline。当前验证返回文本而不解释 HTML、ASS 样式或运行脚本；最终 renderer 的字体、布局、编码兼容与安全文本处理均待设备 adapter。

DeviceProfile 的 SubtitleProfiles 为空。若调用 PlaybackInfo 的 subtitleIndex≥0，禁用 direct play/direct stream 并请求服务端 burn-in；这避免在没有 renderer 时假称可以外挂显示。独立选择模型仍可由未来已验证 renderer 使用，direct/conversion 的输出不得在现有 appliance 上宣称已显示。UI 本轮只注入播放器测试，不添加未经验证的字幕显示控件。

fixture 覆盖外挂/内嵌 SRT、ASS/SSA 转换及保样式策略、PGS、off、非法/重复索引、坏 metadata、UTF-8/BOM/CRLF、过大内容和时间顺序；HTTP 测试覆盖 SRT 请求及坏内容。真实 Jellyfin 字幕转换/烧录尚未执行，设备显示全部 NOT RUN。
