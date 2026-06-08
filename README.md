# WidgetDesk

> Generate and manage native macOS desktop widgets with natural language.  
> 用自然语言生成和管理 macOS 桌面组件。

[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)
![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)
![Status](https://img.shields.io/badge/status-early%20preview-yellow.svg)

![WidgetDesk preview](docs/images/widgetdesk-hero.png)

WidgetDesk is a standalone macOS app that turns a short prompt into a local desktop widget. It runs a native AppKit prompt window, renders widgets in transparent `WKWebView` desktop windows, and stores every widget as ordinary files on your Mac.

WidgetDesk 是一个独立 macOS 应用：输入一句话，它会在桌面上生成、修改、显示或隐藏本地组件。宿主使用原生 AppKit 输入窗口，通过透明 `WKWebView` 渲染桌面组件，所有组件都以普通文件形式保存在本机。

## Contents

- [Status](#status)
- [What You Can Build](#what-you-can-build)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Example Prompts](#example-prompts)
- [Privacy And Storage](#privacy-and-storage)
- [Widget Files](#widget-files)
- [Developer CLI](#developer-cli)
- [Development](#development)
- [Architecture](#architecture)
- [Roadmap](#roadmap)
- [Star History](#star-history)

## Status

WidgetDesk is early but usable. The current host supports:

- a menu-bar app and native prompt window
- OpenAI-compatible chat tool calls for widget creation and editing
- local widget templates for offline CLI use
- draggable widget windows with persisted position
- a management CLI for list/create/install/show/hide/delete/doctor
- core unit tests for the widget store and offline agent

Still rough:

- no signed `.app` release yet
- no visual regression test suite yet
- generated widget quality depends on the configured model
- project packaging is still source-first

The project is moving from a prototype into a proper desktop app. If you are looking for a polished installer, wait for the first packaged release. If you are comfortable running Swift source locally, you can use it today.

## What You Can Build

- clocks, timers, pomodoro widgets, and habit reminders
- sticky notes, tiny dashboards, and scratchpad widgets
- system status cards for CPU, memory, battery, and local context
- playful one-off desktop tools that are too small to deserve a full app
- personal workflow panels that live quietly on the desktop

## Requirements

- macOS 13 or newer
- Swift 6 / Xcode Command Line Tools
- an OpenAI-compatible API key for AI generation

Install command-line tools if needed:

```bash
xcode-select --install
```

## Quick Start

```bash
git clone https://github.com/paranoidearth/widgetdesk.git
cd widgetdesk/apps/macos-host
swift run WidgetDeskHost
```

The app opens a compact prompt window and adds a `WD` menu-bar item. Open **Settings**, then enter:

```text
Base URL: https://api.openai.com/v1
Model:    gpt-4.1-mini
API Key:  your provider API key
```

The API key is stored in macOS Keychain. Base URL and model are stored in:

```text
~/Library/Application Support/WidgetDesk/llm-config.json
```

## Example Prompts

```text
Create a pomodoro timer on the bottom left
Add a small clock on the top right
Make a sticky note that says "ship the tiny thing"
Hide the pomodoro widget
Make the clock smaller and more subtle
```

## Privacy And Storage

WidgetDesk keeps widget files on your Mac. Generated widgets are plain local HTML files loaded by the native host.

- API keys are stored in macOS Keychain
- provider settings are stored in `~/Library/Application Support/WidgetDesk/llm-config.json`
- widgets are stored in `~/Library/Application Support/WidgetDesk/widgets/`
- prompts are sent to the OpenAI-compatible provider you configure
- generated widget HTML should not include external scripts, fonts, images, or network resources

## Widget Files

Widgets live in:

```text
~/Library/Application Support/WidgetDesk/widgets/
```

Each widget is a directory:

```text
my-widget/
  widget.json
  index.html
```

`widget.json` controls identity, visibility, position, size, and whether the widget receives mouse input:

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

## Developer CLI

Most people should use the macOS app. The CLI is mainly for development, diagnostics, automation, and CI-friendly checks.

普通用户不需要从命令行使用 WidgetDesk。CLI 主要给开发、诊断、自动化和后续 CI 检查使用。

From `apps/macos-host`:

```bash
swift run widgetdesk -- doctor
swift run widgetdesk -- list
swift run widgetdesk -- create clock my-clock
swift run widgetdesk -- agent add a pomodoro timer bottom left
swift run widgetdesk -- hide my-clock
swift run widgetdesk -- show my-clock
swift run widgetdesk -- delete my-clock
swift run widgetdesk -- path
```

Templates available to the offline CLI:

```text
clock, pomodoro, system-stats, memo, tap-counter
```

## Development

Build:

```bash
cd apps/macos-host
swift build
```

Test:

```bash
swift test
```

Run the host:

```bash
swift run WidgetDeskHost
```

Run the offline template agent:

```bash
swift run widgetdesk-agent -- add a clock on the top right
```

## Architecture

The Swift package is split into four targets:

| Target | Role |
| --- | --- |
| `WidgetDeskCore` | Paths, manifests, widget store, templates, settings, and agent logic |
| `WidgetDeskHost` | Native macOS app, menu-bar item, settings window, and desktop widget windows |
| `widgetdesk` | Management CLI |
| `widgetdesk-agent` | Prompt-to-template CLI entrypoint |

More detail lives in [docs/architecture/independent-host-mvp.md](docs/architecture/independent-host-mvp.md).

## Roadmap

- package and sign a downloadable `WidgetDesk.app`
- add screenshot-based widget rendering tests
- expose App Intents for Shortcuts, Raycast, and launcher workflows
- add an approval policy for destructive edits and shell-backed widgets
- improve model prompts and built-in widget examples

## Contributing

Issues, small fixes, and widget ideas are welcome. Good first contributions:

- improve a built-in template
- add a focused unit test
- tighten the generator prompt
- report a rough edge in the macOS host
- help package the app as a signed `.app`

Please keep changes small and easy to review. For now, run this before opening a PR:

```bash
cd apps/macos-host
swift test
```

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=paranoidearth/widgetdesk&type=Date)](https://www.star-history.com/#paranoidearth/widgetdesk&Date)

## License

MIT
