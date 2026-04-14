import Foundation

struct OllamaClient {
    static let shared = OllamaClient()

    struct OllamaResponse: Codable {
        let response: String
        let done: Bool
    }

    struct OllamaRequest: Codable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    struct OllamaModel: Codable {
        let name: String
    }

    struct OllamaModelsResponse: Codable {
        let models: [OllamaModel]
    }

    /// Generate a completion from Ollama
    func generate(prompt: String, model: String, endpoint: String) async throws -> String {
        let url = URL(string: "\(endpoint)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = OllamaRequest(model: model, prompt: prompt, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.response
    }

    /// List available models from Ollama
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

    /// Check if Ollama is reachable
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
