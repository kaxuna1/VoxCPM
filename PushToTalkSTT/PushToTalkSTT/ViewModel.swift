import SwiftUI

@MainActor
class ViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var lastTranscription: String?
    @Published var modelStatus: String = "Not loaded"
    @Published var isModelReady = false
}
