import AppKit
import SwiftUI
import TouchingBarCore
import UniformTypeIdentifiers

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
                    Menu {
                        Button("新建自定义配置") {
                            store.addPreset()
                            selectedPresetID = store.configuration.activePresetID
                        }
                        Divider()
                        let missingKinds = BuiltInPresets.restorableKinds.filter { kind in
                            !store.configuration.presets.contains(where: { $0.kind == kind })
                        }
                        if missingKinds.isEmpty {
                            Text("所有内置预设都已恢复")
                        } else {
                            ForEach(missingKinds, id: \.self) { kind in
                                Button("恢复 \(BuiltInPresets.title(for: kind))") {
                                    store.restoreBuiltInPreset(kind: kind)
                                    selectedPresetID = store.configuration.activePresetID
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
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
                    .disabled(selectedPresetID == nil)
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
                            ForEach(supportedContents, id: \.self) { content in
                                Text(contentTitle(content)).tag(content)
                            }
                        }
                        .frame(maxWidth: 300)

                        Picker("分类", selection: kindBinding(preset)) {
                            ForEach(BuiltInPresets.restorableKinds, id: \.self) { kind in
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

    private var supportedContents: [PresetContent] {
        [.actions, .developerContext, .nowPlaying, .components]
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
        .init(id: "battery", title: "电池电量", key: "battery", width: .regular, symbol: "battery.75"),
        .init(id: "batteryPower", title: "电池功率", key: "batteryPower", width: .regular, symbol: "bolt.fill"),
        .init(id: "batteryTime", title: "电池时间", key: "batteryTime", width: .regular, symbol: "clock.arrow.circlepath"),
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
                                Image(systemName: item.presentation == .image ? "pawprint.fill" : (item.symbolName ?? "circle"))
                                    .frame(width: 18)
                                Text(item.label)
                                if item.isHidden {
                                    Image(systemName: "eye.slash")
                                        .foregroundStyle(.secondary)
                                }
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
                    .frame(minHeight: 180, maxHeight: 240)

                    if let selectedItemID,
                       let item = preset.items.first(where: { $0.id == selectedItemID }) {
                        ScrollView {
                            switch item.presentation {
                            case .context:
                                ContextItemEditor(presetID: presetID, itemID: item.id, item: item)
                            case .image:
                                PetItemEditor(presetID: presetID, itemID: item.id, item: item)
                            case .button, .label:
                                ActionItemEditor(presetID: presetID, itemID: item.id, item: item)
                            }
                        }
                        .frame(maxHeight: 300)
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
            }

            Section("宠物") {
                Button("宠物") {
                    addPet()
                }
            }

            Section("日期与时间") {
                Button("日期") {
                    addContext("日期", key: "date", width: .regular, symbol: "calendar")
                }
                Button("时间") {
                    addContext("时间", key: "time", width: .regular, symbol: "clock")
                }
                Button("日期 + 时间") {
                    addContext("日期时间", key: "dateTime", width: .wide, symbol: "calendar.badge.clock")
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
        Button("键盘灯 +") {
            addAction("键盘灯 +", symbol: "light.max", width: .regular, action: ActionSpec(kind: .keyboardBacklight, value: "up"))
        }
        Button("键盘灯 -") {
            addAction("键盘灯 -", symbol: "light.min", width: .regular, action: ActionSpec(kind: .keyboardBacklight, value: "down"))
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

    private func addPet() {
        add(
            TouchBarItemConfiguration(
                label: "宠物",
                symbolName: "pawprint.fill",
                width: .compact,
                presentation: .image
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
        var item = item
        item.width = .regular
        item.customWidth = nil
        store.addItem(toPresetID: presetID, item: item)
        selectedItemID = item.id
    }

    private func componentDescription(_ item: TouchBarItemConfiguration) -> String {
        if item.presentation == .image {
            if let petID = item.petID,
               let pet = CodexPetStore.shared.pet(id: petID) {
                return pet.displayName
            }
            return item.imagePath == nil ? "宠物" : "宠物（本地图片）"
        }
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
            "battery": "电池电量", "batteryPower": "电池功率", "batteryTime": "电池时间",
            "nowPlaying": "正在播放", "lyric": "当前歌词",
            "date": "日期", "time": "时间", "dateTime": "日期 + 时间",
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

private struct SymbolChoice: Identifiable {
    let id: String
    let title: String
    let keywords: String
    let category: String
}

private struct IconPickerView: View {
    @Binding var symbolName: String
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var selectedCategory = "全部"

    private static let choices: [SymbolChoice] = [
        .init(id: "circle", title: "圆点", keywords: "圆 图标 通用", category: "常用"),
        .init(id: "square", title: "方块", keywords: "方 图标 通用", category: "常用"),
        .init(id: "star.fill", title: "星标", keywords: "收藏 星 常用", category: "常用"),
        .init(id: "heart.fill", title: "喜欢", keywords: "爱心 收藏", category: "常用"),
        .init(id: "bolt.fill", title: "闪电", keywords: "能量 快速", category: "常用"),
        .init(id: "gearshape.fill", title: "设置", keywords: "齿轮 设置 配置", category: "常用"),
        .init(id: "plus", title: "加号", keywords: "增加 添加", category: "常用"),
        .init(id: "minus", title: "减号", keywords: "减少 删除", category: "常用"),
        .init(id: "checkmark", title: "确认", keywords: "完成 对勾", category: "常用"),
        .init(id: "xmark", title: "关闭", keywords: "取消 叉", category: "常用"),
        .init(id: "info.circle", title: "信息", keywords: "说明 提示", category: "常用"),
        .init(id: "questionmark.circle", title: "帮助", keywords: "问题 提示", category: "常用"),

        .init(id: "backward.fill", title: "上一曲", keywords: "音乐 媒体 后退", category: "媒体"),
        .init(id: "playpause.fill", title: "播放暂停", keywords: "音乐 媒体 播放", category: "媒体"),
        .init(id: "forward.fill", title: "下一曲", keywords: "音乐 媒体 前进", category: "媒体"),
        .init(id: "play.fill", title: "播放", keywords: "音乐 媒体", category: "媒体"),
        .init(id: "pause.fill", title: "暂停", keywords: "音乐 媒体", category: "媒体"),
        .init(id: "speaker.wave.3.fill", title: "音量", keywords: "声音 音量 扬声器", category: "媒体"),
        .init(id: "speaker.wave.1.fill", title: "音量低", keywords: "声音 音量 小", category: "媒体"),
        .init(id: "speaker.slash.fill", title: "静音", keywords: "声音 静音 关闭", category: "媒体"),
        .init(id: "music.note", title: "音乐", keywords: "歌曲 音符", category: "媒体"),
        .init(id: "quote.bubble", title: "歌词", keywords: "歌词 文本 气泡", category: "媒体"),
        .init(id: "waveform", title: "波形", keywords: "音频 播放 波动", category: "媒体"),

        .init(id: "lock.fill", title: "锁屏", keywords: "锁定 安全 锁", category: "系统"),
        .init(id: "rectangle.3.group", title: "调度中心", keywords: "窗口 任务 调度", category: "系统"),
        .init(id: "sun.min", title: "亮度减", keywords: "屏幕 亮度 太阳", category: "系统"),
        .init(id: "sun.max", title: "亮度增", keywords: "屏幕 亮度 太阳", category: "系统"),
        .init(id: "light.max", title: "键盘灯 +", keywords: "键盘 背光 灯 增亮", category: "系统"),
        .init(id: "light.min", title: "键盘灯 -", keywords: "键盘 背光 灯 调暗", category: "系统"),
        .init(id: "moon.fill", title: "专注", keywords: "月亮 勿扰 专注", category: "系统"),
        .init(id: "display", title: "显示器", keywords: "屏幕 显示", category: "系统"),
        .init(id: "keyboard", title: "键盘", keywords: "输入 快捷键", category: "系统"),
        .init(id: "command", title: "Command", keywords: "快捷键 命令", category: "系统"),
        .init(id: "power", title: "电源", keywords: "关机 开机", category: "系统"),
        .init(id: "magnifyingglass", title: "搜索", keywords: "查找 放大镜", category: "系统"),

        .init(id: "cpu", title: "CPU", keywords: "处理器 性能 资源", category: "资源"),
        .init(id: "memorychip", title: "内存", keywords: "内存 资源", category: "资源"),
        .init(id: "internaldrive", title: "硬盘", keywords: "磁盘 存储", category: "资源"),
        .init(id: "thermometer.medium", title: "温度", keywords: "温度 发热 传感器", category: "资源"),
        .init(id: "fan", title: "风扇", keywords: "散热 风扇", category: "资源"),
        .init(id: "arrow.down.circle", title: "下载", keywords: "网络 下载 速度", category: "资源"),
        .init(id: "arrow.up.circle", title: "上传", keywords: "网络 上传 速度", category: "资源"),
        .init(id: "chart.xyaxis.line", title: "图表", keywords: "趋势 监控 折线", category: "资源"),
        .init(id: "gauge.medium", title: "仪表", keywords: "性能 速度", category: "资源"),
        .init(id: "network", title: "网络", keywords: "网速 连接", category: "资源"),
        .init(id: "wifi", title: "Wi-Fi", keywords: "网络 无线", category: "资源"),
        .init(id: "battery.100", title: "电池", keywords: "电量 电源", category: "资源"),

        .init(id: "chevron.left.forwardslash.chevron.right", title: "代码", keywords: "开发 代码", category: "开发"),
        .init(id: "terminal", title: "终端", keywords: "命令行 shell", category: "开发"),
        .init(id: "hammer", title: "构建", keywords: "编译 构建 工具", category: "开发"),
        .init(id: "wrench.and.screwdriver", title: "工具", keywords: "修复 工具", category: "开发"),
        .init(id: "shippingbox", title: "包", keywords: "依赖 软件包", category: "开发"),
        .init(id: "arrow.triangle.branch", title: "分支", keywords: "git 分支", category: "开发"),
        .init(id: "swift", title: "Swift", keywords: "swift 语言", category: "开发"),
        .init(id: "curlybraces", title: "花括号", keywords: "代码 json", category: "开发"),
        .init(id: "doc.text", title: "文档", keywords: "文件 文本", category: "开发"),
        .init(id: "list.bullet", title: "列表", keywords: "清单 列表", category: "开发"),

        .init(id: "person.crop.circle", title: "用户", keywords: "agent 角色 用户", category: "Agent"),
        .init(id: "text.bubble", title: "消息", keywords: "agent 对话 文本", category: "Agent"),
        .init(id: "circle.dashed", title: "状态", keywords: "agent 进行中 状态", category: "Agent"),
        .init(id: "timer", title: "耗时", keywords: "agent 计时 时间", category: "Agent"),
        .init(id: "rectangle.stack", title: "会话", keywords: "agent 会话 列表", category: "Agent"),
        .init(id: "sparkles", title: "智能", keywords: "agent ai 生成", category: "Agent"),
        .init(id: "brain.head.profile", title: "思考", keywords: "agent ai 思考", category: "Agent"),
        .init(id: "bolt.horizontal", title: "活动", keywords: "agent 动作 活动", category: "Agent"),

        .init(id: "message.badge", title: "未读消息", keywords: "消息 聊天 角标", category: "通信"),
        .init(id: "envelope.fill", title: "邮件", keywords: "邮件 信封", category: "通信"),
        .init(id: "phone.fill", title: "电话", keywords: "电话 通话", category: "通信"),
        .init(id: "video.fill", title: "视频", keywords: "视频 通话", category: "通信"),
        .init(id: "bell.fill", title: "通知", keywords: "提醒 通知", category: "通信"),
        .init(id: "at", title: "@", keywords: "提及 邮件", category: "通信"),
        .init(id: "paperplane.fill", title: "发送", keywords: "发送 消息", category: "通信")
    ]

    static func contains(_ symbolName: String) -> Bool {
        choices.contains { $0.id == symbolName }
    }

    private var categories: [String] {
        ["全部", "常用", "媒体", "系统", "资源", "开发", "Agent", "通信"]
    }

    private var filteredChoices: [SymbolChoice] {
        Self.choices.filter { choice in
            let matchesCategory = selectedCategory == "全部" || choice.category == selectedCategory
            guard matchesCategory else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            return choice.title.lowercased().contains(query)
                || choice.id.lowercased().contains(query)
                || choice.keywords.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择图标").font(.title3.bold())
                Spacer()
                Button("完成") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            TextField("搜索图标，例如：播放、音量、CPU、锁屏", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("分类", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 66), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(filteredChoices) { choice in
                        Button {
                            symbolName = choice.id
                            isPresented = false
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: choice.id)
                                    .font(.system(size: 23, weight: .medium))
                                Text(choice.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .padding(4)
                            .background(
                                symbolName == choice.id
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(choice.id)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text(symbolName.isEmpty ? "当前：无图标" : "当前：\(symbolName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("使用当前值") { isPresented = false }
                Button("清空图标", role: .destructive) {
                    symbolName = ""
                    isPresented = false
                }
            }
        }
        .padding(16)
        .frame(width: 620, height: 500)
    }
}

private struct ActionItemsEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    @Binding var selectedItemID: UUID?

    private var preset: TouchBarPreset? {
        store.configuration.presets.first(where: { $0.id == presetID })
    }

    private var presetHideWhenNotPlayingBinding: Binding<Bool> {
        Binding(
            get: { preset?.effectiveHideWhenNotPlaying ?? false },
            set: { value in
                guard var updated = preset else { return }
                updated.hideWhenNotPlaying = value
                store.replacePreset(updated)
            }
        )
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

            if preset?.content == .nowPlaying {
                Toggle("未播放时隐藏", isOn: presetHideWhenNotPlayingBinding)
                    .toggleStyle(.switch)
            }

            if let preset, !preset.items.isEmpty {
                List(selection: $selectedItemID) {
                    ForEach(preset.items) { item in
                        HStack {
                            if let symbol = item.symbolName {
                                Image(systemName: symbol)
                            }
                            Text(item.label)
                            if item.isHidden {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(actionTitle(item.action.kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
                .frame(minHeight: 130, maxHeight: 220)

                if let selectedItemID,
                   let item = preset.items.first(where: { $0.id == selectedItemID }) {
                    ScrollView {
                        ActionItemEditor(presetID: presetID, itemID: item.id, item: item)
                    }
                    .frame(maxHeight: 300)
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

private struct WidthEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    let itemID: UUID
    let item: TouchBarItemConfiguration
    @State private var customWidthText = ""
    @FocusState private var customWidthFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Picker("宽度", selection: widthBinding) {
                Text("紧凑").tag(TouchBarItemWidth.compact)
                Text("常规").tag(TouchBarItemWidth.regular)
                Text("宽").tag(TouchBarItemWidth.wide)
                Text("自定义").tag(TouchBarItemWidth.custom)
            }

            if selectedWidth == .custom {
                TextField("", text: $customWidthText)
                    .frame(width: 72)
                    .focused($customWidthFocused)
                    .onSubmit { commitCustomWidthText() }
                    .onChange(of: customWidthText) { value in
                        applyCustomWidthTextIfValid(value)
                    }
                Text("pt")
                    .foregroundStyle(.secondary)
                Slider(value: customWidthBinding, in: 40...1200, step: 1)
                    .frame(minWidth: 180)
            }
        }
        .onAppear { syncCustomWidthText() }
        .onChange(of: selectedWidth) { _ in syncCustomWidthText() }
        .onChange(of: currentItem?.customWidth) { _ in
            if !customWidthFocused {
                syncCustomWidthText()
            }
        }
        .onChange(of: customWidthFocused) { focused in
            if !focused {
                commitCustomWidthText()
            }
        }
    }

    private var currentItem: TouchBarItemConfiguration? {
        store.configuration.presets
            .first(where: { $0.id == presetID })?
            .items.first(where: { $0.id == itemID })
    }

    private var selectedWidth: TouchBarItemWidth {
        currentItem?.width ?? item.width
    }

    private var widthBinding: Binding<TouchBarItemWidth> {
        Binding(
            get: { selectedWidth },
            set: { value in
                guard var updated = currentItem else { return }
                updated.width = value
                if value == .custom, updated.customWidth == nil {
                    updated.customWidth = suggestedWidth(for: updated)
                }
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var customWidthBinding: Binding<Double> {
        Binding(
            get: { clamped(currentItem?.customWidth ?? suggestedWidth(for: currentItem ?? item)) },
            set: { value in
                guard var updated = currentItem else { return }
                updated.width = .custom
                updated.customWidth = clamped(value)
                store.updateItem(presetID: presetID, item: updated)
                customWidthText = String(format: "%.0f", updated.customWidth ?? value)
            }
        )
    }

    private func syncCustomWidthText() {
        let value = currentItem?.customWidth ?? suggestedWidth(for: currentItem ?? item)
        customWidthText = String(format: "%.0f", clamped(value))
    }

    private func applyCustomWidthTextIfValid(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = Double(trimmed),
              value >= 40,
              value <= 1200,
              var updated = currentItem else {
            return
        }
        updated.width = .custom
        updated.customWidth = value
        store.updateItem(presetID: presetID, item: updated)
    }

    private func commitCustomWidthText() {
        let trimmed = customWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), var updated = currentItem else {
            syncCustomWidthText()
            return
        }
        updated.width = .custom
        updated.customWidth = clamped(value)
        store.updateItem(presetID: presetID, item: updated)
        customWidthText = String(format: "%.0f", updated.customWidth ?? value)
    }

    private func suggestedWidth(for item: TouchBarItemConfiguration) -> Double {
        if let customWidth = item.customWidth {
            return customWidth
        }
        if item.presentation == .image {
            switch item.width {
            case .compact: return 44
            case .regular: return 80
            case .wide: return 140
            case .custom: return 80
            }
        }
        let key = item.contextKey ?? ""
        if ["lyric", "nowPlaying"].contains(key) {
            switch item.width {
            case .compact: return 120
            case .regular: return 240
            case .wide: return 480
            case .custom: return 240
            }
        }
        if ["date", "time"].contains(key) {
            switch item.width {
            case .compact: return 60
            case .regular: return 120
            case .wide: return 240
            case .custom: return 120
            }
        }
        if ["dateTime"].contains(key) {
            switch item.width {
            case .compact: return 120
            case .regular: return 240
            case .wide: return 480
            case .custom: return 240
            }
        }
        if ["latestMessage", "unreadSummary", "messageBadges"].contains(key) {
            switch item.width {
            case .compact: return 90
            case .regular: return 180
            case .wide: return 360
            case .custom: return 180
            }
        }
        if ["cpu", "gpu", "memory", "disk", "cpuTemperature", "fanRPM", "networkDownload", "networkUpload"].contains(key) {
            switch item.width {
            case .compact: return 60
            case .regular: return 120
            case .wide: return 240
            case .custom: return 120
            }
        }
        if ["path", "branch", "changes", "python", "node", "java", "go", "rust", "ruby", "php", "swift", "docker", "kubernetes", "terraform", "cmake", "xcode"].contains(key) {
            switch item.width {
            case .compact: return 60
            case .regular: return 120
            case .wide: return 240
            case .custom: return 120
            }
        }
        if ["provider", "task", "status", "detail", "duration", "sessions", "event", "tool", "cwd", "message"].contains(key) {
            switch item.width {
            case .compact: return 60
            case .regular: return 120
            case .wide: return 240
            case .custom: return 120
            }
        }
        switch item.width {
        case .compact:
            return 60
        case .regular:
            return 120
        case .wide:
            return 240
        case .custom:
            return 120
        }
    }

    private func clamped(_ value: Double) -> Double {
        max(40, min(1200, value))
    }
}

private struct ActionItemEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    let itemID: UUID
    let item: TouchBarItemConfiguration
    @State private var showingIconPicker = false
    @State private var useManualSymbolEntry = false

    var body: some View {
        Form {
            TextField("名称", text: binding(\.label))
            Toggle("自定义图标", isOn: $useManualSymbolEntry)
                .toggleStyle(.switch)

            if useManualSymbolEntry {
                HStack(spacing: 8) {
                    Image(systemName: displaySymbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 22)
                    TextField("SF Symbol", text: optionalBinding(\.symbolName))
                }
            } else {
                Button {
                    showingIconPicker = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: displaySymbolName)
                            .font(.system(size: 16, weight: .semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("选择图标")
                            Text(displaySymbolName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: 180, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .help("从图标库中选择，不需要知道 SF Symbol 名称")
                .sheet(isPresented: $showingIconPicker) {
                    IconPickerView(
                        symbolName: optionalBinding(\.symbolName),
                        isPresented: $showingIconPicker
                    )
                }
            }

            WidthEditor(presetID: presetID, itemID: itemID, item: item)
            Picker("动作", selection: actionBinding(\.kind)) {
                ForEach(TouchBarActionKind.allCases, id: \.self) { kind in
                    Text(actionTitle(kind)).tag(kind)
                }
            }

            actionDetails

            if isMusicRelatedItem {
                Toggle("未播放时隐藏", isOn: hideWhenNotPlayingBinding)
                    .toggleStyle(.switch)
            }

            Toggle("隐藏组件", isOn: hiddenBinding)
                .toggleStyle(.switch)

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
        .onAppear {
            useManualSymbolEntry = !IconPickerView.contains(displaySymbolName)
        }
    }

    private var displaySymbolName: String {
        let name = currentItem?.symbolName ?? item.symbolName ?? ""
        return name.isEmpty ? "circle" : name
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
                Text("调暗").tag("down")
                Text("增亮").tag("up")
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

    private var isMusicRelatedItem: Bool {
        let action = currentItem?.action ?? item.action
        let key = currentItem?.contextKey ?? item.contextKey
        return action.kind == .media || key == "nowPlaying" || key == "lyric"
    }

    private var hideWhenNotPlayingBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.hideWhenNotPlaying ?? item.hideWhenNotPlaying },
            set: { value in
                guard var updated = currentItem else { return }
                updated.hideWhenNotPlaying = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var hiddenBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.isHidden ?? item.isHidden },
            set: { value in
                guard var updated = currentItem else { return }
                updated.isHidden = value
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

private struct PetItemEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    let itemID: UUID
    let item: TouchBarItemConfiguration
    @State private var installedPets: [CodexPet] = []
    @State private var errorMessage: String?
    @State private var showingGitHubInstaller = false

    var body: some View {
        Form {
            TextField("名称", text: binding(\.label))

            HStack {
                Text("已安装宠物")
                Spacer()
                Menu {
                    Button("未选择") {
                        petBinding.wrappedValue = ""
                    }
                    ForEach(installedPets) { pet in
                        Button(pet.displayName) {
                            petBinding.wrappedValue = pet.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedPet?.displayName ?? "未选择")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .frame(width: 190, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if let selectedPet, !selectedPet.assets.isEmpty {
                HStack {
                    Text("动作 / 图片")
                    Spacer()
                    Menu {
                        ForEach(selectedPet.assets) { asset in
                            Button(asset.name) {
                                petAssetBinding.wrappedValue = asset.id
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedAsset?.name ?? "选择")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .frame(width: 190, alignment: .trailing)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            HStack {
                Button("从 GitHub 安装…") {
                    showingGitHubInstaller = true
                }
                Button("从文件夹安装…") {
                    installPetFromFolder()
                }
                Button("扫描 ~/.codex/pets") {
                    installExternalPets()
                }
            }

            if let selectedPet {
                HStack(spacing: 10) {
                    PetItemPreview(image: previewImage(for: selectedPet, asset: selectedAsset))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedPet.displayName)
                        Text("\(selectedPet.id) · \(selectedPet.columns)×\(selectedPet.rows) 帧网格")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let selectedAsset {
                            Text(selectedAsset.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 260, alignment: .leading)
                                .help(selectedAsset.name)
                        }
                    }
                }
            } else if let previewImage {
                HStack(spacing: 10) {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 96, height: 38)
                        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    Text(currentItem?.imagePath ?? item.imagePath ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            } else {
                Label("尚未选择宠物或图片", systemImage: "pawprint")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text("Codex 宠物包需要 pet.json 和精灵图；官方格式为 8×9，兼容 8×11。也可以继续使用本地 PNG、JPEG、GIF 或 WebP。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("图片路径", text: pathBinding)
                Button("选择…") {
                    chooseImage()
                }
            }

            WidthEditor(presetID: presetID, itemID: itemID, item: item)

            Toggle("隐藏组件", isOn: hiddenBinding)
                .toggleStyle(.switch)

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
        .onAppear {
            refreshInstalledPets()
        }
        .sheet(isPresented: $showingGitHubInstaller) {
            GitHubPetInstallSheet { installed in
                refreshInstalledPets()
                if let first = installed.first {
                    select(pet: first)
                }
            }
        }
    }

    private var currentItem: TouchBarItemConfiguration? {
        store.configuration.presets
            .first(where: { $0.id == presetID })?
            .items.first(where: { $0.id == itemID })
    }

    private var selectedPet: CodexPet? {
        guard let id = currentItem?.petID ?? item.petID else { return nil }
        return installedPets.first(where: { $0.id == id }) ?? CodexPetStore.shared.pet(id: id)
    }

    private var selectedAsset: CodexPetAsset? {
        guard let selectedPet else { return nil }
        let id = currentItem?.petAssetID ?? item.petAssetID
        return selectedPet.assets.first(where: { $0.id == id })
            ?? selectedPet.assets.first(where: { $0.id == selectedPet.defaultAssetID })
            ?? selectedPet.assets.first
    }

    private var previewImage: NSImage? {
        guard let path = currentItem?.imagePath ?? item.imagePath, !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var petBinding: Binding<String> {
        Binding(
            get: { currentItem?.petID ?? item.petID ?? "" },
            set: { value in
                guard var updated = currentItem else { return }
                updated.petID = value.isEmpty ? nil : value
                if !value.isEmpty {
                    updated.imagePath = nil
                    if let pet = installedPets.first(where: { $0.id == value }) {
                        updated.label = pet.displayName
                        updated.petAssetID = pet.defaultAssetID
                    }
                }
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var petAssetBinding: Binding<String> {
        Binding(
            get: {
                selectedAsset?.id
                    ?? currentItem?.petAssetID
                    ?? item.petAssetID
                    ?? selectedPet?.defaultAssetID
                    ?? ""
            },
            set: { value in
                guard var updated = currentItem else { return }
                updated.petAssetID = value.isEmpty ? nil : value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { currentItem?.imagePath ?? item.imagePath ?? "" },
            set: { value in
                guard var updated = currentItem else { return }
                updated.imagePath = value.isEmpty ? nil : value
                if !value.isEmpty {
                    updated.petID = nil
                }
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var isMusicRelatedItem: Bool {
        let action = currentItem?.action ?? item.action
        let key = currentItem?.contextKey ?? item.contextKey
        return action.kind == .media || key == "nowPlaying" || key == "lyric"
    }

    private var hideWhenNotPlayingBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.hideWhenNotPlaying ?? item.hideWhenNotPlaying },
            set: { value in
                guard var updated = currentItem else { return }
                updated.hideWhenNotPlaying = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var hiddenBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.isHidden ?? item.isHidden },
            set: { value in
                guard var updated = currentItem else { return }
                updated.isHidden = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
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

    private func refreshInstalledPets() {
        installedPets = CodexPetStore.shared.installedPets()
    }

    private func installPetFromFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 宠物目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "安装宠物"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let installed = try CodexPetStore.shared.install(from: url, replacing: true)
            errorMessage = nil
            refreshInstalledPets()
            if let first = installed.first {
                select(pet: first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installExternalPets() {
        let external = CodexPetStore.shared.externalPets()
        guard !external.isEmpty else {
            errorMessage = "未在 ~/.codex/pets 发现 Codex 宠物"
            return
        }
        do {
            let installed = try external.map { try CodexPetStore.shared.install($0, replacing: true) }
            errorMessage = nil
            refreshInstalledPets()
            if let first = installed.first {
                select(pet: first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(pet: CodexPet) {
        guard var updated = currentItem else { return }
        updated.petID = pet.id
        updated.petAssetID = pet.defaultAssetID
        updated.imagePath = nil
        updated.label = pet.displayName
        store.updateItem(presetID: presetID, item: updated)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "选择 Touch Bar 图片或动图"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              var updated = currentItem else {
            return
        }
        updated.petID = nil
        updated.imagePath = url.path
        store.updateItem(presetID: presetID, item: updated)
    }

    private func previewImage(for pet: CodexPet, asset: CodexPetAsset?) -> NSImage? {
        guard let asset else { return nil }
        switch asset.kind {
        case .spriteRow:
            guard let spritesheet = try? CodexPetSpritesheet(pet: pet),
                  let frame = spritesheet.frames(row: asset.row, count: 1).first else {
                return nil
            }
            return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
        case .imageFile:
            guard let relativePath = asset.relativePath else { return nil }
            return NSImage(contentsOf: pet.directoryURL.appendingPathComponent(relativePath))
        }
    }
}

private struct PetItemPreview: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 38)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
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
                            if item.isHidden {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.presentation == .context ? contextTitle(item.contextKey) : "动作按钮")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
                .frame(minHeight: 130, maxHeight: 220)

                if let selectedItemID,
                   let item = preset.items.first(where: { $0.id == selectedItemID }) {
                    ScrollView {
                        if item.presentation == .context {
                            ContextItemEditor(presetID: presetID, itemID: item.id, item: item)
                        } else {
                            ActionItemEditor(presetID: presetID, itemID: item.id, item: item)
                        }
                    }
                    .frame(maxHeight: 300)
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
            "battery": "电池电量", "batteryPower": "电池功率", "batteryTime": "电池时间",
            "nowPlaying": "正在播放", "lyric": "当前歌词",
            "date": "日期", "time": "时间", "dateTime": "日期 + 时间",
            "unreadSummary": "未读汇总", "latestMessage": "最新消息",
            "messageBadges": "消息角标",
            "provider": "Agent 厂商", "task": "任务", "status": "状态",
            "detail": "详情", "duration": "耗时", "sessions": "会话列表",
            "event": "事件", "tool": "工具", "cwd": "工作目录", "message": "消息"
        ][key ?? ""] ?? "未设置"
    }
}

private struct TextFormatOption: Identifiable {
    let id: String
    let title: String

    init(_ id: String, _ title: String) {
        self.id = id
        self.title = title
    }
}

private struct ContextItemEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    let itemID: UUID
    let item: TouchBarItemConfiguration

    private static let dateFormatOptions: [TextFormatOption] = [
        .init("", "默认（M月d日 EEE）"),
        .init("yyyy-MM-dd", "2026-09-24"),
        .init("M月d日", "9月24日"),
        .init("M/d", "9/24"),
        .init("yyyy年M月d日", "2026年9月24日"),
        .init("EEE, MMM d", "Thu, Sep 24")
    ]

    private static let timeFormatOptions: [TextFormatOption] = [
        .init("", "默认（HH:mm:ss）"),
        .init("HH:mm", "24 小时：22:30"),
        .init("HH:mm:ss", "24 小时带秒：22:30:45"),
        .init("h:mm a", "12 小时：10:30 PM"),
        .init("h:mm:ss a", "12 小时带秒：10:30:45 PM")
    ]

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
                Text("日期").tag("date")
                Text("时间").tag("time")
                Text("日期 + 时间").tag("dateTime")
                Text("电池电量").tag("battery")
                Text("电池功率").tag("batteryPower")
                Text("电池时间").tag("batteryTime")
            }
            if isDateRelatedItem {
                Picker("日期格式", selection: dateFormatBinding) {
                    ForEach(Self.dateFormatOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }
            if isTimeRelatedItem {
                Picker("时间格式", selection: timeFormatBinding) {
                    ForEach(Self.timeFormatOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }
            if isChartMetric {
                ChartColorEditor(presetID: presetID, itemID: itemID, item: item)
            }
            WidthEditor(presetID: presetID, itemID: itemID, item: item)
            if (currentItem?.contextKey ?? item.contextKey) == "lyric" {
                Toggle("双行歌词", isOn: dualLineLyricsBinding)
                    .toggleStyle(.switch)
            }
            if currentItem?.dualLineLyrics == true {
                Text("双行歌词开启时会自动隐藏 Label，上方显示当前句；下方优先显示翻译，无翻译时显示下一句。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("显示标签", isOn: showsLabelBinding)
                    .toggleStyle(.switch)
            }
            if isMusicRelatedItem {
                Toggle("未播放时隐藏", isOn: hideWhenNotPlayingBinding)
                    .toggleStyle(.switch)
            }
            Toggle("隐藏组件", isOn: hiddenBinding)
                .toggleStyle(.switch)
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

    private var contextKey: String {
        currentItem?.contextKey ?? item.contextKey ?? ""
    }

    private var isDateRelatedItem: Bool {
        contextKey == "date" || contextKey == "dateTime"
    }

    private var isTimeRelatedItem: Bool {
        contextKey == "time" || contextKey == "dateTime"
    }

    private var isChartMetric: Bool {
        [
            "cpu", "gpu", "memory", "disk", "cpuTemperature", "fanRPM",
            "networkDownload", "networkUpload", "battery", "batteryPower", "batteryTime"
        ].contains(contextKey)
    }

    private var dateFormatBinding: Binding<String> {
        Binding(
            get: { currentItem?.dateFormat ?? item.dateFormat ?? "" },
            set: { value in
                guard var updated = currentItem else { return }
                updated.dateFormat = value.isEmpty ? nil : value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var timeFormatBinding: Binding<String> {
        Binding(
            get: { currentItem?.timeFormat ?? item.timeFormat ?? "" },
            set: { value in
                guard var updated = currentItem else { return }
                updated.timeFormat = value.isEmpty ? nil : value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var isMusicRelatedItem: Bool {
        let key = currentItem?.contextKey ?? item.contextKey
        return key == "nowPlaying" || key == "lyric"
    }

    private var hideWhenNotPlayingBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.hideWhenNotPlaying ?? item.hideWhenNotPlaying },
            set: { value in
                guard var updated = currentItem else { return }
                updated.hideWhenNotPlaying = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var dualLineLyricsBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.dualLineLyrics ?? item.dualLineLyrics },
            set: { value in
                guard var updated = currentItem else { return }
                updated.dualLineLyrics = value
                if value {
                    updated.showsLabel = false
                }
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var showsLabelBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.showsLabel ?? item.showsLabel },
            set: { value in
                guard var updated = currentItem else { return }
                updated.showsLabel = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
    }

    private var hiddenBinding: Binding<Bool> {
        Binding(
            get: { currentItem?.isHidden ?? item.isHidden },
            set: { value in
                guard var updated = currentItem else { return }
                updated.isHidden = value
                store.updateItem(presetID: presetID, item: updated)
            }
        )
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

}

private enum ChartColorInputMode: String, CaseIterable, Identifiable {
    case hex
    case rgb

    var id: String { rawValue }
}

private struct ChartColorEditor: View {
    @EnvironmentObject private var store: AppStore
    let presetID: UUID
    let itemID: UUID
    let item: TouchBarItemConfiguration

    @State private var hexText = "#000000"
    @State private var redText = "0"
    @State private var greenText = "0"
    @State private var blueText = "0"
    @State private var inputMode: ChartColorInputMode = .hex

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ColorPicker("折线颜色", selection: colorBinding, supportsOpacity: false)
                Spacer()
                Picker("输入方式", selection: $inputMode) {
                    Text("十六进制").tag(ChartColorInputMode.hex)
                    Text("RGB").tag(ChartColorInputMode.rgb)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            switch inputMode {
            case .hex:
                HStack(spacing: 10) {
                    Text("十六进制")
                    TextField("#RRGGBB", text: $hexText)
                        .frame(minWidth: 180)
                        .onSubmit { applyHex() }
                    Button("应用") { applyHex() }
                }
            case .rgb:
                HStack(spacing: 8) {
                    Text("R")
                    TextField("", text: $redText)
                        .labelsHidden()
                        .frame(width: 76)
                    Text("G")
                    TextField("", text: $greenText)
                        .labelsHidden()
                        .frame(width: 76)
                    Text("B")
                    TextField("", text: $blueText)
                        .labelsHidden()
                        .frame(width: 76)
                    Button("应用") { applyRGB() }
                }
            }

            Text("支持 #RRGGBB、RRGGBB 或 0–255 的 RGB 分量。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: syncFromItem)
        .onChange(of: currentItem?.chartColorHex) { _ in
            syncFromItem()
        }
    }

    private var currentItem: TouchBarItemConfiguration? {
        store.configuration.presets
            .first(where: { $0.id == presetID })?
            .items.first(where: { $0.id == itemID })
    }

    private var effectiveColor: NSColor {
        if let hex = currentItem?.chartColorHex ?? item.chartColorHex,
           let color = NSColor(hexRGB: hex) {
            return color
        }
        return .controlAccentColor
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: effectiveColor) },
            set: { newValue in
                guard let color = NSColor(newValue).usingColorSpace(.deviceRGB) else { return }
                updateColor(hex: color.hexRGB)
            }
        )
    }

    private func applyHex() {
        guard let color = NSColor(hexRGB: hexText) else {
            syncFromItem()
            return
        }
        updateColor(hex: color.hexRGB)
    }

    private func applyRGB() {
        guard let red = Int(redText), let green = Int(greenText), let blue = Int(blueText),
              (0...255).contains(red), (0...255).contains(green), (0...255).contains(blue) else {
            syncFromItem()
            return
        }
        let hex = String(format: "#%02X%02X%02X", red, green, blue)
        updateColor(hex: hex)
    }

    private func updateColor(hex: String) {
        guard var updated = currentItem else { return }
        updated.chartColorHex = hex
        store.updateItem(presetID: presetID, item: updated)
        syncFromItem()
    }

    private func syncFromItem() {
        let color = effectiveColor.usingColorSpace(.deviceRGB) ?? .controlAccentColor
        hexText = color.hexRGB
        redText = String(Int((color.redComponent * 255).rounded()))
        greenText = String(Int((color.greenComponent * 255).rounded()))
        blueText = String(Int((color.blueComponent * 255).rounded()))
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
