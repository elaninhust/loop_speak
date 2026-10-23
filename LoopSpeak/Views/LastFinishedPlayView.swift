import SwiftUI

/// Refresh relative ages even when playback is idle, independently of progress ticks.
struct LastFinishedPlayView: View {
    @EnvironmentObject private var language: AppLanguage
    let lastPlayedAt: Date?

    var body: some View {
        let _ = language.selection
        if let lastPlayedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(L10n.text(.lastFullPlay, formatted(lastPlayedAt, now: context.date)))
            }
        } else {
            Text(L10n.text(.neverFinishedFullPlay))
        }
    }

    private func formatted(_ date: Date, now: Date) -> String {
        let locale = language.locale
        let relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.unitsStyle = .full
        relative.dateTimeStyle = .named
        // Clamp future timestamps (for example after a clock change) to "now".
        let age = now.timeIntervalSince(date)
        let relativeText = relative.localizedString(for: min(date, now), relativeTo: now)
        guard age >= 7 * 24 * 60 * 60 || age < 0 else { return relativeText }

        let absolute = DateFormatter()
        absolute.locale = locale
        absolute.dateStyle = .medium
        absolute.timeStyle = .short
        return age < 0 ? absolute.string(from: date) : "\(relativeText) · \(absolute.string(from: date))"
    }
}
