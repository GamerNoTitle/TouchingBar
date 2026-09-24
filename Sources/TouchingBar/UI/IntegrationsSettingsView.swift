import AppKit
import SwiftUI
import TouchingBarCore

struct IntegrationsSettingsView: View {
    @State private var integrationStatus: String?
    @State private var shellHookInstalled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                terminalIntegrationSection
                developerHookExampleSection
            }
            .padding(.vertical, 4)
            .groupBoxStyle(IntegrationGroupBoxStyle())
        }
        .onAppear {
            shellHookInstalled = ShellHookInstaller().isInstalled()
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

                if let integrationStatus {
                    Text(integrationStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }
    }

    private var developerHookExampleSection: some View {
        GroupBox("开发者目录 Hook") {
            VStack(alignment: .leading, spacing: 10) {
                Text("终端扩展或脚本可以在目录变化时上报路径，TouchingBar 接着自动补齐 Git、Python 与 Node 信息：")
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
