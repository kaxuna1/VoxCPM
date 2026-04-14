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
