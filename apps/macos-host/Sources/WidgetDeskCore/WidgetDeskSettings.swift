import Foundation
import Security

public struct WidgetDeskLLMSettings: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String

    public init(
        baseURL: String = "https://api.openai.com/v1",
        model: String = "gpt-4.1-mini"
    ) {
        self.baseURL = baseURL
        self.model = model
    }
}

public enum WidgetDeskSettingsError: Error, CustomStringConvertible {
    case keychainSaveFailed(OSStatus)
    case keychainReadFailed(OSStatus)

    public var description: String {
        switch self {
        case .keychainSaveFailed(let status):
            return "Failed to save API key to Keychain: \(status)"
        case .keychainReadFailed(let status):
            return "Failed to read API key from Keychain: \(status)"
        }
    }
}

public struct WidgetDeskSettingsStore: Sendable {
    private let configURL: URL
    private let service = "WidgetDesk.OpenAICompatible"
    private let account = "default"

    public init(configURL: URL = WidgetDeskPaths.appSupport.appendingPathComponent("llm-config.json")) {
        self.configURL = configURL
    }

    public func load() throws -> WidgetDeskLLMSettings {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return WidgetDeskLLMSettings()
        }

        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(WidgetDeskLLMSettings.self, from: data)
    }

    public func save(_ settings: WidgetDeskLLMSettings) throws {
        try FileManager.default.createDirectory(at: WidgetDeskPaths.appSupport, withIntermediateDirectories: true)
        let data = try JSONEncoder.widgetDesk.encode(settings)
        try data.write(to: configURL, options: [.atomic])
    }

    public func loadAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess else {
            throw WidgetDeskSettingsError.keychainReadFailed(status)
        }
        guard let data = item as? Data else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8)
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WidgetDeskSettingsError.keychainSaveFailed(status)
        }
    }
}
