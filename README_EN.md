# LoopSpeak

[中文](README.md) · **English**

**Version 1.0** · Infinite single-sentence English practice for iOS

LoopSpeak is an iPhone app for English speaking drills: save a sentence (or short passage) as a snippet, synthesize it once with Volcengine **Doubao TTS** into an MP3, then loop that clip locally forever. The UI is Chinese, built with **iOS 26 / SwiftUI**, and keeps Liquid Glass controls.

If Doubao credentials are missing, offline synthesis fails, or the cache is unavailable, playback falls back to **Apple system English voices**. Saving and synthesis never auto-start playback—you tap Play manually.

---

## Features

| Feature | Description |
|---------|-------------|
| Snippet management | Add / edit / delete English body text and optional titles; SwiftData local persistence |
| Cloud synthesis | Doubao V3 HTTP unidirectional streaming TTS → MP3 (24 kHz) on disk |
| Local looping | Same sentence loops forever; play count increments only after a full pass |
| System fallback | `AVSpeechSynthesizer` when credentials, cache, or files are missing/broken |
| Background & lock screen | `UIBackgroundModes = audio`; lock screen and headphone remote controls |
| Scrubbing | Seek on Doubao-cached audio; system TTS is not seekable |
| Stats | Cumulative play count and last-played time; long-press to reset |
| Credential safety | API Key and related settings live in Keychain only—not UserDefaults or logs |

---

## Requirements

- **macOS** + **Xcode 26** (or newer) with the iOS platform components
- **Device**: iPhone on iOS 26+ (prefer a real device for background audio and headphones)
- Default Bundle ID: `com.ivan.LoopSpeak`
- Optional: Volcengine Doubao speech synthesis quota (system voices work without it)

---

## Open and run on a Mac

1. Open `LoopSpeak.xcodeproj` in Xcode and select the shared **LoopSpeak** scheme.
2. **Signing & Capabilities** → pick your Apple ID / Personal Team; change the Bundle Identifier if needed.
3. Confirm **Background Modes → Audio, AirPlay, and Picture in Picture** is enabled (`UIBackgroundModes = [audio]` is already set).
4. Connect an iPhone, trust the Mac, enable Developer Mode, select the device, and Run.

App icons live under `LoopSpeak/Resources/Assets.xcassets/AppIcon.appiconset` (including 1024×1024).

---

## Configure Doubao TTS (optional, recommended)

### 1. Get an API Key

