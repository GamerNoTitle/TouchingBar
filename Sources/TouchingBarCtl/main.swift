import Foundation
import TouchingBarCore

private let baseURL = URL(string: "http://127.0.0.1:\(HookServer.defaultPort)")!
private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()
private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

do {
    try TouchingBarCtlCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
    exit(1)
}

private enum TouchingBarCtlCommand {
    static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        let options = parseOptions(Array(arguments.dropFirst()))
        switch command {
        case "health":
            let response = try request(method: "GET", path: "/health")
            print(String(data: response, encoding: .utf8) ?? "")

        case "agent":
            let provider = options["provider"] ?? "unknown"
            let status = AgentStatus(rawValue: options["status"] ?? "running") ?? .unknown
            let context = AgentContext(
                provider: provider,
                task: options["task"],
                status: status,
                detail: options["detail"],
                sessionID: options["session"],
                startedAt: options["started-at"].flatMap(parseDate),
                updatedAt: Date()
            )
            try post(context, path: "/v1/context/agent")
            print("Agent 状态已发送：\(provider) / \(status.rawValue)")

        case "developer":
            let directory = options["directory"] ?? FileManager.default.currentDirectoryPath
            let terminal = options["terminal"]
            var context = try awaitValue {
                await DeveloperContextProvider().collect(at: directory, terminalName: terminal)
            }
            context.pythonEnvironment = options["python-env"] ?? context.pythonEnvironment
            context.pythonVersion = options["python-version"] ?? context.pythonVersion
            context.nodeVersion = options["node-version"] ?? context.nodeVersion
            context.packageManager = options["node-manager"] ?? context.packageManager
            context.updatedAt = Date()
            try post(context, path: "/v1/context/developer")
            print("开发者上下文已发送：\(directory)")

        case "install-shell-hook":
            let ctlPath = options["ctl"] ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
            let installation = try ShellHookInstaller().install(
                controlExecutablePath: ctlPath,
                shell: options["shell"] ?? "zsh"
            )
            print("已安装 zsh 集成：\(installation.scriptURL.path)")
            print("请执行 source \(installation.shellConfigurationURL.path) 或打开新的终端。")

        case "uninstall-shell-hook":
            try ShellHookInstaller().uninstall()
            print("已卸载 zsh 集成。")

        case "shell-hook-status":
            print(ShellHookInstaller().isInstalled() ? "installed" : "not-installed")

        case "lyrics":
            guard let title = options["title"], !title.isEmpty else {
                throw CLIError.missingOption("--title")
            }
            let artist = options["artist"] ?? ""
            let album = options["album"] ?? ""
            let duration = options["duration"].flatMap(Double.init)
            if let result = NetEaseLyricsProvider().lyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            ) {
                let lines = result.components(separatedBy: .newlines)
                print("网易云歌词已命中：\(lines.count) 行")
                print(lines.prefix(8).joined(separator: "\n"))
            } else {
                print("未找到网易云歌词")
            }

        case "message":
            guard let body = options["body"], !body.isEmpty else {
                throw CLIError.missingOption("--body")
            }
            let count = Int(options["count"] ?? "1") ?? 1
            let message = MessageContext(
                application: options["app"] ?? "App",
                bundleIdentifier: options["bundle"],
                sender: options["sender"],
                body: body,
                conversation: options["conversation"],
                unreadCount: count
            )
            try post(message, path: "/v1/messages")
            print("消息已发送：\(message.application)")

        case "agent-event":
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let envelope: [String: Any] = [
                "provider": options["provider"] ?? "unknown",
                "event": (try? JSONSerialization.jsonObject(with: data)) ?? [:]
            ]
            let payload = try JSONSerialization.data(withJSONObject: envelope)
            _ = try request(method: "POST", path: "/v1/hooks/agent", body: payload)
            print("Agent 原始事件已发送。")

