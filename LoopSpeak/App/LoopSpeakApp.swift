import SwiftUI
import SwiftData

@main
struct LoopSpeakApp: App {
    @StateObject private var playback = SpeechPlaybackController()

    var body: some Scene {
        WindowGroup {
            SnippetListView()
                .environmentObject(playback)
        }
        .modelContainer(for: Snippet.self)
    }
}
