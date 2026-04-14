import CoreGraphics

struct KeyboardTyper {
    /// Fallback: inject text via CGEvent unicode string, character by character.
    static func type(_ string: String) {
        // Use .combinedSessionState to avoid conflicts with held modifier keys
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        for character in string {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            // Clear modifier flags to prevent accented characters
            keyDown?.flags = []
            keyUp?.flags = []

            let chars = String(character)
            let length = chars.utf16.count

            chars.withCString(encodedAs: UTF16.self) { pointer in
                keyDown?.keyboardSetUnicodeString(stringLength: length, unicodeString: pointer)
                keyUp?.keyboardSetUnicodeString(stringLength: length, unicodeString: pointer)
            }

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            usleep(2000) // 2ms delay between characters for reliability
        }
    }
}
