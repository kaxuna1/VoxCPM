import SwiftUI
import AppKit

enum OverlayPhase: Equatable {
    case listening
    case transcribing
    case processing  // AI post-processing in progress
}

@MainActor
class OverlayModel: ObservableObject {
    @Published var audioLevel: CGFloat = 0.0
    @Published var phase: OverlayPhase = .listening
    @Published var partialText: String = ""
}

class OverlayWindowController: NSWindowController {
    let overlayModel = OverlayModel()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
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
        window.ignoresMouseEvents = true

        self.init(window: window)
        window.contentView = NSHostingView(rootView: OverlayRootView(model: overlayModel))
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
        overlayModel.audioLevel = level
    }

    func updatePartialText(_ text: String) {
        overlayModel.partialText = text
    }

    func showListening() {
        overlayModel.phase = .listening
        overlayModel.audioLevel = 0
        overlayModel.partialText = ""
        centerWindow()
        window?.orderFront(nil)
    }

    func showTranscribing() {
        overlayModel.phase = .transcribing
        overlayModel.audioLevel = 0
    }

    func showProcessing() {
        overlayModel.phase = .processing
    }

    func hide() {
        window?.orderOut(nil)
    }
}
