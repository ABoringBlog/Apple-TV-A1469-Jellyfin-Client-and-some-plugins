# 12H1006 播放器静态 API 分级

证据层级：VERIFIED ON DEVICE STATIC EVIDENCE / VERIFIED OFFLINE / PROVISIONAL / NOT RUN ON DEVICE。没有实现、注入或运行真实播放器。

BRMediaPlayer、BRMediaPlayerController、BRMediaPlayerWaitControl、BRMediaPlayerManager 的直接方法与继承、编码、IMP 已提取；全部 **VERIFIED METHOD + ABI**。完整清单见 [player-api.md](../device-evidence/12H1006/analysis/player-api.md)。实际解码、seek、认证、字幕均 **NOT RUN ON DEVICE**。

AVPlayer / AVPlayerItem / AVPlayerLayer / AVURLAsset：**CLASS REFERENCE ONLY**，来自 AVFoundation 外部导入；不是它们的方法表。

| 待追踪 AV API 名称 | 分级 |
|---|---|
| `playerWithPlayerItem:` | METHOD NAME PRESENT ONLY |
| `playerItemWithAsset:` | METHOD NAME PRESENT ONLY |
| `playerLayerWithPlayer:` | METHOD NAME PRESENT ONLY |
| `play` | METHOD NAME PRESENT ONLY |
| `pause` | METHOD NAME PRESENT ONLY |
| `setRate:` | METHOD NAME PRESENT ONLY |
| `seekToTime:` | METHOD NAME PRESENT ONLY |
| `seekToTime:completionHandler:` | METHOD NAME PRESENT ONLY |
| `seekToTime:toleranceBefore:toleranceAfter:completionHandler:` | METHOD NAME PRESENT ONLY |
| `addPeriodicTimeObserverForInterval:queue:usingBlock:` | METHOD NAME PRESENT ONLY |
| `removeTimeObserver:` | METHOD NAME PRESENT ONLY |
| `replaceCurrentItemWithPlayerItem:` | NOT FOUND |

selector 全局存在不证明接收者是 AVPlayer；这些行没有借用 BR 类同名编码，也没有借用新 SDK 反推旧固件签名。

| notification / symbol | 证据与边界 |
|---|---|
| BRMediaPlaybackInitiatedNotification | 字符串存在；触发/载荷语义 PROVISIONAL |
| AVPlayerItemDidPlayToEndTimeNotification | 外部符号导入；不是 callback ABI |
| AVPlayerItemFailedToPlayToEndTimeNotification | 外部符号导入；不是 callback ABI |
| AVPlayerItemPlaybackStalledNotification | 外部符号导入；不是 callback ABI |
| AVPlayerItemNewAccessLogEntryNotification | 外部符号导入；不是 callback ABI |

BRMediaPlayer 的 setState:error: 为 `c16@0:4i8^@12`，状态枚举值仍未确认；setElapsedTime: 为 `v16@0:4d8`，duration/rate/elapsedTime 为 `d8@0:4`；setStartPosition:/setVolume: 为 `v12@0:4f8`。subtitleOptions/audioOptions 与选择方法的对象 ABI 已证实，支持格式与播放效果未证实。

AVURLAssetHTTPHeaderFieldsKey、AVURLAssetHTTPCookiesKey、AVURLAssetOutOfBandAlternateTracksKey 为外部符号引用；认证 header 传播/重定向、HLS、外挂字幕不能判通过。Codec/profile、硬解能力、AC3、state 枚举、asset 数据模型、player factory、回调生命周期仍 PROVISIONAL。
