import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(viewModel.isModelReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.modelStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !viewModel.isModelReady {
                Text("Press Right Option to record once model is loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .foregroundColor(viewModel.isRecording ? .red : .primary)
                Text(viewModel.isRecording ? "Listening..." : "Idle")
                    .font(.headline)
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
