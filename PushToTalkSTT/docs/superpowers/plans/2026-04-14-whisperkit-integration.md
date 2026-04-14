# WhisperKit Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Apple SFSpeechRecognizer with WhisperKit's multilingual small model (`openai_whisper-small`), bundled inside the app, loaded at launch.

**Architecture:** WhisperKit is added as an SPM dependency. A new `WhisperRecognizer` replaces `SpeechRecognizer`, recording audio via AVAudioEngine during push-to-talk, then batch-transcribing the collected audio buffer when the user releases the key. The CoreML model files are pre-downloaded and embedded in the app bundle's `Resources/` directory. Model loading happens async at launch with status shown in the menu bar popover.

**Tech Stack:** WhisperKit (SPM), CoreML, AVFoundation, Swift 6.0, macOS 14+

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `PushToTalkSTT/WhisperRecognizer.swift` | New STT engine: model loading, audio capture, transcription via WhisperKit |
| Modify | `PushToTalkSTT/ViewModel.swift` | Add `modelState` property for loading status |
| Modify | `PushToTalkSTT/ContentView.swift` | Show model loading status in popover |
| Modify | `PushToTalkSTT/AppDelegate.swift` | Wire up WhisperRecognizer, remove SFSpeech permission code |
| Delete | `PushToTalkSTT/SpeechRecognizer.swift` | Replaced by WhisperRecognizer |
| Modify | `project.yml` | Add WhisperKit SPM dependency |
| Modify | `PushToTalkSTT/Info.plist` | Remove NSSpeechRecognitionUsageDescription |
| Create | `PushToTalkSTT/Resources/` | Directory for bundled WhisperKit model files |
| Create | `scripts/download-model.sh` | One-time script to download model into Resources/ |

---

### Task 1: Download and Bundle the WhisperKit Model

**Files:**
- Create: `scripts/download-model.sh`
- Create: `PushToTalkSTT/Resources/openai_whisper-small/` (model files)

The model must be pre-downloaded so the app ships self-contained. WhisperKit models are hosted on HuggingFace at `argmaxinc/whisperkit-coreml`. We use `huggingface-cli` to download the specific model folder.

- [ ] **Step 1: Create the download script**

```bash
#!/bin/bash
# scripts/download-model.sh
# Downloads the WhisperKit multilingual small model into the app's Resources directory.
# Run once before building. Requires: pip install huggingface_hub

set -euo pipefail

MODEL_NAME="openai_whisper-small"
REPO="argmaxinc/whisperkit-coreml"
DEST="PushToTalkSTT/Resources/${MODEL_NAME}"

if [ -d "$DEST" ] && [ "$(ls -A "$DEST")" ]; then
    echo "Model already exists at $DEST — skipping download."
    exit 0
fi

echo "Downloading ${MODEL_NAME} from ${REPO}..."
mkdir -p "$DEST"

huggingface-cli download "${REPO}" \
    --include "${MODEL_NAME}/*" \
    --local-dir "$DEST/_tmp" \
    --local-dir-use-symlinks False

# Move files out of the nested folder
mv "$DEST/_tmp/${MODEL_NAME}"/* "$DEST/"
rm -rf "$DEST/_tmp"

echo "Model downloaded to $DEST"
ls -lh "$DEST/"
```

- [ ] **Step 2: Run the download script**

```bash
cd /Users/kaxuna1/Code/VoxCPM/PushToTalkSTT
chmod +x scripts/download-model.sh
pip install huggingface_hub 2>/dev/null || pip3 install huggingface_hub
bash scripts/download-model.sh
```

Expected: Model files (`.mlmodelc` directories, `config.json`, etc.) appear in `PushToTalkSTT/Resources/openai_whisper-small/`.

- [ ] **Step 3: Verify model files exist**

```bash
ls PushToTalkSTT/Resources/openai_whisper-small/
```

Expected: Multiple `.mlmodelc` folders (AudioEncoder, TextDecoder, MelSpectrogram, etc.), `config.json`, `generation_config.json`, tokenizer files.

