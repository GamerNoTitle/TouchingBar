import Foundation

public enum BuiltInPresets {
    public static let restorableKinds: [PresetKind] = [
        .functionKeys,
        .systemFunctions,
        .developer,
        .music,
        .metrics
    ]

    public static func make() -> [TouchBarPreset] {
        restorableKinds.compactMap(preset(for:))
    }

    public static func preset(for kind: PresetKind) -> TouchBarPreset? {
        switch kind {
        case .functionKeys:
            return functionKeys()
        case .systemFunctions:
            return systemFunctions()
        case .developer:
            return developer()
        case .music:
            return music()
        case .metrics:
            return metrics()
        case .agents, .messages, .custom:
            return nil
        }
    }

    public static func title(for kind: PresetKind) -> String {
        switch kind {
        case .functionKeys: return "F1–F12"
        case .systemFunctions: return "Mac 功能键"
        case .developer: return "开发者"
        case .music: return "音乐与歌词"
        case .metrics: return "系统资源"
        case .agents: return "Agent"
        case .messages: return "未读消息"
        case .custom: return "自定义配置"
        }
    }

    public static func functionKeys() -> TouchBarPreset {
        TouchBarPreset(
            name: "F1–F12",
            kind: .functionKeys,
            items: (1...12).map { number in
                TouchBarItemConfiguration(
                    label: "F\(number)",
                    width: .regular,
                    action: ActionSpec(kind: .functionKey, value: "\(number)")
                )
            },
            isBuiltIn: true
        )
    }

    public static func systemFunctions() -> TouchBarPreset {
        let items: [TouchBarItemConfiguration] = [
            .init(label: "F1", symbolName: "sun.min", width: .regular, action: ActionSpec(kind: .brightness, value: "down")),
            .init(label: "F2", symbolName: "sun.max", width: .regular, action: ActionSpec(kind: .brightness, value: "up")),
            .init(label: "F3", symbolName: "rectangle.3.group", width: .regular, action: ActionSpec(kind: .missionControl)),
            .init(label: "F4", symbolName: "lock.fill", width: .regular, action: ActionSpec(kind: .lockScreen)),
            .init(label: "F5", symbolName: "light.min", width: .regular, action: ActionSpec(kind: .keyboardBacklight, value: "down")),
            .init(label: "F6", symbolName: "light.max", width: .regular, action: ActionSpec(kind: .keyboardBacklight, value: "up")),
            .init(label: "F7", symbolName: "backward.end.fill", width: .regular, action: .previousTrack),
            .init(label: "F8", symbolName: "playpause.fill", width: .regular, action: .playPause),
            .init(label: "F9", symbolName: "forward.end.fill", width: .regular, action: .nextTrack),
            .init(label: "F10", symbolName: "speaker.slash", width: .regular, action: ActionSpec(kind: .volume, volume: .mute)),
            .init(label: "F11", symbolName: "speaker.wave.1", width: .regular, action: ActionSpec(kind: .volume, volume: .down)),
            .init(label: "F12", symbolName: "speaker.wave.3", width: .regular, action: ActionSpec(kind: .volume, volume: .up))
        ]
        return TouchBarPreset(name: "Mac 功能键", kind: .systemFunctions, items: items, isBuiltIn: true)
    }

    public static func developer() -> TouchBarPreset {
        TouchBarPreset(
            name: "开发者",
            kind: .developer,
            content: .developerContext,
            items: [
                .init(label: "路径", width: .wide, presentation: .context, contextKey: "path"),
                .init(label: "分支", width: .regular, presentation: .context, contextKey: "branch"),
                .init(label: "改动", width: .regular, presentation: .context, contextKey: "changes"),
                .init(label: "Python", width: .regular, presentation: .context, contextKey: "python"),
                .init(label: "Node", width: .regular, presentation: .context, contextKey: "node"),
                .init(label: "Java", width: .regular, presentation: .context, contextKey: "java"),
                .init(label: "Go", width: .regular, presentation: .context, contextKey: "go"),
                .init(label: "Rust", width: .regular, presentation: .context, contextKey: "rust"),
                .init(label: "Ruby", width: .regular, presentation: .context, contextKey: "ruby"),
                .init(label: "PHP", width: .regular, presentation: .context, contextKey: "php"),
                .init(label: "Swift", width: .regular, presentation: .context, contextKey: "swift"),
                .init(label: "Docker", width: .regular, presentation: .context, contextKey: "docker"),
                .init(label: "Kubernetes", width: .regular, presentation: .context, contextKey: "kubernetes"),
                .init(label: "Terraform", width: .regular, presentation: .context, contextKey: "terraform"),
                .init(label: "CMake", width: .regular, presentation: .context, contextKey: "cmake"),
                .init(label: "Xcode", width: .regular, presentation: .context, contextKey: "xcode")
            ],
            isBuiltIn: true
        )
    }

    public static func music() -> TouchBarPreset {
        TouchBarPreset(
            name: "音乐与歌词",
            kind: .music,
            content: .nowPlaying,
            items: [
                .init(label: "上一曲", symbolName: "backward.fill", width: .regular, action: .previousTrack),
                .init(label: "播放", symbolName: "playpause.fill", width: .regular, action: .playPause),
                .init(label: "下一曲", symbolName: "forward.fill", width: .regular, action: .nextTrack)
            ],
            isBuiltIn: true
        )
    }

    public static func metrics() -> TouchBarPreset {
        TouchBarPreset(
            name: "系统资源",
            kind: .metrics,
            content: .components,
            items: [
                .init(label: "当前时间", width: .custom, customWidth: 130, presentation: .context, contextKey: "dateTime"),
                .init(label: "CPU", width: .regular, presentation: .context, contextKey: "cpu"),
                .init(label: "GPU", width: .regular, presentation: .context, contextKey: "gpu"),
                .init(label: "内存", width: .regular, presentation: .context, contextKey: "memory"),
                .init(label: "温度", width: .regular, presentation: .context, contextKey: "cpuTemperature"),
                .init(label: "风扇", width: .regular, presentation: .context, contextKey: "fanRPM"),
                .init(label: "下载", width: .regular, presentation: .context, contextKey: "networkDownload"),
                .init(label: "上传", width: .regular, presentation: .context, contextKey: "networkUpload")
            ],
            isBuiltIn: true
        )
    }
}
