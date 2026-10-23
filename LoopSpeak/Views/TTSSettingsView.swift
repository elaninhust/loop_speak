import SwiftUI
import SwiftData

struct TTSSettingsView: View {
    @EnvironmentObject private var language: AppLanguage
    private static let customTag = "__custom__"

    @EnvironmentObject private var playback: SpeechPlaybackController
    @Environment(\.dismiss) private var dismiss
    @Query private var snippets: [Snippet]
    @State private var draft = TTSConfiguration()
    @State private var presetVoice = "en_male_michael_uranus_bigtts"
    @State private var customVoice = ""
    @State private var busy = false
    @State private var status: L10n.Message?
    @State private var progress = 0

    var body: some View {
        let _ = language.selection
        NavigationStack {
            Form {
                Section(L10n.text(.language)) {
                    Picker(L10n.text(.language), selection: $language.selection) {
                        Text(L10n.text(.system)).tag(UILanguage.system)
                        Text("简体中文").tag(UILanguage.chinese)
                        Text("English").tag(UILanguage.english)
                    }
                    Text(L10n.text(.languageHint))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(L10n.text(.credentials)) {
                    SecureField(L10n.text(.apiKey), text: $draft.apiKey)
                    TextField(L10n.text(.resourceId), text: $draft.resourceId)
                    Text(L10n.text(.credentialsHint))
                        .font(.footnote).foregroundStyle(.secondary)
                    if draft.needsAPIKeyMigration {
                        Text(L10n.text(.migration)).foregroundStyle(.orange)
                    }
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Section {
                    Picker(L10n.text(.presetVoice), selection: $presetVoice) {
                        ForEach(TTSConfiguration.voices, id: \.0) { voice in
                            Text(voice.1).tag(voice.0)
                        }
                        Text(L10n.text(.custom)).tag(Self.customTag)
                    }
                    .onChange(of: presetVoice) { _, newValue in
                        if newValue != Self.customTag {
                            customVoice = ""
                        }
                    }

                    TextField(L10n.text(.customVoice), text: $customVoice)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: customVoice) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                presetVoice = Self.customTag
                            }
                        }

                    Text(L10n.text(.customHint))
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text(L10n.text(.voice))
                } footer: {
                    Text(L10n.text(.voiceHint))
                }

                Section {
                    Button(L10n.text(.saveSettings)) { apply(resynthesize: false) }
                    Button(L10n.text(.resynthesize)) { apply(resynthesize: true) }
                    Button(L10n.text(.testVoice)) {
                        busy = true
                        status = L10n.Message(.testing)
                        Task { @MainActor in
                            defer { busy = false }
                            do {
                                let configuration = try resolvedConfiguration()
                                let data = try await playback.testVoice(configuration: configuration)
                                status = L10n.Message(.testSuccess, String(data.count), String(configuration.voice))
                            } catch { status = L10n.Message(error: error) }
                        }
                    }
                    Text(L10n.text(.synthesisHint))
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(busy)

                if busy { Section { ProgressView(L10n.text(.processing, String(progress), String(snippets.count))) } }
                if let status { Section { Text(status.string).textSelection(.enabled) } }
                if !playback.settings.configuration.isReady {
                    Section {
                        Label(L10n.text(.fallbackBanner), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(busy)
            .navigationTitle(L10n.text(.speechSettings))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(.done)) {
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
            status = L10n.Message(error: error)
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
        catch { status = L10n.Message(error: error); return }

        let changed = previous.voice != draft.voice
            || previous.apiKey != draft.apiKey
            || previous.resourceId != draft.resourceId
        playback.stop()
        playback.refreshVoice()

        guard draft.isReady else {
            status = L10n.Message(.savedFallback)
            if dismissAfterSave { dismiss() }
            return
        }
        guard changed || resynthesize else {
            status = L10n.Message(.savedVoice, String(draft.voice))
            if dismissAfterSave { dismiss() }
            return
        }

        if dismissAfterSave && !resynthesize {
            // Persist first; resynthesis can continue while sheet is open only when explicitly requested.
            // For 完成: save then dismiss; trigger resynth in background after dismiss via playback.
            busy = true
            progress = 0
            status = L10n.Message(.newVoiceSynthesis)
            let items = snippets
            Task { @MainActor in
                for snippet in items {
                    await playback.synthesize(snippet, force: false)
                    progress += 1
                }
                let failures = items.filter { playback.synthesisErrors[$0.id] != nil }.count
                status = failures == 0
                    ? L10n.Message(.savedSynthesis, String(draft.voice))
                    : L10n.Message(.savedFailures, String(draft.voice), String(failures))
                busy = false
                dismiss()
            }
            return
        }

        busy = true
        progress = 0
        status = L10n.Message(.keepOpen)
        let items = snippets
        Task { @MainActor in
            for snippet in items {
                await playback.synthesize(snippet, force: resynthesize)
                progress += 1
            }
            let failures = items.filter { playback.synthesisErrors[$0.id] != nil }.count
            status = failures == 0
                ? L10n.Message(.synthesisComplete, String(draft.voice))
                : L10n.Message(.synthesisFailures, String(failures))
            busy = false
        }
    }
}
