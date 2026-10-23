import Foundation
import CryptoKit
import Security
import Combine

struct TTSConfiguration: Codable, Sendable {
    var apiKey = ""
    var resourceId = "seed-tts-2.0"
    var voice = "en_male_michael_uranus_bigtts"
    // Persist the migration reminder, never the legacy token.
    var needsAPIKeyMigration = false
    var isReady: Bool { !apiKey.isEmpty && !resourceId.isEmpty && !voice.isEmpty }

    static let voices = [("en_male_michael_uranus_bigtts", "Michael（男）")]

    init() {}
    private enum CodingKeys: String, CodingKey { case apiKey, resourceId, voice, accessToken, needsAPIKeyMigration }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        resourceId = try values.decodeIfPresent(String.self, forKey: .resourceId) ?? "seed-tts-2.0"
        let legacyToken = try values.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        let migrationReminder = try values.decodeIfPresent(Bool.self, forKey: .needsAPIKeyMigration) ?? false
        needsAPIKeyMigration = apiKey.isEmpty && (!legacyToken.isEmpty || migrationReminder)
        let decodedVoice = try values.decodeIfPresent(String.self, forKey: .voice) ?? ""
        if decodedVoice.hasPrefix("BV") || decodedVoice.isEmpty {
            voice = "en_male_michael_uranus_bigtts"
        } else {
            voice = decodedVoice
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(apiKey, forKey: .apiKey)
        try values.encode(resourceId, forKey: .resourceId)
        try values.encode(voice, forKey: .voice)
        try values.encode(needsAPIKeyMigration, forKey: .needsAPIKeyMigration)
    }
}

enum TTSError: LocalizedError {
    case keychain(OSStatus), network(Int), http(Int), server(Int, String)
    case response, emptyAudio, missingKey, missingResource, missingVoice
    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "钥匙串读写失败（\(status)）"
        case .network(let code): return "语音请求网络失败（\(code)），请检查网络连接。"
        case .http(let status): return "语音服务 HTTP 错误（\(status)），请检查 API Key、资源授权及服务状态。"
        case .server(let code, let message): return "语音服务 V3 错误（\(code)）：\(message)"
        case .response: return "语音服务返回格式无效，或音频无法解码、播放。"
        case .emptyAudio: return "语音服务未返回音频，请检查音色授权、文本及额度。"
        case .missingKey: return "请填写控制台 API Key。"
        case .missingResource: return "请填写 Resource Id，例如 seed-tts-2.0。"
        case .missingVoice: return "请填写控制台音色库中的 speaker 音色 ID。"
        }
    }
}

@MainActor
final class TTSSettings: ObservableObject {
    @Published private(set) var configuration = TTSConfiguration()
    @Published private(set) var error: String?
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.loopspeak.doubao",
        kSecAttrAccount as String: "configuration"
    ]

    init() {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            do { configuration = try JSONDecoder().decode(TTSConfiguration.self, from: data) }
            catch { self.error = "无法读取语音配置，请重新保存。" }
        } else if status != errSecItemNotFound {
            error = TTSError.keychain(status).localizedDescription
        }
    }

    func save(_ value: TTSConfiguration) throws {
        let data = try JSONEncoder().encode(value)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TTSError.keychain(status) }
        configuration = value
        error = nil
    }
}

actor DoubaoTTS {
    func synthesize(text: String, configuration: TTSConfiguration) async throws -> Data {
        guard !configuration.apiKey.isEmpty else { throw TTSError.missingKey }
        guard !configuration.resourceId.isEmpty else { throw TTSError.missingResource }
        guard !configuration.voice.isEmpty else { throw TTSError.missingVoice }
        var request = URLRequest(url: URL(string: "https://openspeech.bytedance.com/api/v3/tts/unidirectional")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(configuration.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["req_params": [
            "text": text, "speaker": configuration.voice,
            "audio_params": ["format": "mp3", "sample_rate": 24000],
            "additions": "{\"explicit_language\":\"en\"}"
        ]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        // URLSession removes HTTP chunk framing; parse JSON objects after the body completes.
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw TTSError.network((error as NSError).code) }
        guard let http = response as? HTTPURLResponse else { throw TTSError.response }
        guard (200..<300).contains(http.statusCode) else { throw TTSError.http(http.statusCode) }
        return try Self.decodeAudio(data, apiKey: configuration.apiKey)
    }

    // Accept a full JSON object, NDJSON, or adjacent objects irrespective of transport boundaries.
    static func decodeAudio(_ data: Data, apiKey: String) throws -> Data {
        struct Reply: Decodable { let code: Int?; let message: String?; let data: String? }
        var audio = Data()
        var start: Int?
        var depth = 0
        var quoted = false
        var escaped = false
        let bytes = Array(data)
        for (index, byte) in bytes.enumerated() {
            if start == nil {
                if [9, 10, 13, 32].contains(byte) { continue }
                guard byte == 123 else { throw TTSError.response }
                start = index
            }
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else {
                if byte == 34 { quoted = true }
                else if byte == 123 { depth += 1 }
                else if byte == 125 { depth -= 1 }
            }
            if depth == 0, let first = start {
                guard let reply = try? JSONDecoder().decode(Reply.self, from: Data(bytes[first...index])) else {
                    throw TTSError.response
                }
                // 20000000 = synthesis finished successfully (end of stream), not an error.
                if let code = reply.code, code == 20000000 {
                    start = nil
                    continue
                }
                if let code = reply.code, code != 0 {
                    // A server may echo credentials; redact before presenting any message.
                    let message = (reply.message ?? "服务未提供错误详情")
                        .replacingOccurrences(of: apiKey, with: "[已隐藏]")
                    throw TTSError.server(code, message)
                }
                if let encoded = reply.data, !encoded.isEmpty {
                    guard let fragment = Data(base64Encoded: encoded), !fragment.isEmpty else {
                        throw TTSError.response
                    }
                    audio.append(fragment)
                }
                // Empty data / sentence / usage-only objects carry no audio; continue.
                start = nil
            }
        }
        guard start == nil else { throw TTSError.response }
        guard !audio.isEmpty else { throw TTSError.emptyAudio }
        return audio
    }

}

@MainActor
enum AudioCache {
    static func hash(text: String, voice: String) -> String {
        SHA256.hash(data: Data("\(voice)\u{0}\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func url(id: UUID) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(id.uuidString).mp3")
    }
    static func existingURL(for snippet: Snippet, voice: String) -> URL? {
        guard snippet.audioContentHash == hash(text: snippet.text, voice: voice),
              snippet.audioRelativePath == "Audio/\(snippet.id.uuidString).mp3",
              let url = try? url(id: snippet.id), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    static func remove(id: UUID) throws {
        let url = try url(id: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
