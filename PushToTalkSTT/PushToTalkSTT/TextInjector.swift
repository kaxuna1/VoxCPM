import ApplicationServices
import CoreGraphics

struct TextInjector {
    static func inject(_ text: String) {
        if injectViaAccessibility(text) {
            return
        }
        KeyboardTyper.type(text)
    }

    private static func injectViaAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let error = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard error == .success, let element = focused else {
            return false
        }

        let axElement = element as! AXUIElement
        let result = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return result == .success
    }
}
