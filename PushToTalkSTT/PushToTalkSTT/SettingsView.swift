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
    @State private var agentEnabled = !UserDefaults.standard.bool(forKey: "agentDisabled")
    @State private var triggerWord = UserDefaults.standard.string(forKey: "agentTriggerWord") ?? "Hey"
    @State private var minimaxApiKey = UserDefaults.standard.string(forKey: "minimaxApiKey") ?? ""
    @State private var minimaxModel = UserDefaults.standard.string(forKey: "minimaxModel") ?? "MiniMax-M2.7-highspeed"
    @State private var connectionStatus = ""
    @State private var isTestingConnection = false

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

            agentSettingsTab
                .tabItem {
                    Label("AI Agent", systemImage: "wand.and.stars")
                }
        }
        .padding(20)
        .frame(width: 500, height: 480)
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

    // MARK: - AI Agent Tab

    private var agentSettingsTab: some View {
        Form {
            Section("Voice Agent") {
                Toggle("Enable AI Agent", isOn: $agentEnabled)
                    .onChange(of: agentEnabled) { _, newValue in
                        UserDefaults.standard.set(!newValue, forKey: "agentDisabled")
                    }

                if agentEnabled {
                    HStack {
                        Text("Trigger Word:")
                        TextField("Hey", text: $triggerWord)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                            .onChange(of: triggerWord) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "agentTriggerWord")
                            }
                    }
                    Text("Say \"\(triggerWord.isEmpty ? "Hey" : triggerWord), <command>\" to activate the agent.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("MiniMax API") {
                SecureField("API Key", text: $minimaxApiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: minimaxApiKey) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "minimaxApiKey")
                    }

                HStack {
                    Text("Model:")
                    TextField("MiniMax-M2.7-highspeed", text: $minimaxModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: minimaxModel) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "minimaxModel")
                        }
                }

                HStack {
                    Button("Test Connection") {
                        testMiniMaxConnection()
                    }
                    .disabled(minimaxApiKey.isEmpty || isTestingConnection)

                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !connectionStatus.isEmpty {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green : .red)
                    }
                }
            }

            Section("Available Tools") {
                VStack(alignment: .leading, spacing: 4) {
                    toolRow("open_application", "Open any macOS app")
                    toolRow("open_url", "Open URL in browser")
                    toolRow("search_google", "Google search")
                    toolRow("run_shell_command", "Run terminal command")
                    toolRow("toggle_music", "Play/pause Apple Music")
                    toolRow("set_volume", "Set system volume")
                    toolRow("toggle_dark_mode", "Toggle dark/light mode")
                    toolRow("create_file", "Create a file")
                    toolRow("read_clipboard", "Read & type clipboard")
                    toolRow("type_text", "Type text (fallback)")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func toolRow(_ name: String, _ desc: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.accentColor)
            Text("— \(desc)")
                .foregroundColor(.secondary)
        }
    }

    private func testMiniMaxConnection() {
        isTestingConnection = true
        connectionStatus = ""
        Task {
            let result = await MiniMaxClient.shared.testConnection()
            await MainActor.run {
                connectionStatus = result.message
                isTestingConnection = false
            }
        }
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
