# Independent App Agent MVP

WidgetDesk has moved from an agent-skill packaging model to a standalone macOS app-agent runtime with a native prompt dialog.

## Goal

Run and create desktop widgets without depending on:

- Uebersicht
- Claude Code skills
- Codex skills
- OpenClaw plugins or gateways

## Runtime

The independent runtime lives in `apps/macos-host` and is split into four Swift targets:

| Target | Role |
|--------|------|
| `WidgetDeskCore` | Shared paths, manifests, widget store, templates, local agent planner |
| `WidgetDeskHost` | Native macOS prompt dialog, provider settings dialog, menu-bar process, and transparent desktop-level `WKWebView` windows |
| `widgetdesk` | Management CLI for list/create/install/show/hide/delete/doctor |
| `widgetdesk-agent` | Standalone prompt-to-widget entrypoint |

## Harness Design

The host now uses `WidgetDeskToolAgent`, a small OpenAI-compatible tool-loop harness:

1. The model receives a WidgetDesk system prompt plus a bounded tool surface.
2. The model can call `list_components`, `read_component_file`, `edit_component_file`, and `set_component_visibility` over multiple turns.
3. Swift validates tool arguments before touching disk.
4. `WidgetStore` is the only layer that writes manifests or component directories.
5. The host observes manifest and entry-file modification signatures and reloads when they change.

`WidgetIntentPlanner` remains as an offline CLI template planner. `OpenAIWidgetGenerator` remains as the older one-shot JSON generator, but the host generation path uses the tool agent.

The previous Übersicht skill constraints were migrated as product rules rather than copied literally. The new prompt preserves the useful parts: compact dimensions, Dock-safe bottom spacing, restrained macOS glass styling, display-only pointer behavior, interactive-state guidance, localStorage persistence, no secrets, no external assets, and no permission-triggering browser APIs by default. Übersicht-only JSX rules, such as `import { React } from 'uebersicht'`, do not apply to the standalone WKWebView HTML runtime.

See `docs/apple-api-reference.md` for the AppKit, WebKit, Keychain, App Intents, URL scheme, and global-hotkey checklist required to replicate the native host experience.

## Provider Settings

`WidgetDeskHost` includes a Settings dialog for OpenAI-compatible providers:

- base URL and model are saved to `~/Library/Application Support/WidgetDesk/llm-config.json`
- API key is stored in macOS Keychain under `WidgetDesk.OpenAICompatible`
- requests are sent to `<baseURL>/chat/completions`

The LLM must support OpenAI-compatible chat tool calls for the host agent path.

## Widget Directory

Widgets live at:

```text
~/Library/Application Support/WidgetDesk/widgets/
```

Each widget is a directory:

```text
my-widget/
  widget.json
  index.html
```

Manifest:

```json
{
  "id": "my-widget",
  "name": "My Widget",
  "entry": "index.html",
  "x": 40,
  "y": 90,
  "width": 320,
  "height": 160,
  "interactive": false,
  "visible": true,
  "anchor": "bottom-right"
}
```

`anchor` supports `top-left`, `top-center`, `top-right`, `center-left`, `center`, `center-right`, `bottom-left`, `bottom-center`, and `bottom-right`.

## Commands

```bash
cd apps/macos-host
swift run WidgetDeskHost
swift run widgetdesk-agent -- add a clock on the top right
swift run widgetdesk -- list
swift run widgetdesk -- doctor
```

## Next Milestones

1. Add a model-provider interface behind `WidgetIntentPlanner`.
2. Add an approval policy for destructive actions and shell-backed widgets.
3. Add drag-to-position and persist changed anchors/margins.
4. Package `WidgetDeskHost` as `WidgetDesk.app`.
5. Add snapshot-based visual tests for generated widgets.
