# PushToTalkSTT Enhancement Roadmap — Full Spec

## Overview

11 enhancements organized into 3 priority tiers. Each feature is specified with enough detail to write an implementation plan. Features are independent — they can be built in any order, though the suggested sequence minimizes rework.

**Current state:** macOS menu bar push-to-talk app with WhisperKit large-v3, Right Option hotkey, Cmd+V text injection, animated overlay, transcription history with search.

---

## Tier 1: High Impact

---

### Feature 1: AI Post-Processing

**Goal:** Optionally run transcribed text through an LLM to improve quality before injection.

**Modes:**
- **Off** — raw transcription injected as-is (current behavior)
- **Clean** — fix grammar, punctuation, capitalize sentences. "hello world how are you" → "Hello world, how are you?"
- **Code** — interpret dictation as code intent. "def hello name return f string hello name" → `def hello(name):\n    return f"Hello {name}"`. Handles: snake_case conversion, bracket insertion, indentation, common keywords.
- **Command** — interpret as editor commands (Feature 3 below, separate)

**Architecture:**
- `PostProcessor.swift` — protocol with `process(text: String, mode: ProcessingMode) async -> String`
- `LocalPostProcessor.swift` — uses Ollama (localhost:11434) with a small model (e.g. llama3.2:3b or qwen2.5-coder:3b). Falls back to raw text if Ollama isn't running.
- `CloudPostProcessor.swift` — uses Claude API (anthropic SDK). Requires API key stored in Keychain.
- User picks backend + mode in a Settings view.

**Settings stored in:** `UserDefaults` — keys: `postProcessingMode` (off/clean/code), `postProcessingBackend` (local/cloud), `claudeApiKey` (Keychain)

**Flow change in AppDelegate.stopRecording:**
1. WhisperKit returns raw text
2. If post-processing is enabled, show a "Processing..." phase in the overlay (new overlay phase)
3. Run through PostProcessor
4. Inject the processed text

**UI:**
- New overlay phase: `.processing` — similar to `.transcribing` but with a different color (blue/teal) and label "Enhancing..."
- Settings accessible from right-click menu → "Settings..."
- Settings window: dropdown for mode (Off / Clean / Code), dropdown for backend (Local Ollama / Claude API), API key field for Claude

**Latency budget:** Local Ollama should respond in <1s for short text on M5 Max. Claude API adds 0.5-2s network latency. Show processing animation during this time.

**Error handling:** If LLM fails (Ollama not running, API error, timeout after 5s), fall back to raw text and show a subtle warning in the notification.

---

### Feature 2: Configurable Hotkey

**Goal:** Let users choose their own push-to-talk key instead of hardcoded Right Option.

**Supported keys:**
- Any modifier key: Right Option, Left Option, Right Command, Left Command, Right Shift, Left Shift, Right Control, Left Control, Fn
- Any regular key: F13-F20 (extended keyboards), any letter/number with modifier combo (e.g. Ctrl+Space)
- Modifier-only keys detected via `keyCode` on `.flagsChanged` events
- Regular keys detected via `.keyDown`/`.keyUp` events

**Architecture:**
- `HotkeyManager.swift` — replaces the hardcoded Right Option monitor in AppDelegate. Manages global+local event monitors based on configured key.
- `HotkeyRecorder.swift` — SwiftUI view component. Shows current hotkey, click to record new one (like System Settings keyboard shortcuts). Captures next key press as the new hotkey.
- Hotkey config stored in `UserDefaults`: `hotkeyKeyCode: UInt16`, `hotkeyModifierFlags: UInt` (raw value of `NSEvent.ModifierFlags`), `hotkeyIsModifierOnly: Bool`

**Settings UI:** In the Settings window (from Feature 1), a "Hotkey" section with the recorder component showing current binding and a "Record" button.

**Default:** Right Option (keyCode 61, modifier .option, modifierOnly true) — same as current behavior.

**Migration:** On first launch after update, if no hotkey is stored in UserDefaults, write the default (Right Option) so the recorder shows it correctly.

---

### Feature 3: Multi-Mode Dictation

**Goal:** Quick-toggle between dictation modes that change how transcribed text is processed.

**Modes:**
- **Prose** (default) — normal text, optionally cleaned by AI post-processing
- **Code** — AI post-processing in code mode (Feature 1). Also: auto-detect programming language from context if possible
- **Command** — voice commands that control the system:
  - "select all" → Cmd+A
  - "undo" → Cmd+Z
  - "copy" → Cmd+C
  - "paste" → Cmd+V
  - "new line" → Return key
  - "tab" → Tab key
  - "delete" → Backspace
  - "escape" → Escape key
  - Custom commands configurable in settings

**Mode switching:**
- **Via overlay:** Three small mode icons at the bottom of the listening overlay. Current mode highlighted.
- **Via hotkey:** Double-tap the push-to-talk key quickly (within 300ms) to cycle modes: Prose → Code → Command → Prose
- **Via menu:** Right-click menu shows current mode with submenu to switch

