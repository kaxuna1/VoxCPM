import CoreGraphics

struct CommandExecutor {
    private static let commands: [(phrases: [String], action: () -> Void)] = [
        (["select all"], { postKeyCombo(key: 0, flags: .maskCommand) }),       // Cmd+A
        (["undo"], { postKeyCombo(key: 6, flags: .maskCommand) }),             // Cmd+Z
        (["redo"], { postKeyCombo(key: 6, flags: [.maskCommand, .maskShift]) }), // Cmd+Shift+Z
        (["copy"], { postKeyCombo(key: 8, flags: .maskCommand) }),             // Cmd+C
        (["paste"], { postKeyCombo(key: 9, flags: .maskCommand) }),            // Cmd+V
        (["cut"], { postKeyCombo(key: 7, flags: .maskCommand) }),              // Cmd+X
        (["save"], { postKeyCombo(key: 1, flags: .maskCommand) }),             // Cmd+S
        (["new line", "enter", "return"], { postKey(key: 36) }),               // Return
        (["tab"], { postKey(key: 48) }),                                        // Tab
        (["delete", "backspace"], { postKey(key: 51) }),                        // Backspace
        (["escape"], { postKey(key: 53) }),                                     // Escape
        (["space"], { postKey(key: 49) }),                                      // Space
    ]

    /// Try to execute a voice command. Returns true if a command was matched.
    static func execute(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        for entry in commands {
            for phrase in entry.phrases {
                if normalized == phrase || normalized.contains(phrase) {
                    entry.action()
                    return true
                }
            }
        }
        return false
    }

    private static func postKey(key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postKeyCombo(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
