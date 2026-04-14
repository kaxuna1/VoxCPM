import SwiftUI
import AppKit
import UserNotifications
import ApplicationServices
import AVFoundation
import Speech

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var wasRightOptionPressed = false
    private let speechRecognizer = SpeechRecognizer()
    private let viewModel = ViewModel()
    private var overlayController: OverlayWindowController?

    private enum DefaultsKey {
        static let hasRequestedSpeech = "PushToTalkSTT.hasRequestedSpeech"
        static let hasRequestedMic = "PushToTalkSTT.hasRequestedMic"
        static let hasRequestedNotifications = "PushToTalkSTT.hasRequestedNotifications"
        static let hasPromptedAccessibility = "PushToTalkSTT.hasPromptedAccessibility"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Push to Talk")
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 220)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))

        overlayController = OverlayWindowController()

        speechRecognizer.onAudioLevel = { [weak self] level in
            self?.overlayController?.updateAudioLevel(CGFloat(level))
        }

        setupRightOptionMonitor()
        requestPermissionsIfNeeded()
        checkAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Right Option Global + Local Monitor

    private func setupRightOptionMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            // keyCode 58 = Left Option, 61 = Right Option
            guard event.keyCode == 61 else { return }
            let isOptionDown = event.modifierFlags.contains(.option)
            if isOptionDown && !self.wasRightOptionPressed {
                self.toggleRecording()
            }
            self.wasRightOptionPressed = isOptionDown
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if viewModel.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let speechStatus = SpeechRecognizer.authorizationStatus()
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if speechStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
            showNotification(title: "Permission Requested", body: "Please grant Speech Recognition permission, then press Right Option again.")
            return
        }
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            showNotification(title: "Permission Requested", body: "Please grant Microphone access, then press Right Option again.")
            return
        }

        guard speechStatus == .authorized else {
            showNotification(title: "Permission Denied", body: "Speech Recognition is disabled in System Settings.")
            return
        }
        guard micStatus == .authorized else {
            showNotification(title: "Permission Denied", body: "Microphone access is disabled in System Settings.")
            return
        }

        viewModel.isRecording = true
        updateIcon()
        overlayController?.show()

        speechRecognizer.startRecording { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.viewModel.isRecording = false
                    self?.updateIcon()
                    self?.overlayController?.hide()
                    self?.showNotification(title: "Error", body: error.localizedDescription)
                }
            }
        }
    }

    private func stopRecording() {
        guard viewModel.isRecording else { return }
        viewModel.isRecording = false
        updateIcon()
        overlayController?.hide()

        speechRecognizer.stopRecording { [weak self] text in
            guard let self = self else { return }
            if let text = text, !text.isEmpty {
                self.viewModel.lastTranscription = text
                ClipboardManager.copy(text)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    TextInjector.inject(text)
                }
                self.showNotification(title: "Typed & Copied", body: text)
            } else {
                self.showNotification(title: "No speech detected", body: "Try speaking a bit longer.")
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = viewModel.isRecording ? "mic.fill" : "mic"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Push to Talk")
        button.contentTintColor = viewModel.isRecording ? .systemRed : .labelColor
        button.needsDisplay = true
    }

    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    // MARK: - Permissions

    private func requestPermissionsIfNeeded() {
        let speechStatus = SpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined && !UserDefaults.standard.bool(forKey: DefaultsKey.hasRequestedSpeech) {
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasRequestedSpeech)
            SFSpeechRecognizer.requestAuthorization { _ in }
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined && !UserDefaults.standard.bool(forKey: DefaultsKey.hasRequestedMic) {
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasRequestedMic)
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    private func checkAccessibility() {
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(nil)
        if !accessibilityEnabled {
            let hasPrompted = UserDefaults.standard.bool(forKey: DefaultsKey.hasPromptedAccessibility)
            if !hasPrompted {
                UserDefaults.standard.set(true, forKey: DefaultsKey.hasPromptedAccessibility)
                showNotification(
                    title: "Accessibility Required",
                    body: "Grant Accessibility access in System Settings for global Right Option hotkey and text typing."
                )
            }
        }
    }

    private func showNotification(title: String, body: String) {
        if !UserDefaults.standard.bool(forKey: DefaultsKey.hasRequestedNotifications) {
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasRequestedNotifications)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.deliverNotification(title: title, body: body)
                }
            }
        } else {
            deliverNotification(title: title, body: body)
        }
    }

    private func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
