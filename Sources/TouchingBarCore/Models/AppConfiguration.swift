import Foundation

public struct MenuBarSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}

public struct MessageSettings: Codable, Equatable, Sendable {
    public var showNotificationBanners: Bool
    public var monitoredApplications: [String]

    public init(
        showNotificationBanners: Bool = true,
        monitoredApplications: [String] = [
            "com.tencent.xinWeChat",
            "com.tencent.qq",
            "ru.keepcoder.Telegram",
            "com.tencent.WeWorkMac",
            "com.electron.lark",
            "com.bytedance.lark"
        ]
    ) {
        self.showNotificationBanners = showNotificationBanners
        self.monitoredApplications = monitoredApplications
    }
}

public struct WebDAVSettings: Codable, Equatable, Sendable {
    public var serverURL: String
    public var username: String
    public var remotePath: String

    public init(serverURL: String = "", username: String = "", remotePath: String = "TouchingBar/backup.json") {
        self.serverURL = serverURL
        self.username = username
        self.remotePath = remotePath
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var activePresetID: UUID?
    /// Retained for backward-compatible configuration decoding. While TouchingBar
    /// is running it always occupies the Touch Bar; quitting releases it.
    public var alwaysOccupyTouchBar: Bool
    public var hideTouchBarCloseButton: Bool
    public var silentLaunch: Bool?
    public var menuBar: MenuBarSettings
    public var messages: MessageSettings
    public var webDAV: WebDAVSettings
    public var lyricsOffset: Double?
    public var metricsHistorySeconds: Int?
    public var showAgentNotifications: Bool?
    public var presets: [TouchBarPreset]

    public init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        id: UUID = UUID(),
        activePresetID: UUID? = nil,
        alwaysOccupyTouchBar: Bool = true,
        hideTouchBarCloseButton: Bool = true,
        silentLaunch: Bool = true,
        menuBar: MenuBarSettings = MenuBarSettings(),
        messages: MessageSettings = MessageSettings(),
        webDAV: WebDAVSettings = WebDAVSettings(),
        lyricsOffset: Double = 0,
        metricsHistorySeconds: Int = 30,
        showAgentNotifications: Bool = true,
        presets: [TouchBarPreset] = BuiltInPresets.make()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.activePresetID = activePresetID
        self.alwaysOccupyTouchBar = alwaysOccupyTouchBar
        self.hideTouchBarCloseButton = hideTouchBarCloseButton
        self.silentLaunch = silentLaunch
        self.menuBar = menuBar
        self.messages = messages
        self.webDAV = webDAV
        self.lyricsOffset = lyricsOffset
        self.metricsHistorySeconds = metricsHistorySeconds
        self.showAgentNotifications = showAgentNotifications
        self.presets = presets
        if self.activePresetID == nil {
            self.activePresetID = presets.first?.id
        }
    }

    public var effectiveSilentLaunch: Bool {
        get { silentLaunch ?? true }
        set { silentLaunch = newValue }
    }

    public var effectiveMetricsHistorySeconds: Int {
        get {
            let value = metricsHistorySeconds ?? 30
            return [10, 30, 60, 120, 300, 600].contains(value) ? value : 30
        }
        set { metricsHistorySeconds = newValue }
    }

    public var effectiveShowAgentNotifications: Bool {
        get { showAgentNotifications ?? true }
        set { showAgentNotifications = newValue }
    }

    public var effectiveLyricsOffset: Double {
        get { lyricsOffset ?? 0 }
        set { lyricsOffset = max(-10, min(10, newValue)) }
    }

    public var activePreset: TouchBarPreset? {
        guard let activePresetID else { return presets.first }
        return presets.first(where: { $0.id == activePresetID }) ?? presets.first
    }

    public mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        if presets.isEmpty {
            presets = BuiltInPresets.make()
        }
        ensureBuiltInPresets()
        migrateDeveloperPresetToolchains()
        migrateSystemFunctionPreset()
        migrateAgentPresetContext()
        migrateCustomPresetContent()
        normalizeCustomItemWidths()
        if activePresetID == nil || !presets.contains(where: { $0.id == activePresetID }) {
            activePresetID = presets.first?.id
        }
    }

    private mutating func ensureBuiltInPresets() {
        for builtIn in BuiltInPresets.make() where !presets.contains(where: { $0.kind == builtIn.kind }) {
            presets.append(builtIn)
        }
    }

    private mutating func normalizeCustomItemWidths() {
        for presetIndex in presets.indices {
            for itemIndex in presets[presetIndex].items.indices {
                guard let width = presets[presetIndex].items[itemIndex].customWidth else { continue }
                presets[presetIndex].items[itemIndex].customWidth = max(40, min(1200, width))
            }
        }
    }

    private mutating func migrateCustomPresetContent() {
        for index in presets.indices where presets[index].kind == .custom {
            presets[index].content = .components
        }
    }

    private mutating func migrateAgentPresetContext() {
        let defaults = BuiltInPresets.agents().items
        for index in presets.indices where presets[index].kind == .agents {
            let existingKeys = Set(presets[index].items.compactMap(\.contextKey))
            for item in defaults where item.presentation == .context {
                guard let key = item.contextKey, !existingKeys.contains(key) else { continue }
                var copied = item
                copied.id = UUID()
                presets[index].items.append(copied)
            }
        }
    }

    private mutating func migrateSystemFunctionPreset() {
        let replacements = Dictionary(
            uniqueKeysWithValues: BuiltInPresets.systemFunctions().items.map { ($0.label, $0) }
        )
        for presetIndex in presets.indices where presets[presetIndex].kind == .systemFunctions {
            for itemIndex in presets[presetIndex].items.indices {
                let old = presets[presetIndex].items[itemIndex]
                guard [.spotlight, .dictation, .doNotDisturb].contains(old.action.kind),
                      var replacement = replacements[old.label] else { continue }
                replacement.id = old.id
                presets[presetIndex].items[itemIndex] = replacement
            }
        }
    }

    private mutating func migrateDeveloperPresetToolchains() {
        let defaults = BuiltInPresets.developer().items
        for index in presets.indices where presets[index].kind == .developer {
            let existingKeys = Set(presets[index].items.compactMap(\.contextKey))
            for item in defaults where item.presentation == .context {
                guard let key = item.contextKey, !existingKeys.contains(key) else { continue }
                var copied = item
                copied.id = UUID()
                presets[index].items.append(copied)
            }
        }
    }
}
