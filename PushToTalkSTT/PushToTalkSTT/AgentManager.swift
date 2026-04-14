import Foundation

struct AgentManager {

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
        return trimmed.lowercased().hasPrefix(triggerWord.lowercased())
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