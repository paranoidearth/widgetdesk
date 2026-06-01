import Foundation
import WidgetDeskCore

private let usage = """
Usage:
  widgetdesk-agent <prompt...>

Examples:
  widgetdesk-agent add a clock on the top right
  widgetdesk-agent create a pomodoro timer bottom left
  widgetdesk-agent list widgets
  widgetdesk-agent hide sample-clock
"""

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "--" {
    args.removeFirst()
}

let prompt = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
guard !prompt.isEmpty else {
    print(usage)
    exit(1)
}

do {
    let result = try WidgetDeskAgent().run(prompt: prompt)
    print(result.message)
} catch let error as WidgetDeskError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
