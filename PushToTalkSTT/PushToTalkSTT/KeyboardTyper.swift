import CoreGraphics

struct KeyboardTyper {
    /// Fallback: inject text via CGEvent unicode string, character by character.
    static func type(_ string: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        for character in string {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            // Clear modifier flags to prevent accented characters if Option key
            // hasn't fully released from the push-to-talk trigger
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
            usleep(1000) // 1ms delay between characters for reliability
        }
    }
}
