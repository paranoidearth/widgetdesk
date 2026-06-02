# Apple API Reference

This document is the replication checklist for the native WidgetDesk host.

这份文档用于约束 WidgetDesk 原生宿主的 Apple API 选型，目标是尽量完整复刻当前体验，并补齐后续快捷调用能力。

## Current Host APIs / 当前已使用

### App Lifecycle / 应用生命周期

- `NSApplication.shared`
- `NSApplication.setActivationPolicy(.regular)`
- `NSApplication.activate(ignoringOtherApps:)`
- `NSAlert(error:)`

Used for launching WidgetDesk as a normal macOS app, opening the prompt window, and showing fatal startup errors.

用于把 WidgetDesk 作为普通 macOS App 启动、拉起输入窗口，以及展示启动错误。

### Prompt Window / 输入窗口

- `NSWindow`
- `NSWindowController`
- `NSTextField`
- `NSSecureTextField`
- `NSTextFieldDelegate`
- `NSTextFieldCell`
- `NSButton`
- `NSImage(systemSymbolName:)`
- `NSView`
- `CAGradientLayer`

The prompt UI should remain a native borderless AppKit window, not a web view. Text input, paste, focus, and keyboard handling should stay in AppKit.

输入框必须保持原生 AppKit 无边框窗口，不使用 WebView。文本输入、粘贴、焦点和键盘处理都应继续走 AppKit。

### Desktop Widget Windows / 桌面组件窗口

- `NSWindow`
- `WKWebView`
- `WKWebViewConfiguration`
- `WKNavigationDelegate`
- `CGWindowLevelForKey`
- `CGWindowLevelKey.desktopWindow`
- `CGWindowLevelKey.desktopIconWindow`
- `NSScreen.visibleFrame`
- `NSView.hitTest(_:)`
- `NSEvent`
- `NSCursor`

Widget windows are transparent borderless `NSWindow` instances hosting `WKWebView`.

组件窗口是透明无边框 `NSWindow`，内部渲染 `WKWebView`。

Rules:

- display-only widgets use desktop-level placement and pass through mouse events except the drag handle
- interactive widgets use a clickable desktop-icon-level window
- host-level drag is handled by `NSWindow.sendEvent(_:)`
- drag position persists back into `widget.json`

规则：

- 展示型组件放在桌面层，除拖拽手柄外尽量透传鼠标事件
- 交互型组件放在可点击的 desktop-icon 层
- 宿主层通过 `NSWindow.sendEvent(_:)` 处理拖拽
- 拖拽位置写回 `widget.json`

### Menus / 菜单

- `NSMenu`
- `NSMenuItem`
- `NSStatusBar.system.statusItem(withLength:)`
- `NSStatusItem`
- `NSWorkspace.shared.open(_:)`

WidgetDesk uses both the app menu and a menu-bar `WD` item.

WidgetDesk 同时使用应用菜单和菜单栏 `WD` 入口。

Required menu behaviors:

- new widget
- settings
- open widgets folder
- reload widgets
- list visible/hidden widgets with checkmarks
- show/hide each widget
- quit

必须保留的菜单行为：

- 新建组件
- 设置
- 打开组件目录
- 重新加载组件
- 用勾选状态展示组件显示/隐藏
- 切换组件显示/隐藏
- 退出

### Settings And Keychain / 设置与 Keychain

- `Security`
- `SecItemCopyMatching`
- `SecItemAdd`
- `SecItemDelete`
- `kSecClassGenericPassword`
- `kSecAttrService`
- `kSecAttrAccount`
- `kSecValueData`

Current service/account:

```text
service: WidgetDesk.OpenAICompatible
account: default
```

The API key must stay in macOS Keychain. Base URL and model can stay in:

API Key 必须继续保存在 macOS Keychain。Base URL 和 model 可以继续保存在：

```text
~/Library/Application Support/WidgetDesk/llm-config.json
```

## Missing Shortcut APIs / 仍需补齐的快捷调用

### 1. App Intents For Shortcuts / 面向快捷指令的 App Intents

Use `AppIntents` to expose WidgetDesk actions to the Shortcuts app on Mac.

用 `AppIntents` 把 WidgetDesk 的动作暴露给 macOS 快捷指令。

Recommended intents:

建议实现：

