import ApplicationServices
import CoreGraphics
import AppKit

struct TextInjector {

    /// Injects text into the currently focused input field.
    /// Uses clipboard paste (Cmd+V) — the industry standard approach used by
    /// Superwhisper, WhisperType, TextExpander, and macOS dictation.
    static func inject(_ text: String) {
        guard !text.isEmpty else { return }
        clipboardPaste(text)
    }

    // MARK: - Clipboard Paste (primary)

    private static func clipboardPaste(_ text: String) {
        let clipboard = ClipboardManager.shared

        // Save current clipboard so we can restore it
        clipboard.save()

        // Put our text on the clipboard
        clipboard.set(text)

        // Allow pasteboard server to sync (it's a separate process)
        usleep(50_000) // 50ms

        // Simulate Cmd+V
        postCmdV()

        // Restore user's clipboard after target app has read it
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            clipboard.restore()
        }
    }

    private static func postCmdV() {
        // Use .combinedSessionState — merges hardware + software key state.
        // .hidSystemState can conflict with the Option key still releasing
        // from the push-to-talk trigger.
        let source = CGEventSource(stateID: .combinedSessionState)

        // keyCode 9 = 'V'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // .cghidEventTap injects at the HID layer, before the window server
        // routes events — the standard for all production text injection tools
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
