import Foundation

enum DictationMode: String, CaseIterable, Codable {
    case prose = "Prose"
    case code = "Code"
    case command = "Command"

    var icon: String {
        switch self {
        case .prose: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .command: return "terminal"
        }
    }

    static var current: DictationMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "dictationMode"),
                  let mode = DictationMode(rawValue: raw) else { return .prose }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "dictationMode") }
    }

    func next() -> DictationMode {
        let all = DictationMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
