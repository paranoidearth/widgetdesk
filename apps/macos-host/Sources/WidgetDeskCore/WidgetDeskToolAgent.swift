import Foundation

public struct WidgetDeskToolAgentResult: Equatable, Sendable {
    public var message: String
    public var changedWidgetIDs: [String]
}

public enum WidgetDeskToolAgentError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidBaseURL(String)
    case requestFailed(Int, String)
    case missingAssistantMessage
    case exceededTurnLimit
    case invalidToolArguments(String)
    case unsafePath(String)

    public var description: String {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI-compatible API key in Settings first."
        case .invalidBaseURL(let value):
            return "Invalid OpenAI-compatible base URL: \(value)"
        case .requestFailed(let status, let body):
            return "Agent request failed with HTTP \(status): \(body)"
        case .missingAssistantMessage:
            return "The agent response did not include an assistant message."
        case .exceededTurnLimit:
            return "The agent reached its turn limit before finishing."
        case .invalidToolArguments(let details):
            return "Invalid tool arguments: \(details)"
        case .unsafePath(let path):
            return "Unsafe widget file path: \(path)"
        }
    }
}

public struct WidgetDeskToolAgent: Sendable {
    private let settingsStore: WidgetDeskSettingsStore
    private let store: WidgetStore
    private let validator: WidgetComponentValidator
    private let session: URLSession
    private let maxTurns: Int

    public init(
        settingsStore: WidgetDeskSettingsStore = WidgetDeskSettingsStore(),
        store: WidgetStore = WidgetStore(),
        session: URLSession = .shared,
        maxTurns: Int = 8
    ) {
        self.settingsStore = settingsStore
        self.store = store
        self.validator = WidgetComponentValidator(store: store)
        self.session = session
        self.maxTurns = maxTurns
    }

    public func run(prompt: String) async throws -> WidgetDeskToolAgentResult {
        let settings = try settingsStore.load()
        let apiKey = try settingsStore.loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw WidgetDeskToolAgentError.missingAPIKey
        }

        var messages: [ToolAgentMessage] = [
            ToolAgentMessage(role: "system", content: Self.systemPrompt),
            ToolAgentMessage(role: "user", content: prompt)
        ]
        var changedWidgetIDs = Set<String>()

        for _ in 0..<maxTurns {
            let assistant = try await chatCompletion(messages: messages, settings: settings, apiKey: apiKey)
            messages.append(assistant)

            guard let toolCalls = assistant.toolCalls, !toolCalls.isEmpty else {
                guard !changedWidgetIDs.isEmpty else {
                    return WidgetDeskToolAgentResult(
                        message: assistant.content ?? "Done.",
                        changedWidgetIDs: []
                    )
                }

                let validation = validator.validate(ids: changedWidgetIDs)
                if validation.isReady {
                    return WidgetDeskToolAgentResult(
                        message: "Updated \(validation.validIDs.joined(separator: ", ")). Validation passed.",
                        changedWidgetIDs: validation.validIDs
                    )
                }
                messages.append(ToolAgentMessage(
                    role: "user",
                    content: "WidgetDesk validation failed. Fix the component files with tool calls before finishing:\n\(validation.summary)"
                ))
                continue
            }

            for toolCall in toolCalls {
                let execution = execute(toolCall: toolCall)
                changedWidgetIDs.formUnion(execution.changedWidgetIDs)
                messages.append(ToolAgentMessage(
                    role: "tool",
                    content: execution.content,
                    toolCallID: toolCall.id
                ))
            }

            let validation = validator.validate(ids: changedWidgetIDs)
            if validation.isReady {
                return WidgetDeskToolAgentResult(
                    message: "Updated \(validation.validIDs.joined(separator: ", ")). Validation passed.",
                    changedWidgetIDs: validation.validIDs
                )
            }
            if !validation.issues.isEmpty {
                messages.append(ToolAgentMessage(
                    role: "user",
                    content: "WidgetDesk validation failed. Fix the component files before finishing:\n\(validation.summary)"
                ))
            }
        }

        let validation = validator.validate(ids: changedWidgetIDs)
        if validation.isReady {
            return WidgetDeskToolAgentResult(
                message: "Updated \(validation.validIDs.joined(separator: ", ")). Validation passed.",
                changedWidgetIDs: validation.validIDs
            )
        }

