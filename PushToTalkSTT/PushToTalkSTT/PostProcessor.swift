import Foundation

enum ProcessingMode: String, CaseIterable, Codable {
    case off = "Off"
    case clean = "Clean (Grammar & Punctuation)"
    case code = "Code (Format as Code)"
}

class PostProcessor {
    static let shared = PostProcessor()

    var mode: ProcessingMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "postProcessingMode"),
                  let mode = ProcessingMode(rawValue: raw) else { return .off }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "postProcessingMode") }
    }

    var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2:3b" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }

    var ollamaEndpoint: String {
        get { UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaEndpoint") }
    }

    func process(_ text: String) async -> String {
        guard mode != .off else { return text }

        let prompt = buildPrompt(for: mode, text: text)

        do {
            let result = try await OllamaClient.shared.generate(
                prompt: prompt,
                model: ollamaModel,
                endpoint: ollamaEndpoint
            )
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("PostProcessor: Ollama failed (\(error)), returning raw text")
            return text
        }
    }

    private func buildPrompt(for mode: ProcessingMode, text: String) -> String {
        switch mode {
        case .off:
            return text
        case .clean:
            return """
            Fix the grammar, punctuation, and capitalization of this dictated text. \
            Return ONLY the corrected text, nothing else. Do not add explanations or quotes.

            Text: \(text)
            """
        case .code:
            return """
            Convert this dictated speech into properly formatted code. \
            Interpret coding intent: use snake_case for Python, camelCase for JS/Swift, \
            add proper brackets, indentation, and syntax. \
            Return ONLY the code, nothing else. No explanations, no markdown fences.

            Dictated: \(text)
            """
        }
    }
}
