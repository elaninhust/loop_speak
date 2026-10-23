import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var language: AppLanguage
    @EnvironmentObject private var playback: SpeechPlaybackController
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    private var repeatStatistics: some View {
        Label(L10n.text(.infiniteLoop), systemImage: "infinity")
        if let snippet = playback.selectedSnippet {
            Text(L10n.text(.repeatCount, String(snippet.playCount)))
                .monospacedDigit()
        }
    }

    var body: some View {
        let _ = language.selection
        ScrollView {
            VStack(spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { repeatStatistics }
                    VStack(spacing: 6) { repeatStatistics }
                }
                .font(.headline).foregroundStyle(.tint)
                if let snippet = playback.selectedSnippet {
                    LastFinishedPlayView(lastPlayedAt: snippet.lastPlayedAt)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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
                    .accessibilityLabel(playback.isPlaying ? L10n.text(.pause) : L10n.text(.play))
                    Button { playback.stop() } label: {
                        Label(L10n.text(.stop), systemImage: "stop.fill")
                    }.buttonStyle(.bordered)
                }
                Text(playback.isPlaying ? L10n.text(.looping) : L10n.text(.paused))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text(playback.voiceDescription).font(.footnote)
                    if playback.needsVoiceDownload {
                        Text(L10n.text(.voiceDownload))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let notice = playback.notice {
                        Text(notice.string).font(.callout).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(24)
        }
        .navigationTitle(L10n.text(.nowPlaying))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.accentColor.opacity(0.06))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { playback.refreshVoice() }
        }
    }
}

/// Subscribes only to PlaybackProgress so 4Hz ticks stay off SnippetListView.
private struct SeekBar: View {
    @EnvironmentObject private var language: AppLanguage
    @ObservedObject var progress: PlaybackProgress
    let beginScrubbing: () -> Void
    let endScrubbing: (TimeInterval) -> Void
    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false

    var body: some View {
        let _ = language.selection
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
                .accessibilityLabel(L10n.text(.seek))
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
            Text(L10n.text(.seekHint))
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
