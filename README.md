# WidgetDesk

> Create macOS desktop widgets with natural language.  
> 用自然语言生成 macOS 桌面组件。

![WidgetDesk preview](docs/images/widgetdesk-hero.png)

## What It Is / 这是什么

WidgetDesk is a standalone macOS app for generating and managing desktop widgets. Open the app, type what you want, and an OpenAI-compatible model will create or edit a local widget.

WidgetDesk 是一个独立的 macOS 桌面组件应用。打开应用，输入你想要的组件，兼容 OpenAI 格式的模型会在本地创建或修改组件。

Widgets are stored here:

组件会保存在：

```text
~/Library/Application Support/WidgetDesk/widgets/
```

Each widget is a folder with:

每个组件是一个文件夹，包含：

```text
widget.json
index.html
```

## Requirements / 环境要求

- macOS 13+
- Swift 6 / Xcode Command Line Tools
- An OpenAI-compatible API key

- macOS 13 或更新版本
- Swift 6 / Xcode 命令行工具
- 一个兼容 OpenAI 格式的 API Key

## Run The App / 启动应用

```bash
git clone https://github.com/paranoidearth/widgetdesk.git
cd widgetdesk/apps/macos-host
swift run WidgetDeskHost
```

The app will open a small input window. Type a widget request and press Return.

应用会打开一个小输入框。输入你想要的组件，然后按 Return。

Example prompts:

示例：

```text
Create a pomodoro timer
Add a clock on the top right
Make a sticky note widget
Hide the pomodoro widget
Make the clock smaller
```

## Configure API Key / 配置 API Key

Open **Settings** from the app menu or the `WD` menu-bar item.

从应用菜单或菜单栏 `WD` 打开 **Settings**。

Fill in:

填写：

```text
Base URL: https://api.openai.com/v1
Model:    gpt-4.1-mini or any compatible model
API Key:  your provider API key
```

The API key is stored in macOS Keychain.

API Key 会保存在 macOS Keychain 里。

## Manage Widgets / 管理组件

You can show or hide widgets from the app menu or the `WD` menu-bar menu.

你可以在应用菜单或菜单栏 `WD` 菜单里显示或隐藏组件。

You can also use the CLI:

也可以使用命令行：

```bash
cd apps/macos-host

swift run widgetdesk -- list
swift run widgetdesk -- create clock my-clock
swift run widgetdesk -- hide my-clock
swift run widgetdesk -- show my-clock
swift run widgetdesk -- delete my-clock
swift run widgetdesk -- path
swift run widgetdesk -- doctor
```

## Development / 开发

Build:

构建：

```bash
cd apps/macos-host
swift build
```

Run:

运行：

```bash
swift run WidgetDeskHost
```

Run the offline template agent:

运行离线模板 agent：

```bash
swift run widgetdesk-agent -- add a clock on the top right
swift run widgetdesk-agent -- create a pomodoro timer bottom left
```

## License / 许可证

MIT
