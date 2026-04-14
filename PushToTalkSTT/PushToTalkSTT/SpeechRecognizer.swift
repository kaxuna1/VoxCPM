import Speech
import AVFoundation
import Accelerate

class SpeechRecognizer: NSObject {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let resultLock = NSLock()
    private var _latestResult: String?
    private var stopCompletion: ((String?) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private var latestResult: String? {
        get { resultLock.withLock { _latestResult } }
        set { resultLock.withLock { _latestResult = newValue } }
    }

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        speechRecognizer?.delegate = self
    }

    static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    func startRecording(completion: ((Error?) -> Void)? = nil) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            completion?(NSError(
                domain: "PushToTalkSTT",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available."]
            ))
            return
        }

        stopAudioSession()
        latestResult = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            completion?(NSError(
                domain: "PushToTalkSTT",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request."]
            ))
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.latestResult = result.bestTranscription.formattedString
                if result.isFinal {
                    self.deliverStopCompletion()
                }
            }
            if let error = error {
                let nsError = error as NSError
                // Code 216 = no speech detected, not a real error
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    self.deliverStopCompletion()
                    return
                }
                self.deliverStopCompletion()
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
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

    func stopRecording(completion: @escaping (String?) -> Void) {
        guard audioEngine.isRunning else {
            completion(nil)
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(0.0)
        }

        stopCompletion = completion

        // Use finish() to request final transcription delivery instead of cancel()
        recognitionTask?.finish()

        // Safety timeout in case final result never arrives
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.deliverStopCompletion()
        }
    }

    private func deliverStopCompletion() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let completion = self.stopCompletion else { return }
            self.stopCompletion = nil
            let result = self.latestResult
            self.latestResult = nil
            self.recognitionTask = nil
            self.recognitionRequest = nil
            completion(result)
        }
    }

    private func stopAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        stopCompletion = nil
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
}

extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        // no-op
    }
}
