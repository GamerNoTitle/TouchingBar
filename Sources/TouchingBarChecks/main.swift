import Foundation
import Network
import TouchingBarCore

@main
struct TouchingBarChecks {
    static func main() async throws {
        try checkBuiltInPresets()
        try checkBackupRoundTrip()
        try checkConfigurationNormalization()
        try checkMetricsPresetMigration()
        try checkMetricsHistoryRange()
        try checkSystemFunctionMigration()
        try checkRuntimeFormatting()
        try checkTouchBarLayoutBudget()
        try await checkDeveloperContextProvider()
        try checkAgentHookNormalizer()
        try checkAgentSessionStore()
        try checkShellHookInstaller()
        try checkAgentHookInstaller()
        try await checkWebDAVClient()
        try await checkHookServer()
        print("TouchingBarChecks: all checks passed")
    }

    private static func checkBuiltInPresets() throws {
        let presets = BuiltInPresets.make()
        try expect(presets.map(\.kind) == [
            .functionKeys, .systemFunctions, .developer, .agents, .metrics, .messages, .music
        ], "all built-in presets are present")

        let functionKeys = BuiltInPresets.functionKeys()
        try expect(functionKeys.items.count == 12, "F1-F12 preset has twelve items")
        try expect(functionKeys.items.map(\.label) == (1...12).map { "F\($0)" }, "F1-F12 labels are ordered")
        try expect(functionKeys.items.map { $0.action.value } == (1...12).map(String.init), "F1-F12 actions are ordered")

        let systemItems = BuiltInPresets.systemFunctions().items
        try expect(systemItems[0].action.kind == .brightness && systemItems[0].action.value == "down", "F1 brightness down")
        let music = BuiltInPresets.music()
        try expect(music.items.count == 3, "music preset has three independent media controls")
        try expect(music.items.map(\.action.media) == [.previous, .playPause, .next], "music controls are separate components")
        try expect(systemItems[1].action.kind == .brightness && systemItems[1].action.value == "up", "F2 brightness up")
        try expect(systemItems[2].action.kind == .missionControl, "F3 Mission Control")
        try expect(systemItems[3].action.kind == .lockScreen, "F4 locks the screen")
        try expect(systemItems[4].action.kind == .keyboardBacklight && systemItems[4].action.value == "on", "F5 enables keyboard backlight")
        try expect(systemItems[5].action.kind == .keyboardBacklight && systemItems[5].action.value == "off", "F6 disables keyboard backlight")
        try expect(systemItems[6].action.media == .previous, "F7 previous track")
        try expect(systemItems[7].action.media == .playPause, "F8 play/pause")
        try expect(systemItems[8].action.media == .next, "F9 next track")
        try expect(systemItems[9].action.volume == .mute, "F10 mute")
        try expect(systemItems[10].action.volume == .down, "F11 volume down")
        try expect(systemItems[11].action.volume == .up, "F12 volume up")
    }

    private static func checkBackupRoundTrip() throws {
        let service = BackupService()
        var configuration = AppConfiguration()
        configuration.activePresetID = configuration.presets.last?.id
        configuration.menuBar.isEnabled = false
        configuration.messages.showNotificationBanners = false

        let data = try service.encode(configuration: configuration)
        let restored = try service.decode(data)
        try expect(restored.menuBar == configuration.menuBar, "menu bar setting round-trips")
        try expect(restored.messages == configuration.messages, "message setting round-trips")
        try expect(restored.activePresetID == configuration.activePresetID, "active preset round-trips")
        try expect(restored.presets.map(\.name) == configuration.presets.map(\.name), "presets round-trip")
    }

    private static func checkConfigurationNormalization() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ConfigurationStore(fileURL: file)
        var configuration = AppConfiguration()
        configuration.presets = []
        try store.save(configuration)
        let loaded = try store.load()
        try expect(!loaded.presets.isEmpty, "empty configurations are normalized")
        try expect(loaded.activePresetID == loaded.presets.first?.id, "normalized configuration selects a preset")

        var customConfiguration = AppConfiguration()
        customConfiguration.presets.append(
            TouchBarPreset(name: "Custom", kind: .custom, content: .actions)
        )
        customConfiguration.normalize()
        let custom = customConfiguration.presets.first { $0.kind == .custom }
        try expect(custom?.content == .components, "custom presets migrate to free components")

