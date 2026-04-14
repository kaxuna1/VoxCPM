import Foundation

struct AgentManager {

    private static func dbg(_ msg: String) {
        let logFile = "/tmp/ptt_debug.log"
        let line = "\(Date()): [Agent] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data)
            }
        }
    }

    static var isEnabled: Bool {
        !UserDefaults.standard.bool(forKey: "agentDisabled")
    }

    static var triggerWord: String {
        let word = UserDefaults.standard.string(forKey: "agentTriggerWord") ?? "Hey"
        return word.isEmpty ? "Hey" : word
    }

    static func hasTrigger(_ text: String) -> Bool {
        guard isEnabled else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = trimmed.lowercased().hasPrefix(triggerWord.lowercased())
        if matches {
            dbg("Trigger '\(triggerWord)' matched in: \"\(trimmed)\"")
        }
        return matches
    }

    static func stripTrigger(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = triggerWord
        guard trimmed.lowercased().hasPrefix(prefix.lowercased()) else { return trimmed }
        var result = String(trimmed.dropFirst(prefix.count))
        while result.first == "," || result.first == "." || result.first == " " {
            result = String(result.dropFirst())
        }
        return result
    }

    static func process(_ text: String) async -> ToolResult {
        let command = stripTrigger(text)
        dbg("Command after strip: \"\(command)\"")

        guard !command.isEmpty else {
            return ToolResult(success: false, message: "Empty command after trigger word")
        }

        dbg("Sending to MiniMax...")
        let action = await MiniMaxClient.shared.chat(
            userMessage: command,
            tools: AgentTools.definitions
        )

        switch action {
        case .toolCall(let name, let arguments):
            dbg("MiniMax → tool_call: \(name)(\(arguments))")
            let result = await AgentTools.execute(name: name, arguments: arguments)
            dbg("Tool result: success=\(result.success) message=\"\(result.message)\"")
            return result
        case .textResponse(let text):
            dbg("MiniMax → text: \"\(text)\"")
            TextInjector.inject(text)
            return ToolResult(success: true, message: "Typed: \(String(text.prefix(50)))")
        case .error(let message):
            dbg("MiniMax → ERROR: \(message)")
            return ToolResult(success: false, message: message)
        }
    }
}
