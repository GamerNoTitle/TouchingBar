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
    public var disableAnimations: Bool?
    public var menuBar: MenuBarSettings
    public var messages: MessageSettings
    public var webDAV: WebDAVSettings
    public var lyricsOffset: Double?
    public var metricsHistorySeconds: Int?
    public var batteryComponentsMigrated: Bool?
    public var showAgentNotifications: Bool?
    public var presets: [TouchBarPreset]

    public init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        id: UUID = UUID(),
        activePresetID: UUID? = nil,
        alwaysOccupyTouchBar: Bool = true,
        hideTouchBarCloseButton: Bool = true,
        silentLaunch: Bool = true,
        disableAnimations: Bool = false,
        menuBar: MenuBarSettings = MenuBarSettings(),
        messages: MessageSettings = MessageSettings(),
        webDAV: WebDAVSettings = WebDAVSettings(),
        lyricsOffset: Double = 0,
        metricsHistorySeconds: Int = 30,
        batteryComponentsMigrated: Bool? = nil,
        showAgentNotifications: Bool = true,
        presets: [TouchBarPreset] = BuiltInPresets.make()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.activePresetID = activePresetID
        self.alwaysOccupyTouchBar = alwaysOccupyTouchBar
        self.hideTouchBarCloseButton = hideTouchBarCloseButton
        self.silentLaunch = silentLaunch
        self.disableAnimations = disableAnimations
        self.menuBar = menuBar
        self.messages = messages
        self.webDAV = webDAV
        self.lyricsOffset = lyricsOffset
        self.metricsHistorySeconds = metricsHistorySeconds
        self.batteryComponentsMigrated = batteryComponentsMigrated
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

    public var effectiveDisableAnimations: Bool {
        get { disableAnimations ?? false }
        set { disableAnimations = newValue }
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
        removeRetiredPresets()
        migrateBatteryComponents()
        migrateDeveloperPresetToolchains()
        migrateSystemFunctionPreset()
        migrateCustomPresetContent()
        normalizeCustomItemWidths()
        if presets.isEmpty {
            presets = BuiltInPresets.make()
        }
        if activePresetID == nil || !presets.contains(where: { $0.id == activePresetID }) {
            activePresetID = presets.first?.id
        }
    }

    public mutating func restoreMissingBuiltInPresets() {
        for builtIn in BuiltInPresets.make() where !presets.contains(where: { $0.kind == builtIn.kind }) {
            presets.append(builtIn)
        }
        normalize()
    }

    private mutating func migrateBatteryComponents() {
        guard batteryComponentsMigrated != true else { return }
        batteryComponentsMigrated = true
        guard let presetIndex = presets.firstIndex(where: { $0.kind == .metrics }) else { return }
        let existingKeys = Set(presets[presetIndex].items.compactMap(\.contextKey))
        let batteryItems = BuiltInPresets.metrics().items.filter {
            guard let key = $0.contextKey else { return false }
            return ["battery", "batteryPower", "batteryTime"].contains(key)
        }
        for item in batteryItems where !existingKeys.contains(item.contextKey ?? "") {
            presets[presetIndex].items.append(item)
        }
    }

    private mutating func removeRetiredPresets() {
        let retiredKinds: Set<PresetKind> = [.agents, .messages]
        let retiredContextKeys: Set<String> = [
            "provider", "task", "status", "detail", "duration", "sessions", "event", "tool", "cwd",
            "message", "unreadSummary", "latestMessage", "messageBadges"
        ]
        presets.removeAll { retiredKinds.contains($0.kind) }
        for index in presets.indices {
            presets[index].items.removeAll { item in
                guard let key = item.contextKey else { return false }
                return retiredContextKeys.contains(key)
            }
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

            guard presets[presetIndex].items.count >= 6 else { continue }
            let f5 = presets[presetIndex].items[4]
            let f6 = presets[presetIndex].items[5]
            let oldBacklightOrder = f5.action.kind == .keyboardBacklight
                && f5.action.value == "on"
                && f6.action.kind == .keyboardBacklight
                && f6.action.value == "off"
            if oldBacklightOrder,
               var newF5 = replacements["F5"],
               var newF6 = replacements["F6"] {
                newF5.id = f5.id
                newF6.id = f6.id
                presets[presetIndex].items[4] = newF5
                presets[presetIndex].items[5] = newF6
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
