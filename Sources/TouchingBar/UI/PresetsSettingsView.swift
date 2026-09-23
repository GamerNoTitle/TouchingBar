import SwiftUI
import TouchingBarCore

struct PresetsSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPresetID: UUID?
    @State private var selectedItemID: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                List(store.configuration.presets, selection: $selectedPresetID) { preset in
                    HStack {
                        Image(systemName: symbol(for: preset.kind))
                            .frame(width: 18)
                        Text(preset.name)
                        Spacer()
                        if preset.id == store.configuration.activePresetID {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .tag(preset.id)
                }
                .onChange(of: selectedPresetID) { _ in selectedItemID = nil }

                HStack {
                    Button {
                        store.addPreset()
                        selectedPresetID = store.configuration.activePresetID
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        guard let selectedPresetID else { return }
                        store.duplicatePreset(store.configuration.presets.first(where: { $0.id == selectedPresetID }) ?? store.configuration.presets[0])
                        self.selectedPresetID = store.configuration.activePresetID
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .disabled(selectedPresetID == nil)
                    Button {
                        guard let selectedPresetID else { return }
                        store.deletePreset(id: selectedPresetID)
                        self.selectedPresetID = store.configuration.activePresetID
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedPresetID == nil || store.configuration.presets.first(where: { $0.id == selectedPresetID })?.isBuiltIn == true)
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .frame(minWidth: 210, idealWidth: 240)

            if let selectedPresetID,
               let preset = store.configuration.presets.first(where: { $0.id == selectedPresetID }) {
                PresetDetailView(presetID: preset.id, selectedItemID: $selectedItemID)
                    .frame(minWidth: 500)
            } else {
                SettingsEmptyState(
                    title: "选择一个配置",
                    systemImage: "rectangle.topthird.inset.filled"
                )
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectedPresetID = store.configuration.activePresetID
        }
    }

    private func symbol(for kind: PresetKind) -> String {
        switch kind {
        case .functionKeys: return "f.circle"
        case .systemFunctions: return "sun.max"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .agents: return "sparkles"
        case .messages: return "message.badge"
        case .music: return "music.note"
        case .custom: return "slider.horizontal.3"
        }
    }
}

private struct PresetDetailView: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    @Binding var selectedItemID: UUID?

    private var preset: TouchBarPreset? {
        store.configuration.presets.first(where: { $0.id == presetID })
    }

    var body: some View {
        if let preset {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.isBuiltIn ? "内置配置" : "自定义配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("配置名称", text: nameBinding(preset))
                            .font(.title2.bold())
                            .textFieldStyle(.plain)
                    }
                    Spacer()
                    Button(preset.id == store.configuration.activePresetID ? "正在使用" : "使用此配置") {
                        store.selectPreset(id: preset.id)
                    }
                    .disabled(preset.id == store.configuration.activePresetID)
                }

                HStack {
                    Picker("内容类型", selection: contentBinding(preset)) {
                        ForEach(PresetContent.allCases, id: \.self) { content in
                            Text(contentTitle(content)).tag(content)
                        }
                    }
                    .frame(maxWidth: 300)

                    Picker("分类", selection: kindBinding(preset)) {
                        ForEach(PresetKind.allCases, id: \.self) { kind in
                            Text(kindTitle(kind)).tag(kind)
                        }
                    }
                    .frame(maxWidth: 260)
                }

                Divider()

                switch preset.content {
                case .unreadMessages:
                    MessagesPresetDetail()
                case .actions, .nowPlaying:
                    ActionItemsEditor(presetID: preset.id, selectedItemID: $selectedItemID)
                case .developerContext, .agentContext:
                    ContextItemsEditor(presetID: preset.id, selectedItemID: $selectedItemID)
                }
            }
            .padding(18)
        }
    }

    private func nameBinding(_ preset: TouchBarPreset) -> Binding<String> {
        Binding(
            get: { self.preset?.name ?? "" },
            set: { value in
                guard var updated = self.preset else { return }
                updated.name = value
                store.replacePreset(updated)
            }
        )
    }

    private func contentBinding(_ preset: TouchBarPreset) -> Binding<PresetContent> {
        Binding(
            get: { self.preset?.content ?? .actions },
            set: { value in
                guard var updated = self.preset else { return }
                updated.content = value
                store.replacePreset(updated)
            }
        )
    }

    private func kindBinding(_ preset: TouchBarPreset) -> Binding<PresetKind> {
        Binding(
            get: { self.preset?.kind ?? .custom },
            set: { value in
                guard var updated = self.preset else { return }
                updated.kind = value
                store.replacePreset(updated)
            }
        )
    }

    private func contentTitle(_ content: PresetContent) -> String {
        switch content {
        case .actions: return "动作按钮"
        case .developerContext: return "开发者上下文"
        case .agentContext: return "Agent 上下文"
        case .unreadMessages: return "未读消息"
        case .nowPlaying: return "正在播放与歌词"
        }
    }

    private func kindTitle(_ kind: PresetKind) -> String {
        switch kind {
        case .functionKeys: return "功能键"
        case .systemFunctions: return "系统功能键"
        case .developer: return "开发者"
        case .agents: return "Agent"
        case .messages: return "消息"
        case .music: return "音乐"
        case .custom: return "自定义"
        }
    }
}

