# LoopSpeak

**中文** · [English](README_EN.md)

**版本 1.0** · iOS 英语单句无限循环练习

LoopSpeak 是一款面向英语口语跟读的 iPhone 应用：把一句（或一小段）英语存成片段，保存时用火山引擎**豆包语音**合成一次 MP3，之后在本地无限循环播放。界面为中文，基于 **iOS 26 / SwiftUI**，保留 Liquid Glass 控件风格。

缺少豆包凭据、离线合成失败或缓存不可用时，自动回退到 **Apple 系统英语语音**。保存与合成完成后**不会自动播放**，需手动点播放。

---

## 功能概览

| 能力 | 说明 |
|------|------|
| 片段管理 | 添加 / 编辑 / 删除英语正文与可选标题；SwiftData 本地持久化 |
| 云端合成 | 豆包 V3 HTTP 单向流式 TTS，合成 MP3（24 kHz）后落盘 |
| 本地循环 | 同一句无限循环；每完整播完一遍才累加播放次数 |
| 系统回退 | 无凭据 / 无缓存 / 缓存损坏时使用 AVSpeechSynthesizer |
| 后台与锁屏 | `UIBackgroundModes = audio`；锁屏与耳机支持播控 |
| 进度条 | 豆包缓存音频可拖动定位；系统 TTS 不支持 seek |
| 统计 | 累计播放遍数、最近播放时间；可长按重置 |
| 凭据安全 | API Key 等仅存 Keychain，不写 UserDefaults / 日志 |

---

## 环境要求

- **macOS** + **Xcode 26**（或更新）及 iOS 平台组件
- **真机**：iOS 26+ iPhone（建议真机验收后台音频与耳机）
- Bundle ID 默认：`com.ivan.LoopSpeak`
- 可选：火山引擎豆包语音合成额度（不配置也能用系统语音练习）

---

## 在 Mac 上打开与运行

1. 用 Xcode 打开 `LoopSpeak.xcodeproj`，选择共享 Scheme **LoopSpeak**。
2. **Signing & Capabilities** → Team 选自己的 Apple ID / Personal Team；必要时改 Bundle Identifier。
3. 确认 **Background Modes → Audio, AirPlay, and Picture in Picture** 已勾选（工程已配置 `UIBackgroundModes = [audio]`）。
4. 连接 iPhone，信任本机并开启开发者模式，选设备后 Run。

App Icon 已包含在 `LoopSpeak/Resources/Assets.xcassets/AppIcon.appiconset`（含 1024×1024）。

---

## 配置豆包语音（可选但推荐）

### 1. 获取 API Key

