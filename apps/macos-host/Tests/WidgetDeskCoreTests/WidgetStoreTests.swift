import Foundation
import Testing
@testable import WidgetDeskCore

@Suite("WidgetStore")
struct WidgetStoreTests {
    @Test("creates, lists, hides, shows, and deletes widgets in an injected directory")
    func widgetLifecycle() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let draft = WidgetTemplate.clock.draft(id: "desk-clock", prompt: "clock")
        let created = try fixture.store.createWidget(from: draft)
        #expect(created.manifest.id == "desk-clock")
        #expect(FileManager.default.fileExists(atPath: created.entryURL.path))

        #expect(try fixture.store.loadWidgets().map(\.manifest.id) == ["desk-clock"])

        let hidden = try fixture.store.setVisibility(id: "desk-clock", visible: false)
        #expect(hidden.manifest.visible == false)
        #expect(try fixture.store.loadWidgets().isEmpty)
        #expect(try fixture.store.loadWidgets(includeHidden: true).count == 1)

        let shown = try fixture.store.setVisibility(id: "desk-clock", visible: true)
        #expect(shown.manifest.visible == true)

        try fixture.store.deleteWidget(id: "desk-clock")
        #expect(try fixture.store.loadWidgets(includeHidden: true).isEmpty)
    }

    @Test("rejects invalid widget identifiers before writing files")
    func invalidWidgetID() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let draft = WidgetTemplate.memo.draft(id: "../bad", prompt: "bad")
        #expect(throws: WidgetDeskError.self) {
            try fixture.store.createWidget(from: draft)
        }
        #expect(try fixture.store.loadWidgets(includeHidden: true).isEmpty)
    }

    @Test("installs a complete widget directory")
    func installWidgetDirectory() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let source = fixture.root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manifest = WidgetManifest(
            id: "installed-widget",
            name: "Installed Widget",
            x: 20,
            y: 30,
            width: 240,
            height: 120,
            interactive: false
        )
        try fixture.store.writeManifest(manifest, in: source)
        try "<!doctype html><title>Installed</title>".write(
            to: source.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )

        let installed = try fixture.store.installWidget(from: source)
        #expect(installed.manifest.id == "installed-widget")
        #expect(installed.directory.deletingLastPathComponent() == fixture.paths.widgets)
    }
}

@Suite("WidgetDeskAgent")
struct WidgetDeskAgentTests {
    @Test("maps natural-language prompts to widget actions")
    func promptPlanning() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let agent = WidgetDeskAgent(store: fixture.store)
        let create = try agent.run(prompt: "add a clock on the top left")
        #expect(create.widgets.first?.id == "clock")
        #expect(create.widgets.first?.anchor == .topLeft)

        let hide = try agent.run(prompt: "hide clock")
        #expect(hide.widgets.first?.visible == false)

        let show = try agent.run(prompt: "show clock")
        #expect(show.widgets.first?.visible == true)

        let list = try agent.run(prompt: "list widgets")
        #expect(list.message.contains("clock visible"))

        let path = try agent.run(prompt: "path")
        #expect(path.message == fixture.paths.widgets.path)
    }
}

private struct TestFixture {
    let root: URL
    let paths: WidgetDeskPathSet
    let store: WidgetStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetDeskTests-\(UUID().uuidString)", isDirectory: true)
        paths = WidgetDeskPathSet(appSupport: root)
        store = WidgetStore(paths: paths)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
