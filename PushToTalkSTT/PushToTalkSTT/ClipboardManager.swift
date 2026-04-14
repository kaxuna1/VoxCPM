import AppKit

final class ClipboardManager {
    static let shared = ClipboardManager()
    private var savedItems: [NSPasteboardItem] = []

    /// Save current clipboard contents (all types, not just strings)
    func save() {
        let pb = NSPasteboard.general
        savedItems = []
        guard let items = pb.pasteboardItems else { return }
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            savedItems.append(copy)
        }
    }

    /// Set text on clipboard
    func set(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Restore previously saved clipboard contents
    func restore() {
        guard !savedItems.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(savedItems)
        savedItems = []
    }

    /// One-shot copy (no save/restore, for notification or manual paste)
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
