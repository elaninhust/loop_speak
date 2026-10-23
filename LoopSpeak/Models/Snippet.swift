import Foundation
import SwiftData

@Model
final class Snippet {
    @Attribute(.unique) var id: UUID
    var title: String
    var text: String
    // Stored defaults allow existing stores to migrate without replacing their data.
    var playCount: Int = 0
    var lastPlayedAt: Date? = nil
    var audioRelativePath: String? = nil
    var audioContentHash: String? = nil
    var updatedAt: Date

    init(title: String, text: String) {
        id = UUID()
        self.title = title
        self.text = text
        updatedAt = .now
    }
}
