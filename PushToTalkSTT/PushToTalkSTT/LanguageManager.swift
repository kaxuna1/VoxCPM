import Foundation

struct LanguageManager {
    /// Languages supported by Parakeet TDT v3 (25 European languages)
    static let supportedLanguages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("ru", "Russian (Русский)"),
        ("uk", "Ukrainian (Українська)"),
        ("de", "German (Deutsch)"),
        ("fr", "French (Français)"),
        ("es", "Spanish (Español)"),
        ("it", "Italian (Italiano)"),
        ("pt", "Portuguese (Português)"),
        ("nl", "Dutch (Nederlands)"),
        ("pl", "Polish (Polski)"),
        ("cs", "Czech (Čeština)"),
        ("ro", "Romanian (Română)"),
        ("hu", "Hungarian (Magyar)"),
        ("bg", "Bulgarian (Български)"),
        ("sr", "Serbian (Српски)"),
        ("hr", "Croatian (Hrvatski)"),
        ("sk", "Slovak (Slovenčina)"),
        ("sl", "Slovenian (Slovenščina)"),
        ("tr", "Turkish (Türkçe)"),
        ("el", "Greek (Ελληνικά)"),
        ("fi", "Finnish (Suomi)"),
        ("sv", "Swedish (Svenska)"),
        ("da", "Danish (Dansk)"),
        ("no", "Norwegian (Norsk)"),
        ("ca", "Catalan"),
    ]

    /// Current locked language. nil = auto-detect
    static var lockedLanguage: String? {
        get {
            let val = UserDefaults.standard.string(forKey: "languageLock")
            return val == "auto" ? nil : val
        }
        set {
            UserDefaults.standard.set(newValue ?? "auto", forKey: "languageLock")
        }
    }

    static var currentDisplayName: String {
        let code = UserDefaults.standard.string(forKey: "languageLock") ?? "auto"
        return supportedLanguages.first { $0.code == code }?.name ?? "Auto-detect"
    }

    static var currentShortLabel: String {
        if let code = lockedLanguage {
            return code.uppercased()
        }
        return "Auto"
    }
}
