import SwiftUI
import SwiftData

struct SnippetListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var playback: SpeechPlaybackController
    @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
    @State private var showingSettings = false
    @State private var adding = false
    @State private var editing: Snippet?
    @State private var showingPlayer = false
    @State private var storageError: String?
    @State private var resetting: Snippet?

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("LoopSpeak")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("设置", systemImage: "gearshape") { showingSettings = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("添加片段", systemImage: "plus") { adding = true }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    MiniPlayerBar(showingPlayer: $showingPlayer)
                }
                .sheet(isPresented: $showingSettings) { TTSSettingsView() }
                .sheet(isPresented: $adding) { SnippetEditorView() }
                .sheet(item: $editing) { SnippetEditorView(snippet: $0) }
                .navigationDestination(isPresented: $showingPlayer) { NowPlayingView() }
                .confirmationDialog("重置播放次数？", isPresented: Binding(
                    get: { resetting != nil },
                    set: { if !$0 { resetting = nil } }
                ), titleVisibility: .visible, presenting: resetting) { snippet in
                    Button("重置为 0", role: .destructive) {
                        resetCount(for: snippet)
                        resetting = nil
                    }
                    Button("取消", role: .cancel) { resetting = nil }
                } message: { _ in
                    Text("将清除该片段的累计播放次数及最近播放时间。正在进行的朗读完整结束后仍会计数。")
                }
                .alert("无法保存", isPresented: Binding(get: { storageError != nil }, set: { if !$0 { storageError = nil } })) {
                    Button("好") { storageError = nil }
                } message: { Text(storageError ?? "") }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            if !playback.settings.configuration.isReady {
                Label("未配置豆包凭据，使用 Apple 系统语音。请在设置中配置。", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let error = playback.settings.error { Text(error).foregroundStyle(.orange) }
            if snippets.isEmpty {
                ContentUnavailableView("开始英语循环练习", systemImage: "text.bubble", description: Text("点击右上角 + 添加英语片段，保存后点击播放。"))
            }
            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                SnippetRow(
                    index: index + 1,
                    title: snippet.title,
                    text: snippet.text,
                    playCount: snippet.playCount,
                    isSelected: playback.selectedID == snippet.id,
                    isSynthesizing: playback.synthesizing.contains(snippet.id),
                    synthesisError: playback.synthesisErrors[snippet.id]
                )
                .equatable()
                .contentShape(Rectangle())
                .onTapGesture {
                    playback.select(snippet)
                    showingPlayer = true
                }
                .swipeActions(edge: .leading) {
                    Button("编辑") { editing = snippet }.tint(.blue)
                }
                .contextMenu {
                    Button("编辑片段") { editing = snippet }
                    Button("重置播放次数", systemImage: "arrow.counterclockwise", role: .destructive) {
                        resetting = snippet
                    }
                }
            }
            .onDelete(perform: delete)
        }
    }

    private func resetCount(for snippet: Snippet) {
        let previousCount = snippet.playCount
        let previousDate = snippet.lastPlayedAt
        snippet.playCount = 0
        snippet.lastPlayedAt = nil
        do {
            try context.save()
        } catch {
            snippet.playCount = previousCount
            snippet.lastPlayedAt = previousDate
            storageError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let deleted = offsets.map { snippets[$0] }
        let deletedIDs = deleted.map(\.id)
        for item in deleted { context.delete(item) }
        do {
            try context.save()
            for id in deletedIDs {
                do { try playback.removeAudio(id: id) }
                catch { storageError = "片段已删除，但音频文件清理失败：\(error.localizedDescription)" }
            }
        } catch {
            context.rollback()
            storageError = error.localizedDescription
        }
    }
}

/// Value-typed row so SwiftUI can skip redraws when only unrelated playback fields change.
private struct SnippetRow: View, Equatable {
    let index: Int
    let title: String
    let text: String
    let playCount: Int
    let isSelected: Bool
    let isSynthesizing: Bool
    let synthesisError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
                .accessibilityLabel("第 \(index) 条")

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if isSynthesizing { ProgressView("正在合成…") }
                if let synthesisError {
                    Text(synthesisError).font(.caption).foregroundStyle(.orange)
                }
                Text("已重复 \(playCount) 遍")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "infinity").foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 6)
    }

    static func == (lhs: SnippetRow, rhs: SnippetRow) -> Bool {
        lhs.index == rhs.index
            && lhs.title == rhs.title
            && lhs.text == rhs.text
            && lhs.playCount == rhs.playCount
            && lhs.isSelected == rhs.isSelected
            && lhs.isSynthesizing == rhs.isSynthesizing
            && lhs.synthesisError == rhs.synthesisError
    }
}

/// Bottom bar only needs selection / play state — kept separate for clearer invalidation scope.
private struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: SpeechPlaybackController
    @Binding var showingPlayer: Bool

    var body: some View {
        if playback.selectedID != nil {
            HStack {
                Button { showingPlayer = true } label: {
                    VStack(alignment: .leading) {
                        Text(playback.title).lineLimit(1).font(.headline)
                        Label("单句循环", systemImage: "infinity").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button { playback.isPlaying ? playback.pause() : playback.play() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2).frame(width: 52, height: 52)
                }.accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
            }
            .padding(12).loopGlass().padding(.horizontal).padding(.bottom, 8)
        }
    }
}
