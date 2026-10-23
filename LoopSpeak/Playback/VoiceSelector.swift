import AVFoundation

enum VoiceSelector {
    /// Prefer US English; within that locale prefer Premium, then Enhanced.
    static func preferredEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let american = voices.filter { $0.language.caseInsensitiveCompare("en-US") == .orderedSame }
        let english = voices.filter { $0.language.lowercased().hasPrefix("en-") }
        return (american.isEmpty ? english : american).sorted {
            if $0.quality.rawValue != $1.quality.rawValue {
                return $0.quality.rawValue > $1.quality.rawValue
            }
            return $0.identifier < $1.identifier
        }.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}
