import SwiftUI

@MainActor
class ViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var lastTranscription: String?
}