        throw WidgetDeskToolAgentError.exceededTurnLimit
    }

    private func chatCompletion(
        messages: [ToolAgentMessage],
        settings: WidgetDeskLLMSettings,
        apiKey: String
    ) async throws -> ToolAgentMessage {
        let endpoint = try chatCompletionsURL(from: settings.baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body = ToolChatCompletionRequest(
            model: settings.model,
            messages: messages,
            tools: Self.tools,
            toolChoice: "auto",
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WidgetDeskToolAgentError.requestFailed(status, body)
        }

        let decoded = try JSONDecoder().decode(ToolChatCompletionResponse.self, from: data)
        guard let message = decoded.choices.first?.message else {
            throw WidgetDeskToolAgentError.missingAssistantMessage
        }
        return message
    }

    private func chatCompletionsURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WidgetDeskToolAgentError.invalidBaseURL(baseURL)
        }
        if trimmed.hasSuffix("/chat/completions"), let url = URL(string: trimmed) {
            return url
        }
        guard var components = URLComponents(string: trimmed) else {
            throw WidgetDeskToolAgentError.invalidBaseURL(baseURL)
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else {
            throw WidgetDeskToolAgentError.invalidBaseURL(baseURL)
        }
        return url
    }

    private func execute(toolCall: ToolAgentToolCall) -> ToolExecutionResult {
        do {
            switch toolCall.function.name {
            case "list_components":
                return try listComponents()
            case "read_component_file":
                let args = try decodeArguments(ReadComponentFileArguments.self, from: toolCall)
                return try readComponentFile(id: args.id, path: args.path)
            case "edit_component_file":
                let args = try decodeArguments(EditComponentFileArguments.self, from: toolCall)
                return try editComponentFile(id: args.id, path: args.path, content: args.content)
            case "set_component_visibility":
                let args = try decodeArguments(SetComponentVisibilityArguments.self, from: toolCall)
                return try setComponentVisibility(id: args.id, visible: args.visible)
            default:
                return ToolExecutionResult.error("Unknown tool: \(toolCall.function.name)")
            }
        } catch let error as CustomStringConvertible {
            return ToolExecutionResult.error(error.description)
        } catch {
            return ToolExecutionResult.error(error.localizedDescription)
        }
    }

    private func decodeArguments<T: Decodable>(_ type: T.Type, from toolCall: ToolAgentToolCall) throws -> T {
        guard let data = toolCall.function.arguments.data(using: .utf8) else {
            throw WidgetDeskToolAgentError.invalidToolArguments(toolCall.function.arguments)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WidgetDeskToolAgentError.invalidToolArguments(error.localizedDescription)
        }
    }

    private func listComponents() throws -> ToolExecutionResult {
        try store.ensureBaseDirectories()
        let widgets = try store.loadWidgets(includeHidden: true)
        let summaries = try widgets.map { widget in
            let files = try directFiles(in: widget.directory)
            return ComponentSummary(
                id: widget.manifest.id,
                name: widget.manifest.name,
                visible: widget.manifest.visible,
                anchor: widget.manifest.anchor?.rawValue,
                width: widget.manifest.width,
                height: widget.manifest.height,
                files: files
            )
        }
        return ToolExecutionResult.json(ListComponentsToolResult(ok: true, components: summaries))
    }

    private func readComponentFile(id: String, path: String) throws -> ToolExecutionResult {
        let url = try componentFileURL(id: id, path: path, createDirectory: false)
        let content = try String(contentsOf: url, encoding: .utf8)
        return ToolExecutionResult.json(FileContentToolResult(ok: true, id: id, path: path, content: content))
    }

    private func editComponentFile(id: String, path: String, content: String) throws -> ToolExecutionResult {
        let url = try componentFileURL(id: id, path: path, createDirectory: true)
        if path == "widget.json" {
            guard let data = content.data(using: .utf8) else {
                throw WidgetDeskToolAgentError.invalidToolArguments("widget.json content is not UTF-8")
            }
            let manifest = try JSONDecoder().decode(WidgetManifest.self, from: data)
            guard manifest.id == id else {
                throw WidgetDeskToolAgentError.invalidToolArguments("widget.json id must match the component id")
            }
            try store.writeManifest(manifest, in: url.deletingLastPathComponent())
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return ToolExecutionResult.json(
            FileWriteToolResult(ok: true, id: id, path: path, message: "File written."),
            changedWidgetIDs: [id]
        )
    }

    private func setComponentVisibility(id: String, visible: Bool) throws -> ToolExecutionResult {
        let widget = try store.setVisibility(id: id, visible: visible)
        return ToolExecutionResult.json(
            VisibilityToolResult(ok: true, id: id, visible: widget.manifest.visible),
            changedWidgetIDs: [id]
        )
    }

    private func componentFileURL(id: String, path: String, createDirectory: Bool) throws -> URL {
        try validateComponentID(id)
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty,
              !normalizedPath.hasPrefix("/"),
              normalizedPath.split(separator: "/").allSatisfy({ $0 != ".." && !$0.isEmpty }) else {
            throw WidgetDeskToolAgentError.unsafePath(path)
        }

        try store.ensureBaseDirectories()
        let directory = store.paths.widgets.appendingPathComponent(id, isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let url = directory.appendingPathComponent(normalizedPath).standardizedFileURL
        let root = directory.standardizedFileURL.path
        guard url.path == root || url.path.hasPrefix(root + "/") else {
            throw WidgetDeskToolAgentError.unsafePath(path)
        }
        return url
    }

    private func validateComponentID(_ id: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !id.isEmpty, id.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw WidgetDeskError.invalidWidgetID(id)
        }
    }

    private func directFiles(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .map(\.lastPathComponent)
        .sorted()
    }
}