- [ ] **Step 4: Add Resources to .gitignore**

The model is ~460MB — do not commit it. Add to `.gitignore`:

```
# WhisperKit model (too large for git — download via scripts/download-model.sh)
PushToTalkSTT/Resources/openai_whisper-small/
```

- [ ] **Step 5: Commit**

```bash
git add scripts/download-model.sh .gitignore
git commit -m "feat: add WhisperKit model download script"
```

---

### Task 2: Add WhisperKit SPM Dependency and Update Build Config

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Update project.yml to add WhisperKit package**

```yaml
name: PushToTalkSTT
options:
  bundleIdPrefix: com.user
  deploymentTarget:
    macOS: "14.0"
packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit.git
    from: "0.9.0"
targets:
  PushToTalkSTT:
    type: application
    platform: macOS
    sources:
      - PushToTalkSTT
    resources:
      - path: PushToTalkSTT/Resources
        buildPhase: resources
    dependencies:
      - package: WhisperKit
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.user.PushToTalkSTT
      CODE_SIGN_IDENTITY: "-"
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: ""
      ENABLE_HARDENED_RUNTIME: YES
      SWIFT_VERSION: "6.0"
      MACOSX_DEPLOYMENT_TARGET: "14.0"
    info:
      path: PushToTalkSTT/Info.plist
    entitlements:
      path: PushToTalkSTT/PushToTalkSTT.entitlements
```

Key changes:
- Added `packages:` block with WhisperKit SPM dependency
- Added `resources:` to bundle the model directory
- Added `dependencies:` to link WhisperKit

- [ ] **Step 2: Regenerate Xcode project (if using xcodegen)**

```bash
cd /Users/kaxuna1/Code/VoxCPM/PushToTalkSTT
xcodegen generate 2>/dev/null || echo "xcodegen not installed — project.yml updated for reference, will build with swiftc + manual SPM"
```

Note: Since we build with `swiftc` directly, the SPM dependency will need to be resolved and linked manually. An alternative approach for the direct `swiftc` build: clone WhisperKit into a local directory and compile its sources alongside the app. Task 6 covers the build integration.

- [ ] **Step 3: Commit**

```bash
git add project.yml
git commit -m "feat: add WhisperKit SPM dependency to project config"
```

---

### Task 3: Create WhisperRecognizer

**Files:**
- Create: `PushToTalkSTT/WhisperRecognizer.swift`

This is the core replacement for `SpeechRecognizer.swift`. It:
- Loads the bundled WhisperKit model at init
- Captures audio via AVAudioEngine into a buffer during push-to-talk
- Batch-transcribes the buffer when recording stops
- Reports audio levels for the overlay animation
- Reports model loading state

- [ ] **Step 1: Create WhisperRecognizer.swift**