        var widthConfiguration = AppConfiguration()
        widthConfiguration.presets.append(
            TouchBarPreset(
                name: "Width",
                kind: .custom,
                content: .components,
                items: [
                    TouchBarItemConfiguration(
                        label: "Lyrics",
                        width: .custom,
                        customWidth: 10,
                        presentation: .context,
                        contextKey: "lyric"
                    )
                ]
            )
        )
        widthConfiguration.normalize()
        try expect(
            widthConfiguration.presets.first { $0.kind == .custom }?.items.first?.customWidth == 40,
            "custom item widths are clamped to a safe minimum"
        )
    }

    private static func checkMetricsPresetMigration() throws {
        var configuration = AppConfiguration()
        configuration.presets.removeAll { $0.kind == .metrics }
        configuration.normalize()
        try expect(configuration.presets.contains { $0.kind == .metrics }, "system metrics preset is migrated")
        let metrics = configuration.presets.first { $0.kind == .metrics }
        let keys = Set(metrics?.items.compactMap(\.contextKey) ?? [])
        try expect(keys.isSuperset(of: ["cpu", "gpu", "memory", "disk", "cpuTemperature", "fanRPM", "networkDownload", "networkUpload"]), "metrics preset contains all resource components")
    }

    private static func checkMetricsHistoryRange() throws {
        var configuration = AppConfiguration()
        configuration.metricsHistorySeconds = 600
        try expect(configuration.effectiveMetricsHistorySeconds == 600, "metrics history accepts ten minutes")
        configuration.metricsHistorySeconds = 77
        try expect(configuration.effectiveMetricsHistorySeconds == 30, "invalid metrics history falls back to thirty seconds")
    }

    private static func checkSystemFunctionMigration() throws {
        var configuration = AppConfiguration()
        guard let presetIndex = configuration.presets.firstIndex(where: { $0.kind == .systemFunctions }) else {
            throw CheckFailure(message: "system function preset is missing")
        }
        for itemIndex in configuration.presets[presetIndex].items.indices {
            switch configuration.presets[presetIndex].items[itemIndex].label {
            case "F4":
                configuration.presets[presetIndex].items[itemIndex].action = ActionSpec(kind: .spotlight)
            case "F5":
                configuration.presets[presetIndex].items[itemIndex].action = ActionSpec(kind: .dictation)
            case "F6":
                configuration.presets[presetIndex].items[itemIndex].action = ActionSpec(kind: .doNotDisturb)
            default:
                break
            }
        }

        configuration.normalize()
        let items = configuration.presets[presetIndex].items
        try expect(items[3].action.kind == .lockScreen, "existing F4 migrates to lock screen")
        try expect(items[4].action.kind == .keyboardBacklight && items[4].action.value == "on", "existing F5 migrates to keyboard backlight on")
        try expect(items[5].action.kind == .keyboardBacklight && items[5].action.value == "off", "existing F6 migrates to keyboard backlight off")
    }

    private static func checkRuntimeFormatting() throws {
        let developer = DeveloperContext(
            workingDirectory: "/Users/example/Developer/TouchingBar",
            branch: "feature/touchbar",
            added: 3,
            modified: 2,
            deleted: 1,
            pythonEnvironment: ".venv",
            pythonVersion: "3.12.4",
            nodeVersion: "22.4.1",
            packageManager: "pnpm"
        )
        let agent = AgentContext(
            provider: "codex",
            task: "Implement settings",
            status: .running,
            startedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 225)
        )
        let snapshot = RuntimeContextSnapshot(developer: developer, agent: agent)
        try expect(snapshot.value(for: "changes") == "+3 -1 ~2", "Git summary is formatted")
        try expect(snapshot.value(for: "python") == ".venv 3.12.4", "Python context is formatted")
        try expect(snapshot.value(for: "node") == "pnpm 22.4.1", "Node context is formatted")
        try expect(snapshot.value(for: "duration") == "2m 5s", "Agent duration is formatted")
        let toolchainSnapshot = RuntimeContextSnapshot(
            developer: DeveloperContext(toolchains: ["go": "1.24.1", "docker": "27.0.1"])
        )
        try expect(toolchainSnapshot.value(for: "go") == "1.24.1", "Go toolchain context is exposed")
        try expect(toolchainSnapshot.value(for: "docker") == "27.0.1", "Docker toolchain context is exposed")
    }

    private static func checkDeveloperContextProvider() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try expect(CommandRunner.run("/usr/bin/git", arguments: ["init"], currentDirectory: directory).exitCode == 0, "git init succeeds")
        try expect(CommandRunner.run("/usr/bin/git", arguments: ["config", "user.email", "checks@example.com"], currentDirectory: directory).exitCode == 0, "git user email config succeeds")
        try expect(CommandRunner.run("/usr/bin/git", arguments: ["config", "user.name", "Checks"], currentDirectory: directory).exitCode == 0, "git user name config succeeds")
        try "initial\n".write(to: directory.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try expect(CommandRunner.run("/usr/bin/git", arguments: ["add", "tracked.txt"], currentDirectory: directory).exitCode == 0, "git add succeeds")
        try expect(CommandRunner.run("/usr/bin/git", arguments: ["commit", "-m", "initial"], currentDirectory: directory).exitCode == 0, "git commit succeeds")
        try "new\n".write(to: directory.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        let context = await DeveloperContextProvider().collect(at: directory.path, terminalName: "Checks")
        try expect(context.workingDirectory == directory.path, "developer context keeps working directory")
        try expect(context.branch != nil, "developer context detects Git branch")
        try expect(context.added >= 1, "developer context counts untracked files")
    }

    private static func checkTouchBarLayoutBudget() throws {
        try expect(TouchBarLayoutMetrics.functionKeyCount == 12, "dashboard budget covers twelve function keys")
        try expect(TouchBarLayoutMetrics.actionDashboardFits, "function row plus navigation fits the dashboard budget")
        try expect(
            TouchBarLayoutMetrics.actionDashboardContentWidth == 971,
            "dashboard content width remains compact"
        )
    }

    private static func checkAgentHookNormalizer() throws {
        let normalizer = AgentHookNormalizer()
        let runningData = Data(#"{"hook_event_name":"PreToolUse","prompt":"Run tests","tool_name":"shell","cwd":"/tmp/project","session_id":"abc"}"#.utf8)
        let running = try normalizer.normalize(data: runningData, fallbackProvider: "claude-code")
        try expect(running.provider == "claude-code", "raw agent hook keeps provider")
        try expect(running.status == .running, "PreToolUse maps to running")
        try expect(running.task == "Run tests", "agent hook extracts task")
        try expect(running.detail == "shell", "agent hook extracts tool detail")
        try expect(running.tool == "shell", "agent hook extracts tool")
        try expect(running.event == "PreToolUse", "agent hook extracts event")
        try expect(running.workingDirectory == "/tmp/project", "agent hook extracts working directory")

        let started = try normalizer.normalize(
            data: Data(#"{"hook_event_name":"SessionStart","session_id":"abc","cwd":"/tmp/project"}"#.utf8),
            fallbackProvider: "claude-code"
        )
        try expect(started.task == nil, "SessionStart does not use the working directory as a task")

        let stopped = try normalizer.normalize(
            data: Data(#"{"event":{"type":"Stop","session_id":"abc"}}"#.utf8),
            fallbackProvider: "codex"
        )
        try expect(stopped.status == .completed, "Stop maps to completed")
        try expect(stopped.sessionID == "abc", "agent hook extracts session")

        let wrapped = try normalizer.normalize(
            data: Data(#"{"provider":"codex","event":{"event":{"type":"Stop","session_id":"wrapped"}}}"#.utf8),
            fallbackProvider: "unknown"
        )
        try expect(wrapped.status == .completed, "nested CLI envelope maps status")
        try expect(wrapped.sessionID == "wrapped", "nested CLI envelope extracts session")
    }

    private static func checkAgentSessionStore() throws {
        var snapshot = RuntimeContextSnapshot()
        let first = AgentContext(
            provider: "codex",
            task: "Build",
            status: .running,
            sessionID: "same-session"
        )
        snapshot.upsertAgent(first)
        let toolUpdate = AgentContext(
            provider: "codex",
            task: nil,
            status: .running,
            sessionID: "same-session",
            tool: "apply_patch"
        )
        snapshot.upsertAgent(toolUpdate)
        try expect(snapshot.agents?.first?.task == "Build", "Agent session updates preserve the original task")
        try expect(snapshot.agents?.first?.tool == "apply_patch", "Agent session updates replace active tool")

        let second = AgentContext(
            provider: "codex",
            task: nil,
            status: .completed,
            sessionID: "same-session"
        )
        snapshot.upsertAgent(second)
        try expect(snapshot.agents?.count == 1, "Agent sessions are upserted by session id")
        try expect(snapshot.agents?.first?.status == .completed, "latest Agent session replaces prior state")
        try expect(snapshot.value(for: "sessions")?.contains("completed") == true, "Agent session summary is exposed")

        let secondSession = AgentContext(
            provider: "codex",
            task: "Review",
            status: .waiting,
            sessionID: "other-session",
            workingDirectory: "/tmp/project"
        )
        snapshot.upsertAgent(secondSession)
        try expect(snapshot.agents?.count == 2, "different Agent session ids stay separate in one workspace")
        try expect(snapshot.agents?.first?.sessionID == "other-session", "attention sessions sort first")

        let ended = AgentContext(
            provider: "codex",
            status: .idle,
            sessionID: "same-session",
            event: "SessionEnd"
        )
        snapshot.upsertAgent(ended)
        try expect(snapshot.agents?.count == 1, "SessionEnd removes only the matching Agent session")

        snapshot.upsertAgent(
            AgentContext(
                provider: "codex",
                status: .idle,
                sessionID: "other-session",
                event: "SessionEnd"
            )
        )
        try expect(snapshot.agents == nil, "SessionEnd removes the final Agent session")

        var configuration = AppConfiguration()
        guard let agentIndex = configuration.presets.firstIndex(where: { $0.kind == .agents }) else {
            throw CheckFailure(message: "agent preset missing")
        }
        configuration.presets[agentIndex].items.removeAll { ["sessions", "event", "tool", "cwd"].contains($0.contextKey ?? "") }
        configuration.normalize()
        let keys = Set(configuration.presets[agentIndex].items.compactMap(\.contextKey))
        try expect(keys.isSuperset(of: ["sessions", "event", "tool", "cwd"]), "existing Agent presets migrate context fields")
    }

    private static func checkShellHookInstaller() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let applicationSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let zshrc = home.appendingPathComponent(".zshrc")
        try "export TEST_VALUE=1\n".write(to: zshrc, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = ShellHookInstaller()
        let installation = try installer.install(
            controlExecutablePath: "/tmp/TouchingBarCtl",
            homeDirectory: home,
            applicationSupportDirectory: applicationSupport
        )
        let installedContent = try String(contentsOf: zshrc, encoding: .utf8)
        try expect(installedContent.contains("export TEST_VALUE=1"), "shell installer preserves existing zshrc")
        try expect(installedContent.contains(ShellHookInstaller.beginMarker), "shell installer adds marker")
        try expect(FileManager.default.fileExists(atPath: installation.scriptURL.path), "shell installer writes script")
        let syntaxCheck = CommandRunner.run("/bin/zsh", arguments: ["-n", installation.scriptURL.path])
        try expect(syntaxCheck.exitCode == 0, "generated zsh integration has valid syntax: \(syntaxCheck.standardError)")

        _ = try installer.install(
            controlExecutablePath: "/tmp/TouchingBarCtl",
            homeDirectory: home,
            applicationSupportDirectory: applicationSupport
        )
        let reinstalledContent = try String(contentsOf: zshrc, encoding: .utf8)
        let markerCount = reinstalledContent.components(separatedBy: ShellHookInstaller.beginMarker).count - 1
        try expect(markerCount == 1, "shell installer is idempotent")

        try installer.uninstall(homeDirectory: home, applicationSupportDirectory: applicationSupport)
        let uninstalledContent = try String(contentsOf: zshrc, encoding: .utf8)
        try expect(!uninstalledContent.contains(ShellHookInstaller.beginMarker), "shell installer removes marker")
        try expect(uninstalledContent.contains("export TEST_VALUE=1"), "shell installer preserves zshrc on uninstall")
    }

    private static func checkAgentHookInstaller() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let configURL = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "user-hook"]]]
                ]
            ],
            "permissions": ["allow": ["Bash(git status)"]]
        ]
        try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted])
            .write(to: configURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = AgentHookInstaller()
        _ = try installer.install(
            provider: .claudeCode,
            controlExecutablePath: "/tmp/TouchingBarCtl",
            homeDirectory: home,
            applicationSupportDirectory: support
        )
        try expect(installer.isInstalled(provider: .claudeCode, homeDirectory: home), "Agent hook installs")

        let installedText = try String(contentsOf: configURL, encoding: .utf8)
        try expect(installedText.contains("user-hook"), "Agent hook installer preserves user hooks")
        try expect(installedText.contains(AgentHookInstaller.managedMarker), "Agent hook installer adds managed hook")

        _ = try installer.install(
            provider: .claudeCode,
            controlExecutablePath: "/tmp/TouchingBarCtl",
            homeDirectory: home,
            applicationSupportDirectory: support
        )
        let reinstalledText = try String(contentsOf: configURL, encoding: .utf8)
        let managedCount = reinstalledText.components(separatedBy: AgentHookInstaller.managedMarker).count - 1
        try expect(managedCount == 9, "Agent hook installation is idempotent")

        try installer.uninstall(provider: .claudeCode, homeDirectory: home)
        let uninstalledText = try String(contentsOf: configURL, encoding: .utf8)
        try expect(!uninstalledText.contains(AgentHookInstaller.managedMarker), "Agent hook uninstall removes managed hooks")
        try expect(uninstalledText.contains("user-hook"), "Agent hook uninstall preserves user hooks")
    }

    private static func checkWebDAVClient() async throws {
        let server = WebDAVStubServer()
        try server.start()
        defer { server.stop() }

        let payload = Data(#"{"backup":"webdav-smoke"}"#.utf8)
        let settings = WebDAVSettings(
            serverURL: "http://127.0.0.1:\(server.port)",
            username: "tester",
            remotePath: "TouchingBar/backup.json"
        )
        let client = WebDAVClient()
        try await client.upload(payload, settings: settings, password: "secret")
        let downloaded = try await client.download(settings: settings, password: "secret")

        try expect(downloaded == payload, "WebDAV upload/download round-trips")
        try expect(server.lastAuthorization?.hasPrefix("Basic ") == true, "WebDAV sends Basic Authentication")
        try expect(server.lastPath == "/TouchingBar/backup.json", "WebDAV preserves remote path")
    }

    private static func checkHookServer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("runtime.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RuntimeContextStore(fileURL: file)
        let port = UInt16.random(in: 30_000...45_000)
        let server = HookServer(port: port, contextStore: store)
        try server.start()
        defer { server.stop() }

        let payload = AgentContext(provider: "codex", task: "Test hook", status: .running)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/context/agent")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        try expect((response as? HTTPURLResponse)?.statusCode == 202, "agent hook returns 202")
        let snapshot = store.load()
        try expect(snapshot.agent?.provider == "codex", "agent hook is persisted")
        try expect(snapshot.agent?.status == .running, "agent status is persisted")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(message: message)
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { "检查失败：\(message)" }
}


private final class WebDAVStubServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.touchingbar.webdav-stub")
    private var portValue: UInt16 = 0
    private var listener: NWListener?
    private var storedData = Data()
    private var authorization: String?
    private var path: String?

    init() {}
    var port: UInt16 { portValue }
    var lastAuthorization: String? { authorization }
    var lastPath: String? { path }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success,
              let assignedPort = listener.port?.rawValue else {
            listener.cancel()
            throw CheckFailure(message: "WebDAV stub server did not become ready")
        }
        portValue = assignedPort
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if let request = self.parse(accumulated) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || accumulated.count >= 128 * 1024 {
                self.send(status: 400, body: Data(), on: connection)
            } else {
                self.receive(connection, buffer: accumulated)
            }
        }
    }

    private func parse(_ data: Data) -> StubRequest? {
        guard let delimiter = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<delimiter.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            headers[line[..<separator].lowercased()] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = delimiter.upperBound
        guard data.count - bodyStart >= contentLength else { return nil }
        return StubRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            body: Data(data[bodyStart..<(bodyStart + contentLength)]),
            authorization: headers["authorization"]
        )
    }

    private func respond(to request: StubRequest, on connection: NWConnection) {
        path = request.path
        authorization = request.authorization
        switch request.method {
        case "PUT":
            storedData = request.body
            send(status: 201, body: Data(), on: connection)
        case "GET":
            send(status: 200, body: storedData, on: connection)
        default:
            send(status: 405, body: Data(), on: connection)
        }
    }

    private func send(status: Int, body: Data, on connection: NWConnection) {
        let reason = status == 200 ? "OK" : status == 201 ? "Created" : "Error"
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Length: \(body.count)",
            "Content-Type: application/json",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

private struct StubRequest {
    var method: String
    var path: String
    var body: Data
    var authorization: String?
}
