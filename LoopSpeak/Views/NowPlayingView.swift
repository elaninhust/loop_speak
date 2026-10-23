import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var playback: SpeechPlaybackController
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    private var repeatStatistics: some View {
        Label("单句无限循环", systemImage: "infinity")
        if let snippet = playback.selectedSnippet {
            Text("已重复 \(snippet.playCount) 遍")
                .monospacedDigit()
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { repeatStatistics }
                    VStack(spacing: 6) { repeatStatistics }
                }
                .font(.headline).foregroundStyle(.tint)
                Text(playback.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(playback.text).font(.title3).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Isolated observer: progress ticks do not invalidate the rest of this screen's parent list.
                SeekBar(
                    progress: playback.progress,
                    beginScrubbing: { playback.beginScrubbing() },
                    endScrubbing: { playback.endScrubbing(at: $0) }
                )

                HStack(spacing: 32) {
                    Button { playback.isPlaying ? playback.pause() : playback.play() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48)).frame(width: 104, height: 104)
                    }
                    .buttonStyle(.plain)
                    .loopGlass()
                    .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
                    Button { playback.stop() } label: {
                        Label("停止", systemImage: "stop.fill")
                    }.buttonStyle(.bordered)
                }
                Text(playback.isPlaying ? "正在循环 ∞" : "已暂停 · 点击播放继续")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text(playback.voiceDescription).font(.footnote)
                    if playback.needsVoiceDownload {
                        Text("想要更自然的发音？前往 设置 > 辅助功能 > 朗读内容 > 声音 > 英语，下载增强或优质语音（Enhanced / Premium）。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let notice = playback.notice {
                        Text(notice).font(.callout).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(24)
        }
        .navigationTitle("正在播放")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.accentColor.opacity(0.06))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { playback.refreshVoice() }
        }
    }
}

/// Subscribes only to PlaybackProgress so 4Hz ticks stay off SnippetListView.
private struct SeekBar: View {
    @ObservedObject var progress: PlaybackProgress
    let beginScrubbing: () -> Void
    let endScrubbing: (TimeInterval) -> Void
    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false

    var body: some View {
        if progress.isSeekable, progress.duration > 0 {
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : progress.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(progress.duration, 0.01),
                    onEditingChanged: { editing in
                        if editing {
                            isScrubbing = true
                            scrubTime = progress.currentTime
                            beginScrubbing()
                        } else {
                            endScrubbing(scrubTime)
                            isScrubbing = false
                        }
                    }
                )
                .tint(.accentColor)
                HStack {
                    Text(formatTime(isScrubbing ? scrubTime : progress.currentTime))
                    Spacer()
                    Text(formatTime(progress.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        } else {
            Text("Apple 系统语音不支持拖动进度；豆包缓存音频可拖动。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
