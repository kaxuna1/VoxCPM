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

        guard let modelPath = Bundle.main.resourcePath.map({ $0 + "/openai_whisper-small" }),
              FileManager.default.fileExists(atPath: modelPath) else {
            print("WhisperRecognizer: model not found in bundle")
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
                download: false
            )
            whisperKit = try await WhisperKit(config)
            print("WhisperRecognizer: model loaded successfully")
            modelState = .loaded
        } catch {
            print("WhisperRecognizer: model load failed – \(error)")
            modelState = .error
        }
    }

    // MARK: - Recording

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
        bufferLock.withLock { audioBuffer.removeAll() }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.appendAudio(buffer: buffer)
            self.processAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("WhisperRecognizer: recording at \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount)ch")
            completion?(nil)
        } catch {
            completion?(error)
        }
    }

    func stopRecording(completion: @escaping (String?) -> Void) {
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

        guard !samples.isEmpty, let whisperKit = whisperKit else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let duration = Double(samples.count) / inputSampleRate
        print("WhisperRecognizer: captured \(samples.count) samples (\(String(format: "%.1f", duration))s) at \(inputSampleRate)Hz")

        Task {
            do {
                // Resample to 16kHz mono — WhisperKit expects this format.
                // Raw float arrays don't carry sample rate metadata.
                let targetRate = 16000.0
                let resampledSamples: [Float]
                if abs(inputSampleRate - targetRate) < 1.0 {
                    resampledSamples = samples
                } else {
                    resampledSamples = Self.resample(samples, fromRate: inputSampleRate, toRate: targetRate)
                    print("WhisperRecognizer: resampled to \(resampledSamples.count) samples at 16kHz")
                }

                let options = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    detectLanguage: true
                )

                let results = try await whisperKit.transcribe(
                    audioArray: resampledSamples,
                    decodeOptions: options
                )

                let rawText = results.map { $0.text }.joined(separator: " ")
                print("WhisperRecognizer: raw = \"\(rawText)\"")

                let text = Self.cleanTranscription(rawText)
                print("WhisperRecognizer: clean = \"\(text)\"")

                let finalText = text.isEmpty ? nil : text
                DispatchQueue.main.async { completion(finalText) }
            } catch {
                print("WhisperRecognizer: transcription failed – \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Private Helpers

    /// Resample audio from one sample rate to another using linear interpolation
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

    /// Strip Whisper special tokens and non-speech annotations
    private static func cleanTranscription(_ text: String) -> String {
        var cleaned = text

        // Remove special tokens: <|startoftranscript|>, <|en|>, <|transcribe|>, <|0.00|>, etc.
        cleaned = cleaned.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )

        // Remove non-speech annotations: [music], [laughter], [sound of...], (music), etc.
        cleaned = cleaned.replacingOccurrences(
            of: "\\[.*?\\]|\\(.*?\\)",
            with: "",
            options: .regularExpression
        )

        // Collapse multiple spaces and trim
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

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