```swift
import AVFoundation
import Accelerate
import WhisperKit

enum WhisperModelState: String {
    case unloaded = "Not loaded"
    case loading = "Loading model..."
    case loaded = "Ready"
    case error = "Model error"
}

class WhisperRecognizer {
    private var whisperKit: WhisperKit?
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    var onAudioLevel: ((Float) -> Void)?
    var onModelStateChanged: ((WhisperModelState) -> Void)?

    private(set) var modelState: WhisperModelState = .unloaded {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onModelStateChanged?(self.modelState)
            }
        }
    }

    /// Load the bundled WhisperKit model. Call once at app launch (runs async).
    func loadModel() async {
        modelState = .loading

        // Find the bundled model directory
        guard let modelPath = Bundle.main.resourcePath.map({ $0 + "/openai_whisper-small" }),
              FileManager.default.fileExists(atPath: modelPath) else {
            modelState = .error
            return
        }

        do {
            let config = WhisperKitConfig(
                model: "openai_whisper-small",
                modelFolder: modelPath,
                computeOptions: ModelComputeOptions(
                    melCompute: .cpuAndNeuralEngine,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine,
                    prefillCompute: .cpuAndNeuralEngine
                ),
                verbose: false,
                logLevel: .error,
                download: false  // Model is bundled, don't download
            )
            whisperKit = try await WhisperKit(config)
            modelState = .loaded
        } catch {
            print("WhisperKit model load failed: \(error)")
            modelState = .error
        }
    }

    /// Start capturing audio from the microphone.
    func startRecording(completion: ((Error?) -> Void)? = nil) {
        guard whisperKit != nil else {
            completion?(NSError(
                domain: "PushToTalkSTT",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit model not loaded."]
            ))
            return
        }

        stopAudioSession()
        bufferLock.withLock { audioBuffer = [] }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.appendAudioBuffer(buffer)
            self?.processAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            completion?(nil)
        } catch {
            completion?(error)
        }
    }

    /// Stop recording and transcribe the captured audio.
    func stopRecording(completion: @escaping (String?) -> Void) {
        guard audioEngine.isRunning else {
            completion(nil)
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(0.0)
        }

        // Grab the recorded audio
        let samples: [Float] = bufferLock.withLock {
            let copy = audioBuffer
            audioBuffer = []
            return copy
        }

        guard !samples.isEmpty, let whisperKit = whisperKit else {
            completion(nil)
            return
        }

        // Transcribe in background
        Task {
            do {
                let options = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    detectLanguage: true  // Auto-detect language (multilingual)
                )
                let results = try await whisperKit.transcribe(
                    audioArray: samples,
                    decodeOptions: options
                )
                let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    completion(text.isEmpty ? nil : text)
                }
            } catch {
                print("Transcription error: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Private

    private func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // WhisperKit expects 16kHz mono Float32 audio.
        // AVAudioEngine's inputNode typically outputs at the hardware sample rate (e.g., 48kHz).
        // WhisperKit's AudioProcessor handles resampling internally when we pass the raw samples,
        // but for efficiency we collect at the native rate and let WhisperKit resample.
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        bufferLock.withLock {
            audioBuffer.append(contentsOf: samples)
        }
    }

    private func processAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = UInt32(buffer.frameLength)
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let level = min(max((rms - 0.01) * 15.0, 0.0), 1.0)
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(level)
        }
    }

    private func stopAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
}
```

- [ ] **Step 2: Verify file is syntactically valid**

```bash
# This will fail until WhisperKit is linked, but checks for Swift syntax issues
swiftc -typecheck PushToTalkSTT/WhisperRecognizer.swift 2>&1 | head -5
```

Expected: Errors about missing WhisperKit module (not syntax errors). This is fine — linking comes in Task 6.

- [ ] **Step 3: Commit**

```bash
git add PushToTalkSTT/WhisperRecognizer.swift
git commit -m "feat: add WhisperRecognizer with WhisperKit transcription"
```

---

### Task 4: Update ViewModel and ContentView for Model Loading Status

**Files:**
- Modify: `PushToTalkSTT/ViewModel.swift`
- Modify: `PushToTalkSTT/ContentView.swift`

- [ ] **Step 1: Add modelStatus to ViewModel**

Replace `PushToTalkSTT/ViewModel.swift` with:

```swift
import SwiftUI

@MainActor
class ViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var lastTranscription: String?
    @Published var modelStatus: String = "Not loaded"
    @Published var isModelReady = false
}
```

- [ ] **Step 2: Update ContentView to show model status**

