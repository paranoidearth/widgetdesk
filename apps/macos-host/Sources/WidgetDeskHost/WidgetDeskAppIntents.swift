import AppIntents
import AppKit
import Foundation
import WidgetDeskCore

private enum WidgetDeskIntentBridge {
    static func notify(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @MainActor
    static func openHost() {
        NSWorkspace.shared.open(Bundle.main.bundleURL)
    }

    static func widgetSummary(_ manifest: WidgetManifest) -> String {
        let state = manifest.visible ? "visible" : "hidden"
        let mode = manifest.interactive ? "interactive" : "passive"
        let anchor = manifest.anchor?.rawValue ?? "legacy"
        return "\(manifest.id)\t\(state)\t\(mode)\t\(anchor)\t\(Int(manifest.width))x\(Int(manifest.height))\t\(manifest.name)"
    }
}

struct ShowPromptIntent: AppIntent {
    static let title: LocalizedStringResource = "Show WidgetDesk Prompt"
    static let description = IntentDescription("Bring the WidgetDesk prompt window to the front.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        WidgetDeskIntentBridge.openHost()
        WidgetDeskIntentBridge.notify(WidgetDeskNotifications.showPrompt)
        return .result(value: "Opened WidgetDesk prompt.")
    }
}

struct CreateWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Widget"
    static let description = IntentDescription("Create or edit a WidgetDesk desktop widget from a prompt.")
    static let openAppWhenRun = true

    @Parameter(title: "Prompt")
    var prompt: String

    @Parameter(title: "System Prompt")
    var systemPrompt: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        WidgetDeskIntentBridge.openHost()
        let result = try await WidgetDeskToolAgent().run(prompt: prompt, systemPrompt: systemPrompt)
        WidgetDeskIntentBridge.notify(WidgetDeskNotifications.reloadWidgets)
        return .result(value: result.message)
    }
}

struct ListWidgetsIntent: AppIntent {
    static let title: LocalizedStringResource = "List Widgets"
    static let description = IntentDescription("List installed WidgetDesk widgets.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let widgets = try WidgetStore().loadWidgets(includeHidden: true)
        guard !widgets.isEmpty else {
            return .result(value: "No widgets installed.")
        }
        return .result(value: widgets.map { WidgetDeskIntentBridge.widgetSummary($0.manifest) }.joined(separator: "\n"))
    }
}

struct ShowWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Widget"
    static let description = IntentDescription("Show a WidgetDesk widget by id.")

    @Parameter(title: "Widget ID")
    var widgetID: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let widget = try WidgetStore().setVisibility(id: widgetID, visible: true)
        WidgetDeskIntentBridge.notify(WidgetDeskNotifications.reloadWidgets)
        return .result(value: "Showed \(widget.manifest.id).")
    }
}

struct HideWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Hide Widget"
    static let description = IntentDescription("Hide a WidgetDesk widget by id.")

    @Parameter(title: "Widget ID")
    var widgetID: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let widget = try WidgetStore().setVisibility(id: widgetID, visible: false)
        WidgetDeskIntentBridge.notify(WidgetDeskNotifications.reloadWidgets)
        return .result(value: "Hid \(widget.manifest.id).")
    }
}

struct BuildWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Build Widget"
    static let description = IntentDescription("Build a WidgetDesk source widget by id.")

    @Parameter(title: "Widget ID")
    var widgetID: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try WidgetComponentBuilder().build(id: widgetID)
        WidgetDeskIntentBridge.notify(WidgetDeskNotifications.reloadWidgets)
        return .result(value: "\(result.message) Entry: \(result.entry)")
    }
}

struct DeleteWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete Widget"
    static let description = IntentDescription("Delete a WidgetDesk widget by id.")

    @Parameter(title: "Widget ID")
    var widgetID: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try WidgetStore().deleteWidget(id: widgetID)
        WidgetDeskIntentBridge.notify(WidgetDeskNotifications.reloadWidgets)
        return .result(value: "Deleted \(widgetID).")
    }
}

struct OpenWidgetsFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Widgets Folder"
    static let description = IntentDescription("Open the WidgetDesk widgets folder in Finder.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try WidgetStore().ensureBaseDirectories()
        NSWorkspace.shared.open(WidgetDeskPaths.widgets)
        return .result(value: WidgetDeskPaths.widgets.path)
    }
}

struct ReloadWidgetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Reload Widgets"
    static let description = IntentDescription("Ask the running WidgetDesk host to reload widgets.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        WidgetDeskIntentBridge.notify(WidgetDeskNotifications.reloadWidgets)
        return .result(value: "Reload requested.")
    }
}

struct WidgetDeskAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowPromptIntent(),
            phrases: [
                "Show \(.applicationName) prompt",
                "Create a widget with \(.applicationName)"
            ],
            shortTitle: "Show Prompt",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: ListWidgetsIntent(),
            phrases: [
                "List \(.applicationName) widgets"
            ],
            shortTitle: "List Widgets",
            systemImageName: "list.bullet.rectangle"
        )
        AppShortcut(
            intent: OpenWidgetsFolderIntent(),
            phrases: [
                "Open \(.applicationName) widgets folder"
            ],
            shortTitle: "Open Folder",
            systemImageName: "folder"
        )
        AppShortcut(
            intent: ReloadWidgetsIntent(),
            phrases: [
                "Reload \(.applicationName) widgets"
            ],
            shortTitle: "Reload Widgets",
            systemImageName: "arrow.clockwise"
        )
    }
}