**Architecture:**
- `DictationMode.swift` — enum with `.prose`, `.code`, `.command`
- `CommandExecutor.swift` — maps voice command strings to CGEvent keypresses. Uses a dictionary of command → keycode mappings. Fuzzy matching for close matches.
- Mode stored in `UserDefaults` as `dictationMode`
- ViewModel gets `@Published var dictationMode: DictationMode`

**Overlay change:** Small mode indicator at bottom of listening overlay: three dots/icons, current mode highlighted. Subtle enough not to distract.

---

### Feature 4: Instant Paste vs Clipboard-Only

**Goal:** Option to just copy to clipboard without auto-injecting into the active field.

**Modes:**
- **Auto-inject** (default, current behavior) — paste into active app via Cmd+V
- **Clipboard only** — copy to clipboard, show notification, don't inject. User pastes manually when ready.

**Architecture:**
- `UserDefaults` key: `injectionMode` ("auto" / "clipboard")
- In `AppDelegate.stopRecording`, check mode before calling `TextInjector.inject()`
- Settings UI: toggle in Settings window
- Right-click menu: checkmark indicator for current mode, click to toggle

**Notification change:** When in clipboard mode, notification says "Copied to clipboard" instead of "Typed & Copied"

---

## Tier 2: Medium Impact

---

### Feature 5: Language Lock

**Goal:** Pin transcription to a specific language for better accuracy and speed.

**Architecture:**
- `UserDefaults` key: `languageLock` — nil for auto-detect, or ISO 639-1 code (e.g. "en", "ka", "es")
- In `WhisperRecognizer.stopRecording`, pass the language to `DecodingOptions`:
  ```swift
  let options = DecodingOptions(
      verbose: false,
      task: .transcribe,
      language: languageLock,       // nil = auto-detect, "en" = force English
      detectLanguage: languageLock == nil
  )
  ```
- Settings UI: dropdown with common languages + "Auto-detect" option. Languages: Auto, English, Georgian, Spanish, French, German, Russian, Chinese, Japanese, Korean, Arabic, + "Other..." with text field for ISO code.
- Right-click menu: "Language: Auto" submenu to quick-switch

**Performance benefit:** Skipping language detection saves ~100-200ms per transcription and eliminates misdetection (e.g. short English phrases detected as Dutch).

---

### Feature 6: Sound Feedback

**Goal:** Audio cues when recording starts and stops.

**Sounds:**
- **Start:** Short, subtle rising tone (~200ms). Like a soft "ping" or the macOS dictation start sound.
- **Stop:** Short falling tone (~200ms).
- **Error:** Different tone for "no speech detected" or errors.

**Architecture:**
- `SoundManager.swift` — plays system sounds or bundled audio files via `NSSound` or `AVAudioPlayer`
- Use system sounds where possible: `NSSound(named: "Tink")` for start, `NSSound(named: "Pop")` for stop
- `UserDefaults` key: `soundFeedbackEnabled` (Bool, default true)
- Settings UI: toggle in Settings window
- Play sounds in `AppDelegate.startRecording()` and `stopRecording()`

**Constraint:** Sounds must not be picked up by the microphone. Since recording starts AFTER the sound plays, and stops BEFORE the sound plays, this is naturally handled by sequencing. Verify: start sound → then start audio engine. Stop audio engine → then stop sound.

---

### Feature 7: Transcription Streaming (Partial Results)

**Goal:** Show partial text in the overlay as the user speaks.

**Architecture:**
- WhisperKit supports streaming via its `transcribe` callback. Instead of batch-transcribing after recording stops, run transcription in a background loop during recording:
  1. Every ~1 second, take the current audio buffer
  2. Run WhisperKit transcription on it
  3. Display partial result in the overlay
  4. When recording stops, run final transcription on the complete buffer
- `WhisperRecognizer` gets a new callback: `onPartialResult: ((String) -> Void)?`
- Overlay gets a text display area below the orb showing the partial transcription

**Overlay change:**
- During `.listening` phase, show partial text below the orb animation
- Text appears with a subtle typing animation
- Fades out when transitioning to `.transcribing` phase

**Performance consideration:** Running transcription every second during recording uses significant CPU/Neural Engine. On M5 Max this is fine, but on lesser hardware it could cause audio glitches. Make this opt-in via Settings: `streamingPreview` (Bool, default false on machines with <16GB RAM, true otherwise).

**Latency:** Partial results are 1-2 seconds behind speech. This is acceptable for a preview — the final result is what gets injected.

---

### Feature 8: Snippet Templates

**Goal:** Save and quickly insert frequently used phrases.

**Architecture:**
- `SnippetStore.swift` — similar to `TranscriptionStore`, JSON file in Application Support
- Data model:
  ```swift
  struct Snippet: Identifiable, Codable {
      let id: UUID
      var name: String        // "Email sign-off", "Meeting intro"
      var text: String        // "Best regards,\nJohn"
      var triggerPhrase: String?  // Optional: if spoken text matches this, auto-expand
  }
  ```
