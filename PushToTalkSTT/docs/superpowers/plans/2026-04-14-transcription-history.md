# Transcription History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent, searchable transcription history with a master-detail window accessible from the menu bar.

**Architecture:** A `TranscriptionStore` (ObservableObject) manages an array of `TranscriptionEntry` structs, persisted as JSON in Application Support. A new `HistoryView` (SwiftUI) provides the master-detail UI inside an `NSWindow` managed by `HistoryWindowController`. `WhisperRecognizer.stopRecording` is extended to return detected language alongside text. `AppDelegate` wires everything together — saving entries, opening the history window from the right-click menu.

**Tech Stack:** SwiftUI, AppKit (NSWindow, NSMenu), Foundation (JSONEncoder/Decoder, FileManager), Swift 6.0, macOS 14+

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `PushToTalkSTT/TranscriptionStore.swift` | Data model, JSON persistence, search, CRUD |
| Create | `PushToTalkSTT/HistoryView.swift` | SwiftUI master-detail view |
| Create | `PushToTalkSTT/HistoryWindowController.swift` | NSWindow lifecycle, singleton |
| Modify | `PushToTalkSTT/WhisperRecognizer.swift` | Return language + duration from transcription |
| Modify | `PushToTalkSTT/AppDelegate.swift` | Right-click menu, save to store, open history |
| Modify | `PushToTalkSTT/ContentView.swift` | Show last transcription from store |

---

### Task 1: Create TranscriptionStore

**Files:**
- Create: `PushToTalkSTT/TranscriptionStore.swift`

- [ ] **Step 1: Create TranscriptionStore.swift**

```swift
import Foundation
import SwiftUI

struct TranscriptionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let date: Date
    let language: String
    let duration: Double
    var isFavorite: Bool

    init(text: String, language: String, duration: Double) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.language = language
        self.duration = duration
        self.isFavorite = false
    }
}

@MainActor
class TranscriptionStore: ObservableObject {
    @Published private(set) var entries: [TranscriptionEntry] = []

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PushToTalkSTT", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func update(_ entry: TranscriptionEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func toggleFavorite(_ entry: TranscriptionEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        save()
    }

    // MARK: - Search

    func filtered(by query: String) -> [TranscriptionEntry] {
        let all = query.isEmpty ? entries : entries.filter {
            $0.text.localizedCaseInsensitiveContains(query)
        }
        // Favorites first, then by date descending
        return all.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.date > rhs.date
        }
    }

    var lastTranscription: TranscriptionEntry? {
        entries.first
    }

    // MARK: - Persistence

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("TranscriptionStore: save failed – \(error)")
        }
    }

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([TranscriptionEntry].self, from: data)
        } catch {
            print("TranscriptionStore: load failed – \(error)")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushToTalkSTT/TranscriptionStore.swift
git commit -m "feat: add TranscriptionStore with JSON persistence"
```

---

### Task 2: Update WhisperRecognizer to Return Language and Duration

**Files:**
- Modify: `PushToTalkSTT/WhisperRecognizer.swift`

The current `stopRecording` completion returns `String?`. Change it to return a result struct with text, language, and duration.

- [ ] **Step 1: Add TranscriptionResult struct and update stopRecording signature**

Add this struct at the top of WhisperRecognizer.swift (after the imports, before `WhisperModelState`):

```swift
struct RecognitionResult {
    let text: String
    let language: String
    let duration: Double
}
```

- [ ] **Step 2: Update stopRecording to return RecognitionResult?**

Change the signature from:
```swift
func stopRecording(completion: @escaping (String?) -> Void)
```
to:
```swift
func stopRecording(completion: @escaping (RecognitionResult?) -> Void)
```

In the transcription Task block, change the success path from:
```swift
let finalText = text.isEmpty ? nil : text
DispatchQueue.main.async { completion(finalText) }
```
to:
```swift
if text.isEmpty {
    DispatchQueue.main.async { completion(nil) }
} else {
    let language = results.first?.language ?? "unknown"
    let result = RecognitionResult(text: text, language: language, duration: duration)
    DispatchQueue.main.async { completion(result) }
}
```

