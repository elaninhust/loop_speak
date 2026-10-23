import SwiftUI
import SwiftData

struct SnippetEditorView: View {
    @EnvironmentObject private var language: AppLanguage
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: SpeechPlaybackController
    let snippet: Snippet?
    @State private var title: String
    @State private var text: String
    @State private var saving = false
    @State private var saved = false
    @State private var saveError: L10n.Message?

    init(snippet: Snippet? = nil) {
        self.snippet = snippet
        _title = State(initialValue: snippet?.title ?? "")
        _text = State(initialValue: snippet?.text ?? "")
    }

    var body: some View {
        let _ = language.selection
        NavigationStack {
            Form {
                Section(L10n.text(.optionalTitle)) { TextField(L10n.text(.titleExample), text: $title) }
                Section(L10n.text(.englishContent)) {
                    TextEditor(text: $text)
                        .frame(minHeight: 240)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel(L10n.text(.contentAccessibility))
                }
                Section { Text(L10n.text(.saveHint)) }
                if saving { Section { ProgressView(L10n.text(.synthesizingSpeech)) } }
                if saved { Section { Button(L10n.text(.done)) { dismiss() } } }
                if let saveError { Section { Text(saveError.string).foregroundStyle(.red) } }
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .navigationTitle(snippet == nil ? L10n.text(.addSnippet) : L10n.text(.editSnippet))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text(.cancel)) { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(.save), action: save)
                        .disabled(saving || saved || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = snippet ?? Snippet(title: "", text: "")
        item.title = name.isEmpty ? String(content.prefix(40)) : name
        item.text = content
        item.updatedAt = .now
        if snippet == nil { context.insert(item) }
        do {
            try context.save()
            playback.select(item)
            saved = true
            saving = true
            Task { @MainActor in
                await playback.synthesize(item)
                saving = false
                if let error = playback.synthesisErrors[item.id] {
                    saveError = error
                } else {
                    dismiss()
                }
            }
        } catch {
            context.rollback()
            saveError = L10n.Message(.saveError, String(error.localizedDescription))
        }
    }
}