| Intent | Purpose |
| --- | --- |
| `ShowPromptIntent` | Bring the WidgetDesk prompt window to front |
| `CreateWidgetIntent` | Create or edit a widget from a prompt string |
| `ListWidgetsIntent` | Return installed widget names/ids |
| `ShowWidgetIntent` | Show one widget by id |
| `HideWidgetIntent` | Hide one widget by id |
| `OpenWidgetsFolderIntent` | Open the widget directory in Finder |

Minimal shape:

```swift
import AppIntents

struct CreateWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Widget"
    static var description = IntentDescription("Create or edit a WidgetDesk desktop widget.")

    @Parameter(title: "Prompt")
    var prompt: String

    func perform() async throws -> some IntentResult {
        // Call WidgetDeskToolAgent or hand off to the running host.
        return .result()
    }
}
```

Important macOS note:

重要的 macOS 限制：

- App Intents are the correct API for Shortcuts integration.
- App Shortcuts are not the primary target for macOS; users can build custom shortcuts using app intents in the Shortcuts app on Mac.

- `AppIntents` 是接入快捷指令的正确 API。
- `App Shortcuts` 不是 macOS 上的主要路径；macOS 用户可以在快捷指令 App 中基于 App Intents 自行创建快捷指令。

### 2. URL Scheme / URL Scheme 唤起

Add a URL scheme for external launchers, scripts, Raycast, Alfred, and browser links.

增加 URL Scheme，方便外部启动器、脚本、Raycast、Alfred 或浏览器链接调用。

Suggested scheme:

```text
widgetdesk://prompt?text=Create%20a%20clock
widgetdesk://show?id=pomodoro
widgetdesk://hide?id=pomodoro
widgetdesk://settings
```

Implementation notes:

- add `CFBundleURLTypes` to `Info.plist`
- add an AppKit app delegate
- handle incoming URLs through `application(_:open:)`
- route URL actions to the same host methods used by menus

实现要点：

- 在 `Info.plist` 增加 `CFBundleURLTypes`
- 增加 AppKit app delegate
- 通过 `application(_:open:)` 处理 URL
- URL 动作必须复用菜单已使用的宿主方法

### 3. Global Hotkey / 全局快捷键

For a 100% native desktop feel, add a global hotkey to show the prompt window.

为了完整桌面体验，应增加一个全局快捷键唤起输入框。

Suggested default:

```text
Option + Space
```

Implementation options:

| Option | Notes |
| --- | --- |
| `NSEvent.addGlobalMonitorForEvents(matching:handler:)` | Can observe global events but cannot modify/cancel them; may require permissions depending on use |
| Carbon `RegisterEventHotKey` | Older API, still commonly used for global hotkeys in macOS apps |
| Small Swift package wrapper | Acceptable only if packaging policy allows dependencies |

For WidgetDesk, prefer a tiny host-owned hotkey layer. Do not put hotkey logic inside generated widgets.

WidgetDesk 应优先在宿主层实现全局快捷键，不要把快捷键逻辑放进生成组件里。

### 4. AppleScript Or CLI Bridge / AppleScript 或 CLI 桥接

Keep the CLI as the stable automation bridge:

继续保留 CLI 作为稳定自动化入口：

```bash
swift run widgetdesk -- show pomodoro
swift run widgetdesk -- hide pomodoro
swift run widgetdesk-agent -- create a clock
```

Optional future AppleScript support can be added later, but it is not required for the first full native replication.

AppleScript 可以后续补，但第一版完整原生复刻不强依赖它。

## Replication Checklist / 复刻检查表

- [x] native prompt window
- [x] native settings window
- [x] menu-bar `WD` item
- [x] app menu with Edit/Paste support
- [x] transparent desktop `WKWebView` widget windows
- [x] interactive widget click support
- [x] host-level drag handle
- [x] persisted widget position
- [x] menu show/hide per widget
- [x] Keychain API key storage
- [ ] App Intents for Shortcuts on Mac
- [ ] URL scheme
- [ ] global hotkey
- [ ] packaged `.app` with Info.plist URL registration

## Official References / 官方参考

- [App Intents](https://developer.apple.com/documentation/AppIntents/app-intents)
- [AppIntent](https://developer.apple.com/documentation/appintents/appintent)
- [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)
- [Human Interface Guidelines: App Shortcuts](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts)
- [NSEvent](https://developer.apple.com/documentation/AppKit/NSEvent)
- [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [Keychain services](https://developer.apple.com/documentation/security/keychain-services)
- [SecItemAdd](https://developer.apple.com/documentation/security/secitemadd%28_%3A_%3A%29)
