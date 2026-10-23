"""Run the actual Swift configuration/parser without iOS frameworks: python3 Tests/test_tts.py (Mac with Swift)."""
from pathlib import Path
import shutil
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'LoopSpeak/TTS/DoubaoTTS.swift').read_text()
core = source[source.index('struct TTSConfiguration'):source.index('@MainActor\nfinal class TTSSettings')]
actor = source[source.index('actor DoubaoTTS'):source.index('@MainActor\nenum AudioCache')]
checks = r'''
func json(_ value: String) -> Data { Data(value.utf8) }
func expectFailure(_ value: String, matching: (TTSError) -> Bool) throws {
    do {
        _ = try DoubaoTTS.decodeAudio(json(value), apiKey: "test-secret")
        fatalError("Expected failure")
    } catch let error as TTSError { precondition(matching(error)) }
}
let decoder = JSONDecoder()
let defaults = try decoder.decode(TTSConfiguration.self, from: json("{}"))
precondition(defaults.resourceId == "seed-tts-2.0")
precondition(defaults.voice == "en_male_michael_uranus_bigtts" && !defaults.isReady)
let legacy = try decoder.decode(TTSConfiguration.self, from: json(#"{"appID":"old","accessToken":"old-token","cluster":"old","voice":"BV027_streaming"}"#))
precondition(legacy.apiKey.isEmpty && legacy.needsAPIKeyMigration)
precondition(legacy.voice == defaults.voice)
let saved = try JSONEncoder().encode(legacy)
precondition(!String(decoding: saved, as: UTF8.self).contains("old-token"))
let migratedAgain = try decoder.decode(TTSConfiguration.self, from: saved)
precondition(migratedAgain.needsAPIKeyMigration)
var custom = TTSConfiguration()
custom.apiKey = "test-secret"
custom.resourceId = "seed-icl-2.0"
custom.voice = "custom-speaker"
let restored = try decoder.decode(TTSConfiguration.self, from: JSONEncoder().encode(custom))
precondition(restored.isReady && restored.voice == custom.voice && restored.resourceId == custom.resourceId)
let first = #"{"code":0,"data":"SUQz"}"#
let second = #"{"code":0,"data":"YWJj","message":"escaped \" } {"}"#
let end = #"{"code":0,"data":"","usage":{"characters":3}}"#
let usage = #"{"usage":{"characters":3}}"#
let single = try DoubaoTTS.decodeAudio(json(first), apiKey: "test-secret")
precondition(single == Data("ID3".utf8))
for separator in ["\n", "\r\n", "", " \n "] {
    let audio = try DoubaoTTS.decodeAudio(json(first + separator + second + separator + end + separator + usage), apiKey: "test-secret")
    precondition(audio == Data("ID3abc".utf8))
}
try expectFailure(first + #"{"code":403,"message":"denied test-secret"}"#) {
    if case .server(let code, let message) = $0 {
        return code == 403 && message.contains("denied") && !message.contains("test-secret")
    }
    return false
}
for invalid in [#"{"code":0,"data":"???"}"#, first + "{", "[]", first + "garbage", #"{"data":"SUQz"}"#] {
    try expectFailure(invalid) { if case .response = $0 { return true }; return false }
}
for empty in ["", end, usage] {
    try expectFailure(empty) { if case .emptyAudio = $0 { return true }; return false }
}
print("TTS configuration migration and response parser checks passed")
'''
if not shutil.which('swift'):
    raise SystemExit('Swift unavailable: run python3 Tests/test_tts.py on a Mac with Swift installed.')
with tempfile.TemporaryDirectory(prefix='loopspeak-tts-') as directory:
    script = Path(directory) / 'main.swift'
    script.write_text('import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\ntypealias OSStatus = Int32\n' + core + actor + checks)
    subprocess.run(['swift', str(script)], check=True)
