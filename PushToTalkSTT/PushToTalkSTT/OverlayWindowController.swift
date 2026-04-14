import SwiftUI
import AppKit

@MainActor
class AudioLevelModel: ObservableObject {
    @Published var audioLevel: CGFloat = 0.0
}

class OverlayWindowController: NSWindowController {
    let audioLevelModel = AudioLevelModel()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.contentView = NSHostingView(rootView: ListeningOverlayView(model: audioLevelModel))
        centerWindow()
    }

    func centerWindow() {
        guard let window = window, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let windowSize = window.frame.size
        let originX = screenRect.midX - windowSize.width / 2
        let originY = screenRect.midY - windowSize.height / 2
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    func updateAudioLevel(_ level: CGFloat) {
        audioLevelModel.audioLevel = level
    }

    func show() {
        centerWindow()
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
