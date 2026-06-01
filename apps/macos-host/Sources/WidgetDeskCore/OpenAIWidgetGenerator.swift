import Foundation

public enum WidgetGeneratorError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidBaseURL(String)
    case requestFailed(Int, String)
    case missingAssistantMessage
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI-compatible API key in Settings first."
        case .invalidBaseURL(let value):
            return "Invalid OpenAI-compatible base URL: \(value)"
        case .requestFailed(let status, let body):
            return "LLM request failed with HTTP \(status): \(body)"
        case .missingAssistantMessage:
            return "The LLM response did not include a widget payload."
        case .invalidJSON(let content):
            return "The LLM response was not valid widget JSON: \(content)"
        }
    }
}

public struct OpenAIWidgetGenerator: Sendable {
    private let settingsStore: WidgetDeskSettingsStore
    private let session: URLSession

    public init(settingsStore: WidgetDeskSettingsStore = WidgetDeskSettingsStore(), session: URLSession = .shared) {
        self.settingsStore = settingsStore
        self.session = session
    }

    public func generate(prompt: String) async throws -> WidgetDraft {
        let settings = try settingsStore.load()
        let apiKey = try settingsStore.loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw WidgetGeneratorError.missingAPIKey
        }

        let content = try await chatCompletion(prompt: prompt, settings: settings, apiKey: apiKey)
        let payload = try parsePayload(from: content)
        return payload.draft(fallbackPrompt: prompt)
    }

    private func chatCompletion(prompt: String, settings: WidgetDeskLLMSettings, apiKey: String) async throws -> String {
        let endpoint = try chatCompletionsURL(from: settings.baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let body = ChatCompletionRequest(
            model: settings.model,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt),
                ChatMessage(role: "user", content: prompt)
            ],
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WidgetGeneratorError.requestFailed(status, body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw WidgetGeneratorError.missingAssistantMessage
        }
        return content
    }

    private func chatCompletionsURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WidgetGeneratorError.invalidBaseURL(baseURL)
        }
        if trimmed.hasSuffix("/chat/completions"), let url = URL(string: trimmed) {
            return url
        }
        guard var components = URLComponents(string: trimmed) else {
            throw WidgetGeneratorError.invalidBaseURL(baseURL)
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else {
            throw WidgetGeneratorError.invalidBaseURL(baseURL)
        }
        return url
    }

    private func parsePayload(from content: String) throws -> GeneratedWidgetPayload {
        let json = extractJSON(from: content)
        guard let data = json.data(using: .utf8) else {
            throw WidgetGeneratorError.invalidJSON(content)
        }
        do {
            return try JSONDecoder().decode(GeneratedWidgetPayload.self, from: data)
        } catch {
            throw WidgetGeneratorError.invalidJSON(content)
        }
    }

    private func extractJSON(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.dropFirst().dropLast().joined(separator: "\n")
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    private static let systemPrompt = """
    You are WidgetDesk's widget generator. Return exactly one JSON object and nothing else.

    JSON schema:
    {
      "id": "short-kebab-case-id",
      "name": "Human name",
      "width": 320,
      "height": 180,
      "interactive": true,
      "anchor": "bottom-right",
      "html": "<!doctype html>..."
    }

    Rules:
    - html must be a complete self-contained document.
    - Use transparent html/body background so the desktop shows through.
    - Do not load external scripts, fonts, images, or network resources.
    - Keep CSS polished, compact, and readable on macOS.
    - Use localStorage for tiny interactive state when useful.
    - Valid anchors: top-left, top-center, top-right, center-left, center, center-right, bottom-left, bottom-center, bottom-right.
    - IDs may contain only letters, numbers, hyphen, and underscore.
    """
}

private struct ChatCompletionRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Codable {
    var choices: [Choice]

    struct Choice: Codable {
        var message: ChatMessage
    }
}

private struct GeneratedWidgetPayload: Codable {
    var id: String
    var name: String
    var width: Double
    var height: Double
    var interactive: Bool
    var anchor: WidgetAnchor?
    var html: String

    func draft(fallbackPrompt: String) -> WidgetDraft {
        let cleanID = sanitize(id).isEmpty ? sanitize(fallbackPrompt) : sanitize(id)
        let manifest = WidgetManifest(
            id: cleanID.isEmpty ? "generated-widget" : cleanID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Generated Widget" : name,
            x: 40,
            y: 90,
            width: min(max(width, 120), 900),
            height: min(max(height, 80), 700),
            interactive: interactive,
            anchor: anchor ?? .bottomRight
        )
        return WidgetDraft(manifest: manifest, html: html)
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .prefix(48)
            .description
            .lowercased()
    }
}
