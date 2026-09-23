import Foundation

public enum AgentHookProvider: String, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case gemini = "gemini"
    case cursor = "cursor"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .cursor: return "Cursor"
        }
    }

    fileprivate var configRelativePath: String {
        switch self {
        case .claudeCode: return ".claude/settings.json"
        case .codex: return ".codex/hooks.json"
        case .gemini: return ".gemini/settings.json"
        case .cursor: return ".cursor/hooks.json"
        }
    }

    fileprivate var events: [(name: String, matcher: String?)] {
        switch self {
        case .claudeCode:
            return [
                ("SessionStart", nil),
                ("UserPromptSubmit", nil),
                ("PreToolUse", "*"),
                ("PostToolUse", "*"),
                ("PermissionRequest", "*"),
                ("Notification", "*"),
                ("Stop", nil),
                ("SubagentStop", nil),
                ("SessionEnd", nil)
            ]
        case .codex:
            return [
                ("SessionStart", "*"),
                ("UserPromptSubmit", "*"),
                ("PreToolUse", "*"),
                ("PostToolUse", "*"),
                ("PermissionRequest", "*"),
                ("Stop", "*")
            ]
        case .gemini:
            return [
                ("SessionStart", nil),
                ("SessionEnd", nil),
                ("BeforeAgent", nil),
                ("AfterAgent", nil),
                ("BeforeTool", ".*"),
                ("AfterTool", ".*"),
                ("Notification", nil)
            ]
        case .cursor:
            return [
                ("SessionStart", nil),
                ("UserPromptSubmit", nil),
                ("PreToolUse", "*"),
                ("PostToolUse", "*"),
                ("Stop", nil)
            ]
        }
    }
}

public struct AgentHookInstaller: Sendable {
    public static let launcherName = "touchingbar-agent-hook"
    public static let managedMarker = "touchingbar-agent-hook"

    public init() {}

    @discardableResult
    public func install(
        provider: AgentHookProvider,
        controlExecutablePath: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL? = nil
    ) throws -> URL {
        guard controlExecutablePath.hasPrefix("/") else {
            throw AgentHookInstallerError.controlExecutableMustBeAbsolute(controlExecutablePath)
        }
        let supportDirectory = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let launcher = supportDirectory
            .appendingPathComponent("TouchingBar", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(Self.launcherName)
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try launcherScript(controlExecutablePath: controlExecutablePath, provider: provider)
            .write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let configURL = homeDirectory.appendingPathComponent(provider.configRelativePath)
        var root = try loadJSONObject(at: configURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in provider.events {
            var eventEntries = hooks[event.name] as? [[String: Any]] ?? []
            eventEntries.removeAll { entryContainsManagedHook($0) }
            eventEntries.append(makeHookEntry(launcher: launcher, matcher: event.matcher))
            hooks[event.name] = eventEntries
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: configURL)
        return configURL
    }

    public func uninstall(
        provider: AgentHookProvider,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let configURL = homeDirectory.appendingPathComponent(provider.configRelativePath)
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        var root = try loadJSONObject(at: configURL)
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for key in hooks.keys {
            guard var entries = hooks[key] as? [[String: Any]] else { continue }
            entries.removeAll { entryContainsManagedHook($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = entries
            }
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try writeJSONObject(root, to: configURL)
    }

    public func isInstalled(
        provider: AgentHookProvider,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let configURL = homeDirectory.appendingPathComponent(provider.configRelativePath)
        guard let root = try? loadJSONObject(at: configURL),
              let hooks = root["hooks"] else { return false }
        return valueContainsManagedHook(hooks)
    }

    private func launcherScript(
        controlExecutablePath: String,
        provider: AgentHookProvider
    ) -> String {
        let quotedPath = shellQuote(controlExecutablePath)
        return """
        #!/bin/sh
        exec \(quotedPath) agent-event --provider \(provider.rawValue)
        """
    }

    private func makeHookEntry(launcher: URL, matcher: String?) -> [String: Any] {
        let command = shellQuote(launcher.path)
        let hook: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": 86_400
        ]
        if let matcher {
            return ["matcher": matcher, "hooks": [hook]]
        }
        return ["hooks": [hook]]
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    private func entryContainsManagedHook(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            if let command = dictionary["command"] as? String,
               command.contains(Self.managedMarker) {
                return true
            }
            return dictionary.values.contains { entryContainsManagedHook($0) }
        }
        if let array = value as? [Any] {
            return array.contains { entryContainsManagedHook($0) }
        }
        return false
    }

    private func valueContainsManagedHook(_ value: Any) -> Bool {
        if let string = value as? String {
            return string.contains(Self.managedMarker)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains { valueContainsManagedHook($0) }
        }
        if let array = value as? [Any] {
            return array.contains { valueContainsManagedHook($0) }
        }
        return false
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum AgentHookInstallerError: Error, LocalizedError {
    case controlExecutableMustBeAbsolute(String)

    public var errorDescription: String? {
        switch self {
        case .controlExecutableMustBeAbsolute(let path):
            return "TouchingBarCtl 必须使用绝对路径：\(path)"
        }
    }
}
