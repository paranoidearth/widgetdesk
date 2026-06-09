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

@Suite("WidgetComponentValidator")
struct WidgetComponentValidatorTests {
    @Test("accepts complete local HTML widgets")
    func acceptsValidWidget() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        try fixture.writeWidget(
            id: "valid-widget",
            html: """
            <!doctype html>
            <html>
            <head><meta charset="utf-8"><style>body { margin: 0; background: transparent; }</style></head>
            <body><main class="card">Ready</main></body>
            </html>
            """
        )

        let report = WidgetComponentValidator(store: fixture.store).validate(ids: ["valid-widget"])
        #expect(report.isReady)
        #expect(report.validIDs == ["valid-widget"])
        #expect(report.issues.isEmpty)
    }

    @Test("rejects external resources in generated HTML")
    func rejectsExternalResources() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        try fixture.writeWidget(
            id: "remote-widget",
            html: """
            <!doctype html>
            <html>
            <body><script src="https://cdn.example.com/app.js"></script></body>
            </html>
            """
        )

        let report = WidgetComponentValidator(store: fixture.store).validate(ids: ["remote-widget"])
        #expect(!report.isReady)
        #expect(report.issues.contains { $0.contains("must not load external") })
    }

    @Test("rejects missing entry files")
    func rejectsMissingEntryFile() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let directory = fixture.paths.widgets.appendingPathComponent("missing-entry", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fixture.store.writeManifest(
            WidgetManifest(
                id: "missing-entry",
                name: "Missing Entry",
                x: 20,
                y: 20,
                width: 240,
                height: 120,
                interactive: false
            ),
            in: directory
        )

        let report = WidgetComponentValidator(store: fixture.store).validate(ids: ["missing-entry"])
        #expect(!report.isReady)
        #expect(report.issues.contains { $0.contains("entry file is missing") })
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

    func writeWidget(id: String, html: String, width: Double = 240, height: Double = 120) throws {
        let directory = paths.widgets.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.writeManifest(
            WidgetManifest(
                id: id,
                name: id,
                x: 20,
                y: 20,
                width: width,
                height: height,
                interactive: false
            ),
            in: directory
        )
        try html.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}
