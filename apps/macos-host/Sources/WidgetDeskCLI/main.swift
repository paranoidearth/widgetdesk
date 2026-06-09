import Foundation
import WidgetDeskCore

private let usageText = """
Usage:
  widgetdesk list
  widgetdesk install <widget-directory> [--overwrite]
  widgetdesk create <template> [widget-id]
  widgetdesk build <widget-id>
  widgetdesk agent <prompt...>
  widgetdesk show <widget-id>
  widgetdesk hide <widget-id>
  widgetdesk delete <widget-id>
  widgetdesk path
  widgetdesk doctor

Templates:
  clock, pomodoro, system-stats, memo, tap-counter
"""

private enum CLIError: Error, CustomStringConvertible {
    case usage

    var description: String { usageText }
}

private func printWidgets(_ widgets: [WidgetManifest]) {
    if widgets.isEmpty {
        print("No widgets installed at \(WidgetDeskPaths.widgets.path)")
        return
    }

    widgets
        .sorted { $0.id < $1.id }
        .forEach { manifest in
            let state = manifest.visible ? "visible" : "hidden"
            let mode = manifest.interactive ? "interactive" : "passive"
            let anchor = manifest.anchor?.rawValue ?? "legacy"
            print("\(manifest.id)\t\(state)\t\(mode)\t\(anchor)\t\(Int(manifest.width))x\(Int(manifest.height))\t\(manifest.name)")
        }
}

private func run() throws {
    let store = WidgetStore()
    var args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--" {
        args.removeFirst()
    }
    guard let command = args.first else {
        throw CLIError.usage
    }
    args.removeFirst()

    switch command {
    case "list":
        printWidgets(try store.loadWidgets(includeHidden: true).map(\.manifest))
    case "install":
        guard let path = args.first else {
            throw CLIError.usage
        }
        let overwrite = args.contains("--overwrite")
        let widget = try store.installWidget(from: URL(fileURLWithPath: path).standardizedFileURL, overwrite: overwrite)
        print("Installed \(widget.manifest.id) -> \(widget.directory.path)")
    case "create":
        guard let templateName = args.first else {
            throw CLIError.usage
        }
        let template = try WidgetTemplate.template(named: templateName)
        let id = args.dropFirst().first ?? template.rawValue
        let widget = try store.createWidget(from: template.draft(id: id, prompt: templateName), overwrite: true)
        print("Created \(widget.manifest.id) -> \(widget.directory.path)")
    case "build":
        guard let id = args.first else {
            throw CLIError.usage
        }
        let result = try WidgetComponentBuilder(store: store).build(id: id)
        print("\(result.message) Entry: \(result.entry)")
    case "agent", "ask":
        guard !args.isEmpty else {
            throw CLIError.usage
        }
        let result = try WidgetDeskAgent(store: store).run(prompt: args.joined(separator: " "))
        print(result.message)
    case "show":
        guard let id = args.first else {
            throw CLIError.usage
        }
        _ = try store.setVisibility(id: id, visible: true)
        print("Show \(id)")
    case "hide":
        guard let id = args.first else {
            throw CLIError.usage
        }
        _ = try store.setVisibility(id: id, visible: false)
        print("Hide \(id)")
    case "delete", "remove", "rm":
        guard let id = args.first else {
            throw CLIError.usage
        }
        try store.deleteWidget(id: id)
        print("Deleted \(id)")
    case "path":
        try store.ensureBaseDirectories()
        print(WidgetDeskPaths.widgets.path)
    case "doctor":
        try store.ensureBaseDirectories()
        print("WidgetDesk app support: \(WidgetDeskPaths.appSupport.path)")
        print("Widget directory: \(WidgetDeskPaths.widgets.path)")
        print("Installed widgets: \(try store.loadWidgets(includeHidden: true).count)")
        print("Host: swift run WidgetDeskHost")
        print("Agent: swift run widgetdesk-agent -- \"add a clock\"")
    default:
        throw CLIError.usage
    }
}

do {
    try run()
} catch let error as CLIError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch let error as WidgetDeskError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