Note: `duration` is already computed earlier in the method as `Double(samples.count) / inputSampleRate`.

- [ ] **Step 3: Commit**

```bash
git add PushToTalkSTT/WhisperRecognizer.swift
git commit -m "feat: return language and duration from WhisperRecognizer"
```

---

### Task 3: Create HistoryView (SwiftUI Master-Detail)

**Files:**
- Create: `PushToTalkSTT/HistoryView.swift`

- [ ] **Step 1: Create HistoryView.swift**

```swift
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: TranscriptionStore
    @State private var searchText = ""
    @State private var selectedID: UUID?

    private var filteredEntries: [TranscriptionEntry] {
        store.filtered(by: searchText)
    }

    private var selectedEntry: TranscriptionEntry? {
        guard let id = selectedID else { return nil }
        return store.entries.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            masterPanel
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 350)
            detailPanel
                .frame(minWidth: 280)
        }
        .frame(minWidth: 500, minHeight: 350)
    }

    // MARK: - Master Panel

    private var masterPanel: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            // Entry list
            List(selection: $selectedID) {
                let entries = filteredEntries
                let favorites = entries.filter(\.isFavorite)
                let regular = entries.filter { !$0.isFavorite }

                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { entry in
                            EntryRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                }

                Section(favorites.isEmpty ? "All" : "Recent") {
                    ForEach(regular) { entry in
                        EntryRow(entry: entry)
                            .tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)

            // Footer
            HStack {
                Text("\(store.entries.count) transcriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let entry = selectedEntry {
                DetailView(entry: entry, store: store)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a transcription to view details")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Entry Row

struct EntryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.language.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(3)
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
            Text(entry.text)
                .font(.body)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail View

struct DetailView: View {
    let entry: TranscriptionEntry
    @ObservedObject var store: TranscriptionStore
    @State private var editedText: String = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(entry.date, format: .dateTime.month().day().year().hour().minute())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Text(entry.language.uppercased())
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Text(String(format: "%.1fs", entry.duration))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()

            Divider()

            // Text content
            if isEditing {
                TextEditor(text: $editedText)
                    .font(.body)
                    .padding(8)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isEditing = false
                    }
                    Button("Save") {
                        var updated = entry
                        updated.text = editedText
                        store.update(updated)
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                ScrollView {
                    Text(entry.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }

            Divider()

            // Action bar
            HStack(spacing: 12) {
                Button { ClipboardManager.copy(entry.text) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button { TextInjector.inject(entry.text) } label: {
                    Label("Re-inject", systemImage: "text.insert")
                }

                Button {
                    editedText = entry.text
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button { store.toggleFavorite(entry) } label: {
                    Label(
                        entry.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: entry.isFavorite ? "star.fill" : "star"
                    )
                }
                .foregroundColor(entry.isFavorite ? .yellow : nil)

                Spacer()

                Button(role: .destructive) { store.delete(entry) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .padding()
            .background(.bar)
        }
        .onChange(of: entry.id) { _, _ in
            isEditing = false
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushToTalkSTT/HistoryView.swift
git commit -m "feat: add HistoryView with master-detail layout"
```

---

### Task 4: Create HistoryWindowController

**Files:**
- Create: `PushToTalkSTT/HistoryWindowController.swift`

- [ ] **Step 1: Create HistoryWindowController.swift**

```swift
import AppKit
import SwiftUI

class HistoryWindowController {
    private var window: NSWindow?
    private let store: TranscriptionStore

    init(store: TranscriptionStore) {
        self.store = store
    }

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView(store: store)
        let hostingView = NSHostingView(rootView: historyView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcription History"
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 500, height: 350)
        window.setFrameAutosaveName("HistoryWindow")
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushToTalkSTT/HistoryWindowController.swift
git commit -m "feat: add HistoryWindowController for singleton history window"
```

---

### Task 5: Wire Everything in AppDelegate

**Files:**
- Modify: `PushToTalkSTT/AppDelegate.swift`
- Modify: `PushToTalkSTT/ContentView.swift`

- [ ] **Step 1: Add TranscriptionStore and HistoryWindowController to AppDelegate**

Add these properties alongside the existing ones (around line 15):