        case "json":
            guard let kind = options["kind"] else {
                throw CLIError.missingOption("--kind")
            }
            let path: String
            switch kind {
            case "agent": path = "/v1/context/agent"
            case "developer": path = "/v1/context/developer"
            case "message": path = "/v1/messages"
            default: throw CLIError.invalidValue("--kind", kind)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            do {
                switch kind {
                case "agent": _ = try decoder.decode(AgentContext.self, from: data)
                case "developer": _ = try decoder.decode(DeveloperContext.self, from: data)
                case "message": _ = try decoder.decode(MessageContext.self, from: data)
                default: break
                }
            } catch {
                throw CLIError.invalidJSON
            }
            let response = try request(method: "POST", path: path, body: data)
            print(String(data: response, encoding: .utf8) ?? "")

        case "export":
            guard let path = options["path"] else { throw CLIError.missingOption("--path") }
            let configuration = try ConfigurationStore.shared.load()
            let data = try BackupService().encode(configuration: configuration)
            try data.write(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), options: .atomic)
            print("已导出：\(path)")

        case "import":
            guard let path = options["path"] else { throw CLIError.missingOption("--path") }
            let data = try Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            let configuration = try BackupService().decode(data)
            try ConfigurationStore.shared.save(configuration)
            print("已导入：\(path)")

        case "version":
            print("TouchingBarCtl 0.1.0")

        case "help", "--help", "-h":
            printHelp()

        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func post<T: Encodable>(_ value: T, path: String) throws {
        let data = try encoder.encode(value)
        _ = try request(method: "POST", path: path, body: data)
    }

    @discardableResult
    private static func request(method: String, path: String, body: Data? = nil) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 3
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(CLIError.invalidResponse)
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure(CLIError.http(http.statusCode, message))
                return
            }
            result = .success(data ?? Data())
        }.resume()
        semaphore.wait()
        return try result?.get() ?? Data()
    }

    private static func parseOptions(_ arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let key = String(argument.dropFirst(2))
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    result[key] = arguments[index + 1]
                    index += 2
                } else {
                    result[key] = "true"
                    index += 1
                }
            } else {
                index += 1
            }
        }
        return result
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func awaitValue<T>(_ operation: @escaping () async -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        Task {
            result = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        guard let result else { throw CLIError.invalidResponse }
        return result
    }

    private static func printHelp() {
        print("""
        TouchingBarCtl - TouchingBar 本地 Hook 客户端

        用法：
          TouchingBarCtl health
          TouchingBarCtl agent --provider codex --status running --task "Build app"
          TouchingBarCtl developer [--directory /path] [--terminal "VS Code"]
          TouchingBarCtl install-shell-hook [--shell zsh] [--ctl /path/to/TouchingBarCtl]
          TouchingBarCtl uninstall-shell-hook
          TouchingBarCtl shell-hook-status
          TouchingBarCtl agent-event --provider claude-code < raw-hook.json
          TouchingBarCtl lyrics --title "晴天" --artist "周杰伦" --duration 269
          TouchingBarCtl message --app WeChat --sender Alice --body "Hello"
          TouchingBarCtl json --kind agent < payload.json
          TouchingBarCtl export --path ~/TouchingBar-backup.json
          TouchingBarCtl import --path ~/TouchingBar-backup.json
        """)
    }
}

private enum CLIError: LocalizedError {
    case missingOption(String)
    case invalidValue(String, String)
    case unknownCommand(String)
    case invalidJSON
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingOption(let option):
            return "缺少参数 \(option)"
        case .invalidValue(let option, let value):
            return "\(option) 的值无效：\(value)"
        case .unknownCommand(let command):
            return "未知命令：\(command)"
        case .invalidJSON:
            return "标准输入不是有效的 JSON 数据"
        case .invalidResponse:
            return "Hook 服务返回了无效响应"
        case .http(let code, let message):
            return "Hook 服务返回 HTTP \(code)：\(message)"
        }
    }
}
