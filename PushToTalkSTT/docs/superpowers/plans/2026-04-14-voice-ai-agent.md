# Voice AI Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a trigger-word-activated AI agent that sends voice commands to MiniMax M2.7 Highspeed with 10 macOS tools, executing actions like opening apps, searching Google, controlling music, and running shell commands.

**Architecture:** When transcribed text starts with the trigger word (default "Hey"), `AgentManager` strips the trigger, sends the command to MiniMax via `MiniMaxClient` (OpenAI-compatible API) with 10 tool definitions, parses the `tool_calls` response, and dispatches to the matching handler in `AgentTools`. If no trigger word or agent is disabled, existing text injection flow runs unchanged.

**Tech Stack:** MiniMax M2.7 Highspeed API (OpenAI-compatible), URLSession, NSWorkspace, NSAppleScript, Process, Swift 6.0, macOS 14+

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `PushToTalkSTT/MiniMaxClient.swift` | HTTP client for MiniMax chat completions with tool calling |
| Create | `PushToTalkSTT/AgentTools.swift` | 10 tool definitions (JSON schemas + handler closures) |
| Create | `PushToTalkSTT/AgentManager.swift` | Trigger word detection, orchestration, MiniMax → tool dispatch |
| Modify | `PushToTalkSTT/AppDelegate.swift` | Route transcription through AgentManager |
| Modify | `PushToTalkSTT/SettingsView.swift` | Add AI Agent settings tab |

---

### Task 1: Create MiniMaxClient

**Files:**
- Create: `PushToTalkSTT/MiniMaxClient.swift`

- [ ] **Step 1: Create MiniMaxClient.swift**

```swift
import Foundation

struct MiniMaxClient {
    static let shared = MiniMaxClient()

    var apiKey: String {
        UserDefaults.standard.string(forKey: "minimaxApiKey") ?? ""
    }

    var model: String {
        UserDefaults.standard.string(forKey: "minimaxModel") ?? "MiniMax-M2.7-highspeed"
    }

    var endpoint: String {
        "https://api.minimax.chat/v1/chat/completions"
    }

    // MARK: - Request/Response Types

    struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let tools: [[String: Any]]?
        let tool_choice: String?

        struct Message: Encodable {
            let role: String
            let content: String
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encodeIfPresent(tool_choice, forKey: .tool_choice)
            // tools is [[String: Any]] which isn't Encodable, handled in buildRequestBody()
        }

        enum CodingKeys: String, CodingKey {
            case model, messages, tools, tool_choice
        }
    }

    struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let finish_reason: String?
            let message: ResponseMessage
        }

        struct ResponseMessage: Decodable {
            let content: String?
            let tool_calls: [ToolCall]?
        }

        struct ToolCall: Decodable {
            let id: String?
            let type: String?
            let function: FunctionCall
        }

        struct FunctionCall: Decodable {
            let name: String
            let arguments: String
        }
    }

    enum AgentAction {
        case toolCall(name: String, arguments: [String: String])
        case textResponse(String)
        case error(String)
    }

    // MARK: - API Call

    func chat(userMessage: String, tools: [[String: Any]]) async -> AgentAction {
        guard !apiKey.isEmpty else {
            return .error("MiniMax API key not set. Configure in Settings.")
        }

        let systemPrompt = """
        You are a voice assistant running on macOS. The user speaks commands and you decide which tool to call.

        Rules:
        - Pick the most appropriate tool for the user's request
        - If the user wants text typed/written, use the type_text tool
        - If unsure, use type_text with the original text
        - Only call one tool per request
        - Keep tool arguments concise and accurate
        """

        // Build JSON body manually since tools contains [String: Any]
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "tools": tools,
            "tool_choice": "auto"
        ]

        guard let url = URL(string: endpoint),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return .error("Failed to build request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .error("MiniMax API error (HTTP \(statusCode))")
            }

            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)

            guard let choice = decoded.choices.first else {
                return .error("No response from MiniMax")
            }

            // Check for tool calls
            if let toolCalls = choice.message.tool_calls, let firstCall = toolCalls.first {
                let argsData = firstCall.function.arguments.data(using: .utf8) ?? Data()
                let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                let stringArgs = args.mapValues { "\($0)" }
                return .toolCall(name: firstCall.function.name, arguments: stringArgs)
            }

            // Plain text response
            if let content = choice.message.content, !content.isEmpty {
                return .textResponse(content)
            }

            return .error("Empty response from MiniMax")
        } catch {
            return .error("MiniMax request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Connection Test

    func testConnection() async -> (success: Bool, message: String) {
        guard !apiKey.isEmpty else {
            return (false, "No API key configured")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "Hello"]]
        ]

        guard let url = URL(string: endpoint),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return (false, "Failed to build request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                return (true, "Connected to MiniMax (\(model))")
            } else {
                return (false, "HTTP \(code) — check API key")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushToTalkSTT/MiniMaxClient.swift
git commit -m "feat: add MiniMaxClient for OpenAI-compatible tool calling"
```

