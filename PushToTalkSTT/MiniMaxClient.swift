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

            if let toolCalls = choice.message.tool_calls, let firstCall = toolCalls.first {
                let argsData = firstCall.function.arguments.data(using: .utf8) ?? Data()
                let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                let stringArgs = args.mapValues { "\($0)" }
                return .toolCall(name: firstCall.function.name, arguments: stringArgs)
            }

            if let content = choice.message.content, !content.isEmpty {
                return .textResponse(content)
            }

            return .error("Empty response from MiniMax")
        } catch {
            return .error("MiniMax request failed: \(error.localizedDescription)")
        }
    }

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
