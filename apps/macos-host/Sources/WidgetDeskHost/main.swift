import AppKit
import Foundation
import WebKit
import WidgetDeskCore

@MainActor
private final class DesktopWidgetWindow: NSWindow {
    var dragHandleFrame: NSRect = .zero
    var onDragDelta: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    private var lastDragScreenPoint: NSPoint?
    private var isDraggingWidget = false

    override var canBecomeKey: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown where dragHandleFrame.contains(event.locationInWindow):
            isDraggingWidget = true
            lastDragScreenPoint = NSEvent.mouseLocation
            NSCursor.closedHand.set()
            return
        case .leftMouseDragged where isDraggingWidget:
            let current = NSEvent.mouseLocation
            if let lastDragScreenPoint {
                onDragDelta?(CGSize(width: current.x - lastDragScreenPoint.x, height: current.y - lastDragScreenPoint.y))
            }
            self.lastDragScreenPoint = current
            return
        case .leftMouseUp where isDraggingWidget:
            isDraggingWidget = false
            lastDragScreenPoint = nil
            NSCursor.openHand.set()
            onDragEnded?()
            return
        default:
            super.sendEvent(event)
        }
    }
}

@MainActor
private final class WidgetContentView: NSView {
    var isWidgetInteractive = false
    weak var dragHandle: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let dragHandle {
            let handlePoint = dragHandle.convert(point, from: self)
            if dragHandle.bounds.contains(handlePoint) {
                return dragHandle.hitTest(handlePoint)
            }
        }

        return isWidgetInteractive ? super.hitTest(point) : nil
    }
}

@MainActor
private final class WidgetDragHandleView: NSView {
    var onDragDelta: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    private var lastScreenPoint: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        alphaValue = 0.38
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseEntered(with event: NSEvent) {
        alphaValue = 0.78
    }

    override func mouseExited(with event: NSEvent) {
        alphaValue = 0.38
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseDown(with event: NSEvent) {
        lastScreenPoint = NSEvent.mouseLocation
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        guard let lastScreenPoint else {
            self.lastScreenPoint = current
            return
        }
        onDragDelta?(CGSize(width: current.x - lastScreenPoint.x, height: current.y - lastScreenPoint.y))
        self.lastScreenPoint = current
    }

    override func mouseUp(with event: NSEvent) {
        lastScreenPoint = nil
        NSCursor.openHand.set()
        onDragEnded?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.withAlphaComponent(0.56).setFill()
        let dotGroupWidth: CGFloat = 12.2
        let dotGroupHeight: CGFloat = 8.2
        let originX = (bounds.width - dotGroupWidth) / 2
        let originY = (bounds.height - dotGroupHeight) / 2
        for row in 0..<2 {
            for column in 0..<3 {
                let x = originX + CGFloat(column) * 5
                let y = originY + CGFloat(row) * 6
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2.2, height: 2.2)).fill()
            }
        }
    }
}

@MainActor
private final class WidgetWindowController: NSObject, WKNavigationDelegate {
    private let window: DesktopWidgetWindow
    private let webView: WKWebView
    private let store: WidgetStore
    private var widget: WidgetInstance

    init(widget: WidgetInstance, store: WidgetStore) {
        self.widget = widget
        self.store = store

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = Self.windowFrame(for: widget.manifest, in: screenFrame)
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]

        window = DesktopWidgetWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        let contentView = WidgetContentView(frame: NSRect(origin: .zero, size: frame.size))
        contentView.autoresizingMask = [.width, .height]
        contentView.isWidgetInteractive = widget.manifest.interactive

        webView.navigationDelegate = self
        contentView.addSubview(webView)

        let dragHandleFrame = Self.dragHandleFrame(in: frame.size)
        let dragHandle = WidgetDragHandleView(frame: dragHandleFrame)
        dragHandle.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        dragHandle.onDragDelta = { [weak self] delta in
            self?.dragWindow(by: delta)
        }
        dragHandle.onDragEnded = { [weak self] in
            self?.persistCurrentFrame()
        }
        contentView.dragHandle = dragHandle
        contentView.addSubview(dragHandle)

