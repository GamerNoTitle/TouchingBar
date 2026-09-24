import Foundation

public final class RuntimeContextStore: @unchecked Sendable {
    public static let shared = RuntimeContextStore()

    public let fileURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = applicationSupport
                .appendingPathComponent("TouchingBar", isDirectory: true)
                .appendingPathComponent("runtime-context.json", isDirectory: false)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> RuntimeContextSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    public func save(_ snapshot: RuntimeContextSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveUnlocked(snapshot)
    }

    @discardableResult
    public func update(_ mutation: (inout RuntimeContextSnapshot) -> Void) throws -> RuntimeContextSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var snapshot = loadUnlocked()
        mutation(&snapshot)
        if snapshot.messages.count > 100 {
            snapshot.messages = Array(snapshot.messages.prefix(100))
        }
        try saveUnlocked(snapshot)
        return snapshot
    }

    private func loadUnlocked() -> RuntimeContextSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              var snapshot = try? decoder.decode(RuntimeContextSnapshot.self, from: data) else {
            return RuntimeContextSnapshot()
        }
        snapshot.pruneStaleAgents()
        return snapshot
    }

    private func saveUnlocked(_ snapshot: RuntimeContextSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }
}
