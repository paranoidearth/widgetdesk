import Foundation

public enum WidgetDeskPaths {
    public static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WidgetDesk", isDirectory: true)
    }()

    public static let widgets = appSupport.appendingPathComponent("widgets", isDirectory: true)
    public static let sessions = appSupport.appendingPathComponent("sessions", isDirectory: true)
    public static let sampleWidget = widgets.appendingPathComponent("sample-clock", isDirectory: true)
}

public enum WidgetAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft = "top-left"
    case topCenter = "top-center"
    case topRight = "top-right"
    case centerLeft = "center-left"
    case center = "center"
    case centerRight = "center-right"
    case bottomLeft = "bottom-left"
    case bottomCenter = "bottom-center"
    case bottomRight = "bottom-right"
}

public struct WidgetManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var entry: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var interactive: Bool
    public var visible: Bool
    public var anchor: WidgetAnchor?

    public init(
        id: String,
        name: String,
        entry: String = "index.html",
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        interactive: Bool,
        visible: Bool = true,
        anchor: WidgetAnchor? = nil
    ) {
        self.id = id
        self.name = name
        self.entry = entry
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.interactive = interactive
        self.visible = visible
        self.anchor = anchor
    }
}

public struct WidgetInstance: Equatable, Sendable {
    public var directory: URL
    public var manifest: WidgetManifest

    public var entryURL: URL {
        directory.appendingPathComponent(manifest.entry)
    }
}

public enum WidgetDeskError: Error, CustomStringConvertible {
    case invalidWidgetID(String)
    case missingWidget(String)
    case missingManifest(URL)
    case missingEntry(URL)
    case installSourceMissing(URL)
    case installDestinationExists(URL)
    case unsafeInstallSource(URL)
    case unknownTemplate(String)
    case unsupportedPrompt(String)

    public var description: String {
        switch self {
        case .invalidWidgetID(let id):
            return "Invalid widget id: \(id)"
        case .missingWidget(let id):
            return "Widget not found: \(id)"
        case .missingManifest(let url):
            return "Missing widget manifest: \(url.path)"
        case .missingEntry(let url):
            return "Missing widget entry: \(url.path)"
        case .installSourceMissing(let url):
            return "Install source does not exist: \(url.path)"
        case .installDestinationExists(let url):
            return "Install destination already exists: \(url.path)"
        case .unsafeInstallSource(let url):
            return "Install source must be a local directory: \(url.path)"
        case .unknownTemplate(let name):
            return "Unknown widget template: \(name)"
        case .unsupportedPrompt(let prompt):
            return "I could not map this prompt to a WidgetDesk action: \(prompt)"
        }
    }
}

public struct WidgetStore: Sendable {
    public init() {}

    public func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(at: WidgetDeskPaths.widgets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: WidgetDeskPaths.sessions, withIntermediateDirectories: true)
    }

    public func ensureSampleWidget() throws {
        try ensureBaseDirectories()
        let sample = WidgetTemplate.sampleClock.draft(id: "sample-clock", prompt: "sample clock")
        try createWidget(from: sample, overwrite: false)
    }

    public func loadWidgets(includeHidden: Bool = false) throws -> [WidgetInstance] {
        try ensureBaseDirectories()
        let directories = try FileManager.default.contentsOfDirectory(
            at: WidgetDeskPaths.widgets,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return try directories.compactMap { directory in
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                return nil
            }

            let manifest = try? loadManifest(in: directory)
            guard let manifest else {
                return nil
            }

            if !includeHidden && !manifest.visible {
                return nil
            }

            let instance = WidgetInstance(directory: directory, manifest: manifest)
            guard FileManager.default.fileExists(atPath: instance.entryURL.path) else {
                return nil
            }

            return instance
        }.sorted { $0.manifest.id < $1.manifest.id }
    }

    public func loadManifest(in directory: URL) throws -> WidgetManifest {
        let manifestURL = directory.appendingPathComponent("widget.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw WidgetDeskError.missingManifest(manifestURL)
        }

        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(WidgetManifest.self, from: data)
    }

    public func writeManifest(_ manifest: WidgetManifest, in directory: URL) throws {
        try validateWidgetID(manifest.id)
        let data = try JSONEncoder.widgetDesk.encode(manifest)
        try data.write(to: directory.appendingPathComponent("widget.json"), options: [.atomic])
    }

    public func findWidget(_ id: String) throws -> WidgetInstance {
        try validateWidgetID(id)
        guard let widget = try loadWidgets(includeHidden: true).first(where: { $0.manifest.id == id }) else {
            throw WidgetDeskError.missingWidget(id)
        }
        return widget
    }

    public func installWidget(from source: URL, overwrite: Bool = false) throws -> WidgetInstance {
        guard source.isFileURL else {
            throw WidgetDeskError.unsafeInstallSource(source)
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WidgetDeskError.installSourceMissing(source)
        }

        let manifest = try loadManifest(in: source)
        try validateWidgetID(manifest.id)
        let entry = source.appendingPathComponent(manifest.entry)
        guard FileManager.default.fileExists(atPath: entry.path) else {
            throw WidgetDeskError.missingEntry(entry)
        }

        try ensureBaseDirectories()
        let destination = WidgetDeskPaths.widgets.appendingPathComponent(manifest.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard overwrite else {
                throw WidgetDeskError.installDestinationExists(destination)
            }
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: source, to: destination)
        return WidgetInstance(directory: destination, manifest: manifest)
    }

    @discardableResult
    public func createWidget(from draft: WidgetDraft, overwrite: Bool = true) throws -> WidgetInstance {
        try validateWidgetID(draft.manifest.id)
        try ensureBaseDirectories()

        let directory = WidgetDeskPaths.widgets.appendingPathComponent(draft.manifest.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            guard overwrite else {
                return try findWidget(draft.manifest.id)
            }
            try FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeManifest(draft.manifest, in: directory)
        try draft.html.write(to: directory.appendingPathComponent(draft.manifest.entry), atomically: true, encoding: .utf8)
        return WidgetInstance(directory: directory, manifest: draft.manifest)
    }

    public func setVisibility(id: String, visible: Bool) throws -> WidgetInstance {
        let widget = try findWidget(id)
        var manifest = widget.manifest
        manifest.visible = visible
        try writeManifest(manifest, in: widget.directory)
        return WidgetInstance(directory: widget.directory, manifest: manifest)
    }

    public func deleteWidget(id: String) throws {
        let widget = try findWidget(id)
        try FileManager.default.removeItem(at: widget.directory)
    }

    public func snapshotSignature() throws -> String {
        try ensureBaseDirectories()
        let widgets = try loadWidgets(includeHidden: true)
        return try widgets.map { widget in
            let manifestURL = widget.directory.appendingPathComponent("widget.json")
            let manifestDate = try manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970 ?? 0
            let entryDate = try widget.entryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970 ?? 0
            return "\(widget.manifest.id):\(widget.manifest.visible):\(manifestDate):\(entryDate)"
        }.joined(separator: "|")
    }

    private func validateWidgetID(_ id: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !id.isEmpty, id.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw WidgetDeskError.invalidWidgetID(id)
        }
    }
}

extension JSONEncoder {
    static var widgetDesk: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
