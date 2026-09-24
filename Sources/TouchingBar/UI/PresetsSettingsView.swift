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
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .metrics: return "chart.bar.xaxis"
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

                if preset.kind == .custom {
                    Label("自由组件 · 每个组件都是独立的 Touch Bar 项目", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
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
                }

                Divider()

                if preset.kind == .custom {
                    CustomPresetEditor(presetID: preset.id, selectedItemID: $selectedItemID)
                } else {
                    switch preset.content {
                    case .unreadMessages:
                        MessagesPresetDetail()
                    case .actions, .nowPlaying:
                        ActionItemsEditor(presetID: preset.id, selectedItemID: $selectedItemID)
                    case .developerContext, .agentContext, .components:
                        ContextItemsEditor(presetID: preset.id, selectedItemID: $selectedItemID)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .components: return "自由组件"
        }
    }

    private func kindTitle(_ kind: PresetKind) -> String {
        switch kind {
        case .functionKeys: return "功能键"
        case .systemFunctions: return "系统功能键"
        case .developer: return "开发者"
        case .agents: return "Agent"
        case .messages: return "消息"
        case .metrics: return "系统资源"
        case .music: return "音乐"
        case .custom: return "自定义"
        }
    }
}

private struct ContextComponentOption: Identifiable {
    let id: String
    let title: String
    let key: String
    let width: TouchBarItemWidth
    let symbol: String
}

