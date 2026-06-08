import Foundation

public enum AgentAction: Equatable, Sendable {
    case create(template: WidgetTemplate, id: String)
    case show(id: String)
    case hide(id: String)
    case delete(id: String)
    case list
    case path
}

public struct AgentRunResult: Equatable, Sendable {
    public var action: AgentAction
    public var message: String
    public var widgets: [WidgetManifest]
}

public struct WidgetDeskAgent: Sendable {
    private let store: WidgetStore

    public init(store: WidgetStore = WidgetStore()) {
        self.store = store
    }

    @discardableResult
    public func run(prompt: String) throws -> AgentRunResult {
        let plan = try WidgetIntentPlanner.plan(prompt: prompt)

        switch plan {
        case .list:
            let widgets = try store.loadWidgets(includeHidden: true).map(\.manifest)
            return AgentRunResult(
                action: .list,
                message: widgets.isEmpty ? "No widgets installed." : widgets.map { "\($0.id) \($0.visible ? "visible" : "hidden") \($0.name)" }.joined(separator: "\n"),
                widgets: widgets
            )
        case .path:
            return AgentRunResult(action: .path, message: try store.widgetDirectoryPath(), widgets: [])
        case .show(let id):
            let widget = try store.setVisibility(id: id, visible: true)
            return AgentRunResult(action: .show(id: id), message: "Show \(id)", widgets: [widget.manifest])
        case .hide(let id):
            let widget = try store.setVisibility(id: id, visible: false)
            return AgentRunResult(action: .hide(id: id), message: "Hide \(id)", widgets: [widget.manifest])
        case .delete(let id):
            try store.deleteWidget(id: id)
            return AgentRunResult(action: .delete(id: id), message: "Deleted \(id)", widgets: [])
        case .create(let template, let id, let anchor):
            let draft = template.draft(id: id, prompt: prompt, anchor: anchor)
            let widget = try store.createWidget(from: draft, overwrite: true)
            return AgentRunResult(
                action: .create(template: template, id: id),
                message: "Created \(widget.manifest.id) from \(template.rawValue)",
                widgets: [widget.manifest]
            )
        }
    }
}

private enum WidgetPlan: Equatable {
    case create(template: WidgetTemplate, id: String, anchor: WidgetAnchor?)
    case show(id: String)
    case hide(id: String)
    case delete(id: String)
    case list
    case path
}

private enum WidgetIntentPlanner {
    static func plan(prompt: String) throws -> WidgetPlan {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WidgetDeskError.unsupportedPrompt(prompt)
        }

        let lower = trimmed.lowercased()
        let tokens = lower.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)

        if containsAny(tokens, ["list", "ls", "status"]) || lower.contains("列出") {
            return .list
        }
        if containsAny(tokens, ["path", "folder", "directory"]) || lower.contains("目录") {
            return .path
        }
        if containsAny(tokens, ["show", "enable", "unhide"]) || lower.contains("显示") {
            return .show(id: requestedID(from: tokens) ?? lastToken(tokens))
        }
        if containsAny(tokens, ["hide", "disable"]) || lower.contains("隐藏") {
            return .hide(id: requestedID(from: tokens) ?? lastToken(tokens))
        }
        if containsAny(tokens, ["delete", "remove", "rm"]) || lower.contains("删除") {
            return .delete(id: requestedID(from: tokens) ?? lastToken(tokens))
        }

        let template = inferTemplate(lower: lower, tokens: tokens)
        let id = requestedID(from: tokens) ?? makeID(template: template, prompt: lower)
        return .create(template: template, id: id, anchor: inferAnchor(lower: lower, tokens: tokens))
    }

    private static func inferTemplate(lower: String, tokens: [String]) -> WidgetTemplate {
        if containsAny(tokens, ["clock", "time", "date"]) || lower.contains("时钟") || lower.contains("时间") {
            return .clock
        }
        if containsAny(tokens, ["pomodoro", "timer", "focus"]) || lower.contains("番茄") || lower.contains("计时") {
            return .pomodoro
        }
        if containsAny(tokens, ["system", "stats", "cpu", "memory", "battery"]) || lower.contains("系统") || lower.contains("电量") {
            return .systemStats
        }
        if containsAny(tokens, ["counter", "tap", "count"]) || lower.contains("计数") {
            return .tapCounter
        }
        return .memo
    }

    private static func inferAnchor(lower: String, tokens: [String]) -> WidgetAnchor? {
        let top = containsAny(tokens, ["top"]) || lower.contains("上")
        let bottom = containsAny(tokens, ["bottom"]) || lower.contains("下")
        let left = containsAny(tokens, ["left"]) || lower.contains("左")
        let right = containsAny(tokens, ["right"]) || lower.contains("右")
        let center = containsAny(tokens, ["center", "middle"]) || lower.contains("中间") || lower.contains("居中")

        switch (top, bottom, left, right, center) {
        case (true, _, true, _, _): return .topLeft
        case (true, _, _, true, _): return .topRight
        case (true, _, _, _, true): return .topCenter
        case (_, true, true, _, _): return .bottomLeft
        case (_, true, _, true, _): return .bottomRight
        case (_, true, _, _, true): return .bottomCenter
        case (_, _, true, _, true): return .centerLeft
        case (_, _, _, true, true): return .centerRight
        case (_, _, _, _, true): return .center
        case (true, _, _, _, _): return .topRight
        case (_, true, _, _, _): return .bottomRight
        case (_, _, true, _, _): return .centerLeft
        case (_, _, _, true, _): return .centerRight
        default: return nil
        }
    }

    private static func requestedID(from tokens: [String]) -> String? {
        for marker in ["id", "widget"] {
            guard let index = tokens.firstIndex(of: marker), tokens.indices.contains(index + 1) else {
                continue
            }
            let id = sanitizedID(tokens[index + 1])
            if !id.isEmpty {
                return id
            }
        }
        if tokens.count == 1, let only = tokens.first {
            return sanitizedID(only)
        }
        return nil
    }

    private static func makeID(template: WidgetTemplate, prompt: String) -> String {
        let stopWords = Set([
            "add", "create", "make", "a", "an", "the", "on", "in", "to", "me", "my",
            "top", "bottom", "left", "right", "center", "middle",
            "widget", "clock", "time", "pomodoro", "timer", "focus", "system", "stats",
            "cpu", "memory", "battery", "memo", "note", "sticky", "saying", "that",
            "一个", "创建"
        ] + template.rawValue.split(separator: "-").map(String.init))
        let meaningful = prompt
            .split { !$0.isLetter && !$0.isNumber }
            .filter { word in
                !stopWords.contains(String(word))
            }
            .prefix(3)
            .joined(separator: "-")
        let suffix = sanitizedID(meaningful)
        return suffix.isEmpty ? template.rawValue : "\(template.rawValue)-\(suffix)"
    }

    private static func sanitizedID(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .prefix(48)
            .description
            .lowercased()
    }

    private static func lastToken(_ tokens: [String]) -> String {
        sanitizedID(tokens.last ?? "")
    }

    private static func containsAny(_ tokens: [String], _ words: [String]) -> Bool {
        words.contains { tokens.contains($0) }
    }
}