Replace `PushToTalkSTT/ContentView.swift` with:

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Model status
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isModelReady ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.modelStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Recording status
            HStack {
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .foregroundColor(viewModel.isRecording ? .red : .primary)
                Text(viewModel.isRecording ? "Listening..." : "Idle")
                    .font(.headline)
            }

            if !viewModel.isModelReady {
                Text("Press Right Option to record once model is loaded")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let text = viewModel.lastTranscription, !text.isEmpty {
                Text("Last transcription:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.body)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Divider()

            Button("Quit PushToTalkSTT") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add PushToTalkSTT/ViewModel.swift PushToTalkSTT/ContentView.swift
git commit -m "feat: show WhisperKit model loading status in popover"
```

---

### Task 5: Update AppDelegate to Use WhisperRecognizer

**Files:**
- Modify: `PushToTalkSTT/AppDelegate.swift`
- Modify: `PushToTalkSTT/Info.plist`
- Delete: `PushToTalkSTT/SpeechRecognizer.swift`

- [ ] **Step 1: Replace AppDelegate.swift**

Key changes:
- Replace `SpeechRecognizer` with `WhisperRecognizer`
- Remove `import Speech`
- Remove speech recognition permission code
- Add async model loading at launch
- Block recording until model is loaded

```swift
import SwiftUI
import AppKit
import UserNotifications
import ApplicationServices
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var wasRightOptionPressed = false
    private let whisperRecognizer = WhisperRecognizer()
    private let viewModel = ViewModel()
    private var overlayController: OverlayWindowController?

    private enum DefaultsKey {
        static let hasRequestedMic = "PushToTalkSTT.hasRequestedMic"
        static let hasRequestedNotifications = "PushToTalkSTT.hasRequestedNotifications"
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
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))

        overlayController = OverlayWindowController()

        whisperRecognizer.onAudioLevel = { [weak self] level in
            self?.overlayController?.updateAudioLevel(CGFloat(level))
        }

        whisperRecognizer.onModelStateChanged = { [weak self] state in
            self?.viewModel.modelStatus = state.rawValue
            self?.viewModel.isModelReady = (state == .loaded)
            self?.updateIcon()
        }

        setupRightOptionMonitor()
        requestMicPermission()
        checkAccessibility()

        // Load WhisperKit model in background
        Task {
            await whisperRecognizer.loadModel()
        }
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
            showNotification(title: "Not Ready", body: "WhisperKit model is still loading. Please wait.")
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
        overlayController?.show()

        whisperRecognizer.startRecording { [weak self] error in
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

        whisperRecognizer.stopRecording { [weak self] text in
            guard let self = self else { return }
            if let text = text, !text.isEmpty {
                self.viewModel.lastTranscription = text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
        if viewModel.isRecording {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
        } else if !viewModel.isModelReady {
            button.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "Model loading")
            button.contentTintColor = .systemOrange
        } else {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Push to Talk")
            button.contentTintColor = .labelColor
        }
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

    private func requestMicPermission() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    private func checkAccessibility() {
        if !AXIsProcessTrusted() {
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
```

- [ ] **Step 2: Remove NSSpeechRecognitionUsageDescription from Info.plist**

Update `PushToTalkSTT/Info.plist` — remove the speech recognition key (WhisperKit doesn't need it), keep the microphone key:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>PushToTalkSTT</string>
	<key>CFBundleIdentifier</key>
	<string>com.user.PushToTalkSTT</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>PushToTalkSTT</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>PushToTalkSTT needs microphone access to capture your voice for speech recognition.</string>
</dict>
</plist>
```

- [ ] **Step 3: Delete SpeechRecognizer.swift**

```bash
rm PushToTalkSTT/SpeechRecognizer.swift
```

- [ ] **Step 4: Commit**

```bash
git add PushToTalkSTT/AppDelegate.swift PushToTalkSTT/Info.plist
git rm PushToTalkSTT/SpeechRecognizer.swift
git add PushToTalkSTT/WhisperRecognizer.swift
git commit -m "feat: replace SFSpeechRecognizer with WhisperKit in AppDelegate"
```

---

### Task 6: Build Integration

**Files:**
- Modify: build process

Since the app uses `swiftc` direct compilation (not Xcode), WhisperKit must be resolved and linked. The practical approach: resolve SPM, then compile with the framework path.

- [ ] **Step 1: Create a build script that resolves SPM and compiles**

Create `scripts/build.sh`:

```bash
#!/bin/bash
# scripts/build.sh
# Builds PushToTalkSTT with WhisperKit dependency resolved via SPM.

set -euo pipefail

cd "$(dirname "$0")/.."

SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
DEST="build_out"
APP="$DEST/PushToTalkSTT.app"

echo "==> Resolving SPM packages..."
export DEVELOPER_DIR
swift package resolve 2>/dev/null || true

echo "==> Building with xcodebuild..."
xcodebuild -project PushToTalkSTT.xcodeproj \
    -scheme PushToTalkSTT \
    -configuration Release \
    -derivedDataPath "$DEST/derived" \
    -destination "platform=macOS,arch=arm64" \
    SWIFT_VERSION=6.0 \
    CODE_SIGN_IDENTITY="PushToTalkSTT Dev" \
    build 2>&1 | tail -20

# Find and copy the built app
BUILT_APP=$(find "$DEST/derived" -name "PushToTalkSTT.app" -type d | head -1)
if [ -n "$BUILT_APP" ]; then
    rm -rf "$APP"
    cp -R "$BUILT_APP" "$APP"
    echo "==> App at: $APP"
else
    echo "==> ERROR: Build succeeded but .app not found"
    exit 1
fi
```

Note: With WhisperKit as an SPM dependency, `xcodebuild` is required (not bare `swiftc`) because WhisperKit brings in CoreML model compilation and multiple transitive dependencies. The `project.yml` must be regenerated with `xcodegen` to include the SPM package, or the Xcode project must be updated manually to add the package.

- [ ] **Step 2: Regenerate Xcode project and build**

```bash
# If xcodegen is available:
cd /Users/kaxuna1/Code/VoxCPM/PushToTalkSTT
xcodegen generate

# Then open Xcode to resolve SPM (first time):
# open PushToTalkSTT.xcodeproj
# Or build from command line:
bash scripts/build.sh
```

If `xcodegen` is not installed, open the Xcode project manually, add WhisperKit package via File → Add Package Dependencies → `https://github.com/argmaxinc/WhisperKit.git`, add the Resources folder to the target, then build.

- [ ] **Step 3: Verify the model is bundled in the .app**

```bash
ls build_out/PushToTalkSTT.app/Contents/Resources/openai_whisper-small/
```

Expected: Model files present inside the app bundle.

- [ ] **Step 4: Launch and test**

```bash
open build_out/PushToTalkSTT.app
```

Expected:
1. Menu bar icon appears as orange mic (loading)
2. After a few seconds, icon turns to normal mic (model loaded)
3. Click the icon — popover shows green dot with "Ready"
4. Press Right Option, speak, release — text is pasted into the focused app
5. Popover shows last transcription

- [ ] **Step 5: Commit**

```bash
git add scripts/build.sh
git commit -m "feat: add build script with WhisperKit SPM integration"
```

---

## Summary of Changes

| Before | After |
|--------|-------|
| Apple SFSpeechRecognizer | WhisperKit `openai_whisper-small` (multilingual) |
| Streaming recognition (partial results during recording) | Batch transcription (full audio after key release) |
| Speech Recognition permission required | No speech permission needed (only microphone) |
| Model managed by macOS | Model bundled in .app (~460MB) |
| English-biased (locale-dependent) | 99+ languages with auto-detection |
| ~1 min recognition limit (with restart workaround) | No time limit |

## Key Decisions

1. **Batch over streaming**: For push-to-talk (2-30 second utterances), batch transcription after the key release is simpler and produces better results than streaming partial results. WhisperKit processes a 30-second clip in ~3 seconds on M1 with the small model.

2. **Auto language detection**: Using `detectLanguage: true` in DecodingOptions lets WhisperKit detect the language automatically. No language picker needed.

3. **Audio resampling**: WhisperKit expects 16kHz mono audio. The `transcribe(audioArray:)` method handles resampling internally from whatever sample rate the input provides.

4. **Model bundling**: The ~460MB model is bundled in Resources/ rather than downloaded at runtime. This makes the app self-contained but large. A future enhancement could offer model size options (tiny=75MB for faster/smaller, large-v3=3GB for maximum accuracy).
