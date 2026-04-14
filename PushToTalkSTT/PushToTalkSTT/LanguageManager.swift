import Foundation

struct LanguageManager {
    /// All languages supported by Whisper large-v3, sorted by name
    static let supportedLanguages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("ka", "Georgian (ქართული)"),
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
        ("ar", "Arabic (العربية)"),
        ("he", "Hebrew (עברית)"),
        ("fa", "Persian (فارسی)"),
        ("hi", "Hindi (हिन्दी)"),
        ("bn", "Bengali (বাংলা)"),
        ("ta", "Tamil (தமிழ்)"),
        ("te", "Telugu (తెలుగు)"),
        ("zh", "Chinese (中文)"),
        ("ja", "Japanese (日本語)"),
        ("ko", "Korean (한국어)"),
        ("vi", "Vietnamese (Tiếng Việt)"),
        ("th", "Thai (ไทย)"),
        ("id", "Indonesian (Bahasa)"),
        ("ms", "Malay (Bahasa Melayu)"),
        ("fi", "Finnish (Suomi)"),
        ("sv", "Swedish (Svenska)"),
        ("da", "Danish (Dansk)"),
        ("no", "Norwegian (Norsk)"),
        ("el", "Greek (Ελληνικά)"),
        ("af", "Afrikaans"),
        ("az", "Azerbaijani"),
        ("be", "Belarusian"),
        ("bs", "Bosnian"),
        ("ca", "Catalan"),
        ("cy", "Welsh"),
        ("et", "Estonian"),
        ("gl", "Galician"),
        ("hy", "Armenian"),
        ("is", "Icelandic"),
        ("kk", "Kazakh"),
        ("la", "Latin"),
        ("lt", "Lithuanian"),
        ("lv", "Latvian"),
        ("mk", "Macedonian"),
        ("mn", "Mongolian"),
        ("mr", "Marathi"),
        ("ne", "Nepali"),
        ("sw", "Swahili"),
        ("tl", "Tagalog"),
        ("ur", "Urdu"),
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

    /// Display name for current setting
    static var currentDisplayName: String {
        let code = UserDefaults.standard.string(forKey: "languageLock") ?? "auto"
        return supportedLanguages.first { $0.code == code }?.name ?? "Auto-detect"
    }

    /// Short label for menu
    static var currentShortLabel: String {
        if let code = lockedLanguage {
            return code.uppercased()
        }
        return "Auto"
    }
}
