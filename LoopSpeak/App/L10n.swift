import Foundation
import Combine

/// UI language only. Never used to select a TTS voice or utterance language.
enum UILanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
}

final class AppLanguage: ObservableObject {
    @Published var selection: UILanguage {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: L10n.preferenceKey) }
    }
    init() { selection = L10n.selection }
    var locale: Locale { Locale(identifier: L10n.isChinese ? "zh-Hans" : "en") }
}

enum L10n {
    static let preferenceKey = "LoopSpeak.uiLanguage"
    static var selection: UILanguage {
        UILanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system
    }
    static var isChinese: Bool {
        switch selection {
        case .chinese: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") == true
        }
    }
    enum Key: CaseIterable {
        case apiKey, resourceId, delete, premium, enhanced
        case settings
        case addSnippet
        case resetQuestion
        case resetZero
        case cancel
        case resetExplanation
        case cannotSave
        case ok
        case credentialsBanner
        case emptyTitle
        case emptyDescription
        case edit
        case editSnippet
        case resetCount
        case cleanupError
        case snippetIndex
        case synthesizing
        case repeatCount
        case lastFullPlay
        case neverFinishedFullPlay
        case singleLoop
        case pause
        case play
        case optionalTitle
        case titleExample
        case englishContent
        case contentAccessibility
        case saveHint
        case synthesizingSpeech
        case done
        case save
        case saveError
        case infiniteLoop
        case stop
        case looping
        case paused
        case voiceDownload
        case nowPlaying
        case seekHint
        case credentials
        case credentialsHint
        case migration
        case presetVoice
        case custom
        case customVoice
        case customHint
        case voice
        case voiceHint
        case saveSettings
        case resynthesize
        case testVoice
        case testing
        case testSuccess
        case synthesisHint
        case processing
        case fallbackBanner
        case speechSettings
        case savedFallback
        case savedVoice
        case newVoiceSynthesis
        case savedSynthesis
        case savedFailures
        case keepOpen
        case synthesisComplete
        case synthesisFailures
        case noSelection
        case doubao
        case standard
        case noEnglishVoice
        case cacheFallback
        case localFallback
        case missingEnglishVoice
        case audioStartError
        case countSaveError
        case audioFailed
        case resumeFailed
        case decodeFailed
        case synthesisError
        case retry
        case interrupted
        case routeChanged
        case servicesReset
        case remoteArtist
        case michael
        case keychainError
        case networkError
        case httpError
        case serverError
        case invalidResponse
        case emptyAudio
        case missingKey
        case missingResource
        case missingVoice
        case configurationError
        case noErrorDetails
        case redacted
        case language
        case system
        case languageHint
        case seek
    }
    static func text(_ key: Key, _ arguments: String...) -> String {
        let pair = translations[key]!
        let template = isChinese ? pair.0 : pair.1
        return String(format: template, locale: Locale(identifier: isChinese ? "zh-Hans" : "en"), arguments: arguments)
    }
    /// Store message identity so banners and async results also follow language changes.
    struct Message {
        private let key: Key?
        private let arguments: [String]
        private let error: (any Error)?
        private var details: [Message] = []
        init(_ key: Key, _ arguments: String...) {
            self.key = key
            self.arguments = arguments
            self.error = nil
        }
        init(error: any Error) {
            key = nil
            arguments = []
            self.error = error
        }
        init(_ key: Key, detail: Message) {
            self.key = key
            arguments = []
            error = nil
            details = [detail]
        }
        var string: String {
            if let error { return error.localizedDescription }
            guard let key else { return "" }
            let pair = L10n.translations[key]!
            return String(format: L10n.isChinese ? pair.0 : pair.1, arguments: arguments + details.map(\.string))
        }
    }
    private static let translations: [Key: (String, String)] = [
        .premium: ("优质", "Premium"),
        .enhanced: ("增强", "Enhanced"),
        .apiKey: ("API 密钥", "API Key"),
        .resourceId: ("资源 ID", "Resource Id"),
        .delete: ("删除", "Delete"),
        .settings: ("设置", "Settings"),
        .addSnippet: ("添加片段", "Add Snippet"),
        .resetQuestion: ("重置播放次数？", "Reset play count?"),
        .resetZero: ("重置为 0", "Reset to 0"),
        .cancel: ("取消", "Cancel"),
        .resetExplanation: ("将清除该片段的累计播放次数及最近播放时间。正在进行的朗读完整结束后仍会计数。", "This clears the snippet’s play count and last played time. A reading currently in progress will still count when it finishes."),
        .cannotSave: ("无法保存", "Unable to Save"),
        .ok: ("好", "OK"),
        .credentialsBanner: ("未配置豆包凭据，使用 Apple 系统语音。请在设置中配置。", "Doubao credentials are missing. Using Apple system speech. Configure credentials in Settings."),
        .emptyTitle: ("开始英语循环练习", "Start English Loop Practice"),
        .emptyDescription: ("点击右上角 + 添加英语片段，保存后点击播放。", "Tap + in the top right to add an English snippet, then save and play."),
        .edit: ("编辑", "Edit"),
        .editSnippet: ("编辑片段", "Edit Snippet"),
        .resetCount: ("重置播放次数", "Reset Play Count"),
        .cleanupError: ("片段已删除，但音频文件清理失败：%@", "Snippet deleted, but audio cleanup failed: %@"),
        .snippetIndex: ("第 %@ 条", "Snippet %@"),
        .synthesizing: ("正在合成…", "Synthesizing…"),
        .repeatCount: ("已重复 %@ 遍", "Completed repeats: %@"),
        .lastFullPlay: ("上次完整播完：%@", "Last full play: %@"),
        .neverFinishedFullPlay: ("尚未完整播完", "Never finished a full play"),
        .singleLoop: ("单句循环", "Single-snippet loop"),
        .pause: ("暂停", "Pause"),
        .play: ("播放", "Play"),
        .optionalTitle: ("标题（可选）", "Title (optional)"),
        .titleExample: ("例如：自我介绍", "For example: Self-introduction"),
        .englishContent: ("英语内容", "English Content"),
        .contentAccessibility: ("英语片段内容", "English snippet content"),
        .saveHint: ("保存后点击播放。当前片段将无限循环，直到暂停或停止。", "Save, then tap Play. The snippet repeats until you pause or stop."),
        .synthesizingSpeech: ("正在合成语音…", "Synthesizing speech…"),
        .done: ("完成", "Done"),
        .save: ("保存", "Save"),
        .saveError: ("保存失败：%@", "Save failed: %@"),
        .infiniteLoop: ("单句无限循环", "Repeat one snippet forever"),
        .stop: ("停止", "Stop"),
        .looping: ("正在循环 ∞", "Looping ∞"),
        .paused: ("已暂停 · 点击播放继续", "Paused · Tap Play to continue"),
        .voiceDownload: ("想要更自然的发音？前往 设置 > 辅助功能 > 朗读内容 > 声音 > 英语，下载增强或优质语音（Enhanced / Premium）。", "For more natural speech, go to Settings > Accessibility > Spoken Content > Voices > English and download an Enhanced or Premium voice."),
        .nowPlaying: ("正在播放", "Now Playing"),
        .seekHint: ("Apple 系统语音不支持拖动进度；豆包缓存音频可拖动。", "Seeking is available for cached Doubao audio. Apple system speech does not support seeking."),
        .credentials: ("凭据", "Credentials"),
        .credentialsHint: ("凭据仅存储在钥匙串。Resource Id 默认 seed-tts-2.0，也可填写 seed-icl-2.0，需与音色及授权匹配。", "Credentials are stored only in Keychain. Resource Id defaults to seed-tts-2.0; seed-icl-2.0 is also supported. It must match your voice and authorization."),
        .migration: ("请改用控制台 API Key", "Switch to the console API Key"),
        .presetVoice: ("预设音色", "Preset Voice"),
        .custom: ("自定义", "Custom"),
        .customVoice: ("自定义音色 ID", "Custom Voice ID"),
        .customHint: ("选「自定义」并填写音色库里的 speaker ID；点「保存设置」或「完成」都会写入钥匙串。", "Choose Custom and enter a speaker ID from the voice library. Save Settings and Done both save to Keychain."),
        .voice: ("音色", "Voice"),
        .voiceHint: ("新版控制台只需 API Key；Secret Key / AppID 不用于本接口。音色例如 en_male_michael_uranus_bigtts。合成一次后本地循环不计费。", "Only the console API Key is required; this API does not use Secret Key / AppID. Example voice: en_male_michael_uranus_bigtts. Local looping after synthesis incurs no extra charges."),
        .saveSettings: ("保存设置", "Save Settings"),
        .resynthesize: ("重新合成全部片段", "Resynthesize All Snippets"),
        .testVoice: ("测试：合成一句英语", "Test: Synthesize an English Sentence"),
        .testing: ("正在合成测试语音…", "Synthesizing test speech…"),
        .testSuccess: ("测试合成成功（%@ 字节 MP3）。当前音色：%@", "Test succeeded (%@ bytes of MP3). Voice: %@"),
        .synthesisHint: ("保存声音变化后会自动合成全部片段；相同正文和声音已有缓存则跳过。强制重新合成会消耗额度。保存、合成均不会自动播放。", "Saving voice changes synthesizes all snippets, skipping matching cached text and voice. Forced resynthesis uses your quota. Saving and synthesis do not start playback."),
        .processing: ("处理中 %@/%@", "Processing %@/%@"),
        .fallbackBanner: ("尚未配置凭据，将使用 Apple 系统语音。", "No credentials configured. Apple system speech will be used."),
        .speechSettings: ("语音设置", "Speech Settings"),
        .savedFallback: ("设置已保存，将使用 Apple 系统语音。", "Settings saved. Apple system speech will be used."),
        .savedVoice: ("设置已保存。当前音色：%@", "Settings saved. Voice: %@"),
        .newVoiceSynthesis: ("正在按新音色合成，请稍候…", "Synthesizing with the new voice. Please wait…"),
        .savedSynthesis: ("设置已保存，音色：%@。合成完成。", "Settings saved. Voice: %@. Synthesis complete."),
        .savedFailures: ("设置已保存，音色：%@。其中 %@ 条合成失败。", "Settings saved. Voice: %@. %@ snippets failed to synthesize."),
        .keepOpen: ("正在合成，请保持此页面打开。", "Synthesizing. Keep this page open."),
        .synthesisComplete: ("合成完成，音色：%@。点击片段播放。", "Synthesis complete. Voice: %@. Tap a snippet to play."),
        .synthesisFailures: ("合成完成，其中 %@ 条失败，可使用系统语音或重试。", "Synthesis complete with %@ failures. Use system speech or try again."),
        .noSelection: ("尚未选择片段", "No snippet selected"),
        .doubao: ("豆包 · ", "Doubao · "),
        .standard: ("标准", "Standard"),
        .noEnglishVoice: ("系统英语语音不可用", "System English voice unavailable"),
        .cacheFallback: ("缓存音频无法播放，已使用 Apple 系统语音。", "Cached audio could not play. Using Apple system speech."),
        .localFallback: ("本地音频不可用，已使用 Apple 系统语音。", "Local audio unavailable. Using Apple system speech."),
        .missingEnglishVoice: ("未找到英语语音，请先在系统设置下载。", "No English voice found. Download one in system Settings."),
        .audioStartError: ("无法启动音频：%@", "Unable to start audio: %@"),
        .countSaveError: ("播放次数保存失败：%@", "Could not save play count: %@"),
        .audioFailed: ("音频播放失败，请重新合成。", "Audio playback failed. Resynthesize the snippet."),
        .resumeFailed: ("无法继续播放，请点击播放重试。", "Unable to continue playback. Tap Play to retry."),
        .decodeFailed: ("缓存音频解码失败，请重新合成。", "Cached audio could not be decoded. Resynthesize the snippet."),
        .synthesisError: ("合成失败，可使用系统语音。%@", "Synthesis failed. You can use system speech. %@"),
        .retry: ("请稍后重试。", "Please try again later."),
        .interrupted: ("音频已中断，点击播放从本句开头继续。", "Audio interrupted. Tap Play to restart this snippet."),
        .routeChanged: ("音频输出已改变，确认耳机后点击播放。", "Audio output changed. Check your headphones, then tap Play."),
        .servicesReset: ("音频服务已重置，请点击播放。", "Audio services reset. Tap Play to continue."),
        .remoteArtist: ("LoopSpeak · 单句无限循环 ∞", "LoopSpeak · Repeat one snippet ∞"),
        .michael: ("Michael（男）", "Michael (Male)"),
        .keychainError: ("钥匙串读写失败（%@）", "Keychain access failed (%@)"),
        .networkError: ("语音请求网络失败（%@），请检查网络连接。", "Speech request network error (%@). Check your connection."),
        .httpError: ("语音服务 HTTP 错误（%@），请检查 API Key、资源授权及服务状态。", "Speech service HTTP error (%@). Check your API Key, resource authorization, and service status."),
        .serverError: ("语音服务 V3 错误（%@）：%@", "Speech service V3 error (%@): %@"),
        .invalidResponse: ("语音服务返回格式无效，或音频无法解码、播放。", "Invalid speech service response, or audio could not be decoded or played."),
        .emptyAudio: ("语音服务未返回音频，请检查音色授权、文本及额度。", "The speech service returned no audio. Check voice authorization, text, and quota."),
        .missingKey: ("请填写控制台 API Key。", "Enter your console API Key."),
        .missingResource: ("请填写 Resource Id，例如 seed-tts-2.0。", "Enter a Resource Id, such as seed-tts-2.0."),
        .missingVoice: ("请填写控制台音色库中的 speaker 音色 ID。", "Enter a speaker ID from the console voice library."),
        .configurationError: ("无法读取语音配置，请重新保存。", "Unable to read speech settings. Save them again."),
        .noErrorDetails: ("服务未提供错误详情", "The service provided no error details"),
        .redacted: ("[已隐藏]", "[redacted]"),
        .language: ("界面语言", "UI Language"),
        .system: ("跟随系统", "Follow System"),
        .languageHint: ("仅更改界面语言，不改变片段内容或朗读语言。", "Changes the interface language only. Snippet content and speech language stay unchanged."),
        .seek: ("播放进度", "Playback position"),
    ]
}
