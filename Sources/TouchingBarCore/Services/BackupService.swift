import Foundation

public struct ConfigurationBackup: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var configuration: AppConfiguration

    public init(
        formatVersion: Int = ConfigurationBackup.currentFormatVersion,
        exportedAt: Date = Date(),
        configuration: AppConfiguration
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.configuration = configuration
    }
}

public enum BackupError: Error, LocalizedError {
    case unsupportedFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let version):
            return "备份格式版本 \(version) 暂不受支持。"
        }
    }
}

public struct BackupService: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func encode(configuration: AppConfiguration) throws -> Data {
        try encoder.encode(ConfigurationBackup(configuration: configuration))
    }

    public func decode(_ data: Data) throws -> AppConfiguration {
        let backup = try decoder.decode(ConfigurationBackup.self, from: data)
        guard backup.formatVersion <= ConfigurationBackup.currentFormatVersion else {
            throw BackupError.unsupportedFormat(backup.formatVersion)
        }
        var configuration = backup.configuration
        configuration.normalize()
        return configuration
    }
}
