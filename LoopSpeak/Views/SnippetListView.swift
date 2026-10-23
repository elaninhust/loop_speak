import SwiftUI
import SwiftData

struct SnippetListView: View {
    @EnvironmentObject private var language: AppLanguage
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var playback: SpeechPlaybackController
    @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
    @State private var showingSettings = false
    @State private var adding = false
    @State private var editing: Snippet?
    @State private var showingPlayer = false
    @State private var storageError: L10n.Message?
    @State private var resetting: Snippet?

    var body: some View {
        let _ = language.selection
        NavigationStack {
            listContent
                .navigationTitle("LoopSpeak")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.text(.settings), systemImage: "gearshape") { showingSettings = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.text(.addSnippet), systemImage: "plus") { adding = true }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    MiniPlayerBar(showingPlayer: $showingPlayer)
                }
                .sheet(isPresented: $showingSettings) { TTSSettingsView() }
                .sheet(isPresented: $adding) { SnippetEditorView() }
                .sheet(item: $editing) { SnippetEditorView(snippet: $0) }
                .navigationDestination(isPresented: $showingPlayer) { NowPlayingView() }
                .confirmationDialog(L10n.text(.resetQuestion), isPresented: Binding(
                    get: { resetting != nil },
                    set: { if !$0 { resetting = nil } }
                ), titleVisibility: .visible, presenting: resetting) { snippet in
                    Button(L10n.text(.resetZero), role: .destructive) {
                        resetCount(for: snippet)
                        resetting = nil
                    }
                    Button(L10n.text(.cancel), role: .cancel) { resetting = nil }
                } message: { _ in
                    Text(L10n.text(.resetExplanation))
                }
                .alert(L10n.text(.cannotSave), isPresented: Binding(get: { storageError != nil }, set: { if !$0 { storageError = nil } })) {
                    Button(L10n.text(.ok)) { storageError = nil }
                } message: { Text(storageError?.string ?? "") }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            if !playback.settings.configuration.isReady {
                Label(L10n.text(.credentialsBanner), systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let error = playback.settings.error { Text(error.string).foregroundStyle(.orange) }
            if snippets.isEmpty {
                ContentUnavailableView(L10n.text(.emptyTitle), systemImage: "text.bubble", description: Text(L10n.text(.emptyDescription)))
            }
            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                SnippetRow(
                    index: index + 1,
                    title: snippet.title,
                    text: snippet.text,
                    playCount: snippet.playCount,
                    lastPlayedAt: snippet.lastPlayedAt,
                    isSelected: playback.selectedID == snippet.id,
                    isSynthesizing: playback.synthesizing.contains(snippet.id),
                    synthesisError: playback.synthesisErrors[snippet.id]?.string
                )
                .equatable()
                .contentShape(Rectangle())
                .onTapGesture {
                    playback.select(snippet)
                    showingPlayer = true
                }
                .swipeActions(edge: .leading) {
                    Button(L10n.text(.edit)) { editing = snippet }.tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button(L10n.text(.delete), role: .destructive) {
                        delete(at: IndexSet(integer: index))
                    }
                }
                .contextMenu {
                    Button(L10n.text(.editSnippet)) { editing = snippet }
                    Button(L10n.text(.resetCount), systemImage: "arrow.counterclockwise", role: .destructive) {
                        resetting = snippet
                    }
                }
            }
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
            storageError = L10n.Message(error: error)
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
                catch { storageError = L10n.Message(.cleanupError, String(error.localizedDescription)) }
            }
        } catch {
            context.rollback()
            storageError = L10n.Message(error: error)
        }
    }
}

/// Value-typed row so SwiftUI can skip redraws when only unrelated playback fields change.
private struct SnippetRow: View, Equatable {
    @EnvironmentObject private var language: AppLanguage
    let index: Int
    let title: String
    let text: String
    let playCount: Int
    let lastPlayedAt: Date?
    let isSelected: Bool
    let isSynthesizing: Bool
    let synthesisError: String?

    var body: some View {
        let _ = language.selection
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
                .accessibilityLabel(L10n.text(.snippetIndex, String(index)))

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if isSynthesizing { ProgressView(L10n.text(.synthesizing)) }
                if let synthesisError {
                    Text(synthesisError).font(.caption).foregroundStyle(.orange)
                }
                Text(L10n.text(.repeatCount, String(playCount)))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                LastFinishedPlayView(lastPlayedAt: lastPlayedAt)
                    .font(.caption).foregroundStyle(.secondary)
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
            && lhs.lastPlayedAt == rhs.lastPlayedAt
            && lhs.isSelected == rhs.isSelected
            && lhs.isSynthesizing == rhs.isSynthesizing
            && lhs.synthesisError == rhs.synthesisError
    }
}

/// Bottom bar only needs selection / play state — kept separate for clearer invalidation scope.
private struct MiniPlayerBar: View {
    @EnvironmentObject private var language: AppLanguage
    @EnvironmentObject private var playback: SpeechPlaybackController
    @Binding var showingPlayer: Bool

    var body: some View {
        let _ = language.selection
        if playback.selectedID != nil {
            HStack {
                Button { showingPlayer = true } label: {
                    VStack(alignment: .leading) {
                        Text(playback.title).lineLimit(1).font(.headline)
                        Label(L10n.text(.singleLoop), systemImage: "infinity").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button { playback.isPlaying ? playback.pause() : playback.play() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2).frame(width: 52, height: 52)
                }.accessibilityLabel(playback.isPlaying ? L10n.text(.pause) : L10n.text(.play))
            }
            .padding(12).loopGlass().padding(.horizontal).padding(.bottom, 8)
        }
    }
}