struct WidgetComponentValidationReport: Equatable, Sendable {
    var validIDs: [String]
    var issues: [String]

    var isReady: Bool {
        !validIDs.isEmpty && issues.isEmpty
    }

    var summary: String {
        if issues.isEmpty {
            return "Validation passed for \(validIDs.joined(separator: ", "))."
        }
        return issues.joined(separator: "\n")
    }
}

struct WidgetComponentValidator: Sendable {
    private let store: WidgetStore

    init(store: WidgetStore = WidgetStore()) {
        self.store = store
    }

    func validate(ids: Set<String>) -> WidgetComponentValidationReport {
        var validIDs: [String] = []
        var issues: [String] = []

        for id in ids.sorted() {
            do {
                let directory = store.paths.widgets.appendingPathComponent(id, isDirectory: true)
                let manifest = try store.loadManifest(in: directory)
                let widget = WidgetInstance(directory: directory, manifest: manifest)
                let widgetIssues = try validate(widget: widget)
                if widgetIssues.isEmpty {
                    validIDs.append(id)
                } else {
                    issues.append(contentsOf: widgetIssues.map { "\(id): \($0)" })
                }
            } catch {
                issues.append("\(id): \(error.localizedDescription)")
            }
        }

        return WidgetComponentValidationReport(validIDs: validIDs, issues: issues)
    }

    private func validate(widget: WidgetInstance) throws -> [String] {
        var issues: [String] = []
        let manifest = widget.manifest

        if manifest.entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("manifest.entry is empty")
        }
        if manifest.width < 80 || manifest.width > 900 {
            issues.append("manifest.width must be between 80 and 900")
        }
        if manifest.height < 48 || manifest.height > 700 {
            issues.append("manifest.height must be between 48 and 700")
        }
        if manifest.x < 0 || manifest.y < 0 {
            issues.append("manifest.x and manifest.y must be non-negative")
        }

        guard FileManager.default.fileExists(atPath: widget.entryURL.path) else {
            issues.append("entry file is missing: \(manifest.entry)")
            return issues
        }

        let html = try String(contentsOf: widget.entryURL, encoding: .utf8)
        issues.append(contentsOf: validateHTML(html))
        return issues
    }

    private func validateHTML(_ html: String) -> [String] {
        let lower = html.lowercased()
        var issues: [String] = []

        if !lower.contains("<!doctype html") && !lower.contains("<html") {
            issues.append("index.html must be a complete HTML document")
        }
        if !lower.contains("<body") {
            issues.append("index.html must include a body element")
        }
        if lower.contains("src=\"http://") || lower.contains("src=\"https://") ||
            lower.contains("src='http://") || lower.contains("src='https://") ||
            lower.contains("href=\"http://") || lower.contains("href=\"https://") ||
            lower.contains("href='http://") || lower.contains("href='https://") ||
            lower.contains("@import url(") {
            issues.append("index.html must not load external scripts, styles, fonts, images, or links")
        }
        if html.count < 80 {
            issues.append("index.html is too small to be a complete widget")
        }

        return issues
    }
}

