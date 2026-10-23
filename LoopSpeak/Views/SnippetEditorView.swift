import SwiftUI
import SwiftData

struct SnippetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: SpeechPlaybackController
    let snippet: Snippet?
    @State private var title: String
    @State private var text: String
    @State private var saving = false
    @State private var saved = false
    @State private var saveError: String?

    init(snippet: Snippet? = nil) {
        self.snippet = snippet
        _title = State(initialValue: snippet?.title ?? "")
        _text = State(initialValue: snippet?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题（可选）") { TextField("例如：自我介绍", text: $title) }
                Section("英语内容") {
                    TextEditor(text: $text)
                        .frame(minHeight: 240)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("英语片段内容")
                }
                Section { Text("保存后点击播放。当前片段将无限循环，直到暂停或停止。") }
                if saving { Section { ProgressView("正在合成语音…") } }
                if saved { Section { Button("完成") { dismiss() } } }
                if let saveError { Section { Text(saveError).foregroundStyle(.red) } }
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .navigationTitle(snippet == nil ? "添加片段" : "编辑片段")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
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
            saveError = "保存失败：\(error.localizedDescription)"
        }
    }
}
