import SwiftUI
import SwiftData

struct TTSSettingsView: View {
    private static let customTag = "__custom__"

    @EnvironmentObject private var playback: SpeechPlaybackController
    @Environment(\.dismiss) private var dismiss
    @Query private var snippets: [Snippet]
    @State private var draft = TTSConfiguration()
    @State private var presetVoice = "en_male_michael_uranus_bigtts"
    @State private var customVoice = ""
    @State private var busy = false
    @State private var status: String?
    @State private var progress = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("凭据") {
                    SecureField("API Key", text: $draft.apiKey)
                    TextField("Resource Id", text: $draft.resourceId)
                    Text("凭据仅存储在钥匙串。Resource Id 默认 seed-tts-2.0，也可填写 seed-icl-2.0，需与音色及授权匹配。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if draft.needsAPIKeyMigration {
                        Text("请改用控制台 API Key").foregroundStyle(.orange)
                    }
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Section {
                    Picker("预设音色", selection: $presetVoice) {
                        ForEach(TTSConfiguration.voices, id: \.0) { voice in
                            Text(voice.1).tag(voice.0)
                        }
                        Text("自定义").tag(Self.customTag)
                    }
                    .onChange(of: presetVoice) { _, newValue in
                        if newValue != Self.customTag {
                            customVoice = ""
                        }
                    }

                    TextField("自定义音色 ID", text: $customVoice)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: customVoice) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                presetVoice = Self.customTag
                            }
                        }

                    Text("选「自定义」并填写音色库里的 speaker ID；点「保存设置」或「完成」都会写入钥匙串。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("音色")
                } footer: {
                    Text("新版控制台只需 API Key；Secret Key / AppID 不用于本接口。音色例如 en_male_michael_uranus_bigtts。合成一次后本地循环不计费。")
                }

                Section {
                    Button("保存设置") { apply(resynthesize: false) }
                    Button("重新合成全部片段") { apply(resynthesize: true) }
                    Button("测试：合成一句英语") {
                        busy = true
                        status = "正在合成测试语音…"
                        Task { @MainActor in
                            defer { busy = false }
                            do {
                                let configuration = try resolvedConfiguration()
                                let data = try await playback.testVoice(configuration: configuration)
                                status = "测试合成成功（\(data.count) 字节 MP3）。当前音色：\(configuration.voice)"
                            } catch { status = error.localizedDescription }
                        }
                    }
                    Text("保存声音变化后会自动合成全部片段；相同正文和声音已有缓存则跳过。强制重新合成会消耗额度。保存、合成均不会自动播放。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(busy)

                if busy { Section { ProgressView("处理中 \(progress)/\(snippets.count)") } }
                if let status { Section { Text(status).textSelection(.enabled) } }
                if !playback.settings.configuration.isReady {
                    Section {
                        Label("尚未配置凭据，将使用 Apple 系统语音。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("语音设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        // Always persist before dismiss so custom voice is not lost.
                        if busy { return }
                        apply(resynthesize: false, dismissAfterSave: true)
                    }
                    .disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
            .onAppear { loadFromSettings() }
        }
    }

    private func loadFromSettings() {
        draft = playback.settings.configuration
        if TTSConfiguration.voices.contains(where: { $0.0 == draft.voice }) {
            presetVoice = draft.voice
            customVoice = ""
        } else if draft.voice.isEmpty {
            presetVoice = "en_male_michael_uranus_bigtts"
            customVoice = ""
        } else {
            presetVoice = Self.customTag
            customVoice = draft.voice
        }
        status = playback.settings.error
    }

    private func resolvedConfiguration() throws -> TTSConfiguration {
        var value = draft
        value.apiKey = value.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        value.resourceId = value.resourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = customVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if presetVoice == Self.customTag || !custom.isEmpty {
            guard !custom.isEmpty else { throw TTSError.missingVoice }
            value.voice = custom
        } else {
            value.voice = presetVoice
        }
        guard !value.voice.isEmpty, value.voice != Self.customTag else { throw TTSError.missingVoice }
        return value
    }

    private func apply(resynthesize: Bool, dismissAfterSave: Bool = false) {
        let previous = playback.settings.configuration
        let configuration: TTSConfiguration
        do {
            configuration = try resolvedConfiguration()
        } catch {
            status = error.localizedDescription
            return
        }
        draft = configuration
        if !draft.apiKey.isEmpty { draft.needsAPIKeyMigration = false }
        // Keep UI in sync with what we just persisted.
        if TTSConfiguration.voices.contains(where: { $0.0 == draft.voice }) {
            presetVoice = draft.voice
            customVoice = ""
        } else {
            presetVoice = Self.customTag
            customVoice = draft.voice
        }
        do { try playback.settings.save(draft) }
        catch { status = error.localizedDescription; return }

        let changed = previous.voice != draft.voice
            || previous.apiKey != draft.apiKey
            || previous.resourceId != draft.resourceId
        playback.stop()
        playback.refreshVoice()

        guard draft.isReady else {
            status = "设置已保存，将使用 Apple 系统语音。"
            if dismissAfterSave { dismiss() }
            return
        }
        guard changed || resynthesize else {
            status = "设置已保存。当前音色：\(draft.voice)"
            if dismissAfterSave { dismiss() }
            return
        }

        if dismissAfterSave && !resynthesize {
            // Persist first; resynthesis can continue while sheet is open only when explicitly requested.
            // For 完成: save then dismiss; trigger resynth in background after dismiss via playback.
            busy = true
            progress = 0
            status = "正在按新音色合成，请稍候…"
            let items = snippets
            Task { @MainActor in
                for snippet in items {
                    await playback.synthesize(snippet, force: false)
                    progress += 1
                }
                let failures = items.filter { playback.synthesisErrors[$0.id] != nil }.count
                status = failures == 0
                    ? "设置已保存，音色：\(draft.voice)。合成完成。"
                    : "设置已保存，音色：\(draft.voice)。其中 \(failures) 条合成失败。"
                busy = false
                dismiss()
            }
            return
        }

        busy = true
        progress = 0
        status = "正在合成，请保持此页面打开。"
        let items = snippets
        Task { @MainActor in
            for snippet in items {
                await playback.synthesize(snippet, force: resynthesize)
                progress += 1
            }
            let failures = items.filter { playback.synthesisErrors[$0.id] != nil }.count
            status = failures == 0
                ? "合成完成，音色：\(draft.voice)。点击片段播放。"
                : "合成完成，其中 \(failures) 条失败，可使用系统语音或重试。"
            busy = false
        }
    }
}
