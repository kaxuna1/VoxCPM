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
