import AVFoundation
import Accelerate
import FluidAudio

struct RecognitionResult {
    let text: String
    let language: String
    let duration: Double
}

enum WhisperModelState: String {
    case unloaded = "Not loaded"
    case loading = "Loading model..."
    case loaded = "Ready"
    case error = "Model error"
}

class WhisperRecognizer {

    // MARK: - Debug

    private static func dbg(_ msg: String) {
        let logFile = "/tmp/ptt_debug.log"
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data)
            }
        }
    }

    // MARK: - Public

    var onAudioLevel: ((Float) -> Void)?
    var onPartialResult: ((String) -> Void)?
    var onModelStateChanged: ((WhisperModelState) -> Void)?

    private(set) var modelState: WhisperModelState = .unloaded {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onModelStateChanged?(self.modelState)
            }
        }
    }

    // MARK: - Private

    private var asrManager: AsrManager?
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var streamingTimer: Timer?

    // MARK: - Model Loading

    func loadModel() async {
        modelState = .loading

        // Use v2 (English-only) when language is English/auto to avoid
        // Parakeet v3 misdetecting English as Russian.
        // Use v3 (multilingual) only when a non-English language is explicitly locked.
        let lockedLang = LanguageManager.lockedLanguage
        let useV3 = lockedLang != nil && lockedLang != "en"
        let version: AsrModelVersion = useV3 ? .v3 : .v2

        Self.dbg("loadModel() — downloading Parakeet TDT \(useV3 ? "v3 (multilingual)" : "v2 (English)")...")

        do {
            let models = try await AsrModels.downloadAndLoad(version: version)
            Self.dbg("Models downloaded, initializing AsrManager...")
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            Self.dbg("Parakeet TDT \(useV3 ? "v3" : "v2") loaded successfully!")
            modelState = .loaded
        } catch {
            Self.dbg("Model load FAILED: \(error)")
            modelState = .error
        }
    }

    // MARK: - Recording

    func startRecording(completion: ((Error?) -> Void)? = nil) {
        Self.dbg("startRecording(), asrManager=\(asrManager != nil)")

        guard asrManager != nil else {
            completion?(NSError(
                domain: "PushToTalkSTT", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Parakeet model not loaded."]
            ))
            return
        }

        stopAudioSession()
        bufferLock.withLock { audioBuffer.removeAll() }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        Self.dbg("Hardware: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.appendAudio(buffer: buffer)
            self.processAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Self.dbg("Audio engine started")

            DispatchQueue.main.async { [weak self] in
                self?.streamingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    self?.transcribePartial()
                }
            }

            completion?(nil)
        } catch {
            Self.dbg("Audio engine FAILED: \(error)")
            completion?(error)
        }
    }

    func stopRecording(completion: @escaping (RecognitionResult?) -> Void) {
        Self.dbg("stopRecording(), isRunning=\(audioEngine.isRunning)")

        guard audioEngine.isRunning else {
            completion(nil)
            return
        }

        streamingTimer?.invalidate()
        streamingTimer = nil

        let inputSampleRate = audioEngine.inputNode.outputFormat(forBus: 0).sampleRate

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(0.0)
        }

        let samples: [Float] = bufferLock.withLock {
            let copy = audioBuffer
            audioBuffer.removeAll()
            return copy
        }

        let duration = samples.isEmpty ? 0 : Double(samples.count) / inputSampleRate
        Self.dbg("Captured \(samples.count) samples (\(String(format: "%.1f", duration))s)")

        guard !samples.isEmpty, let asr = asrManager else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let resampled = Self.resampleTo16k(samples, fromRate: inputSampleRate)
        Self.dbg("Resampled to \(resampled.count) samples, starting Parakeet transcription...")

        Task {
            do {
                let result = try await asr.transcribe(resampled, source: .microphone)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.dbg("Parakeet: \"\(text)\" (confidence=\(result.confidence), RTFx=\(result.rtfx))")

                if text.isEmpty {
                    DispatchQueue.main.async { completion(nil) }
                } else {
                    let rec = RecognitionResult(text: text, language: "auto", duration: duration)
                    DispatchQueue.main.async { completion(rec) }
                }
            } catch {
                Self.dbg("Transcription FAILED: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Streaming

    private func transcribePartial() {
        guard let asr = asrManager, audioEngine.isRunning else { return }
        let inputSampleRate = audioEngine.inputNode.outputFormat(forBus: 0).sampleRate
        let samples: [Float] = bufferLock.withLock { Array(audioBuffer) }
        guard samples.count > Int(inputSampleRate) else { return }

        Task {
            do {
                let resampled = Self.resampleTo16k(samples, fromRate: inputSampleRate)
                let result = try await asr.transcribe(resampled, source: .microphone)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    DispatchQueue.main.async { [weak self] in
                        self?.onPartialResult?(text)
                    }
                }
            } catch { /* partial failure is non-critical */ }
        }
    }

    // MARK: - Helpers

    private static func resampleTo16k(_ samples: [Float], fromRate: Double) -> [Float] {
        let targetRate = 16000.0
        guard abs(fromRate - targetRate) > 1.0 else { return samples }

        let ratio = targetRate / fromRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcFloor = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcFloor))
            let s0 = samples[min(srcFloor, samples.count - 1)]
            let s1 = samples[min(srcFloor + 1, samples.count - 1)]
            output[i] = s0 + frac * (s1 - s0)
        }
        return output
    }

    private func appendAudio(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
        bufferLock.withLock { audioBuffer.append(contentsOf: samples) }
    }

    private func processAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
        let level = min(max((rms - 0.01) * 15.0, 0.0), 1.0)
        DispatchQueue.main.async { [weak self] in self?.onAudioLevel?(level) }
    }

    private func stopAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        streamingTimer?.invalidate()
        streamingTimer = nil
    }
}