private struct CustomPresetEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    @Binding var selectedItemID: UUID?

    private static let metricOptions: [ContextComponentOption] = [
        .init(id: "cpu", title: "CPU", key: "cpu", width: .compact, symbol: "cpu"),
        .init(id: "gpu", title: "GPU", key: "gpu", width: .compact, symbol: "display"),
        .init(id: "memory", title: "内存", key: "memory", width: .compact, symbol: "memorychip"),
        .init(id: "disk", title: "硬盘", key: "disk", width: .compact, symbol: "internaldrive"),
        .init(id: "cpuTemperature", title: "CPU 温度", key: "cpuTemperature", width: .compact, symbol: "thermometer.medium"),
        .init(id: "fanRPM", title: "风扇", key: "fanRPM", width: .compact, symbol: "fan"),
        .init(id: "networkDownload", title: "下载速度", key: "networkDownload", width: .compact, symbol: "arrow.down.circle"),
        .init(id: "networkUpload", title: "上传速度", key: "networkUpload", width: .compact, symbol: "arrow.up.circle")
    ]

    private static let developerOptions: [ContextComponentOption] = [
        .init(id: "path", title: "路径", key: "path", width: .wide, symbol: "folder"),
        .init(id: "branch", title: "Git 分支", key: "branch", width: .regular, symbol: "arrow.triangle.branch"),
        .init(id: "changes", title: "改动数量", key: "changes", width: .regular, symbol: "plus.forwardslash.minus"),
        .init(id: "python", title: "Python", key: "python", width: .regular, symbol: "chevron.left.forwardslash.chevron.right"),
        .init(id: "node", title: "Node", key: "node", width: .regular, symbol: "shippingbox"),
        .init(id: "java", title: "Java", key: "java", width: .regular, symbol: "cup.and.saucer"),
        .init(id: "go", title: "Go", key: "go", width: .regular, symbol: "bolt.horizontal"),
        .init(id: "rust", title: "Rust", key: "rust", width: .regular, symbol: "gearshape.2"),
        .init(id: "swift", title: "Swift", key: "swift", width: .regular, symbol: "swift"),
        .init(id: "docker", title: "Docker", key: "docker", width: .regular, symbol: "shippingbox.fill"),
        .init(id: "xcode", title: "Xcode", key: "xcode", width: .regular, symbol: "hammer")
    ]

    private static let agentOptions: [ContextComponentOption] = [
        .init(id: "provider", title: "Agent 厂商", key: "provider", width: .regular, symbol: "person.crop.circle"),
        .init(id: "task", title: "Agent 任务", key: "task", width: .wide, symbol: "text.bubble"),
        .init(id: "status", title: "Agent 状态", key: "status", width: .regular, symbol: "circle.dashed"),
        .init(id: "detail", title: "Agent 详情", key: "detail", width: .wide, symbol: "text.alignleft"),
        .init(id: "duration", title: "Agent 耗时", key: "duration", width: .regular, symbol: "timer"),
        .init(id: "sessions", title: "Agent 会话", key: "sessions", width: .wide, symbol: "rectangle.stack"),
        .init(id: "cwd", title: "Agent 目录", key: "cwd", width: .wide, symbol: "folder")
    ]

    private var preset: TouchBarPreset? {
        store.configuration.presets.first(where: { $0.id == presetID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("组件").font(.headline)
                    Text("每个组件都是独立的 Touch Bar 项目，可以分别添加、排序与删除。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                addComponentMenu
            }

            if let preset {
                if preset.items.isEmpty {
                    SettingsEmptyState(
                        title: "还没有组件",
                        systemImage: "square.grid.2x2"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedItemID) {
                        ForEach(preset.items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.symbolName ?? "circle")
                                    .frame(width: 18)
                                Text(item.label)
                                Spacer()
                                Text(componentDescription(item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(item.id)
                        }
                        .onMove { offsets, destination in
                            store.moveItems(
                                presetID: presetID,
                                fromOffsets: offsets,
                                toOffset: destination
                            )
                        }
                    }
                    .frame(minHeight: 220)

                    if let selectedItemID,
                       let item = preset.items.first(where: { $0.id == selectedItemID }) {
                        if item.presentation == .context {
                            ContextItemEditor(presetID: presetID, itemID: item.id, item: item)
                        } else {
                            ActionItemEditor(presetID: presetID, itemID: item.id, item: item)
                        }
                    }
                }
            }
        }
    }

    private var addComponentMenu: some View {
        Menu {
            Section("媒体控件") {
                Button("上一曲") {
                    addMedia("上一曲", symbol: "backward.fill", command: .previous)
                }
                Button("播放/暂停") {
                    addMedia("播放/暂停", symbol: "playpause.fill", command: .playPause)
                }
                Button("下一曲") {
                    addMedia("下一曲", symbol: "forward.fill", command: .next)
                }
            }

            Section("播放与显示") {
                Button("正在播放") {
                    addContext("正在播放", key: "nowPlaying", width: .wide, symbol: "music.note")
                }
                Button("歌词") {
                    addContext("歌词", key: "lyric", width: .wide, symbol: "quote.bubble")
                }
                Button("未读汇总") {
                    addContext("未读汇总", key: "unreadSummary", width: .regular, symbol: "message.badge")
                }
                Button("最新消息") {
                    addContext("最新消息", key: "latestMessage", width: .wide, symbol: "text.bubble")
                }
            }

            Section("系统资源") {
                ForEach(Self.metricOptions) { option in
                    Button(option.title) {
                        addContext(option)
                    }
                }
            }

            Section("开发者") {
                ForEach(Self.developerOptions) { option in
                    Button(option.title) {
                        addContext(option)
                    }
                }
            }

            Section("Agent") {
                ForEach(Self.agentOptions) { option in
                    Button(option.title) {
                        addContext(option)
                    }
                }
            }

            Section("系统功能") {
                systemFunctionButtons
            }

            Section("自定义") {
                Button("普通按钮") {
                    addAction("按钮", symbol: "circle", width: .regular, action: .none)
                }
                Button("键盘快捷键") {
                    addAction("快捷键", symbol: "keyboard", width: .regular, action: ActionSpec(kind: .keyboardShortcut))
                }
                Button("启动应用") {
                    addAction("启动应用", symbol: "app", width: .regular, action: ActionSpec(kind: .launchApplication))
                }
                Button("打开 URL") {
                    addAction("打开 URL", symbol: "link", width: .regular, action: ActionSpec(kind: .openURL))
                }
                Button("运行命令") {
                    addAction("运行命令", symbol: "terminal", width: .regular, action: ActionSpec(kind: .runCommand))
                }
            }
        } label: {
            Label("添加组件", systemImage: "plus")
        }
    }

    @ViewBuilder
    private var systemFunctionButtons: some View {
        Button("调度中心") {
            addAction("调度中心", symbol: "rectangle.3.group", width: .compact, action: ActionSpec(kind: .missionControl))
        }
        Button("快速锁屏") {
            addAction("快速锁屏", symbol: "lock.fill", width: .compact, action: ActionSpec(kind: .lockScreen))
        }
        Button("亮度减") {
            addAction("亮度减", symbol: "sun.min", width: .compact, action: ActionSpec(kind: .brightness, value: "down"))
        }
        Button("亮度增") {
            addAction("亮度增", symbol: "sun.max", width: .compact, action: ActionSpec(kind: .brightness, value: "up"))
        }
        Button("键盘灯开") {
            addAction("键盘灯开", symbol: "light.max", width: .compact, action: ActionSpec(kind: .keyboardBacklight, value: "on"))
        }
        Button("键盘灯关") {
            addAction("键盘灯关", symbol: "light.min", width: .compact, action: ActionSpec(kind: .keyboardBacklight, value: "off"))
        }
        Button("静音") {
            addAction("静音", symbol: "speaker.slash.fill", width: .compact, action: ActionSpec(kind: .volume, volume: .mute))
        }
        Button("音量减") {
            addAction("音量减", symbol: "speaker.wave.1.fill", width: .compact, action: ActionSpec(kind: .volume, volume: .down))
        }
        Button("音量增") {
            addAction("音量增", symbol: "speaker.wave.3.fill", width: .compact, action: ActionSpec(kind: .volume, volume: .up))
        }
    }

    private func addMedia(_ title: String, symbol: String, command: MediaCommand) {
        addAction(title, symbol: symbol, width: .compact, action: ActionSpec(kind: .media, media: command))
    }

    private func addContext(_ option: ContextComponentOption) {
        addContext(option.title, key: option.key, width: option.width, symbol: option.symbol)
    }

    private func addContext(
        _ title: String,
        key: String,
        width: TouchBarItemWidth,
        symbol: String
    ) {
        add(
            TouchBarItemConfiguration(
                label: title,
                symbolName: symbol,
                width: width,
                presentation: .context,
                contextKey: key
            )
        )
    }

    private func addAction(
        _ title: String,
        symbol: String,
        width: TouchBarItemWidth,
        action: ActionSpec
    ) {
        add(
            TouchBarItemConfiguration(
                label: title,
                symbolName: symbol,
                width: width,
                presentation: .button,
                action: action
            )
        )
    }

    private func add(_ item: TouchBarItemConfiguration) {
        store.addItem(toPresetID: presetID, item: item)
        selectedItemID = item.id
    }

    private func componentDescription(_ item: TouchBarItemConfiguration) -> String {
        if item.presentation == .context {
            return contextTitle(item.contextKey)
        }
        if item.action.kind == .media {
            return "媒体控件"
        }
        return actionTitle(item.action.kind)
    }

    private func contextTitle(_ key: String?) -> String {
        [
            "path": "路径", "branch": "Git 分支", "changes": "改动数量",
            "python": "Python", "node": "Node", "java": "Java", "go": "Go",
            "rust": "Rust", "swift": "Swift", "docker": "Docker", "xcode": "Xcode",
            "cpu": "CPU", "gpu": "GPU", "memory": "内存", "disk": "硬盘",
            "cpuTemperature": "CPU 温度", "fanRPM": "风扇",
            "networkDownload": "下载速度", "networkUpload": "上传速度",
            "nowPlaying": "正在播放", "lyric": "当前歌词",
            "unreadSummary": "未读汇总", "latestMessage": "最新消息",
            "messageBadges": "消息角标", "provider": "Agent 厂商",
            "task": "任务", "status": "状态", "detail": "详情",
            "duration": "耗时", "sessions": "会话列表", "event": "事件",
            "tool": "工具", "cwd": "工作目录", "message": "消息"
        ][key ?? ""] ?? "上下文"
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
                            if let symbol = item.symbolName {
                                Image(systemName: symbol)
                            }
                            Text(item.label)
                            Spacer()
                            Text(item.presentation == .context ? contextTitle(item.contextKey) : "动作按钮")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
                .frame(minHeight: 160)

                if let selectedItemID,
                   let item = preset.items.first(where: { $0.id == selectedItemID }) {
                    if item.presentation == .context {
                        ContextItemEditor(presetID: presetID, itemID: item.id, item: item)
                    } else {
                        ActionItemEditor(presetID: presetID, itemID: item.id, item: item)
                    }
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
            "cpu": "CPU", "gpu": "GPU", "memory": "内存", "disk": "硬盘",
            "cpuTemperature": "CPU 温度", "fanRPM": "风扇",
            "networkDownload": "下载速度", "networkUpload": "上传速度",
            "nowPlaying": "正在播放", "lyric": "当前歌词",
            "unreadSummary": "未读汇总", "latestMessage": "最新消息",
            "messageBadges": "消息角标",
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
                Text("CPU").tag("cpu")
                Text("GPU").tag("gpu")
                Text("内存").tag("memory")
                Text("硬盘").tag("disk")
                Text("CPU 温度").tag("cpuTemperature")
                Text("风扇").tag("fanRPM")
                Text("下载速度").tag("networkDownload")
                Text("上传速度").tag("networkUpload")
                Text("正在播放").tag("nowPlaying")
                Text("当前歌词").tag("lyric")
                Text("未读汇总").tag("unreadSummary")
                Text("最新消息").tag("latestMessage")
                Text("消息角标").tag("messageBadges")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