1. Open the [Volcengine console](https://console.volcengine.com/) and go to **Speech → Doubao Voice → Text-to-Speech**.
2. Enable the service, then create and copy an **API Key** under **API Key management**.
3. The new API needs **only the API Key**. Do not use a legacy Access Token / Secret Key / AppID / Cluster as credentials for this endpoint.

### 2. Fill in the app

Path: **Settings** (top-left)

| Field | Notes |
|-------|--------|
| API Key | Console API Key |
| Resource Id | Default `seed-tts-2.0`; `seed-icl-2.0` is also allowed if provisioned and matched to the voice |
| Preset voice | Default **Michael (male)** / `en_male_michael_uranus_bigtts` |
| Custom voice ID | Speaker ID from the console voice library; **non-empty values override the preset** |

Suggested flow:

1. Tap **“Test: synthesize one English line”** → success shows MP3 byte count (no playback, no snippet changes).
2. Tap **“Save settings”** to write Keychain; voice/credential changes trigger synthesis for missing or stale caches.
3. **“Resynthesize all snippets”** force-refreshes and consumes quota.

### 3. Billing

- **Every cloud synthesis** (test, text/voice change, forced resynthesis) is billed per Volcengine rules.
- **After one successful synthesis, local looping does not call the cloud**—repeat count does not add TTS cost.
- Eligibility, validity, and pricing follow the console.

### 4. Upgrading from a legacy build

Old Access Tokens are **not reused**. An empty API Key shows a prompt to switch to the console API Key; defaults move to Michael + TTS 2.0. Body text and play counts are kept—enter a new Key and save.

---

## How to use

### Add and edit snippets

1. Top-right **+** → English body (required) and optional title.
2. **Save**: persist text first, then synthesize asynchronously; progress is shown in the UI.
3. On synthesis failure, text is kept and system voice can still play.
4. List: **swipe left to delete**; **swipe right or long-press → edit**.
5. Long-press can **reset play count** and last-played time.

### Playback

1. Tap a snippet to open the player, then tap **Play**.
2. Mini player, lock screen, and headphones support **play / pause / stop**.
3. Doubao-cached audio supports scrubbing (including lock-screen seek); system TTS falls back to live-stream-style now-playing info without seek.
4. **Pause** keeps progress when possible; **Stop** restarts from the beginning.
5. Headphone unplug, route changes, phone calls, or Siri interruptions stop playback and leave it paused—**never auto-resume**; tap Play again.

### Play-count rules

- Uses `AVAudioPlayer.numberOfLoops = 0`: each **full finish** increments `playCount`, updates `lastPlayedAt`, then immediately replays the same file from the start.
- Pause / stop mid-pass **do not count**; resume and finish a full pass counts as **1**.
- System-voice fallback counts the same way on utterance completion.
- No playlist advancement—always one-sentence loops.

### Cache and offline

- MP3 path: `Application Support/Audio/{snippet UUID}.mp3`
- SwiftData stores the relative path + `SHA256(voice + `\0` + text)`
- **Matching text+voice hash and an existing file** → no cloud request
- **Title-only edits** → no quota use
- **Voice change** → old cache is not used for the new voice; resynthesis required
- Changing API Key / Resource Id **does not** invalidate caches for the same text+voice; use forced resynthesis to refresh
- Airplane mode can play existing caches; otherwise system English voices are used

Tip: on iPhone go to **Settings → Accessibility → Spoken Content → Voices → English** and download Enhanced / Premium voices. The app prefers US English and higher-quality voices.

### Data and privacy

- Text, counts, and MP3s stay **on device**; launch never auto-plays.
- **Uninstalling removes app data**; v1 has no cloud sync or export.
- API Key, Resource Id, and voice settings are stored only in **Keychain** (`AfterFirstUnlockThisDeviceOnly`)—not UserDefaults, SwiftData, or logs.
- Synthesis sends body text to Volcengine over HTTPS; never commit API Keys or include them in screenshots.
- Error UI redacts API Keys echoed in server messages.

---

## Project layout

```
loop_speak/
├── LoopSpeak.xcodeproj
├── LoopSpeak/
│   ├── App/LoopSpeakApp.swift          # Entry; SwiftData + playback controller
│   ├── Models/Snippet.swift            # Snippet model
│   ├── TTS/DoubaoTTS.swift             # Config, Keychain, V3 synthesis, audio cache
│   ├── Playback/
│   │   ├── SpeechPlaybackController.swift  # Playback, synthesis coordination, lock screen, remotes
│   │   └── VoiceSelector.swift             # Preferred system English voice
│   ├── Views/
│   │   ├── SnippetListView.swift       # List + mini player
│   │   ├── SnippetEditorView.swift     # Add / edit
│   │   ├── NowPlayingView.swift        # Player + seek
│   │   ├── TTSSettingsView.swift       # Credentials and batch synthesis
│   │   └── GlassPanel.swift            # Liquid Glass helpers
│   └── Resources/                      # Info.plist, Assets, icons
└── Tests/test_tts.py                   # Offline config-migration and response-parser tests
```

### Module responsibilities

- **`Snippet`**: text, title, audio relative path / content hash, play count, last played; new fields have defaults for lightweight migration.
- **`DoubaoTTS`**: dedicated `actor` for V3 requests; parses a single JSON object, NDJSON, or adjacent JSON objects; concatenates non-empty base64 audio where `code == 0`; `code == 20000000` means successful end-of-stream (not a failure).
- **`SpeechPlaybackController`**: `MainActor` playback and async synthesis; full-pass counting; interruptions never auto-resume; `PlaybackProgress` is observed separately so list views are not redrawn at 4 Hz.
- **`AudioCache`**: hashing and atomic file writes; clears old metadata before replacing the file so a failed save cannot leave an old hash pointing at new audio.

### TTS API summary

Uses the [Doubao V3 HTTP unidirectional streaming API](https://docs.volcengine.com/docs/DoubaoVoice/unidirectional-streaming-text-to-speech-http?lang=zh):

```
POST https://openspeech.bytedance.com/api/v3/tts/unidirectional
```

Headers: `X-Api-Key`, `X-Api-Resource-Id`, `X-Api-Request-Id` (UUID), `Content-Type: application/json`.

`req_params` includes text, speaker, `audio_params` (mp3 / 24000 Hz), and  
`additions: "{\"explicit_language\":\"en\"}"`. No WebSocket.

---

## Tests

On a Mac with Swift installed (no network calls, no real Key required):

```bash
python3 Tests/test_tts.py
```

The script extracts configuration and the parser from `DoubaoTTS.swift` and covers:

- Legacy config migration; Keychain encoding does not persist old tokens
- Single JSON / NDJSON / concatenated JSON assembly
- Usage trailers, non-zero codes, Key redaction
- Invalid base64, truncated responses, empty audio

This test is **not** part of the App target.

---

## Suggested acceptance checklist (Mac / device)

- [ ] Build and install with Xcode 26; background Audio, signing, and all Swift files are in the target
- [ ] Upgrade from a legacy build: text and counts survive without wiping the store
- [ ] No credentials: banner shown, system voice loops, count only on full finish
- [ ] Valid credentials: test succeeds; save shows synthesis progress without auto-play; UUID MP3 created; Airplane Mode plays cache
- [ ] Title-only edits skip synthesis; text/voice changes produce new caches; restart reuses cache; forced resynthesis and batch error counts are correct
- [ ] Bad Key / Resource / speaker, offline, HTTP / V3 errors, empty audio: clear Chinese errors, text kept, Keys redacted
- [ ] After delete, the matching MP3 is gone; no ghost loops
- [ ] Pause / resume / stop / counts / reset / persistence behave correctly; lock screen and background can loop for minutes; AirPods and remotes stay in sync
- [ ] Calls, Siri, headphone unplug, and output switches **never auto-resume**
- [ ] Dynamic Type, Dark Mode, VoiceOver, glass controls, and error UI remain usable

> The Simulator is not a substitute for device checks of background audio and headphones.

---

## Scope and limits (v1)

- Local-only storage—no accounts, iCloud, or export
- Built for **single-sentence looping**, not multi-item playlists
- Doubao quota is optional; system voices work without it
- Targets iOS 26+; requires Xcode 26 to build

---

## License

This project is released under the [MIT License](LICENSE).

Doubao TTS requires your own Volcengine account and compliance with their terms. Do not commit API keys or other credentials to this repository.