---

### Task 2: Create AgentTools

**Files:**
- Create: `PushToTalkSTT/AgentTools.swift`

- [ ] **Step 1: Create AgentTools.swift**

```swift
import AppKit
import Foundation

struct ToolResult {
    let success: Bool
    let message: String
}

struct AgentTools {

    // MARK: - Tool Definitions for MiniMax API

    static let definitions: [[String: Any]] = [
        makeTool(name: "open_application",
                 description: "Open a macOS application by name",
                 properties: ["name": ["type": "string", "description": "Application name, e.g. 'Google Chrome', 'Terminal', 'Finder'"]],
                 required: ["name"]),

        makeTool(name: "open_url",
                 description: "Open a URL in the default web browser",
                 properties: ["url": ["type": "string", "description": "Full URL to open, e.g. 'https://example.com'"]],
                 required: ["url"]),

        makeTool(name: "search_google",
                 description: "Search Google for a query",
                 properties: ["query": ["type": "string", "description": "Search query"]],
                 required: ["query"]),

        makeTool(name: "run_shell_command",
                 description: "Run a shell command in zsh terminal",
                 properties: ["command": ["type": "string", "description": "Shell command to execute"]],
                 required: ["command"]),

        makeTool(name: "toggle_music",
                 description: "Play or pause Apple Music",
                 properties: [:],
                 required: []),

        makeTool(name: "set_volume",
                 description: "Set the system volume level",
                 properties: ["level": ["type": "integer", "description": "Volume level from 0 to 100"]],
                 required: ["level"]),

        makeTool(name: "toggle_dark_mode",
                 description: "Toggle macOS dark mode on or off",
                 properties: [:],
                 required: []),

        makeTool(name: "create_file",
                 description: "Create a new file with content",
                 properties: [
                    "path": ["type": "string", "description": "File path, e.g. '~/Desktop/note.txt'"],
                    "content": ["type": "string", "description": "File content"]
                 ],
                 required: ["path", "content"]),

        makeTool(name: "read_clipboard",
                 description: "Read the current clipboard text and type it",
                 properties: [:],
                 required: []),

        makeTool(name: "type_text",
                 description: "Type text into the currently active application",
                 properties: ["text": ["type": "string", "description": "Text to type"]],
                 required: ["text"]),
    ]

    // MARK: - Tool Execution

    static func execute(name: String, arguments: [String: String]) async -> ToolResult {
        switch name {
        case "open_application":
            return await openApplication(arguments["name"] ?? "")
        case "open_url":
            return openURL(arguments["url"] ?? "")
        case "search_google":
            return searchGoogle(arguments["query"] ?? "")
        case "run_shell_command":
            return runShellCommand(arguments["command"] ?? "")
        case "toggle_music":
            return runAppleScript("tell application \"Music\" to playpause", successMessage: "Music toggled")
        case "set_volume":
            let level = Int(arguments["level"] ?? "50") ?? 50
            return runAppleScript("set volume output volume \(max(0, min(100, level)))", successMessage: "Volume set to \(level)%")
        case "toggle_dark_mode":
            return runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
                successMessage: "Dark mode toggled"
            )
        case "create_file":
            return createFile(path: arguments["path"] ?? "", content: arguments["content"] ?? "")
        case "read_clipboard":
            return readClipboard()
        case "type_text":
            let text = arguments["text"] ?? ""
            TextInjector.inject(text)
            return ToolResult(success: true, message: "Typed: \(String(text.prefix(50)))")
        default:
            return ToolResult(success: false, message: "Unknown tool: \(name)")
        }
    }

    // MARK: - Tool Implementations

    private static func openApplication(_ name: String) async -> ToolResult {
        let workspace = NSWorkspace.shared
        let appURL = workspace.urlForApplication(withBundleIdentifier: name)
            ?? NSWorkspace.shared.urlsForApplications(withBundleIdentifier: name).first

        // Try by name in /Applications
        let appPaths = [
            "/Applications/\(name).app",
            "/Applications/\(name)",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app"
        ]

        for path in appPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    return ToolResult(success: true, message: "Opened \(name)")
                } catch {
                    continue
                }
            }
        }

        // Try using open command as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return ToolResult(success: true, message: "Opened \(name)")
            }
        } catch {}

        return ToolResult(success: false, message: "Could not find app: \(name)")
    }

    private static func openURL(_ urlString: String) -> ToolResult {
        var normalized = urlString
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        guard let url = URL(string: normalized) else {
            return ToolResult(success: false, message: "Invalid URL: \(urlString)")
        }
        NSWorkspace.shared.open(url)
        return ToolResult(success: true, message: "Opened \(normalized)")
    }

    private static func searchGoogle(_ query: String) -> ToolResult {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            return ToolResult(success: false, message: "Invalid query")
        }
        NSWorkspace.shared.open(url)
        return ToolResult(success: true, message: "Searched: \(query)")
    }

    private static func runShellCommand(_ command: String) -> ToolResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let preview = String(output.prefix(100))
            return ToolResult(success: process.terminationStatus == 0,
                              message: process.terminationStatus == 0 ? "Done: \(preview)" : "Error: \(preview)")
        } catch {
            return ToolResult(success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private static func runAppleScript(_ source: String, successMessage: String) -> ToolResult {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let error = error {
            return ToolResult(success: false, message: "AppleScript error: \(error)")
        }
        return ToolResult(success: true, message: successMessage)
    }

    private static func createFile(path: String, content: String) -> ToolResult {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ToolResult(success: true, message: "Created \(path)")
        } catch {
            return ToolResult(success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private static func readClipboard() -> ToolResult {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return ToolResult(success: false, message: "Clipboard is empty")
        }
        TextInjector.inject(text)
        return ToolResult(success: true, message: "Pasted clipboard: \(String(text.prefix(50)))")
    }

    // MARK: - Helper

    private static func makeTool(name: String, description: String,
                                  properties: [String: [String: String]],
                                  required: [String]) -> [String: Any] {
        var params: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty {
            params["required"] = required
        }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": params
            ] as [String: Any]
        ]
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushToTalkSTT/AgentTools.swift
git commit -m "feat: add 10 macOS tools for voice AI agent"
```

