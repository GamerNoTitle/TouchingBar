import AppKit
import SwiftUI
import TouchingBarCore

struct IntegrationsSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var hookProvider = "codex"
    @State private var hookStatus = "running"
    @State private var hookTask = ""
    @State private var messageApplication = "WeChat"
    @State private var messageSender = ""
    @State private var messageBody = ""
    @State private var integrationStatus: String?
    @State private var shellHookInstalled = false
    @State private var agentHookInstalled: [AgentHookProvider: Bool] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                terminalIntegrationSection
                agentHookInstallerSection
                hookSection
                examplesSection
                messageSection
            }
            .padding(.vertical, 4)
            .groupBoxStyle(IntegrationGroupBoxStyle())
        }
        .onAppear {
            shellHookInstalled = ShellHookInstaller().isInstalled()
            refreshAgentHookStatus()
        }
    }

    private var terminalIntegrationSection: some View {
        GroupBox("终端 Shell 集成") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        shellHookInstalled ? "zsh 集成已安装" : "zsh 集成未安装",
                        systemImage: shellHookInstalled ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(shellHookInstalled ? .green : .secondary)
                    Spacer()
                    Button(shellHookInstalled ? "重新安装" : "安装 zsh 集成") {
                        installShellHook()
                    }
                    .buttonStyle(.borderedProminent)
                    if shellHookInstalled {
                        Button("卸载", role: .destructive) {
                            uninstallShellHook()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("安装后，每次终端目录变化都会由 shell 上报真实的 $PWD、虚拟环境和 Node 版本。适用于 Terminal、iTerm2、VS Code、JetBrains、Warp 与其他基于 zsh 的终端。")
                    .foregroundStyle(.secondary)

                Text("会安装到 \(shellIntegrationScriptPath)，并只在 ~/.zshrc 中写入带有标记的 source 区块。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.top, 6)
        }
    }

    private var agentHookInstallerSection: some View {
        GroupBox("Agent Hook 安装") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("安装后会合并现有配置，只添加或移除 TouchingBar 自己的 Hook，不覆盖其他 Hook。")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("全部安装") { installAllAgentHooks() }
                        .buttonStyle(.borderedProminent)
                    Button("全部移除") { uninstallAllAgentHooks() }
                        .buttonStyle(.bordered)
                }

                Divider()

                ForEach(AgentHookProvider.allCases) { provider in
                    HStack(spacing: 10) {
                        Label(provider.title, systemImage: providerIcon(provider))
                        Spacer()
                        Text(agentHookInstalled[provider] == true ? "已安装" : "未安装")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(agentHookInstalled[provider] == true ? Color.green : Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        if agentHookInstalled[provider] == true {
                            Button("移除") { uninstallAgentHook(provider) }
                                .buttonStyle(.bordered)
                        } else {
                            Button("安装") { installAgentHook(provider) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func providerIcon(_ provider: AgentHookProvider) -> String {
        switch provider {
        case .claudeCode: return "moon.stars.fill"
        case .codex: return "apple.terminal.fill"
        case .gemini: return "sparkles"
        case .cursor: return "cursorarrow.rays"
        }
    }

    private func installAgentHook(_ provider: AgentHookProvider) {
        do {
            let url = try AgentHookInstaller().install(
                provider: provider,
                controlExecutablePath: controlExecutablePath
            )
            agentHookInstalled[provider] = true
            integrationStatus = "已安装 \(provider.title) Hook：\(url.path)"
        } catch {
            integrationStatus = "安装 \(provider.title) Hook 失败：\(error.localizedDescription)"
        }
    }

    private func installAllAgentHooks() {
        var installed: [String] = []
        for provider in AgentHookProvider.allCases {
            do {
                _ = try AgentHookInstaller().install(
                    provider: provider,
                    controlExecutablePath: controlExecutablePath
                )
                agentHookInstalled[provider] = true
                installed.append(provider.title)
            } catch {
                integrationStatus = "安装 \(provider.title) Hook 失败：\(error.localizedDescription)"
                return
            }
        }
        integrationStatus = "已安装全部 Agent Hook：\(installed.joined(separator: "、"))。"
    }

    private func uninstallAgentHook(_ provider: AgentHookProvider) {
        do {
            try AgentHookInstaller().uninstall(provider: provider)
            agentHookInstalled[provider] = false
            integrationStatus = "已移除 \(provider.title) Hook。"
        } catch {
            integrationStatus = "移除 \(provider.title) Hook 失败：\(error.localizedDescription)"
        }
    }

    private func uninstallAllAgentHooks() {
        for provider in AgentHookProvider.allCases {
            do {
                try AgentHookInstaller().uninstall(provider: provider)
                agentHookInstalled[provider] = false
            } catch {
                integrationStatus = "移除 \(provider.title) Hook 失败：\(error.localizedDescription)"
                return
            }
        }
        integrationStatus = "已移除全部 Agent Hook。"
    }

    private func refreshAgentHookStatus() {
        let installer = AgentHookInstaller()
        agentHookInstalled = Dictionary(
            uniqueKeysWithValues: AgentHookProvider.allCases.map {
                ($0, installer.isInstalled(provider: $0))
            }
        )
    }

    private var hookSection: some View {
        GroupBox("Agent Hook 模拟器") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Agent")
                    TextField("Claude Code、Codex、Gemini…", text: $hookProvider)
                        .frame(width: 240)
                }
                GridRow {
                    Text("状态")
                    Picker("", selection: $hookStatus) {
                        ForEach(AgentStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                GridRow {
                    Text("任务")
                    TextField("正在执行的任务", text: $hookTask)
                        .frame(width: 360)
                }
                GridRow {
                    Text("")
                    Toggle(
                        "Agent 状态变化时显示系统通知",
                        isOn: Binding(
                            get: { store.configuration.effectiveShowAgentNotifications },
                            set: { value in
                                store.updateConfiguration { $0.effectiveShowAgentNotifications = value }
                            }
                        )
                    )
                }
                GridRow {
                    Text("")
                    Button("发送到 Touch Bar") {
                        sendAgentHook()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 6)

            if let integrationStatus {
                Text(integrationStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private var examplesSection: some View {
        GroupBox("Hook 调用示例") {
            VStack(alignment: .leading, spacing: 10) {
                Text("任何 Agent 都可以在会话开始、状态变化或工具调用结束时发送 JSON：")
                    .foregroundStyle(.secondary)
                CodeBlock(text: """
                curl -X POST http://127.0.0.1:19427/v1/context/agent \\
                  -H 'Content-Type: application/json' \\
                  -d '{"provider":"codex","task":"Build app","status":"running","updatedAt":"2026-09-23T06:00:00Z"}'
                """)
                Text("终端扩展也可以在目录变化时上报路径，TouchingBar 接着自动补齐 Git、Python 与 Node 信息：")
                    .foregroundStyle(.secondary)
                CodeBlock(text: """
                curl -X POST http://127.0.0.1:19427/v1/context/developer \\
                  -H 'Content-Type: application/json' \\
                  -d '{"workingDirectory":"/Users/me/project","terminalName":"VS Code","updatedAt":"2026-09-23T06:00:00Z"}'
                """)
            }
            .padding(.top, 6)
        }
    }

    private var messageSection: some View {
        GroupBox("消息 Hook") {
            VStack(alignment: .leading, spacing: 10) {
                Text("消息 Hook 用于接入无法直接读取角标的应用。通知内容可以关闭，但 Touch Bar 仍会显示最新信息。")
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("应用")
                        TextField("WeChat", text: $messageApplication)
                            .frame(width: 180)
                    }
                    GridRow {
                        Text("发送者")
                        TextField("Alice", text: $messageSender)
                            .frame(width: 260)
                    }
                    GridRow {
                        Text("内容")
                        TextField("消息正文", text: $messageBody)
                            .frame(width: 360)
                    }
                    GridRow {
                        Text("")
                        Button("发送消息 Hook") {
                            sendMessageHook()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                CodeBlock(text: """
                curl -X POST http://127.0.0.1:19427/v1/messages \\
                  -H 'Content-Type: application/json' \\
                  -d '{"application":"WeChat","sender":"Alice","body":"你好","unreadCount":1,"receivedAt":"2026-09-23T06:00:00Z"}'
                """)
            }
            .padding(.top, 6)
        }
    }

    private func installShellHook() {
        do {
            let installation = try ShellHookInstaller().install(controlExecutablePath: controlExecutablePath)
            shellHookInstalled = true
            integrationStatus = "已安装 zsh 集成。打开新终端或执行 source \(installation.shellConfigurationURL.path)。"
        } catch {
            integrationStatus = "安装失败：\(error.localizedDescription)"
        }
    }

    private func uninstallShellHook() {
        do {
            try ShellHookInstaller().uninstall()
            shellHookInstalled = false
            integrationStatus = "已卸载 zsh 集成。"
        } catch {
            integrationStatus = "卸载失败：\(error.localizedDescription)"
        }
    }

    private var controlExecutablePath: String {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("TouchingBarCtl", isDirectory: false)
                .standardizedFileURL
                .path
        }
        return "/Applications/TouchingBar.app/Contents/MacOS/TouchingBarCtl"
    }

    private var shellIntegrationScriptPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("TouchingBar/shell-integration.zsh")
            .path
    }

    private func sendAgentHook() {
        let context = AgentContext(
            provider: hookProvider,
            task: hookTask,
            status: AgentStatus(rawValue: hookStatus) ?? .unknown
        )
        post(context, path: "/v1/context/agent") { result in
            integrationStatus = result
        }
    }

    private func sendMessageHook() {
        guard !messageBody.isEmpty else {
            integrationStatus = "消息内容不能为空。"
            return
        }
        let message = MessageContext(
            application: messageApplication,
            sender: messageSender.isEmpty ? nil : messageSender,
            body: messageBody
        )
        post(message, path: "/v1/messages") { result in
            integrationStatus = result
        }
    }

    private func post<T: Encodable>(_ value: T, path: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(HookServer.defaultPort)\(path)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try? encoder.encode(value)

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion("发送失败：\(error.localizedDescription)")
                } else if let response = response as? HTTPURLResponse {
                    completion(response.statusCode == 202 ? "已发送，Touch Bar 已更新。" : "服务器返回 HTTP \(response.statusCode)。")
                }
            }
        }.resume()
    }
}

private struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct IntegrationGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline)
            Divider()
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