private extension WidgetDeskToolAgent {
    static let systemPrompt = """
    You are WidgetDesk's local component agent. Work by calling tools, not by inventing unseen files.

    WidgetDesk components live under ~/Library/Application Support/WidgetDesk/widgets/<id>/.
    A visible component needs at least:
    - widget.json: WidgetManifest JSON with id, name, entry, x, y, width, height, interactive, visible, anchor.
    - index.html: a complete self-contained HTML document loaded by a transparent WKWebView.

    Rules:
    - For existing components, call list_components first, then read_component_file before editing.
    - For new components, call edit_component_file for widget.json and index.html.
    - WidgetDesk widgets are HTML components, not Swift, Vue, or React projects. The completion baseline is that widget.json decodes and the entry HTML is complete, local-only, and loadable by WKWebView.
    - Do not finish with plain text after editing. Continue using tools until validation accepts the changed component.
    - Always write lowercase kebab-case component ids.
    - Keep component HTML self-contained: no external scripts, fonts, images, or network resources.
    - Use transparent html/body backgrounds unless the user asks otherwise:
      html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
    - Do not write outside the component folder.
    - Prefer polished compact macOS-style widgets, not a new visual language every time.
    - Default to dark translucent cards with blur:
      background: rgba(8, 12, 20, 0.72);
      -webkit-backdrop-filter: blur(24px);
      backdrop-filter: blur(24px);
      border-radius: 18px;
      border: 1px solid rgba(255,255,255,0.10);
      box-shadow: 0 14px 40px rgba(0,0,0,0.35);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
    - Default dimensions should stay between width 140...360 and height 48...220 unless the user explicitly asks for something large.
    - Default edge spacing is x=40 and y=90 for bottom-aligned widgets. Bottom widgets must keep y >= 90 so they do not collide with the Dock.
    - Preferred anchors: clock bottom-right, pomodoro bottom-left, system stats top-right, memo top-center, weather top-left, music bottom-center, controls center-right.
    - Set interactive=false and CSS pointer-events:none for display-only widgets. Set interactive=true only when the widget needs clicking, dragging, text input, or persisted state.
    - Interactive controls must be easy to hit. Avoid complex multi-step desktop interactions by default.
    - The WidgetDesk host already adds a drag handle to every component window and persists x/y in widget.json. Do not implement custom window dragging in HTML unless the user explicitly asks for in-widget drag behavior.
    - Use localStorage for tiny persisted state such as counters, timers, notes, and positions.
    - Keep motion short, light, and purposeful. Avoid high-frequency timers except clocks.
    - Do not use Web Audio, autoplay media, notifications, camera, microphone, or other permission-triggering browser APIs unless the user explicitly asks for them.
    - Use placeholder/loading states for data that may not be immediately available. Never show raw undefined/null.
    - If the user asks for system or network data, prefer browser-safe local approximations unless a data source is explicitly available; do not add external network calls by default.
    - End with a short human-readable summary after the needed tool calls are complete.

    Manifest examples:
    - Display clock:
      {"id":"desk-clock","name":"Desk Clock","entry":"index.html","x":40,"y":90,"width":320,"height":150,"interactive":false,"visible":true,"anchor":"bottom-right"}
    - Interactive pomodoro:
      {"id":"pomodoro","name":"Pomodoro","entry":"index.html","x":40,"y":90,"width":300,"height":172,"interactive":true,"visible":true,"anchor":"bottom-left"}

    Minimal display-only HTML pattern:
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
    html, body { width:100%; height:100%; margin:0; overflow:hidden; background:transparent; pointer-events:none; user-select:none; }
    .card { box-sizing:border-box; width:100%; height:100%; padding:18px 20px; border-radius:18px; background:rgba(8,12,20,.72); border:1px solid rgba(255,255,255,.10); box-shadow:0 14px 40px rgba(0,0,0,.35); -webkit-backdrop-filter:blur(24px); backdrop-filter:blur(24px); color:rgba(255,255,255,.92); }
    </style></head><body><main class="card"></main></body></html>
    """

