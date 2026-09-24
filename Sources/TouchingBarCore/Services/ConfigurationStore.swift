import Foundation

public enum ConfigurationStoreError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "备份文件版本 \(version) 暂不受支持。"
        case .invalidConfiguration:
            return "配置文件内容无效。"
        }
    }
}

public final class ConfigurationStore: @unchecked Sendable {
    public static let shared = ConfigurationStore()

    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = applicationSupport
                .appendingPathComponent("TouchingBar", isDirectory: true)
                .appendingPathComponent("config.json", isDirectory: false)
        }

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            var configuration = AppConfiguration()
            configuration.normalize()
            return configuration
        }
        let data = try Data(contentsOf: fileURL)
        let rawConfiguration: AppConfiguration
        do {
            rawConfiguration = try decoder.decode(AppConfiguration.self, from: data)
        } catch {
            throw ConfigurationStoreError.invalidConfiguration
        }
        guard rawConfiguration.schemaVersion <= AppConfiguration.currentSchemaVersion else {
            throw ConfigurationStoreError.unsupportedSchema(rawConfiguration.schemaVersion)
        }
        var normalized = rawConfiguration
        normalized.normalize()
        if normalized != rawConfiguration {
            try save(normalized)
        }
        return normalized
    }

    public func save(_ configuration: AppConfiguration) throws {
        var normalized = configuration
        normalized.normalize()
        let data = try encoder.encode(normalized)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    public func export(_ configuration: AppConfiguration) throws -> Data {
        try encoder.encode(configuration)
    }

    public func decode(_ data: Data) throws -> AppConfiguration {
        let configuration: AppConfiguration
        do {
            configuration = try decoder.decode(AppConfiguration.self, from: data)
        } catch {
            throw ConfigurationStoreError.invalidConfiguration
        }
        guard configuration.schemaVersion <= AppConfiguration.currentSchemaVersion else {
            throw ConfigurationStoreError.unsupportedSchema(configuration.schemaVersion)
        }
        var normalized = configuration
        normalized.normalize()
        return normalized
    }
}