1. 打开 [火山引擎控制台](https://console.volcengine.com/)，进入 **语音技术 → 豆包语音 → 语音合成**。
2. 开通服务后，在 **API Key 管理** 创建并复制 **API Key**。
3. 新版接口**只需 API Key**。不要把旧版 Access Token / Secret Key / AppID / Cluster 当作本接口凭据。

### 2. 在 App 内填写

路径：**左上角「设置」**

| 字段 | 说明 |
|------|------|
| API Key | 控制台 API Key |
| Resource Id | 默认 `seed-tts-2.0`；也可填 `seed-icl-2.0`（需已开通且与音色匹配） |
| 预设音色 | 默认 **Michael（男）** / `en_male_michael_uranus_bigtts` |
| 自定义音色 ID | 从控制台音色库复制 speaker；**非空时优先于预设** |

操作建议：

1. 点 **「测试：合成一句英语」** → 成功会显示 MP3 字节数（不播放、不改片段）。
2. 点 **「保存设置」** 写入钥匙串；声音或凭据变化后会检查片段并合成缺失 / 失效缓存。
3. **「重新合成全部片段」** 会强制刷新并消耗额度。

### 3. 计费说明

- **每次云合成**（测试、改正文 / 换声音、强制重合成）按火山引擎规则计费。
- **合成一次后，本地循环播放不再请求云端**，循环遍数不增加 TTS 费用。
- 资格、有效期与价格以控制台为准。

### 4. 从旧版升级

旧 Access Token **不会复用**；API Key 留空并提示改用控制台 API Key，默认切到 Michael + TTS 2.0。正文与播放次数会保留，填新 Key 并保存即可。

---

## 使用说明

### 添加与编辑片段

1. 右上角 **+** → 填写英语正文（必填）与可选标题。
2. **保存**：先持久化正文，再异步合成；界面显示进度。
3. 合成失败时正文仍保留，可回退系统语音。
4. 列表项：**左滑删除**；**右滑或长按 → 编辑**。
5. 长按可 **重置播放次数** 与最近播放时间。

### 播放

1. 点列表中的片段进入播放器，再手动点 **播放**。
2. 底部迷你播放器、锁屏、耳机均可 **播放 / 暂停 / 停止**。
3. 豆包缓存音频支持进度拖动与锁屏 scrub；系统语音回退时为“直播流”式信息，不可 seek。
4. **暂停**尽量保留进度；**停止**后从头开始。
5. 耳机断开、音频路线变化、来电或 Siri 中断后会停止并保持暂停，**不会自动恢复**，需手动再点播放。

### 播放计数规则

- 使用 `AVAudioPlayer.numberOfLoops = 0`：每遍**完整结束**才 `playCount + 1`，并更新 `lastPlayedAt`，然后立即从头再播同一文件。
- 中途暂停 / 停止 **不计次**；暂停后继续并完整结束计 **1** 次。
- 系统语音回退同样按完整朗读结束计数。
- 无播放列表跳转，始终单句循环。

### 缓存与离线

- MP3 路径：`Application Support/Audio/{片段 UUID}.mp3`
- SwiftData 存相对路径 + `SHA256(声音 + `\0` + 正文)`
- **正文与声音哈希一致且文件存在** → 不重复请求云端
- **只改标题** → 不消耗额度
- **更换声音** → 旧缓存不再用于新声音；需重新合成
- 更换 API Key / Resource Id **不会**使相同正文+声音的缓存失效；要刷新请用强制重合成
- 飞行模式下可直接播已有缓存；无缓存则用系统英语语音

建议在 iPhone：**设置 → 辅助功能 → 朗读内容 → 声音 → 英语** 下载 Enhanced / Premium；App 优先美式英语与高质量声音。

### 数据与隐私

- 正文、次数、MP3 均在**本机**；启动不自动播放。
- **卸载会清除 App 数据**；本版无云同步 / 导出。
- API Key、Resource Id、音色配置仅存 **Keychain**（`AfterFirstUnlockThisDeviceOnly`），不写 UserDefaults、SwiftData 或日志。
- 合成时正文经 HTTPS 发往火山引擎；请勿把 API Key 提交进仓库或截进截图。
- 错误提示会脱敏服务端 message 中回显的 API Key。

---

## 项目结构

```
loop_speak/
├── LoopSpeak.xcodeproj
├── LoopSpeak/
│   ├── App/LoopSpeakApp.swift          # 入口，SwiftData + 播放控制器
│   ├── Models/Snippet.swift            # 片段模型
│   ├── TTS/DoubaoTTS.swift             # 配置、Keychain、V3 合成、音频缓存
│   ├── Playback/
│   │   ├── SpeechPlaybackController.swift  # 播放、合成协调、锁屏、远程命令
│   │   └── VoiceSelector.swift             # 系统英语音色优选
│   ├── Views/
│   │   ├── SnippetListView.swift       # 列表 + 迷你播放器
│   │   ├── SnippetEditorView.swift     # 添加 / 编辑
│   │   ├── NowPlayingView.swift        # 播放页 + seek
│   │   ├── TTSSettingsView.swift       # 凭据与批量合成
│   │   └── GlassPanel.swift            # Liquid Glass 控件
│   └── Resources/                      # Info.plist、Assets、图标
└── Tests/test_tts.py                   # 配置迁移与响应解析离线测试
```

### 核心模块职责

- **`Snippet`**：正文、标题、音频相对路径 / 内容哈希、累计次数、最近播放时间；新字段带默认值，兼容旧库轻量迁移。
- **`DoubaoTTS`**：独立 `actor` 发 V3 请求；解析单 JSON / NDJSON / 相邻多 JSON；拼接 `code == 0` 的 base64 音频；`code == 20000000` 为流式成功结束码（非失败）。
- **`SpeechPlaybackController`**：`MainActor` 统一播放与异步合成；完整播放计数；中断永不自动恢复；`PlaybackProgress` 单独观察，避免列表 4Hz 重绘。
- **`AudioCache`**：哈希与原子写文件；写新文件前先清旧元数据，避免失败时哈希指向新音频。

### TTS 接口摘要

使用 [豆包 V3 HTTP 单向流式接口](https://docs.volcengine.com/docs/DoubaoVoice/unidirectional-streaming-text-to-speech-http?lang=zh)：

```
POST https://openspeech.bytedance.com/api/v3/tts/unidirectional
```

请求头：`X-Api-Key`、`X-Api-Resource-Id`、`X-Api-Request-Id`（UUID）、`Content-Type: application/json`。

`req_params` 含 text、speaker、`audio_params`（mp3 / 24000 Hz），以及  
`additions: "{\"explicit_language\":\"en\"}"`。无需 WebSocket。

---

## 测试

在装有 Swift 的 Mac 上执行（不发网络请求、不需要真实 Key）：

```bash
python3 Tests/test_tts.py
```

脚本从 `DoubaoTTS.swift` 抽出配置与解析器，覆盖：

- 旧配置迁移、Keychain 编码不保存旧 Token
- 单 JSON / NDJSON / 连续 JSON 拼接
- usage 结尾、非零 code、Key 脱敏
- 非法 base64、截断响应、空音频

该测试**不加入** App target。

---

## 建议验收清单（Mac / 真机）

- [ ] Xcode 26 编译安装；后台 Audio、签名、Swift 文件均在 target 内
- [ ] 从旧版升级：正文与次数保留，无需清库
- [ ] 无凭据：横幅提示，系统语音循环，完整结束才计数
- [ ] 有效凭据：测试成功；保存有合成进度、无自动播放；生成 UUID MP3；飞行模式可播缓存
- [ ] 只改标题不合成；改正文 / 换声音出新缓存；重启后复用；强制重合成与批量错误数正确
- [ ] 错误 Key / Resource / speaker、断网、HTTP / V3 错误、空音频：有明确中文提示，正文不丢，Key 被脱敏
- [ ] 删除后磁盘无对应 MP3；无幽灵循环
- [ ] 暂停 / 继续 / 停止 / 计数 / 重置 / 持久化正确；锁屏与后台可持续循环；AirPods 与远程控制同步
- [ ] 来电、Siri、耳机断开、切输出后**无自动恢复**
- [ ] 大字号、深色模式、VoiceOver、玻璃控件与错误提示可用

> 模拟器不能替代真机的后台音频与耳机验收。

---

## 本版范围与限制

- 仅本地存储，无账号、无 iCloud / 导出
- 面向**单句循环**练习，无多句播放列表
- 依赖豆包额度时需自行开通；不配置亦可系统语音使用
- 面向 iOS 26+；需 Xcode 26 构建

---

## License

本项目以 [MIT License](LICENSE) 开源发布。

使用豆包语音合成时，需自行在火山引擎开通服务并遵守其条款；请勿将 API Key 等凭据提交到本仓库。
