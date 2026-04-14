import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