- **Manual use:** History window gets a "Snippets" tab/section. Click a snippet → inject it.
- **Voice trigger:** If `triggerPhrase` is set and the transcribed text closely matches it (fuzzy match, >80% similarity), replace with the snippet text. E.g., say "email sign off" → injects "Best regards,\nJohn Doe"
- **Creating snippets:** In history, right-click a transcription → "Save as Snippet". Or in Settings → Snippets section → add manually.

**UI:**
- History window: add a tab bar or sidebar toggle between "History" and "Snippets"
- Snippet list: name, preview of text, trigger phrase (if set)
- Snippet detail: editable name, text, trigger phrase

---

## Tier 3: Nice to Have

---

### Feature 9: Menu Bar Waveform

**Goal:** Show a tiny real-time audio waveform in the menu bar while recording.

**Architecture:**
- Replace the static `mic.fill` icon during recording with a custom `NSImage` drawn from audio level data
- `WaveformRenderer.swift` — takes recent audio levels (last ~20 samples) and renders a tiny waveform image (18x18 points) using `NSGraphicsContext`/`CGContext`
- `AppDelegate` updates the status bar icon on every `onAudioLevel` callback (throttled to 15fps to avoid excessive redraws)
- When not recording, restore the static mic icon

**Visual:** 4-6 vertical bars at different heights, animated smoothly. Similar to the music equalizer bars in Shazam's menu bar icon.

**Performance:** Drawing a tiny image 15 times/second is negligible on any Mac.

---

### Feature 10: Auto-Launch at Login

**Goal:** Start PushToTalkSTT automatically when the user logs in.

**Architecture:**
- Use `SMAppService.mainApp` (macOS 13+) to register/unregister as a login item:
  ```swift
  import ServiceManagement
  
  // Enable
  try SMAppService.mainApp.register()
  
  // Disable
  try SMAppService.mainApp.unregister()
  
  // Check status
  SMAppService.mainApp.status == .enabled
  ```
- Settings UI: toggle "Launch at Login"
- No UserDefaults needed — `SMAppService` manages this system-level
- Requires the app to be in `/Applications/` or have a stable bundle identifier

**Note:** This is the modern macOS approach. The old `LSSharedFileList` API is deprecated.

---

### Feature 11: Statistics Dashboard

**Goal:** Show usage statistics: total transcriptions, time saved, words per day, language breakdown.

**Architecture:**
- Statistics computed from `TranscriptionStore.entries` — no separate storage needed
- `StatisticsView.swift` — SwiftUI view showing:
  - **Total transcriptions:** count of entries
  - **Total duration:** sum of all `duration` fields, formatted as "X hours Y minutes"
  - **Estimated time saved:** total_duration * 3 (typing is ~3x slower than speaking)
  - **Words transcribed:** sum of word counts across all entries
  - **Language breakdown:** pie chart or bar chart of entries per language
  - **Daily activity:** bar chart of transcriptions per day (last 30 days)
  - **Streak:** consecutive days with at least one transcription
- Accessible from: right-click menu → "Statistics" or History window → "Stats" tab

**Charts:** Use SwiftUI Charts framework (macOS 14+): `Chart`, `BarMark`, `SectorMark`

---

## Implementation Order (Suggested)

Each feature is independent, but this sequence minimizes rework:

1. **Feature 2: Configurable Hotkey** — foundational, unblocks users with non-standard keyboards
2. **Feature 5: Language Lock** — quick win, improves accuracy for most users
3. **Feature 6: Sound Feedback** — quick win, improves UX
4. **Feature 10: Auto-Launch at Login** — quick win, 5 lines of code
5. **Feature 4: Clipboard-Only Mode** — quick win, simple toggle
6. **Feature 9: Menu Bar Waveform** — visual polish
7. **Feature 1: AI Post-Processing** — biggest feature, needs Settings window (which Features 2-6 also need, so build Settings window as part of this)
8. **Feature 3: Multi-Mode Dictation** — builds on Feature 1's AI post-processing
9. **Feature 8: Snippet Templates** — builds on History window
10. **Feature 7: Transcription Streaming** — complex, nice to have
11. **Feature 11: Statistics Dashboard** — builds on History data

## Settings Window (Shared Infrastructure)

Features 1-6 all need a Settings window. Build this as part of Feature 2 (the first feature that needs it), then each subsequent feature adds its section.

**Settings window structure:**
- `SettingsView.swift` — SwiftUI view with sidebar navigation
- `SettingsWindowController.swift` — NSWindow management (same pattern as HistoryWindowController)
- Sections: General (hotkey, launch at login, sound), Transcription (language, mode, streaming), AI Processing (backend, mode, API key), Snippets

**Access:** Right-click menu → "Settings..." (add between History and Quit)

---

## Out of Scope (For Now)

- Cloud sync of history/settings
- Multi-user support
- Audio recording/playback
- Custom wake word ("Hey Whisper")
- Plugin/extension system
- iOS/iPadOS companion app
