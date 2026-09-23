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
            IntegrationsSettingsView()
                .tabItem { Text("集成") }
            BackupSettingsView()
                .tabItem { Text("备份与恢复") }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
    }
}


struct GeneralSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var accessibilityTrusted = false

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.menuBar.isEnabled },
            set: { value in store.updateConfiguration { $0.menuBar.isEnabled = value } }
        )
    }

    private var occupyBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.alwaysOccupyTouchBar },
            set: { value in store.updateConfiguration { $0.alwaysOccupyTouchBar = value } }
        )
    }

    private var closeBoxBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.hideTouchBarCloseButton },
            set: { value in store.updateConfiguration { $0.hideTouchBarCloseButton = value } }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("在菜单栏显示 TouchingBar", isOn: menuBarBinding)
                Toggle("持续占用 Touch Bar", isOn: occupyBinding)
                Toggle("隐藏 Touch Bar 关闭按钮", isOn: closeBoxBinding)
                    .disabled(!store.configuration.alwaysOccupyTouchBar)
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
                    Text("POST /v1/context/agent")
                    Text("POST /v1/messages")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("Agent、VS Code/JetBrains 终端扩展或脚本可以把上下文写入这些端点。Touch Bar 会立即更新，无需重启应用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("运行状态")
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
                        DockBadgeReader().requestAccessibilityPermission()
                        accessibilityTrusted = DockBadgeReader().isAccessibilityTrusted
                    }
                }
                Text("读取 Dock 未读角标、模拟功能键和部分系统快捷键需要辅助功能权限。授权后请重新启动 TouchingBar。")
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
            accessibilityTrusted = DockBadgeReader().isAccessibilityTrusted
        }
    }
}