---

### Task 3: Create AgentManager

**Files:**
- Create: `PushToTalkSTT/AgentManager.swift`

- [ ] **Step 1: Create AgentManager.swift**

```swift
import Foundation

struct AgentManager {

    static var isEnabled: Bool {
        // Default to true if key not set
        !UserDefaults.standard.bool(forKey: "agentDisabled")
    }

    static var triggerWord: String {
        let word = UserDefaults.standard.string(forKey: "agentTriggerWord") ?? "Hey"
        return word.isEmpty ? "Hey" : word
    }

    /// Check if text starts with the trigger word
    static func hasTrigger(_ text: String) -> Bool {
        guard isEnabled else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix(triggerWord.lowercased())
    }

    /// Strip trigger word and any trailing punctuation/spaces
    static func stripTrigger(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = triggerWord
        guard trimmed.lowercased().hasPrefix(prefix.lowercased()) else { return trimmed }

        var result = String(trimmed.dropFirst(prefix.count))
        // Strip leading comma, period, space after trigger word
        while result.first == "," || result.first == "." || result.first == " " {
            result = String(result.dropFirst())
        }
        return result
    }

    /// Process a voice command through MiniMax with tool calling
    static func process(_ text: String) async -> ToolResult {
        let command = stripTrigger(text)

        guard !command.isEmpty else {
            return ToolResult(success: false, message: "Empty command after trigger word")
        }

        let action = await MiniMaxClient.shared.chat(
            userMessage: command,
            tools: AgentTools.definitions
        )

        switch action {
        case .toolCall(let name, let arguments):
            print("AgentManager: tool_call → \(name)(\(arguments))")
            return await AgentTools.execute(name: name, arguments: arguments)

        case .textResponse(let text):
            print("AgentManager: text response → \(text)")
            TextInjector.inject(text)
            return ToolResult(success: true, message: "Typed: \(String(text.prefix(50)))")

        case .error(let message):
            print("AgentManager: error → \(message)")
            return ToolResult(success: false, message: message)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushToTalkSTT/AgentManager.swift
git commit -m "feat: add AgentManager for trigger detection and tool dispatch"
```

---

