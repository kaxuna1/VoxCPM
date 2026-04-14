import SwiftUI
import AppKit
import UserNotifications
import ApplicationServices
import AVFoundation
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var wasRightOptionPressed = false
    private let whisperRecognizer = WhisperRecognizer()
    private let viewModel = ViewModel()
    private let transcriptionStore = TranscriptionStore()
    private var historyWindowController: HistoryWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var overlayController: OverlayWindowController?
    private let waveformRenderer = WaveformRenderer()

    private enum DefaultsKey {
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
        popover.contentSize = NSSize(width: 280, height: 260)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel, store: transcriptionStore))

        overlayController = OverlayWindowController()

        historyWindowController = HistoryWindowController(store: transcriptionStore)

        settingsWindowController = SettingsWindowController()

        whisperRecognizer.onAudioLevel = { [weak self] level in
            self?.overlayController?.updateAudioLevel(CGFloat(level))
            if self?.viewModel.isRecording == true {
                self?.waveformRenderer.addLevel(CGFloat(level))
                if let icon = self?.waveformRenderer.renderIcon() {
                    self?.statusItem.button?.image = icon
                }
            }
        }

        whisperRecognizer.onPartialResult = { [weak self] text in
            self?.overlayController?.updatePartialText(text)
        }

        whisperRecognizer.onModelStateChanged = { [weak self] state in
            guard let self = self else { return }
            self.viewModel.modelStatus = state.rawValue
            self.viewModel.isModelReady = (state == .loaded)
            self.updateIcon()
        }

        Task { await whisperRecognizer.loadModel() }

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
            menu.addItem(NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "h"))
            menu.addItem(NSMenuItem(title: "Statistics", action: #selector(openStatistics), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(launchItem)
            let soundItem = NSMenuItem(title: "Sound Feedback", action: #selector(toggleSoundFeedback), keyEquivalent: "")
            soundItem.state = SoundManager.isEnabled ? .on : .off
            menu.addItem(soundItem)
            let modeMenu = NSMenu()
            for mode in DictationMode.allCases {
                let item = NSMenuItem(title: mode.rawValue, action: #selector(switchDictationMode(_:)), keyEquivalent: "")
                item.representedObject = mode.rawValue
                item.state = DictationMode.current == mode ? .on : .off
                item.image = NSImage(systemSymbolName: mode.icon, accessibilityDescription: nil)
                modeMenu.addItem(item)
            }
            let modeItem = NSMenuItem(title: "Mode: \(DictationMode.current.rawValue)", action: nil, keyEquivalent: "")
            modeItem.submenu = modeMenu
            menu.addItem(modeItem)

            // Language submenu
            let langMenu = NSMenu()
            for lang in LanguageManager.supportedLanguages {
                let item = NSMenuItem(title: lang.name, action: #selector(switchLanguage(_:)), keyEquivalent: "")
                item.representedObject = lang.code
                let currentCode = UserDefaults.standard.string(forKey: "languageLock") ?? "auto"
                item.state = lang.code == currentCode ? .on : .off
                langMenu.addItem(item)
            }
            let langItem = NSMenuItem(title: "Language: \(LanguageManager.currentShortLabel)", action: nil, keyEquivalent: "")
            langItem.submenu = langMenu
            menu.addItem(langItem)

            menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem.separator())
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

    @objc private func openHistory() {
        historyWindowController?.showWindow()
    }

    @objc private func openStatistics() {
        historyWindowController?.showWindow()
        // The history window has a Statistics tab - user can switch to it
    }

    @objc private func switchLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        LanguageManager.lockedLanguage = code == "auto" ? nil : code
    }

    @objc private func openSettings() {
        settingsWindowController?.showWindow()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Launch at login toggle failed: \(error)")
        }
    }

    @objc private func toggleSoundFeedback() {
        SoundManager.isEnabled.toggle()
    }

    @objc private func switchDictationMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = DictationMode(rawValue: rawValue) else { return }
        DictationMode.current = mode
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
        guard viewModel.isModelReady else {
            showNotification(title: "Model Loading", body: "WhisperKit model is still loading. Please wait.")
            return
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            showNotification(title: "Permission Requested", body: "Please grant Microphone access, then press Right Option again.")
            return
        }

        guard micStatus == .authorized else {
            showNotification(title: "Permission Denied", body: "Microphone access is disabled in System Settings.")
            return
        }

        viewModel.isRecording = true
        updateIcon()
        overlayController?.showListening()
        SoundManager.playStart()

        whisperRecognizer.startRecording { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.viewModel.isRecording = false
                    self?.updateIcon()
                    self?.overlayController?.hide()
                    self?.showNotification(title: "Error", body: error.localizedDescription)
                    SoundManager.playError()
                }
            }
        }
    }

    private func stopRecording() {
        guard viewModel.isRecording else { return }
        viewModel.isRecording = false
        updateIcon()

        overlayController?.showTranscribing()
        SoundManager.playStop()

        whisperRecognizer.stopRecording { [weak self] result in
            guard let self = self else { return }

            if let result = result {
                // AI Agent: check for trigger word
                if AgentManager.hasTrigger(result.text) {
                    let entry = TranscriptionEntry(text: result.text, language: result.language, duration: result.duration)
                    self.transcriptionStore.add(entry)
                    self.overlayController?.showProcessing()

                    Task {
                        let toolResult = await AgentManager.process(result.text)
                        await MainActor.run {
                            self.overlayController?.hide()
                            self.viewModel.lastTranscription = result.text
                            if toolResult.success {
                                self.showNotification(title: "Agent", body: toolResult.message)
                            } else {
                                TextInjector.inject(result.text)
                                self.showNotification(title: "Agent Error", body: toolResult.message)
                            }
                        }
                    }
                    return
                }

                // Command mode: execute voice command instead of injecting text
                if DictationMode.current == .command {
                    self.overlayController?.hide()
                    let entry = TranscriptionEntry(text: result.text, language: result.language, duration: result.duration)
                    self.transcriptionStore.add(entry)
                    if CommandExecutor.execute(result.text) {
                        self.showNotification(title: "Command", body: result.text)
                    } else {
                        self.showNotification(title: "Unknown Command", body: result.text)
                    }
                    return
                }

                let entry = TranscriptionEntry(
                    text: result.text,
                    language: result.language,
                    duration: result.duration
                )
                self.transcriptionStore.add(entry)

                // In Code mode, always run code post-processing
                let shouldProcess = DictationMode.current == .code || PostProcessor.shared.mode != .off
                if shouldProcess {
                    // Show AI processing animation
                    self.overlayController?.showProcessing()

                    Task {
                        let useMode: ProcessingMode = DictationMode.current == .code ? .code : PostProcessor.shared.mode
                        let saved = PostProcessor.shared.mode
                        PostProcessor.shared.mode = useMode
                        let processed = await PostProcessor.shared.process(result.text)
                        PostProcessor.shared.mode = saved
                        await MainActor.run {
                            self.overlayController?.hide()
                            self.viewModel.lastTranscription = processed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                TextInjector.inject(processed)
                            }
                            self.showNotification(title: "Typed & Copied", body: processed)
                        }
                    }
                } else {
                    self.viewModel.lastTranscription = result.text
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        TextInjector.inject(result.text)
                    }
                    self.showNotification(title: "Typed & Copied", body: result.text)
                    self.overlayController?.hide()
                }
            } else {
                self.overlayController?.hide()
                self.showNotification(title: "No speech detected", body: "Try speaking a bit longer.")
                SoundManager.playError()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        if !viewModel.isRecording {
            waveformRenderer.reset()
        }

        let symbolName: String
        let tintColor: NSColor

        if viewModel.isRecording {
            // Waveform icon is set by onAudioLevel callback
            return
        } else if !viewModel.isModelReady {
            symbolName = "mic.badge.xmark"
            tintColor = .systemOrange
        } else {
            symbolName = "mic"
            tintColor = .labelColor
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Push to Talk")
        button.contentTintColor = tintColor
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
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined && !UserDefaults.standard.bool(forKey: DefaultsKey.hasRequestedMic) {
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasRequestedMic)
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    private func checkAccessibility() {
        if !AXIsProcessTrusted() {
            // Show system dialog once, directing to System Settings → Accessibility
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
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
