# Transcription History — Design Spec

## Goal

Add persistent transcription history to PushToTalkSTT with a searchable master-detail window accessible from the menu bar right-click menu.

## Data Model

```swift
struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    var text: String
    let date: Date
    let language: String    // ISO 639-1 code from WhisperKit (e.g. "en", "ka")
    let duration: Double    // recording duration in seconds
    var isFavorite: Bool
}
```

**Storage:** JSON array in `~/Library/Application Support/PushToTalkSTT/history.json`.

**Behavior:**
- Loaded into memory at app launch
- New entries prepended (newest first)
- Written to disk after every mutation (add, edit, delete, favorite toggle)
- Search is in-memory string matching (case-insensitive contains) — fast enough for thousands of entries on M-series chips
- Favorites are pinned to top of the list regardless of date

## Window Layout: Master-Detail

**Window properties:**
- Standard `NSWindow`, not a popover
- Title: "Transcription History"
- Default size: 700x500, resizable, minimum 500x350
- Remembers position/size via `NSWindow.setFrameAutosaveName("HistoryWindow")`
- Single instance — opening again brings existing window to front

**Left panel (master):**
- Search bar at top with magnifying glass icon, placeholder "Search transcriptions..."
- Scrollable list of entries, newest first
- Favorites section pinned at top (separated by a subtle divider if any exist)
- Each row shows:
  - Truncated text (2 lines max)
  - Relative timestamp ("Just now", "5 min ago", "Yesterday", "Apr 12")
  - Language badge (small pill, e.g. "EN", "KA")
  - Star icon if favorited
- Selected row highlighted with accent color left border
- Width: ~40% of window

**Right panel (detail):**
- Shows selected entry's full content
- Header: full timestamp + language + duration (e.g. "Today, 3:42 PM · EN · 2.4s")
- Body: full text in an editable `TextEditor` — user can correct transcription errors
- Action bar at bottom:
  - **Copy** — copies text to clipboard
  - **Re-inject** — pastes text into the previously active app (same as TextInjector.inject)
  - **Favorite** — toggles star (filled/unfilled)
  - **Delete** — removes entry with confirmation (or just removes, since undo is easy with the JSON file)
- Empty state when nothing selected: "Select a transcription to view details"

## Menu Bar Integration

Right-click on status bar icon shows `NSMenu` with:
1. **History** — opens/focuses the history window
2. Separator
3. **Quit** — terminates app

Left-click behavior unchanged (opens popover with status/last transcription).

## Recording Flow Changes

When a transcription completes in `AppDelegate.stopRecording`:
1. Create a `TranscriptionEntry` with the result text, detected language, and duration
2. Add it to `TranscriptionStore`
3. Update `ViewModel.lastTranscription` for the popover display
4. Inject text as before

`WhisperRecognizer.stopRecording` completion should also provide the detected language. Currently it only returns `String?`. Change to return a struct or tuple: `(text: String, language: String)`.

## File Structure

| Action | File | Purpose |
|--------|------|---------|
| Create | `TranscriptionStore.swift` | `TranscriptionEntry` model, JSON load/save, search, CRUD operations |
| Create | `HistoryWindowController.swift` | `NSWindowController` subclass, singleton window management |
| Create | `HistoryView.swift` | SwiftUI master-detail view with search, list, detail pane, actions |
| Modify | `AppDelegate.swift` | Add "History" to right-click menu, save transcriptions to store, pass language/duration |
| Modify | `WhisperRecognizer.swift` | Return language from transcription result alongside text |
| Modify | `ContentView.swift` | Show last transcription from store instead of ViewModel property |

## Out of Scope

- Export (CSV, JSON) — can be added later
- Transcription categories/tags
- Audio playback (we don't store the audio)
- Cloud sync
- Keyboard shortcut to open history
