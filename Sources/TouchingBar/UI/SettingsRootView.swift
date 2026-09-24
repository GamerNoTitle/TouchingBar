import ApplicationServices
import SwiftUI
import TouchingBarCore

struct SettingsRootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Text("通用") }
            PresetsSettingsView()
                .tabItem { Text("Touch Bar 配置") }
            PetsSettingsView()
                .tabItem { Text("宠物") }
            IntegrationsSettingsView()
                .tabItem { Text("集成") }
            BackupSettingsView()
                .tabItem { Text("备份与恢复") }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
        .overlay(alignment: .bottomTrailing) {
            if store.hasUnsavedChanges {
                HStack(spacing: 10) {
                    Text("有未保存的更改")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("撤销") {
                        store.discardChanges()
                    }
                    .buttonStyle(.bordered)
                    Button("保存") {
                        store.save()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: store.hasUnsavedChanges)
    }
}


struct GeneralSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var accessibilityTrusted = false

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.menuBar.isEnabled },
            set: { value in store.updateConfiguration { $0.menuBar.isEnabled = value } }
        )
    }

    private var closeBoxBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.hideTouchBarCloseButton },
            set: { value in store.updateConfiguration { $0.hideTouchBarCloseButton = value } }
        )
    }

    private var silentLaunchBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.effectiveSilentLaunch },
            set: { value in store.updateConfiguration { $0.effectiveSilentLaunch = value } }
        )
    }

    private var disableAnimationsBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.effectiveDisableAnimations },
            set: { value in store.updateConfiguration { $0.effectiveDisableAnimations = value } }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("在菜单栏显示 TouchingBar", isOn: menuBarBinding)
                Toggle("静默启动", isOn: silentLaunchBinding)
                Toggle("关闭动态效果", isOn: disableAnimationsBinding)
                Toggle("隐藏 Touch Bar 关闭按钮", isOn: closeBoxBinding)
                Text("静默启动会在启动或重新打开 TouchingBar 时不自动打开设置窗口，仍可从菜单栏打开。关闭动态效果后，宠物与双行歌词使用静态切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("TouchingBar 运行期间会持续占用 Touch Bar；不使用请从菜单栏退出 TouchingBar。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("应用")
            }

            Section {
                HStack {
                    Label(
                        store.hookServerRunning ? "本地 Hook 服务运行中" : "本地 Hook 服务未运行",
                        systemImage: store.hookServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(store.hookServerRunning ? .green : .red)
                    Spacer()
                    Text("127.0.0.1:\(HookServer.defaultPort)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("接收路径")
                        .font(.headline)
                    Text("POST /v1/context/developer")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("终端 Shell 集成、VS Code/JetBrains 扩展或脚本可以把当前目录上下文写入这个端点。Touch Bar 会立即更新，无需重启应用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("运行状态")
            }

            Section {
                HStack {
                    Text("系统资源趋势范围")
                    Spacer()
                    Picker(
                        "",
                        selection: Binding(
                            get: { store.configuration.effectiveMetricsHistorySeconds },
                            set: { value in
                                store.updateConfiguration { $0.effectiveMetricsHistorySeconds = value }
                            }
                        )
                    ) {
                        Text("10s").tag(10)
                        Text("30s").tag(30)
                        Text("1min").tag(60)
                        Text("2mins").tag(120)
                        Text("5mins").tag(300)
                        Text("10mins").tag(600)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                Text("折线图会保留对应时间范围内的逐秒采样点。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("系统资源")
            }

            Section {
                HStack {
                    Text("歌词全局偏移")
                    Slider(
                        value: Binding(
                            get: { store.configuration.effectiveLyricsOffset },
                            set: { value in
                                store.updateConfiguration { $0.effectiveLyricsOffset = value }
                            }
                        ),
                        in: -5...5,
                        step: 0.1
                    )
                    Text(String(format: "%+.1f 秒", store.configuration.effectiveLyricsOffset))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
                Text("正值会让歌词提前显示，负值会让歌词延后显示，对所有歌曲生效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("音乐歌词")
            }

            Section {
                HStack {
                    Label(
                        accessibilityTrusted ? "辅助功能权限已授权" : "尚未授权辅助功能",
                        systemImage: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Spacer()
                    Button(accessibilityTrusted ? "打开系统设置" : "请求权限") {
                        if accessibilityTrusted {
                            openAccessibilitySettings()
                        } else {
                            requestAccessibilityPermission()
                        }
                    }
                }
                Text("只有 F1–F12 键码模拟、自定义键盘快捷键、听写和专注模式等 AX 操作需要辅助功能权限。系统资源、音乐媒体、亮度、锁屏和宠物不需要。未读消息和 Agent 已移除，因此不再需要为它们授权。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("隐私权限")
            }

            if let error = store.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } header: {
                    Text("最近错误")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }
}
