import SwiftUI

struct SettingsView: View {
    @State private var processingMode: ProcessingMode = PostProcessor.shared.mode
    @State private var ollamaEndpoint: String = PostProcessor.shared.ollamaEndpoint
    @State private var ollamaModel: String = PostProcessor.shared.ollamaModel
    @State private var availableModels: [String] = []
    @State private var ollamaStatus: String = "Checking..."
    @State private var isOllamaAvailable = false
    @State private var soundEnabled = SoundManager.isEnabled
    @State private var selectedLanguage: String = UserDefaults.standard.string(forKey: "languageLock") ?? "auto"

    var body: some View {
        TabView {
            aiSettingsTab
                .tabItem {
                    Label("AI Processing", systemImage: "brain")
                }

            generalSettingsTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .padding(20)
        .frame(width: 500, height: 420)
        .onAppear {
            checkOllama()
        }
    }

    // MARK: - AI Processing Tab

    private var aiSettingsTab: some View {
        Form {
            Section("Post-Processing Mode") {
                Picker("Mode", selection: $processingMode) {
                    ForEach(ProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: processingMode) { _, newValue in
                    PostProcessor.shared.mode = newValue
                }

                if processingMode != .off {
                    Text("Transcribed text will be processed by a local LLM before injection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Ollama Configuration") {
                HStack {
                    TextField("Endpoint", text: $ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: ollamaEndpoint) { _, newValue in
                            PostProcessor.shared.ollamaEndpoint = newValue
                        }
                    Button("Test") {
                        checkOllama()
                    }
                }

                HStack {
                    Text("Status:")
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(isOllamaAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(ollamaStatus)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                if isOllamaAvailable && !availableModels.isEmpty {
                    Picker("Model", selection: $ollamaModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onChange(of: ollamaModel) { _, newValue in
                        PostProcessor.shared.ollamaModel = newValue
                    }
                } else {
                    HStack {
                        Text("Model:")
                            .foregroundColor(.secondary)
                        TextField("Model name", text: $ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: ollamaModel) { _, newValue in
                                PostProcessor.shared.ollamaModel = newValue
                            }
                    }
                }

                if !isOllamaAvailable {
                    Text("Install Ollama from ollama.com and run a model to enable AI processing.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - General Tab

    private var generalSettingsTab: some View {
        Form {
            Section("Sound") {
                Toggle("Play sounds on recording start/stop", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { _, newValue in
                        SoundManager.isEnabled = newValue
                    }
            }

            Section("Language") {
                Picker("Transcription Language", selection: $selectedLanguage) {
                    ForEach(LanguageManager.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    LanguageManager.lockedLanguage = newValue == "auto" ? nil : newValue
                }

                if selectedLanguage != "auto" {
                    Text("Language is locked to \(LanguageManager.currentDisplayName). Auto-detection is disabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Language is auto-detected. For better accuracy with Georgian or other low-resource languages, lock to a specific language.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("About") {
                HStack {
                    Text("PushToTalkSTT")
                        .font(.headline)
                    Spacer()
                    Text("v1.0")
                        .foregroundColor(.secondary)
                }
                Text("Push-to-talk speech recognition powered by WhisperKit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func checkOllama() {
        ollamaStatus = "Checking..."
        Task {
            let available = await OllamaClient.shared.isAvailable(endpoint: ollamaEndpoint)
            await MainActor.run {
                isOllamaAvailable = available
                if available {
                    ollamaStatus = "Connected"
                    fetchModels()
                } else {
                    ollamaStatus = "Not available"
                    availableModels = []
                }
            }
        }
    }

    private func fetchModels() {
        Task {
            do {
                let models = try await OllamaClient.shared.listModels(endpoint: ollamaEndpoint)
                await MainActor.run {
                    availableModels = models
                    if !models.contains(ollamaModel) && !models.isEmpty {
                        ollamaModel = models.first!
                        PostProcessor.shared.ollamaModel = ollamaModel
                    }
                }
            } catch {
                print("Failed to fetch models: \(error)")
            }
        }
    }
}
