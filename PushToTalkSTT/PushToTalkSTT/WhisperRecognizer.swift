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

    private var whisperKit: WhisperKit?
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    // MARK: - Model Loading

    func loadModel() async {
        modelState = .loading
        Self.dbg("loadModel() called")

        let modelName = "openai_whisper-large-v3"
        let modelPath = (Bundle.main.resourcePath ?? Bundle.main.bundlePath) + "/" + modelName
        Self.dbg("modelPath = \(modelPath)")
        Self.dbg("exists = \(FileManager.default.fileExists(atPath: modelPath))")

        guard FileManager.default.fileExists(atPath: modelPath) else {
            Self.dbg("ERROR: model not found")
            modelState = .error
            return
        }

        do {
            Self.dbg("Initializing WhisperKit with \(modelName)...")
            let config = WhisperKitConfig(
                model: modelName,
                modelFolder: modelPath,
                computeOptions: ModelComputeOptions(
                    melCompute: .cpuAndNeuralEngine,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine,
                    prefillCompute: .cpuAndNeuralEngine
                ),
                verbose: false,
                logLevel: .error,
                download: false
            )
            whisperKit = try await WhisperKit(config)
            Self.dbg("Model loaded successfully!")
            modelState = .loaded
        } catch {
            Self.dbg("Model load FAILED: \(error)")
            modelState = .error
        }
    }

    // MARK: - Recording

    func startRecording(completion: ((Error?) -> Void)? = nil) {
        Self.dbg("startRecording() called, whisperKit=\(whisperKit != nil)")

        guard whisperKit != nil else {
            completion?(NSError(
                domain: "PushToTalkSTT",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit model not loaded."]
            ))
            return
        }

        stopAudioSession()
        bufferLock.withLock { audioBuffer.removeAll() }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        Self.dbg("Hardware format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.appendAudio(buffer: buffer)
            self.processAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Self.dbg("Audio engine started")
            completion?(nil)
        } catch {
            Self.dbg("Audio engine start FAILED: \(error)")
            completion?(error)
        }
    }

    func stopRecording(completion: @escaping (String?) -> Void) {
        Self.dbg("stopRecording() called, isRunning=\(audioEngine.isRunning)")

        guard audioEngine.isRunning else {
            completion(nil)
            return
        }

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
        Self.dbg("Captured \(samples.count) samples (\(String(format: "%.1f", duration))s) at \(inputSampleRate)Hz")

        guard !samples.isEmpty, let whisperKit = whisperKit else {
            Self.dbg("No samples or no whisperKit — returning nil")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        Task {
            do {
                // Resample to 16kHz mono
                let targetRate = 16000.0
                let resampledSamples: [Float]
                if abs(inputSampleRate - targetRate) < 1.0 {
                    resampledSamples = samples
                } else {
                    resampledSamples = Self.resample(samples, fromRate: inputSampleRate, toRate: targetRate)
                    Self.dbg("Resampled \(samples.count) -> \(resampledSamples.count) samples (16kHz)")
                }

                Self.dbg("Starting transcription with \(resampledSamples.count) samples...")

                let options = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    detectLanguage: true
                )

                let results = try await whisperKit.transcribe(
                    audioArray: resampledSamples,
                    decodeOptions: options
                )

                Self.dbg("Got \(results.count) results")
                for (i, r) in results.enumerated() {
                    Self.dbg("  result[\(i)].text = \"\(r.text)\"")
                    Self.dbg("  result[\(i)].language = \"\(r.language)\"")
                    Self.dbg("  result[\(i)].segments = \(r.segments.count)")
                    for (j, seg) in r.segments.enumerated() {
                        Self.dbg("    seg[\(j)].text = \"\(seg.text)\" noSpeechProb=\(seg.noSpeechProb)")
                    }
                }

                let rawText = results.map { $0.text }.joined(separator: " ")
                Self.dbg("Raw text: \"\(rawText)\"")

                let text = Self.cleanTranscription(rawText)
                Self.dbg("Clean text: \"\(text)\"")

                let finalText = text.isEmpty ? nil : text
                DispatchQueue.main.async { completion(finalText) }
            } catch {
                Self.dbg("Transcription FAILED: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Private Helpers

    private static func resample(_ samples: [Float], fromRate: Double, toRate: Double) -> [Float] {
        let ratio = toRate / fromRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcIndexFloor = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexFloor))

            let sample0 = samples[min(srcIndexFloor, samples.count - 1)]
            let sample1 = samples[min(srcIndexFloor + 1, samples.count - 1)]
            output[i] = sample0 + frac * (sample1 - sample0)
        }

        return output
    }

    private static func cleanTranscription(_ text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[.*?\\]|\\(.*?\\)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    private func appendAudio(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
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
