import AppKit

struct SoundManager {
    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundFeedbackDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundFeedbackDisabled") }
    }

    static func playStart() {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    static func playStop() {
        guard isEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    static func playError() {
        guard isEnabled else { return }
        NSSound(named: "Basso")?.play()
    }
}
