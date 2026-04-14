import Foundation

struct OllamaClient {
    static let shared = OllamaClient()

    // MARK: - Models

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let options: Options?

        struct Options: Codable {
            let temperature: Double?
            let num_predict: Int?  // Max tokens to generate
        }
    }

    struct ChatResponse: Codable {
        let message: ChatMessage
        let done: Bool
    }

    struct GenerateRequest: Codable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    struct GenerateResponse: Codable {
        let response: String
        let done: Bool
    }

    struct OllamaModel: Codable {
        let name: String
    }

    struct OllamaModelsResponse: Codable {
        let models: [OllamaModel]
    }

    // MARK: - Chat API (preferred — faster, supports system prompts)

    func chat(system: String, user: String, model: String, endpoint: String,
              temperature: Double = 0.1, maxTokens: Int = 256) async throws -> String {
        let url = URL(string: "\(endpoint)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            stream: false,
            options: ChatRequest.Options(temperature: temperature, num_predict: maxTokens)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.message.content
    }

    // MARK: - Generate API (legacy fallback)

    func generate(prompt: String, model: String, endpoint: String) async throws -> String {
        let url = URL(string: "\(endpoint)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = GenerateRequest(model: model, prompt: prompt, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return decoded.response
    }

    // MARK: - Models List

    func listModels(endpoint: String) async throws -> [String] {
        let url = URL(string: "\(endpoint)/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let decoded = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return decoded.models.map(\.name).sorted()
    }

    func isAvailable(endpoint: String) async -> Bool {
        do {
            let _ = try await listModels(endpoint: endpoint)
            return true
        } catch {
            return false
        }
    }

    enum OllamaError: LocalizedError {
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .requestFailed: return "Ollama request failed. Is Ollama running?"
            }
        }
    }
}