```swift
    private let transcriptionStore = TranscriptionStore()
    private var historyWindowController: HistoryWindowController?
```

In `applicationDidFinishLaunching`, after `overlayController = OverlayWindowController()`, add:

```swift
        historyWindowController = HistoryWindowController(store: transcriptionStore)
```

- [ ] **Step 2: Update the right-click menu**

Replace the right-click menu block in `statusBarButtonClicked` (currently around line 72-77):

```swift
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "h"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
```

Add the `openHistory` method near `quitApp`:

```swift
    @objc private func openHistory() {
        historyWindowController?.showWindow()
    }
```

- [ ] **Step 3: Update stopRecording to save entries**

Replace the `stopRecording` method to handle the new `RecognitionResult` type and save to store:

```swift
    private func stopRecording() {
        guard viewModel.isRecording else { return }
        viewModel.isRecording = false
        updateIcon()

        overlayController?.showTranscribing()

        whisperRecognizer.stopRecording { [weak self] result in
            guard let self = self else { return }

            self.overlayController?.hide()

            if let result = result {
                // Save to history
                let entry = TranscriptionEntry(
                    text: result.text,
                    language: result.language,
                    duration: result.duration
                )
                self.transcriptionStore.add(entry)
                self.viewModel.lastTranscription = result.text

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    TextInjector.inject(result.text)
                }
                self.showNotification(title: "Typed & Copied", body: result.text)
            } else {
                self.showNotification(title: "No speech detected", body: "Try speaking a bit longer.")
            }
        }
    }
```

- [ ] **Step 4: Update ContentView to show last transcription from store**

Replace `ContentView.swift` — use the store's `lastTranscription` instead of ViewModel:

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(viewModel.isModelReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.modelStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !viewModel.isModelReady {
                Text("Press Right Option to record once model is loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .foregroundColor(viewModel.isRecording ? .red : .primary)
                Text(viewModel.isRecording ? "Listening..." : "Idle")
                    .font(.headline)
            }

            if let entry = store.lastTranscription {
                Text("Last transcription:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(entry.text)
                    .font(.body)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Divider()

            Button("Quit PushToTalkSTT") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
```

Update the popover creation in `applicationDidFinishLaunching` to pass the store:

```swift
        popover.contentViewController = NSHostingController(
            rootView: ContentView(viewModel: viewModel, store: transcriptionStore)
        )
```

- [ ] **Step 5: Commit**

```bash
git add PushToTalkSTT/AppDelegate.swift PushToTalkSTT/ContentView.swift
git commit -m "feat: wire history store, menu item, and updated recording flow"
```

---

### Task 6: Build, Test, and Verify

**Files:** None (verification only)

- [ ] **Step 1: Build**

```bash
cd /Users/kaxuna1/Code/VoxCPM/PushToTalkSTT
swift build -c release 2>&1 | tail -10
```

Expected: `Build complete!`

- [ ] **Step 2: Package and launch**

```bash
pkill -f "PushToTalkSTT" 2>/dev/null; sleep 1
cp .build/arm64-apple-macosx/release/PushToTalkSTT build_out/PushToTalkSTT.app/Contents/MacOS/PushToTalkSTT
codesign --force --sign "PushToTalkSTT Dev" --entitlements PushToTalkSTT/PushToTalkSTT.entitlements build_out/PushToTalkSTT.app
open build_out/PushToTalkSTT.app
```

- [ ] **Step 3: Verify features**

1. Right-click menu bar icon → "History" appears above "Quit"
2. Click "History" → window opens with empty state
3. Press Right Option, speak, release → text transcribed and injected
4. Right-click → History → window shows the transcription entry
5. Select entry → detail pane shows full text, timestamp, language, duration
6. Click Copy → text on clipboard
7. Click Re-inject → text pasted into focused app
8. Click Edit → text becomes editable, save works
9. Click Favorite → star appears, entry moves to Favorites section
10. Search → filters entries by text content
11. Click Delete → entry removed
12. Quit and relaunch → history persists

- [ ] **Step 4: Commit any fixes, then final commit**

```bash
git add -A
git commit -m "feat: complete transcription history with persistence, search, and master-detail UI"
```
