import AVFoundation
import Combine
import MediaPlayer
import SwiftData

/// High-frequency timeline updates live here so list screens do not redraw on every tick.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isSeekable = false

    func clear() {
        currentTime = 0
        duration = 0
        isSeekable = false
    }
}

/// One selected snapshot, one utterance at a time; model access stays on MainActor.
@MainActor
final class SpeechPlaybackController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var selectedID: UUID?
    @Published private(set) var selectedSnippet: Snippet?
    @Published private(set) var title = "尚未选择片段"
    @Published private(set) var text = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var voiceDescription = ""
    @Published private(set) var needsVoiceDownload = false
    @Published private(set) var notice: String?

    /// Observed only by the now-playing UI; list views must not subscribe to this.
    let progress = PlaybackProgress()
    let settings = TTSSettings()
    private let tts = DoubaoTTS()
    @Published private(set) var synthesizing: Set<UUID> = []
    @Published private(set) var synthesisErrors: [UUID: String] = [:]
    private var generations: [UUID: UUID] = [:]
    private var audioPlayer: AVAudioPlayer?
    private var synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var activeUtteranceID: ObjectIdentifier?
    private var observations: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var progressTimer: Timer?
    /// While the user drags the scrubber, freeze published currentTime updates.
    private var isScrubbing = false

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        refreshVoice()
        observeAudioSession()
        configureRemoteCommands()
    }

    func refreshVoice() {
        voice = VoiceSelector.preferredEnglishVoice()
        if let snippet = selectedSnippet,
           AudioCache.existingURL(for: snippet, voice: settings.configuration.voice) != nil {
            voiceDescription = "豆包 · " + (TTSConfiguration.voices.first { $0.0 == settings.configuration.voice }?.1 ?? settings.configuration.voice)
            needsVoiceDownload = false
            return
        }
        needsVoiceDownload = voice == nil || voice?.quality == .default
        let quality = voice?.quality == .premium ? "Premium" : voice?.quality == .enhanced ? "Enhanced" : "标准"
        voiceDescription = voice.map { "\($0.name) · \(quality) · \($0.language)" } ?? "系统英语语音不可用"
    }

    func select(_ snippet: Snippet) {
        guard selectedID != snippet.id || text != snippet.text || title != snippet.title else { return }
        stop()
        selectedSnippet = snippet
        selectedID = snippet.id
        title = snippet.title
        text = snippet.text
        refreshVoice()
        updateNowPlaying()
    }

    func clearIfSelected(_ id: UUID) {
        guard selectedID == id else { return }
        stop()
        selectedSnippet = nil
        selectedID = nil
        title = "尚未选择片段"
        text = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func play() {
        guard selectedID != nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isPlaying else { return }
        refreshVoice()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            notice = nil
            isPlaying = true
            if let snippet = selectedSnippet,
               let url = AudioCache.existingURL(for: snippet, voice: settings.configuration.voice) {
                do {
                    if audioPlayer == nil {
                        let player = try AVAudioPlayer(contentsOf: url)
                        player.numberOfLoops = 0
                        player.delegate = self
                        player.prepareToPlay()
                        audioPlayer = player
                        progress.duration = player.duration
                        progress.isSeekable = player.duration > 0
                        progress.currentTime = 0
                    }
                    guard audioPlayer?.play() == true else { throw TTSError.response }
                    startProgressTimer()
                    updateNowPlaying()
                    return
                } catch {
                    audioPlayer = nil
                    clearProgress()
                    notice = "缓存音频无法播放，已使用 Apple 系统语音。"
                }
            } else {
                notice = "本地音频不可用，已使用 Apple 系统语音。"
            }
            clearProgress()
            voiceDescription = voice.map { "Apple · \($0.name) · \($0.language)" } ?? "系统英语语音不可用"
            needsVoiceDownload = voice == nil || voice?.quality == .default
            guard voice != nil else {
                isPlaying = false
                notice = "未找到英语语音，请先在系统设置下载。"
                deactivateSession()
                updateNowPlaying()
                return
            }
            if synthesizer.isPaused {
                if !synthesizer.continueSpeaking() { replaceSynthesizer(); speakOnce() }
            } else {
                speakOnce()
            }
            updateNowPlaying()
        } catch {
            isPlaying = false
            clearProgress()
            notice = "无法启动音频：\(error.localizedDescription)"
            updateNowPlaying()
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        audioPlayer?.pause()
        stopProgressTimer()
        publishProgressFromPlayer()
        if audioPlayer == nil && !synthesizer.pauseSpeaking(at: .immediate) { replaceSynthesizer() }
        updateNowPlaying()
        deactivateSession()
    }

    func stop() {
        isPlaying = false
        stopProgressTimer()
        audioPlayer?.delegate = nil
        audioPlayer?.stop()
        audioPlayer = nil
        clearProgress()
        replaceSynthesizer()
        updateNowPlaying()
        deactivateSession()
    }

    /// Seek within the current Doubao/cache loop. No-op for Apple TTS.
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer, player.duration > 0 else { return }
        let clamped = min(max(0, time), max(0, player.duration - 0.05))
        player.currentTime = clamped
        progress.currentTime = clamped
        updateNowPlaying()
        if isPlaying, !player.isPlaying {
            _ = player.play()
            startProgressTimer()
        }
    }

    func beginScrubbing() {
        isScrubbing = true
    }

    func scrub(to time: TimeInterval) {
        guard progress.duration > 0 else { return }
        progress.currentTime = min(max(0, time), progress.duration)
    }

    func endScrubbing(at time: TimeInterval) {
        isScrubbing = false
        seek(to: time)
    }

    private func clearProgress() {
        progress.clear()
        isScrubbing = false
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.publishProgressFromPlayer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
        publishProgressFromPlayer()
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func publishProgressFromPlayer() {
        guard let player = audioPlayer else { return }
        progress.duration = player.duration
        progress.isSeekable = player.duration > 0
        if !isScrubbing {
            progress.currentTime = player.currentTime
        }
        updateNowPlayingElapsed()
    }

    private func replaceSynthesizer() {
        activeUtteranceID = nil
        // Detach first: cancelled utterances must never restart an old loop.
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }

    private func speakOnce() {
        guard isPlaying else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        activeUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Pass only Sendable identities across actors, never AVFoundation objects or models.
        let synthesizerID = ObjectIdentifier(synthesizer)
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finished(synthesizerID: synthesizerID, utteranceID: utteranceID)
        }
    }

    private func finished(synthesizerID: ObjectIdentifier, utteranceID: ObjectIdentifier) {
        guard synthesizerID == ObjectIdentifier(synthesizer),
              activeUtteranceID == utteranceID else { return }
        // A finish queued just before pause still counts; speakOnce checks isPlaying.
        // Consume before saving or starting another read-through: count each finish once.
        activeUtteranceID = nil
        recordCompletion()
        speakOnce()
    }

    private func recordCompletion() {
        if let snippet = selectedSnippet, snippet.id == selectedID,
           let context = snippet.modelContext {
            let previousCount = snippet.playCount
            let previousDate = snippet.lastPlayedAt
            snippet.playCount += 1
            snippet.lastPlayedAt = .now
            do {
                try context.save()
            } catch {
                // Restore only these statistics; do not roll back unrelated model edits.
                snippet.playCount = previousCount
                snippet.lastPlayedAt = previousDate
                notice = "播放次数保存失败：\(error.localizedDescription)"
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.audioPlayer, ObjectIdentifier(current) == identity else { return }
            guard flag else {
                self.stop()
                self.notice = "音频播放失败，请重新合成。"
                return
            }
            self.recordCompletion()
            if self.isPlaying {
                current.currentTime = 0
                self.progress.currentTime = 0
                if !current.play() {
                    self.stop()
                    self.notice = "无法继续播放，请点击播放重试。"
                } else {
                    self.startProgressTimer()
                    self.updateNowPlaying()
                }
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.audioPlayer, ObjectIdentifier(current) == identity else { return }
            self.stop()
            self.notice = "缓存音频解码失败，请重新合成。"
        }
    }

    func synthesize(_ snippet: Snippet, force: Bool = false) async {
        let configuration = settings.configuration
        guard configuration.isReady else { return }
        if !force, AudioCache.existingURL(for: snippet, voice: configuration.voice) != nil { return }
        let id = snippet.id
        let content = snippet.text
        let hash = AudioCache.hash(text: content, voice: configuration.voice)
        let generation = UUID()
        generations[id] = generation
        synthesizing.insert(id)
        synthesisErrors[id] = nil
        if selectedID == id { stop() }
        defer {
            if generations[id] == generation {
                synthesizing.remove(id)
                generations[id] = nil
            }
        }
        do {
            let data = try await tts.synthesize(text: content, configuration: configuration)
            try Task.checkCancellation()
            guard generations[id] == generation, snippet.modelContext != nil,
                  snippet.text == content, settings.configuration.voice == configuration.voice else { return }
            // Invalidate metadata before replacing the fixed-path file. A failed model save
            // must never leave an old hash pointing at new audio.
            snippet.audioContentHash = nil
            snippet.audioRelativePath = nil
            try snippet.modelContext?.save()
            if selectedID == id { stop() }
            try data.write(to: AudioCache.url(id: id), options: .atomic)
            snippet.audioRelativePath = "Audio/\(id.uuidString).mp3"
            snippet.audioContentHash = hash
            do { try snippet.modelContext?.save() }
            catch {
                snippet.audioRelativePath = nil
                snippet.audioContentHash = nil
                throw error
            }
            refreshVoice()
        } catch {
            if generations[id] == generation {
                synthesisErrors[id] = "合成失败，可使用系统语音。\(error is TTSError ? error.localizedDescription : "请稍后重试。")"
            }
        }
    }

    func removeAudio(id: UUID) throws {
        generations[id] = nil
        synthesizing.remove(id)
        synthesisErrors[id] = nil
        clearIfSelected(id)
        try AudioCache.remove(id: id)
    }

    func testVoice(configuration: TTSConfiguration) async throws -> Data {
        try await tts.synthesize(text: "Hello! Welcome to LoopSpeak. Let's practice English together.", configuration: configuration)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func safetyPause(_ message: String) {
        guard isPlaying || synthesizer.isPaused || audioPlayer != nil else { return }
        stop()
        notice = message
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self?.safetyPause("音频已中断，点击播放从本句开头继续。")
                }
                // Never honor shouldResume automatically.
            }
        })
        observations.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            // Our own setCategory call also emits a notification; it is not a route loss.
            guard reason != AVAudioSession.RouteChangeReason.categoryChange.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.safetyPause("音频输出已改变，确认耳机后点击播放。")
            }
        })
        observations.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
                self?.notice = "音频服务已重置，请点击播放。"
            }
        })
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.play() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.isPlaying ? $0.pause() : $0.play() }
        register(center.stopCommand) { $0.stop() }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = true
        let seekTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(to: event.positionTime)
            }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, seekTarget))
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (SpeechPlaybackController) -> Void) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
            return .success
        }
        remoteTargets.append((command, target))
    }

    private func updateNowPlaying() {
        guard selectedID != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "LoopSpeak · 单句无限循环 ∞",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if progress.isSeekable, progress.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = progress.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.currentTime
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
        } else {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard progress.isSeekable, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.currentTime
        info[MPMediaItemPropertyPlaybackDuration] = progress.duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