    static let tools: [ToolAgentTool] = [
        ToolAgentTool(
            function: ToolAgentFunction(
                name: "list_components",
                description: "List installed WidgetDesk components, including ids, visibility, size, anchor, and direct files.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            )
        ),
        ToolAgentTool(
            function: ToolAgentFunction(
                name: "read_component_file",
                description: "Read a UTF-8 file inside a component folder, usually widget.json or index.html.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Component id.")
                        ]),
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Relative file path inside the component folder.")
                        ])
                    ]),
                    "required": .array([.string("id"), .string("path")]),
                    "additionalProperties": .bool(false)
                ])
            )
        ),
        ToolAgentTool(
            function: ToolAgentFunction(
                name: "edit_component_file",
                description: "Create or overwrite a UTF-8 file inside a component folder. Use this for widget.json and index.html.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Component id. It must match widget.json id when editing widget.json.")
                        ]),
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Relative file path inside the component folder.")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Complete replacement file content.")
                        ])
                    ]),
                    "required": .array([.string("id"), .string("path"), .string("content")]),
                    "additionalProperties": .bool(false)
                ])
            )
        ),
        ToolAgentTool(
            function: ToolAgentFunction(
                name: "set_component_visibility",
                description: "Show or hide an installed component by updating its manifest visibility.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Component id.")
                        ]),
                        "visible": .object([
                            "type": .string("boolean"),
                            "description": .string("true to show, false to hide.")
                        ])
                    ]),
                    "required": .array([.string("id"), .string("visible")]),
                    "additionalProperties": .bool(false)
                ])
            )
        )
    ]
}

private struct ToolExecutionResult {
    var content: String
    var changedWidgetIDs: Set<String>

    static func error(_ message: String) -> ToolExecutionResult {
        json(ErrorToolResult(ok: false, error: message))
    }

    static func json<T: Encodable>(_ value: T, changedWidgetIDs: Set<String> = []) -> ToolExecutionResult {
        let encoder = JSONEncoder.widgetDesk
        let data = (try? encoder.encode(value)) ?? Data("{\"ok\":false,\"error\":\"Could not encode tool result.\"}".utf8)
        return ToolExecutionResult(
            content: String(data: data, encoding: .utf8) ?? "{\"ok\":false}",
            changedWidgetIDs: changedWidgetIDs
        )
    }
}

private struct ComponentSummary: Codable {
    var id: String
    var name: String
    var visible: Bool
    var anchor: String?
    var width: Double
    var height: Double
    var files: [String]
}

private struct ListComponentsToolResult: Codable {
    var ok: Bool
    var components: [ComponentSummary]
}

private struct FileContentToolResult: Codable {
    var ok: Bool
    var id: String
    var path: String
    var content: String
}

private struct FileWriteToolResult: Codable {
    var ok: Bool
    var id: String
    var path: String
    var message: String
}

private struct VisibilityToolResult: Codable {
    var ok: Bool
    var id: String
    var visible: Bool
}

private struct ErrorToolResult: Codable {
    var ok: Bool
    var error: String
}

private struct ReadComponentFileArguments: Decodable {
    var id: String
    var path: String
}

private struct EditComponentFileArguments: Decodable {
    var id: String
    var path: String
    var content: String
}

private struct SetComponentVisibilityArguments: Decodable {
    var id: String
    var visible: Bool
}

private struct ToolChatCompletionRequest: Encodable {
    var model: String
    var messages: [ToolAgentMessage]
    var tools: [ToolAgentTool]
    var toolChoice: String
    var temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case tools
        case toolChoice = "tool_choice"
        case temperature
    }
}

private struct ToolChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: ToolAgentMessage
    }
}

private struct ToolAgentMessage: Codable {
    var role: String
    var content: String?
    var toolCallID: String?
    var toolCalls: [ToolAgentToolCall]?

    init(role: String, content: String? = nil, toolCallID: String? = nil, toolCalls: [ToolAgentToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }
}

private struct ToolAgentToolCall: Codable {
    var id: String
    var type: String
    var function: ToolAgentFunctionCall
}

private struct ToolAgentFunctionCall: Codable {
    var name: String
    var arguments: String
}

private struct ToolAgentTool: Encodable {
    var type = "function"
    var function: ToolAgentFunction
}

private struct ToolAgentFunction: Encodable {
    var name: String
    var description: String
    var parameters: JSONValue
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