private struct ActionItemsEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    @Binding var selectedItemID: UUID?

    private var preset: TouchBarPreset? {
        store.configuration.presets.first(where: { $0.id == presetID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("按钮")
                    .font(.headline)
                Spacer()
                Button {
                    store.addItem(toPresetID: presetID)
                    selectedItemID = store.configuration.presets.first(where: { $0.id == presetID })?.items.last?.id
                } label: {
                    Label("添加按钮", systemImage: "plus")
                }
            }

            if let preset, !preset.items.isEmpty {
                List(selection: $selectedItemID) {
                    ForEach(preset.items) { item in
                        HStack {
                            if let symbol = item.symbolName {
                                Image(systemName: symbol)
                            }
                            Text(item.label)
                            Spacer()
                            Text(actionTitle(item.action.kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
                .frame(minHeight: 150)

                if let selectedItemID,
                   let item = preset.items.first(where: { $0.id == selectedItemID }) {
                    ActionItemEditor(presetID: presetID, itemID: item.id, item: item)
                }
            } else {
                SettingsEmptyState(
                    title: "没有按钮",
                    systemImage: "rectangle.topthird.inset.filled"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func actionTitle(_ kind: TouchBarActionKind) -> String {
        switch kind {
        case .none: return "无动作"
        case .functionKey: return "F 键"
        case .keyboardShortcut: return "快捷键"
        case .launchApplication: return "启动应用"
        case .openURL: return "打开 URL"
        case .runCommand: return "运行命令"
        case .media: return "媒体控制"
        case .volume: return "音量"
        case .brightness: return "亮度"
        case .missionControl: return "调度中心"
        case .spotlight: return "Spotlight"
        case .dictation: return "听写"
        case .doNotDisturb: return "专注模式"
        case .lockScreen: return "快速锁屏"
        case .keyboardBacklight: return "键盘背光"
        }
    }
}

private struct ActionItemEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    let itemID: UUID
    let item: TouchBarItemConfiguration

    var body: some View {
        Form {
            TextField("名称", text: binding(\.label))
            HStack {
                TextField("SF Symbol", text: optionalBinding(\.symbolName))
                Picker("宽度", selection: binding(\.width)) {
                    Text("紧凑").tag(TouchBarItemWidth.compact)
                    Text("常规").tag(TouchBarItemWidth.regular)
                    Text("宽").tag(TouchBarItemWidth.wide)
                }
            }
            Picker("动作", selection: actionBinding(\.kind)) {
                ForEach(TouchBarActionKind.allCases, id: \.self) { kind in
                    Text(actionTitle(kind)).tag(kind)
                }
            }

            actionDetails

            HStack {
                Button("上移") { store.moveItem(presetID: presetID, itemID: itemID, offset: -1) }
                Button("下移") { store.moveItem(presetID: presetID, itemID: itemID, offset: 1) }
                Spacer()
                Button("删除", role: .destructive) {
                    store.deleteItem(presetID: presetID, itemID: itemID)
                }
            }
        }
        .formStyle(.columns)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var actionDetails: some View {
        switch item.action.kind {
        case .functionKey:
            TextField("F 键编号（1–12）", text: optionalBinding(\.action.value))
        case .launchApplication, .openURL, .runCommand:
            TextField(item.action.kind == .runCommand ? "Shell 命令" : "Bundle ID、路径或 URL", text: optionalBinding(\.action.value))
        case .media:
            Picker("媒体动作", selection: mediaBinding) {
                Text("上一曲").tag(MediaCommand.previous)
                Text("播放/暂停").tag(MediaCommand.playPause)
                Text("下一曲").tag(MediaCommand.next)
            }
        case .volume:
            Picker("音量动作", selection: volumeBinding) {
                Text("静音").tag(VolumeCommand.mute)
                Text("减小").tag(VolumeCommand.down)
                Text("增大").tag(VolumeCommand.up)
            }
        case .keyboardBacklight:
            Picker("键盘背光", selection: optionalBinding(\.action.value)) {
                Text("打开").tag("on")
                Text("关闭").tag("off")
            }
        case .keyboardShortcut:
            TextField("按键（如 a、space、up、F1）", text: shortcutBinding(\.key))
            HStack {
                Toggle("⌘", isOn: shortcutBinding(\.command))
                Toggle("⌥", isOn: shortcutBinding(\.option))
                Toggle("⌃", isOn: shortcutBinding(\.control))
                Toggle("⇧", isOn: shortcutBinding(\.shift))
            }
        default:
            EmptyView()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TouchBarItemConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { currentItem?[keyPath: keyPath] ?? item[keyPath: keyPath] },
            set: { value in
                guard var updated = currentItem else { return }
                updated[keyPath: keyPath] = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<TouchBarItemConfiguration, String?>) -> Binding<String> {
        Binding(
            get: { currentItem?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var updated = currentItem else { return }
                updated[keyPath: keyPath] = value.isEmpty ? nil : value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private func actionBinding<Value>(_ keyPath: WritableKeyPath<ActionSpec, Value>) -> Binding<Value> {
        Binding(
            get: { currentItem?.action[keyPath: keyPath] ?? item.action[keyPath: keyPath] },
            set: { value in
                guard var updated = currentItem else { return }
                updated.action[keyPath: keyPath] = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var mediaBinding: Binding<MediaCommand> {
        Binding(
            get: { currentItem?.action.media ?? .playPause },
            set: { value in
                guard var updated = currentItem else { return }
                updated.action.media = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var volumeBinding: Binding<VolumeCommand> {
        Binding(
            get: { currentItem?.action.volume ?? .up },
            set: { value in
                guard var updated = currentItem else { return }
                updated.action.volume = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private func shortcutBinding<Value>(_ keyPath: WritableKeyPath<KeyShortcut, Value>) -> Binding<Value> {
        Binding(
            get: {
                let shortcut = currentItem?.action.shortcut ?? item.action.shortcut ?? KeyShortcut(key: "")
                return shortcut[keyPath: keyPath]
            },
            set: { value in
                guard var updated = currentItem else { return }
                var shortcut = updated.action.shortcut ?? KeyShortcut(key: "")
                shortcut[keyPath: keyPath] = value
                updated.action.shortcut = shortcut
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var currentItem: TouchBarItemConfiguration? {
        store.configuration.presets
            .first(where: { $0.id == presetID })?
            .items.first(where: { $0.id == itemID })
    }

    private func actionTitle(_ kind: TouchBarActionKind) -> String {
        switch kind {
        case .none: return "无动作"
        case .functionKey: return "F 键"
        case .keyboardShortcut: return "快捷键"
        case .launchApplication: return "启动应用"
        case .openURL: return "打开 URL"
        case .runCommand: return "运行命令"
        case .media: return "媒体控制"
        case .volume: return "音量"
        case .brightness: return "亮度"
        case .missionControl: return "调度中心"
        case .spotlight: return "Spotlight"
        case .dictation: return "听写"
        case .doNotDisturb: return "专注模式"
        case .lockScreen: return "快速锁屏"
        case .keyboardBacklight: return "键盘背光"
        }
    }
}

private struct ContextItemsEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    @Binding var selectedItemID: UUID?

    private var preset: TouchBarPreset? {
        store.configuration.presets.first(where: { $0.id == presetID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("上下文字段")
                    .font(.headline)
                Spacer()
                Button {
                    let item = TouchBarItemConfiguration(
                        label: "字段",
                        width: .regular,
                        presentation: .context,
                        contextKey: "path"
                    )
                    guard var current = preset else { return }
                    current.items.append(item)
                    store.replacePreset(current)
                    selectedItemID = item.id
                } label: {
                    Label("添加字段", systemImage: "plus")
                }
            }

            if let preset {
                List(selection: $selectedItemID) {
                    ForEach(preset.items) { item in
                        HStack {
                            Text(item.label)
                            Spacer()
                            Text(contextTitle(item.contextKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
                .frame(minHeight: 160)

                if let selectedItemID,
                   let item = preset.items.first(where: { $0.id == selectedItemID }) {
                    ContextItemEditor(presetID: presetID, itemID: item.id, item: item)
                }
            }
        }
    }

    private func contextTitle(_ key: String?) -> String {
        [
            "path": "路径", "branch": "Git 分支", "changes": "改动数量",
            "python": "Python", "node": "Node",
            "java": "Java", "go": "Go", "rust": "Rust", "ruby": "Ruby",
            "php": "PHP", "swift": "Swift", "docker": "Docker",
            "kubernetes": "Kubernetes", "terraform": "Terraform",
            "cmake": "CMake", "xcode": "Xcode",
            "provider": "Agent 厂商", "task": "任务", "status": "状态",
            "detail": "详情", "duration": "耗时", "sessions": "会话列表",
            "event": "事件", "tool": "工具", "cwd": "工作目录", "message": "消息"
        ][key ?? ""] ?? "未设置"
    }
}

private struct ContextItemEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    let itemID: UUID
    let item: TouchBarItemConfiguration

    var body: some View {
        Form {
            TextField("显示名称", text: stringBinding(\.label))
            Picker("上下文字段", selection: optionalStringBinding(\.contextKey)) {
                Text("路径").tag("path")
                Text("Git 分支").tag("branch")
                Text("改动数量").tag("changes")
                Text("Python").tag("python")
                Text("Node").tag("node")
                Text("Java").tag("java")
                Text("Go").tag("go")
                Text("Rust").tag("rust")
                Text("Ruby").tag("ruby")
                Text("PHP").tag("php")
                Text("Swift").tag("swift")
                Text("Docker").tag("docker")
                Text("Kubernetes").tag("kubernetes")
                Text("Terraform").tag("terraform")
                Text("CMake").tag("cmake")
                Text("Xcode").tag("xcode")
                Text("会话列表").tag("sessions")
                Text("事件").tag("event")
                Text("工具").tag("tool")
                Text("工作目录").tag("cwd")
                Text("消息").tag("message")
                Text("Agent 厂商").tag("provider")
                Text("任务").tag("task")
                Text("状态").tag("status")
                Text("详情").tag("detail")
                Text("耗时").tag("duration")
            }
            Picker("宽度", selection: widthBinding) {
                Text("紧凑").tag(TouchBarItemWidth.compact)
                Text("常规").tag(TouchBarItemWidth.regular)
                Text("宽").tag(TouchBarItemWidth.wide)
            }
            Button("删除字段", role: .destructive) {
                store.deleteItem(presetID: presetID, itemID: itemID)
            }
        }
        .formStyle(.columns)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var currentItem: TouchBarItemConfiguration? {
        store.configuration.presets
            .first(where: { $0.id == presetID })?
            .items.first(where: { $0.id == itemID })
    }

    private func stringBinding(_ keyPath: WritableKeyPath<TouchBarItemConfiguration, String>) -> Binding<String> {
        Binding(
            get: { currentItem?[keyPath: keyPath] ?? item[keyPath: keyPath] },
            set: { value in
                guard var updated = currentItem else { return }
                updated[keyPath: keyPath] = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<TouchBarItemConfiguration, String?>) -> Binding<String> {
        Binding(
            get: { currentItem?[keyPath: keyPath] ?? "path" },
            set: { value in
                guard var updated = currentItem else { return }
                updated[keyPath: keyPath] = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var widthBinding: Binding<TouchBarItemWidth> {
        Binding(
            get: { currentItem?.width ?? .regular },
            set: { value in
                guard var updated = currentItem else { return }
                updated.width = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }
}

private struct MessagesPresetDetail: View {
    @EnvironmentObject private var store: AppStore

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.messages.showNotificationBanners },
            set: { value in store.updateConfiguration { $0.messages.showNotificationBanners = value } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("新消息到达时显示通知", isOn: notificationsBinding)
            Text("Touch Bar 会从 Dock 角标读取未读数，并展示 Hook 上报的最新消息。微信、QQ、Telegram、企业微信、飞书与 Lark 可以单独配置。")
                .foregroundStyle(.secondary)
            TextField(
                "监听的 Bundle ID（每行一个）",
                text: Binding(
                    get: { store.configuration.messages.monitoredApplications.joined(separator: "\n") },
                    set: { value in
                        store.updateConfiguration {
                            $0.messages.monitoredApplications = value
                                .split(separator: "\n")
                                .map(String.init)
                                .filter { !$0.isEmpty }
                        }
                    }
                ),
                axis: .vertical
            )
            .lineLimit(8, reservesSpace: true)
            .font(.system(.body, design: .monospaced))
        }
    }
}


private struct SettingsEmptyState: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}
