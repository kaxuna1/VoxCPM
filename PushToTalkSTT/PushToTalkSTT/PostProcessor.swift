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

        let (system, user) = buildMessages(for: mode, text: text)

        do {
            let result = try await OllamaClient.shared.chat(
                system: system,
                user: user,
                model: ollamaModel,
                endpoint: ollamaEndpoint,
                temperature: mode == .code ? 0.0 : 0.1,
                maxTokens: max(text.count * 2, 256)
            )

            // Strip markdown fences if model adds them despite instructions
            let cleaned = stripMarkdownFences(result.trimmingCharacters(in: .whitespacesAndNewlines))
            return cleaned.isEmpty ? text : cleaned
        } catch {
            print("PostProcessor: Ollama failed (\(error)), returning raw text")
            return text
        }
    }

    // MARK: - Prompts

    private func buildMessages(for mode: ProcessingMode, text: String) -> (system: String, user: String) {
        switch mode {
        case .off:
            return ("", text)

        case .clean:
            let system = """
            You are a dictation post-processor. Your ONLY job is to clean up speech-to-text output.

            Rules:
            - Fix capitalization, punctuation, and grammar
            - Keep the original meaning and wording exactly
            - Do NOT add, remove, or rephrase words
            - Do NOT add greetings, explanations, or commentary
            - Output ONLY the corrected text, nothing else
            """
            return (system, text)

        case .code:
            let system = """
            You are a voice-to-code translator. Convert spoken programming descriptions into clean code.

            Rules:
            - Infer the programming language from context (Python, Swift, JS, etc.)
            - Use proper syntax: brackets, indentation, semicolons as needed
            - Use idiomatic naming: snake_case for Python, camelCase for JS/Swift
            - Interpret spoken words: "open paren" → (, "new line" → line break, "equals" → =
            - Output ONLY the code, no explanations, no markdown fences
            - For short expressions, output a single line
            - For function/class descriptions, output the full definition
            """
            return (system, text)
        }
    }

    private func stripMarkdownFences(_ text: String) -> String {
        var result = text
        // Remove ```language\n ... ``` wrapping
        if result.hasPrefix("```") {
            // Remove opening fence (```python, ```swift, ```, etc.)
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            // Remove closing fence
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
