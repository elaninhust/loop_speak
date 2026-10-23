import SwiftUI
import SwiftData

@main
struct LoopSpeakApp: App {
    @StateObject private var language = AppLanguage()
    @StateObject private var playback = SpeechPlaybackController()

    var body: some Scene {
        WindowGroup {
            SnippetListView()
                .environmentObject(playback)
                .environmentObject(language)
                .environment(\.locale, language.locale)
                .onChange(of: language.selection) { _, _ in
                    playback.refreshUILanguage()
                }
        }
        .modelContainer(for: Snippet.self)
    }
}