### Task 4: Wire AgentManager into AppDelegate

**Files:**
- Modify: `PushToTalkSTT/AppDelegate.swift`

- [ ] **Step 1: Update stopRecording to route through AgentManager**

Read `PushToTalkSTT/AppDelegate.swift`. Find the `stopRecording` method. Inside the `if let result = result {` block, BEFORE the existing command mode check (line ~261-273), add the agent check:

```swift
                // AI Agent: check for trigger word
                if AgentManager.hasTrigger(result.text) {
                    let entry = TranscriptionEntry(text: result.text, language: result.language, duration: result.duration)
                    self.transcriptionStore.add(entry)
                    self.overlayController?.showProcessing()

                    Task {
                        let toolResult = await AgentManager.process(result.text)
                        await MainActor.run {
                            self.overlayController?.hide()
                            self.viewModel.lastTranscription = result.text
                            if toolResult.success {
                                self.showNotification(title: "Agent", body: toolResult.message)
                            } else {
                                // Fallback: type the raw text
                                TextInjector.inject(result.text)
                                self.showNotification(title: "Agent Error", body: toolResult.message)
                            }
                        }
                    }
                    return
                }
```

This goes right after `if let result = result {` and before the `if DictationMode.current == .command {` block.

- [ ] **Step 2: Commit**

```bash
git add PushToTalkSTT/AppDelegate.swift
git commit -m "feat: route trigger-word transcriptions through AI agent"
```

---

### Task 5: Add AI Agent Tab to Settings

**Files:**
- Modify: `PushToTalkSTT/SettingsView.swift`

- [ ] **Step 1: Add state variables**

At the top of `SettingsView` struct, alongside existing `@State` properties, add:

```swift
    @State private var agentEnabled = !UserDefaults.standard.bool(forKey: "agentDisabled")
    @State private var triggerWord = UserDefaults.standard.string(forKey: "agentTriggerWord") ?? "Hey"
    @State private var minimaxApiKey = UserDefaults.standard.string(forKey: "minimaxApiKey") ?? ""
    @State private var minimaxModel = UserDefaults.standard.string(forKey: "minimaxModel") ?? "MiniMax-M2.7-highspeed"
    @State private var connectionStatus = ""
    @State private var isTestingConnection = false
```

- [ ] **Step 2: Add the agent tab in the TabView**

Find the `TabView { ... }` block. Add after the general settings tab:

```swift
            agentSettingsTab
                .tabItem {
                    Label("AI Agent", systemImage: "wand.and.stars")
                }
```

Also increase the frame height from 420 to 480:
```swift
        .frame(width: 500, height: 480)
```

- [ ] **Step 3: Add the agentSettingsTab computed property**

Add this alongside the other tab properties (`aiSettingsTab`, `generalSettingsTab`):

```swift
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
```

- [ ] **Step 4: Commit**

```bash
git add PushToTalkSTT/SettingsView.swift
git commit -m "feat: add AI Agent settings tab with trigger word and MiniMax config"
```

---

### Task 6: Build, Test, and Verify

**Files:** None (verification only)

- [ ] **Step 1: Build**

```bash
cd /Users/kaxuna1/Code/VoxCPM/PushToTalkSTT
swift build -c release 2>&1 | tail -10
```

Expected: `Build complete!`

- [ ] **Step 2: Package and launch**

```bash
pkill -f "PushToTalkSTT" 2>/dev/null; sleep 1
cp .build/arm64-apple-macosx/release/PushToTalkSTT build_out/PushToTalkSTT.app/Contents/MacOS/PushToTalkSTT
codesign --force --sign "PushToTalkSTT Dev" --entitlements PushToTalkSTT/PushToTalkSTT.entitlements build_out/PushToTalkSTT.app
open build_out/PushToTalkSTT.app
```

- [ ] **Step 3: Verify**

1. Right-click → Settings → AI Agent tab visible
2. Enter MiniMax API key, click Test Connection → "Connected"
3. Set trigger word to "Hey"
4. Press Right Option, say "Hey, open Google Chrome", release
5. Chrome should open, notification shows "Opened Google Chrome"
6. Press Right Option, say "Hey, search Google for Swift programming", release
7. Browser opens Google search results
8. Press Right Option, say "Hello world" (no trigger), release
9. "Hello world" is typed as text (normal behavior)
10. Toggle agent off in Settings → trigger word ignored, text always typed

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: voice AI agent with MiniMax M2.7 tool calling — 10 macOS tools"
```