        window.dragHandleFrame = dragHandleFrame
        window.onDragDelta = { [weak self] delta in
            self?.dragWindow(by: delta)
        }
        window.onDragEnded = { [weak self] in
            self?.persistCurrentFrame()
        }

        window.contentView = contentView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        let levelKey: CGWindowLevelKey = widget.manifest.interactive ? .desktopIconWindow : .desktopWindow
        let levelOffset = widget.manifest.interactive ? 1 : 0
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(levelKey)) + levelOffset)
        webView.loadFileURL(widget.entryURL, allowingReadAccessTo: widget.directory)
    }

    func show() {
        if widget.manifest.interactive {
            window.orderFrontRegardless()
        } else {
            window.orderBack(nil)
        }
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.orderOut(nil)
    }

    private func dragWindow(by delta: CGSize) {
        guard delta.width != 0 || delta.height != 0 else {
            return
        }
        var origin = window.frame.origin
        origin.x += delta.width
        origin.y += delta.height
        window.setFrameOrigin(origin)
    }

    private func persistCurrentFrame() {
        do {
            var manifest = widget.manifest
            let frame = window.frame
            let screenFrame = (NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            switch manifest.anchor {
            case .topLeft:
                manifest.x = frame.minX - screenFrame.minX
                manifest.y = screenFrame.maxY - frame.maxY
            case .topCenter:
                manifest.x = frame.midX - screenFrame.midX
                manifest.y = screenFrame.maxY - frame.maxY
            case .topRight:
                manifest.x = screenFrame.maxX - frame.maxX
                manifest.y = screenFrame.maxY - frame.maxY
            case .centerLeft:
                manifest.x = frame.minX - screenFrame.minX
                manifest.y = frame.midY - screenFrame.midY
            case .center:
                manifest.x = frame.midX - screenFrame.midX
                manifest.y = frame.midY - screenFrame.midY
            case .centerRight:
                manifest.x = screenFrame.maxX - frame.maxX
                manifest.y = frame.midY - screenFrame.midY
            case .bottomLeft:
                manifest.x = frame.minX - screenFrame.minX
                manifest.y = frame.minY - screenFrame.minY
            case .bottomCenter:
                manifest.x = frame.midX - screenFrame.midX
                manifest.y = frame.minY - screenFrame.minY
            case .bottomRight, .none:
                manifest.x = screenFrame.maxX - frame.maxX
                manifest.y = frame.minY - screenFrame.minY
            }

            manifest.x = manifest.x.rounded()
            manifest.y = manifest.y.rounded()
            try store.writeManifest(manifest, in: widget.directory)
            widget.manifest = manifest
        } catch {
            NSLog("WidgetDesk \(widget.manifest.id) position save failed: \(error.localizedDescription)")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("WidgetDesk \(widget.manifest.id) navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("WidgetDesk \(widget.manifest.id) provisional navigation failed: \(error.localizedDescription)")
    }

    private static func windowFrame(for manifest: WidgetManifest, in screenFrame: NSRect) -> NSRect {
        let width = max(80, manifest.width)
        let height = max(48, manifest.height)
        let marginX = max(0, manifest.x)
        let marginY = max(0, manifest.y)

        guard let anchor = manifest.anchor else {
            let x = screenFrame.maxX - marginX - width
            let y = screenFrame.minY + marginY
            return NSRect(x: x, y: y, width: width, height: height)
        }

        let x: Double
        switch anchor {
        case .topLeft, .centerLeft, .bottomLeft:
            x = screenFrame.minX + marginX
        case .topCenter, .center, .bottomCenter:
            x = screenFrame.midX - width / 2 + marginX
        case .topRight, .centerRight, .bottomRight:
            x = screenFrame.maxX - marginX - width
        }

        let y: Double
        switch anchor {
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = screenFrame.minY + marginY
        case .centerLeft, .center, .centerRight:
            y = screenFrame.midY - height / 2 + marginY
        case .topLeft, .topCenter, .topRight:
            y = screenFrame.maxY - marginY - height
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func dragHandleFrame(in size: NSSize) -> NSRect {
        let handleWidth: CGFloat = min(52, max(34, size.width * 0.18))
        let handleHeight: CGFloat = 18
        return NSRect(
            x: (size.width - handleWidth) / 2,
            y: size.height - handleHeight - 8,
            width: handleWidth,
            height: handleHeight
        )
    }
}

@MainActor
private final class ApplicationMenuController: NSObject {
    private let widgetMenu = NSMenu(title: "Widget")
    var onNewWidget: (() -> Void)?
    var onSettings: (() -> Void)?
    var onToggleWidgetVisibility: ((String, Bool) -> Void)?

    override init() {
        super.init()

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "WidgetDesk")
        appMenu.addItem(NSMenuItem(title: "About WidgetDesk", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide WidgetDesk", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit WidgetDesk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let widgetMenuItem = NSMenuItem()
        rebuildWidgetMenu(widgets: [])
        widgetMenuItem.submenu = widgetMenu
        mainMenu.addItem(widgetMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func newWidget() {
        onNewWidget?()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    func setWidgets(_ widgets: [WidgetManifest]) {
        rebuildWidgetMenu(widgets: widgets)
    }

    private func rebuildWidgetMenu(widgets: [WidgetManifest]) {
        widgetMenu.removeAllItems()

        let newItem = NSMenuItem(title: "New Widget...", action: #selector(newWidget), keyEquivalent: "n")
        newItem.target = self
        widgetMenu.addItem(newItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        widgetMenu.addItem(settingsItem)

        guard !widgets.isEmpty else {
            return
        }

        widgetMenu.addItem(NSMenuItem.separator())
        widgets.forEach { widget in
            let title = widget.name == widget.id ? widget.id : "\(widget.name) (\(widget.id))"
            let item = NSMenuItem(title: title, action: #selector(toggleWidgetVisibility(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = widget.id
            item.state = widget.visible ? .on : .off
            widgetMenu.addItem(item)
        }
    }

    @objc private func toggleWidgetVisibility(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        onToggleWidgetVisibility?(id, sender.state != .on)
    }
}

@MainActor
private final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    var onReload: (() -> Void)?
    var onNewWidget: (() -> Void)?
    var onSettings: (() -> Void)?
    var onToggleWidgetVisibility: ((String, Bool) -> Void)?

    override init() {
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "WD"
        statusItem = item

        rebuildMenu(widgets: [])
    }

    func setWidgets(_ widgets: [WidgetManifest]) {
        rebuildMenu(widgets: widgets)
    }

    private func rebuildMenu(widgets: [WidgetManifest]) {
        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New Widget...", action: #selector(newWidget), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open Widgets Folder", action: #selector(openWidgetsFolder), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let reloadItem = NSMenuItem(title: "Reload Widgets", action: #selector(reloadWidgets), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        if !widgets.isEmpty {
            menu.addItem(NSMenuItem.separator())
            widgets.forEach { widget in
                let title = widget.name == widget.id ? widget.id : "\(widget.name) (\(widget.id))"
                let item = NSMenuItem(title: title, action: #selector(toggleWidgetVisibility(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = widget.id
                item.state = widget.visible ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit WidgetDesk Host", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func newWidget() {
        onNewWidget?()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func openWidgetsFolder() {
        NSWorkspace.shared.open(WidgetDeskPaths.widgets)
    }

    @objc private func reloadWidgets() {
        onReload?()
    }

    @objc private func toggleWidgetVisibility(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        onToggleWidgetVisibility?(id, sender.state != .on)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class MagicGlowView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        gradientLayer.colors = [
            NSColor.systemPink.cgColor,
            NSColor.systemPurple.cgColor,
            NSColor.systemBlue.cgColor,
            NSColor.systemTeal.cgColor,
            NSColor.systemPink.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 0.25, 0.5, 0.75, 1]
        gradientLayer.opacity = 0
        gradientLayer.mask = maskLayer
        layer?.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        let path = CGMutablePath()
        let outer = bounds.insetBy(dx: 1, dy: 1)
        let inner = bounds.insetBy(dx: 4, dy: 4)
        path.addRoundedRect(in: outer, cornerWidth: 20, cornerHeight: 20)
        path.addRoundedRect(in: inner, cornerWidth: 17, cornerHeight: 17)
        maskLayer.path = path
        maskLayer.fillRule = .evenOdd
    }

    func setActive(_ active: Bool) {
        gradientLayer.opacity = active ? 1 : 0
        if active {
            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = [-0.4, -0.15, 0.1, 0.35, 0.6]
            animation.toValue = [0.4, 0.65, 0.9, 1.15, 1.4]
            animation.duration = 2.8
            animation.repeatCount = .infinity
            gradientLayer.add(animation, forKey: "widgetdesk.magic.locations")
        } else {
            gradientLayer.removeAnimation(forKey: "widgetdesk.magic.locations")
        }
    }
}

@MainActor
private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private func centeredRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let heightDelta = max(0, drawingRect.height - textSize.height)
        drawingRect.origin.y += heightDelta / 2
        drawingRect.size.height -= heightDelta
        return drawingRect
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(forBounds: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(withFrame: centeredRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(withFrame: centeredRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

@MainActor
private final class PromptTextField: NSTextField {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class PillButton: NSButton {
    init(title: String, imageName: String? = nil, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .regularSquare
        isBordered = false
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = NSColor(white: 0.82, alpha: 1)
        alignment = .center
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        if let imageName, let symbol = NSImage(systemSymbolName: imageName, accessibilityDescription: title) {
            image = symbol
            imageScaling = .scaleProportionallyDown
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class AssistantWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
private final class AssistantWindowController: NSWindowController, NSTextFieldDelegate {
    private enum AssistantState {
        case idle
        case thinking
        case success
        case refining
    }

    private enum Layout {
        static let width: CGFloat = 640
        static let height: CGFloat = 86
        static let marginX: CGFloat = 4
        static let inputY: CGFloat = 4
        static let inputWidth: CGFloat = 632
        static let inputHeight: CGFloat = 78
        static let rowHeight: CGFloat = 44
        static let rowY: CGFloat = inputY + (inputHeight - rowHeight) / 2
        static let sideInset: CGFloat = 18
        static let sideControlSize: CGFloat = 44
        static let iconX: CGFloat = marginX + sideInset
        static let arrowX: CGFloat = marginX + inputWidth - sideInset - sideControlSize
        static let promptX: CGFloat = iconX + sideControlSize + 18
        static let promptWidth: CGFloat = arrowX - promptX - 18
    }

    private let inputWellView = NSView(frame: NSRect(x: Layout.marginX, y: Layout.inputY, width: Layout.inputWidth, height: Layout.inputHeight))
    private let glowView = MagicGlowView(frame: NSRect(x: Layout.marginX - 2, y: Layout.inputY - 2, width: Layout.inputWidth + 4, height: Layout.inputHeight + 4))
    private let panelView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
    private let iconView = NSImageView(frame: NSRect(x: Layout.iconX, y: Layout.rowY, width: Layout.sideControlSize, height: Layout.sideControlSize))
    private let promptField = PromptTextField(frame: NSRect(x: Layout.promptX, y: Layout.rowY, width: Layout.promptWidth, height: Layout.rowHeight))
    private let placeholderLabel = NSTextField(labelWithString: "Describe your widget...")
    private let arrowButton = NSButton(frame: NSRect(x: Layout.arrowX, y: Layout.rowY, width: Layout.sideControlSize, height: Layout.sideControlSize))
    private let statusLabel = NSTextField(labelWithString: "Describe your widget...")
    private let contextLabel = NSTextField(labelWithString: "")
    private let exitContextButton = NSButton(title: "Exit context", target: nil, action: nil)
    private let tryLabel = NSTextField(labelWithString: "TRY")
    private var chipButtons: [NSButton] = []
    private let settingsButton = PillButton(title: "", imageName: "gearshape", target: nil, action: nil)
    private let countButton = PillButton(title: "0 Active Widgets", imageName: "display", target: nil, action: nil)

    private var assistantState: AssistantState = .idle
    private var activeWidgetName: String?
    private var activeWidgetCount = 0

    var onGenerate: ((String) -> Void)?
    var onSettings: (() -> Void)?

    init() {
        let contentView = NSView()
        let window = AssistantWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.animationBehavior = .none
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.center()

        super.init(window: window)

        buildUI(in: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        promptField.becomeFirstResponder()
    }

    func setBusy(_ busy: Bool) {
        promptField.isEnabled = !busy
        settingsButton.isEnabled = !busy
        if busy {
            assistantState = .thinking
        } else if assistantState == .thinking {
            assistantState = activeWidgetName == nil ? .idle : .refining
        }
        renderState()
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
        if text.hasPrefix("Created ") || text.hasPrefix("Updated ") {
            assistantState = .success
            if let asRange = text.range(of: " as ") {
                let prefixLength = text.hasPrefix("Created ") ? 8 : 8
                activeWidgetName = String(text[text.index(text.startIndex, offsetBy: prefixLength)..<asRange.lowerBound])
            }
            renderState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self, case .success = self.assistantState else {
                    return
                }
                self.assistantState = .refining
                self.promptField.stringValue = ""
                self.renderState()
                self.promptField.becomeFirstResponder()
            }
        }
    }

    func setWidgetCount(_ count: Int) {
        activeWidgetCount = count
        countButton.title = "\(count) Active Widgets"
    }

    private func buildUI(in contentView: NSView) {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        panelView.autoresizingMask = [.width, .height]
        panelView.wantsLayer = true
        panelView.layer?.backgroundColor = NSColor.clear.cgColor

        contentView.addSubview(panelView)
        inputWellView.wantsLayer = true
        inputWellView.layer?.cornerRadius = 22
        inputWellView.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.88).cgColor
        inputWellView.layer?.borderWidth = 1
        inputWellView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        panelView.addSubview(inputWellView)
        panelView.addSubview(glowView)

        contextLabel.frame = .zero
        contextLabel.font = .systemFont(ofSize: 12, weight: .medium)
        contextLabel.textColor = .systemTeal
        contextLabel.isHidden = true

        exitContextButton.frame = .zero
        exitContextButton.font = .systemFont(ofSize: 11, weight: .medium)
        exitContextButton.bezelStyle = .inline
        exitContextButton.isBordered = false
        exitContextButton.contentTintColor = .secondaryLabelColor
        exitContextButton.target = self
        exitContextButton.action = #selector(exitContext)
        exitContextButton.isHidden = true

        iconView.imageAlignment = .alignCenter
        iconView.imageScaling = .scaleNone
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iconView.contentTintColor = .secondaryLabelColor
        panelView.addSubview(iconView)

        placeholderLabel.frame = promptField.frame
        placeholderLabel.cell = VerticallyCenteredTextFieldCell(textCell: placeholderLabel.stringValue)
        placeholderLabel.font = .systemFont(ofSize: 24, weight: .light)
        placeholderLabel.textColor = NSColor(white: 0.66, alpha: 1)
        placeholderLabel.alignment = .left
        placeholderLabel.isSelectable = false
        placeholderLabel.isEditable = false
        placeholderLabel.isBordered = false
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.isHidden = true

        promptField.cell = VerticallyCenteredTextFieldCell(textCell: "")
        promptField.font = .systemFont(ofSize: 24, weight: .light)
        promptField.textColor = .white
        promptField.placeholderString = "Describe your widget..."
        promptField.alignment = .left
        promptField.backgroundColor = .clear
        promptField.isBordered = false
        promptField.isEditable = true
        promptField.isSelectable = true
        promptField.focusRingType = .none
        promptField.delegate = self
        if let cell = promptField.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.wraps = false
            cell.isScrollable = true
        }
        promptField.onSubmit = { [weak self] in
            self?.generate()
        }
        panelView.addSubview(promptField)

        arrowButton.isBordered = false
        arrowButton.wantsLayer = true
        arrowButton.layer?.cornerRadius = 14
        arrowButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        let arrowSymbol = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Generate")
        arrowButton.image = arrowSymbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        arrowButton.imagePosition = .imageOnly
        arrowButton.imageScaling = .scaleNone
        arrowButton.contentTintColor = NSColor(white: 0.82, alpha: 1)
        arrowButton.target = self
        arrowButton.action = #selector(generate)
        panelView.addSubview(arrowButton)

        tryLabel.frame = .zero
        tryLabel.font = .systemFont(ofSize: 10, weight: .bold)
        tryLabel.textColor = NSColor(white: 0.45, alpha: 1)

        chipButtons = [
            ("Weather", "Weather in Top Right"),
            ("Pomodoro", "Minimalist Pomodoro Timer"),
            ("Spotify", "Spotify Control Widget")
        ].map { title, prompt in
            makeChip(title, prompt: prompt, x: 0)
        }

        statusLabel.frame = promptField.frame
        statusLabel.cell = VerticallyCenteredTextFieldCell(textCell: statusLabel.stringValue)
        statusLabel.font = .systemFont(ofSize: 24, weight: .light)
        statusLabel.textColor = NSColor(white: 0.72, alpha: 1)
        statusLabel.alignment = .left
        statusLabel.isHidden = true
        panelView.addSubview(statusLabel)

        settingsButton.frame = .zero
        settingsButton.layer?.cornerRadius = 10
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)

        countButton.frame = .zero
        countButton.isHidden = true

        renderState()
    }

    private func makeChip(_ title: String, prompt: String, x: CGFloat) -> NSButton {
        let button = PillButton(title: title, target: self, action: #selector(useChip(_:)))
        button.frame = NSRect(x: x, y: 12, width: max(74, CGFloat(title.count * 8 + 26)), height: 28)
        button.identifier = NSUserInterfaceItemIdentifier(prompt)
        return button
    }

    private func renderState() {
        let isThinking = assistantState == .thinking
        glowView.setActive(isThinking)
        arrowButton.isHidden = isThinking || assistantState == .success
        promptField.isHidden = isThinking
        statusLabel.isHidden = !isThinking && assistantState != .success

        switch assistantState {
        case .idle:
            iconView.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "North Star")
            iconView.contentTintColor = promptField.stringValue.isEmpty
                ? NSColor(white: 0.70, alpha: 1)
                : NSColor(calibratedRed: 0.70, green: 0.86, blue: 1.0, alpha: 1)
            promptField.placeholderString = "Describe your widget..."
            statusLabel.stringValue = ""
            showChips(true)
            showContext(false)
            countButton.isHidden = true
        case .thinking:
            iconView.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "North Star")
            iconView.contentTintColor = .white
            statusLabel.stringValue = "Crafting widget elegantly..."
            showChips(false)
            showContext(activeWidgetName != nil)
            countButton.isHidden = true
        case .success:
            iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")
            iconView.contentTintColor = .systemGreen
            statusLabel.stringValue = "Widget created."
            showChips(false)
            showContext(activeWidgetName != nil)
            countButton.isHidden = true
        case .refining:
            iconView.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "North Star")
            iconView.contentTintColor = NSColor(calibratedRed: 0.55, green: 0.92, blue: 0.86, alpha: 1)
            promptField.placeholderString = "How should I tweak this widget?"
            statusLabel.stringValue = "Refine the current widget, or exit context."
            showChips(false)
            showContext(activeWidgetName != nil)
            countButton.isHidden = true
        }
        syncPlaceholderVisibility()
        updateInsertionPointVisibility()
    }

    private func syncPlaceholderVisibility() {
        placeholderLabel.isHidden = true
    }

    private func updateInsertionPointVisibility() {
        guard let editor = window?.fieldEditor(false, for: promptField) as? NSTextView else {
            return
        }
        editor.insertionPointColor = .controlAccentColor
    }

    private func showChips(_ visible: Bool) {
        let shouldShow = visible && promptField.stringValue.isEmpty
        tryLabel.isHidden = !shouldShow
        chipButtons.forEach { $0.isHidden = !shouldShow }
    }

    private func showContext(_ visible: Bool) {
        contextLabel.isHidden = !visible
        exitContextButton.isHidden = !visible
        if visible {
            contextLabel.stringValue = "Editing: \(activeWidgetName ?? "Widget")"
        }
    }

    @objc private func generate() {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            setStatus("Type the widget you want first.")
            return
        }
        onGenerate?(prompt)
    }

    @objc private func useChip(_ sender: NSButton) {
        promptField.stringValue = sender.identifier?.rawValue ?? sender.title
        renderState()
        promptField.becomeFirstResponder()
    }

    @objc private func exitContext() {
        activeWidgetName = nil
        assistantState = .idle
        promptField.stringValue = ""
        renderState()
        promptField.becomeFirstResponder()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    func controlTextDidChange(_ obj: Notification) {
        renderState()
        updateInsertionPointVisibility()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        updateInsertionPointVisibility()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        updateInsertionPointVisibility()
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    private let settingsStore: WidgetDeskSettingsStore
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init(settingsStore: WidgetDeskSettingsStore) {
        self.settingsStore = settingsStore

        let contentView = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WidgetDesk Settings"
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()

        super.init(window: window)

        buildUI(in: contentView)
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        loadValues()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI(in contentView: NSView) {
        contentView.wantsLayer = true

        let titleLabel = NSTextField(labelWithString: "OpenAI-compatible provider")
        titleLabel.frame = NSRect(x: 28, y: 246, width: 464, height: 28)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let baseLabel = NSTextField(labelWithString: "Base URL")
        let modelLabel = NSTextField(labelWithString: "Model")
        let keyLabel = NSTextField(labelWithString: "API Key")
        baseLabel.frame = NSRect(x: 28, y: 199, width: 86, height: 20)
        modelLabel.frame = NSRect(x: 28, y: 157, width: 86, height: 20)
        keyLabel.frame = NSRect(x: 28, y: 115, width: 86, height: 20)
        [baseLabel, modelLabel, keyLabel].forEach {
            $0.autoresizingMask = [.maxXMargin, .minYMargin]
            $0.font = .systemFont(ofSize: 13, weight: .medium)
            $0.textColor = .secondaryLabelColor
        }

        baseURLField.frame = NSRect(x: 126, y: 195, width: 366, height: 24)
        modelField.frame = NSRect(x: 126, y: 153, width: 366, height: 24)
        apiKeyField.frame = NSRect(x: 126, y: 111, width: 366, height: 24)
        [baseURLField, modelField, apiKeyField].forEach {
            $0.autoresizingMask = [.width, .minYMargin]
        }

        baseURLField.placeholderString = "https://api.openai.com/v1"
        modelField.placeholderString = "gpt-4.1-mini"
        apiKeyField.placeholderString = "sk-..."

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: 414, y: 28, width: 78, height: 32)
        saveButton.autoresizingMask = [.minXMargin, .maxYMargin]
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        statusLabel.frame = NSRect(x: 28, y: 34, width: 370, height: 18)
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let fields: [(NSTextField, NSView)] = [
            (baseLabel, baseURLField),
            (modelLabel, modelField),
            (keyLabel, apiKeyField)
        ]

        [titleLabel, statusLabel, saveButton].forEach {
            contentView.addSubview($0)
        }
        fields.forEach { label, field in
            contentView.addSubview(label)
            contentView.addSubview(field)
        }
    }

    private func loadValues() {
        do {
            let settings = try settingsStore.load()
            baseURLField.stringValue = settings.baseURL
            modelField.stringValue = settings.model
            apiKeyField.stringValue = try settingsStore.loadAPIKey()
            statusLabel.stringValue = "API key is stored in macOS Keychain."
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func save() {
        do {
            let settings = WidgetDeskLLMSettings(
                baseURL: baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try settingsStore.save(settings)
            try settingsStore.saveAPIKey(apiKeyField.stringValue)
            statusLabel.stringValue = "Saved."
        } catch let error as CustomStringConvertible {
            statusLabel.stringValue = error.description
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }
}

@MainActor
private final class WidgetDeskHostApp {
    private let store = WidgetStore()
    private let settingsStore = WidgetDeskSettingsStore()
    private var controllers: [WidgetWindowController] = []
    private var applicationMenu: ApplicationMenuController?
    private var menuBar: MenuBarController?
    private var assistantWindow: AssistantWindowController?
    private var settingsWindow: SettingsWindowController?
    private var timer: Timer?
    private var lastSignature = ""
    private var isGenerating = false

    func start() throws {
        try store.ensureBaseDirectories()

        let applicationMenu = ApplicationMenuController()
        applicationMenu.onNewWidget = { [weak self] in
            self?.showAssistant()
        }
        applicationMenu.onSettings = { [weak self] in
            self?.showSettings()
        }
        applicationMenu.onToggleWidgetVisibility = { [weak self] id, visible in
            self?.setWidgetVisibility(id: id, visible: visible)
        }
        self.applicationMenu = applicationMenu

        let menuBar = MenuBarController()
        menuBar.onReload = { [weak self] in
            self?.reloadWidgets()
        }
        menuBar.onNewWidget = { [weak self] in
            self?.showAssistant()
        }
        menuBar.onSettings = { [weak self] in
            self?.showSettings()
        }
        menuBar.onToggleWidgetVisibility = { [weak self] id, visible in
            self?.setWidgetVisibility(id: id, visible: visible)
        }
        self.menuBar = menuBar
        reloadWidgets()

        DispatchQueue.main.async { [weak self] in
            self?.showAssistant()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadIfNeeded()
            }
        }
    }

    private func showAssistant() {
        let assistant = assistantWindow ?? AssistantWindowController()
        assistant.onGenerate = { [weak self, weak assistant] prompt in
            self?.generateWidget(prompt: prompt, assistant: assistant)
        }
        assistant.onSettings = { [weak self] in
            self?.showSettings()
        }
        assistantWindow = assistant
        assistant.show()
    }

    private func showSettings() {
        let settings = settingsWindow ?? SettingsWindowController(settingsStore: settingsStore)
        settingsWindow = settings
        settings.show()
    }

    private func generateWidget(prompt: String, assistant: AssistantWindowController?) {
        isGenerating = true
        assistant?.setBusy(true)
        assistant?.setStatus("Generating widget...")

        Task {
            defer {
                isGenerating = false
            }
            do {
                let result = try await WidgetDeskToolAgent(settingsStore: settingsStore, store: store).run(prompt: prompt)
                reloadWidgets()
                assistant?.setBusy(false)
                let changed = result.changedWidgetIDs.first ?? "widget"
                assistant?.setStatus("Updated \(changed) as \(changed).")
            } catch let error as CustomStringConvertible {
                assistant?.setBusy(false)
                assistant?.setStatus(error.description)
            } catch {
                assistant?.setBusy(false)
                assistant?.setStatus(error.localizedDescription)
            }
        }
    }

    private func reloadIfNeeded() {
        guard !isGenerating else {
            return
        }
        do {
            let signature = try store.snapshotSignature()
            guard signature != lastSignature else {
                return
            }
            reloadWidgets(signature: signature)
        } catch {
            NSLog("WidgetDesk reload check failed: \(error.localizedDescription)")
        }
    }

    private func reloadWidgets(signature: String? = nil) {
        do {
            let nextSignature = try signature ?? store.snapshotSignature()
            controllers.forEach { $0.close() }
            let widgets = try store.loadWidgets(includeHidden: true)
            controllers = widgets
                .filter(\.manifest.visible)
                .map { WidgetWindowController(widget: $0, store: store) }
            controllers.forEach { $0.show() }
            assistantWindow?.setWidgetCount(controllers.count)
            let manifests = widgets.map(\.manifest)
            applicationMenu?.setWidgets(manifests)
            menuBar?.setWidgets(manifests)
            lastSignature = nextSignature
        } catch {
            NSLog("WidgetDesk reload failed: \(error.localizedDescription)")
        }
    }

    private func setWidgetVisibility(id: String, visible: Bool) {
        do {
            _ = try store.setVisibility(id: id, visible: visible)
            reloadWidgets()
        } catch {
            NSLog("WidgetDesk visibility update failed: \(error.localizedDescription)")
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

do {
    let host = WidgetDeskHostApp()
    try host.start()
    withExtendedLifetime(host) {
        app.run()
    }
} catch {
    NSAlert(error: error).runModal()
    exit(1)
}
