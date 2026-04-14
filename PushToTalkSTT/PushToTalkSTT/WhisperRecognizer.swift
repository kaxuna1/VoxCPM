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
            let state = modelState
            DispatchQueue.main.async { [weak self] in
                self?.onModelStateChanged?(state)
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
        do {
            guard let resourcePath = Bundle.main.resourcePath else {
                modelState = .error
                return
            }
            let modelPath = resourcePath + "/openai_whisper-small"

            let computeOptions = ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )

            let config = WhisperKitConfig(
                model: "openai_whisper-small",
                modelFolder: modelPath,
                computeOptions: computeOptions,
                verbose: false,
                logLevel: .error,
                download: false
            )

            whisperKit = try await WhisperKit(config)
            modelState = .loaded
        } catch {
            print("WhisperRecognizer: failed to load model – \(error)")
            modelState = .error
        }
    }

    // MARK: - Recording

    func startRecording(completion: ((Error?) -> Void)? = nil) {
        guard modelState == .loaded else {
            completion?(NSError(
                domain: "WhisperRecognizer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model is not loaded."]
            ))
            return
        }

        stopAudioSession()

        bufferLock.withLock {
            audioBuffer.removeAll()
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.appendAudio(buffer: buffer)
            self.processAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
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

        Task {
            do {
                let options = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    detectLanguage: true
                )

                let results: [TranscriptionResult] = try await whisperKit.transcribe(
                    audioArray: samples,
                    decodeOptions: options
                )

                let text = results
                    .flatMap { $0.segments }
                    .map { $0.text }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let finalText = text.isEmpty ? nil : text
                DispatchQueue.main.async { completion(finalText) }
            } catch {
                print("WhisperRecognizer: transcription failed – \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Private Helpers

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
