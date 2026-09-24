import Foundation

public enum BuiltInPresets {
    public static func make() -> [TouchBarPreset] {
        [
            functionKeys(),
            systemFunctions(),
            developer(),
            agents(),
            metrics(),
            messages(),
            music()
        ]
    }

    public static func functionKeys() -> TouchBarPreset {
        TouchBarPreset(
            name: "F1–F12",
            kind: .functionKeys,
            items: (1...12).map { number in
                TouchBarItemConfiguration(
                    label: "F\(number)",
                    width: .compact,
                    action: ActionSpec(kind: .functionKey, value: "\(number)")
                )
            },
            isBuiltIn: true
        )
    }

    public static func systemFunctions() -> TouchBarPreset {
        let items: [TouchBarItemConfiguration] = [
            .init(label: "F1", symbolName: "sun.min", width: .compact, action: ActionSpec(kind: .brightness, value: "down")),
            .init(label: "F2", symbolName: "sun.max", width: .compact, action: ActionSpec(kind: .brightness, value: "up")),
            .init(label: "F3", symbolName: "rectangle.3.group", width: .compact, action: ActionSpec(kind: .missionControl)),
            .init(label: "F4", symbolName: "lock.fill", width: .compact, action: ActionSpec(kind: .lockScreen)),
            .init(label: "F5", symbolName: "light.min", width: .compact, action: ActionSpec(kind: .keyboardBacklight, value: "off")),
            .init(label: "F6", symbolName: "light.max", width: .compact, action: ActionSpec(kind: .keyboardBacklight, value: "on")),
            .init(label: "F7", symbolName: "backward.end.fill", width: .compact, action: .previousTrack),
            .init(label: "F8", symbolName: "playpause.fill", width: .compact, action: .playPause),
            .init(label: "F9", symbolName: "forward.end.fill", width: .compact, action: .nextTrack),
            .init(label: "F10", symbolName: "speaker.slash", width: .compact, action: ActionSpec(kind: .volume, volume: .mute)),
            .init(label: "F11", symbolName: "speaker.wave.1", width: .compact, action: ActionSpec(kind: .volume, volume: .down)),
            .init(label: "F12", symbolName: "speaker.wave.3", width: .compact, action: ActionSpec(kind: .volume, volume: .up))
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

    public static func agents() -> TouchBarPreset {
        TouchBarPreset(
            name: "Agent",
            kind: .agents,
            content: .agentContext,
            items: [
                .init(label: "会话", width: .wide, presentation: .context, contextKey: "sessions"),
                .init(label: "厂商", width: .regular, presentation: .context, contextKey: "provider"),
                .init(label: "状态", width: .regular, presentation: .context, contextKey: "status"),
                .init(label: "任务", width: .wide, presentation: .context, contextKey: "task"),
                .init(label: "事件", width: .regular, presentation: .context, contextKey: "event"),
                .init(label: "工具", width: .regular, presentation: .context, contextKey: "tool"),
                .init(label: "目录", width: .wide, presentation: .context, contextKey: "cwd"),
                .init(label: "耗时", width: .regular, presentation: .context, contextKey: "duration")
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
                .init(label: "CPU", width: .compact, presentation: .context, contextKey: "cpu"),
                .init(label: "GPU", width: .compact, presentation: .context, contextKey: "gpu"),
                .init(label: "内存", width: .compact, presentation: .context, contextKey: "memory"),
                .init(label: "硬盘", width: .compact, presentation: .context, contextKey: "disk"),
                .init(label: "温度", width: .compact, presentation: .context, contextKey: "cpuTemperature"),
                .init(label: "风扇", width: .compact, presentation: .context, contextKey: "fanRPM"),
                .init(label: "下载", width: .compact, presentation: .context, contextKey: "networkDownload"),
                .init(label: "上传", width: .compact, presentation: .context, contextKey: "networkUpload")
            ],
            isBuiltIn: true
        )
    }

    public static func messages() -> TouchBarPreset {
        TouchBarPreset(
            name: "未读消息",
            kind: .messages,
            content: .unreadMessages,
            items: [],
            isBuiltIn: true
        )
    }

    public static func music() -> TouchBarPreset {
        TouchBarPreset(
            name: "音乐与歌词",
            kind: .music,
            content: .nowPlaying,
            items: [
                .init(label: "上一曲", symbolName: "backward.fill", width: .compact, action: .previousTrack),
                .init(label: "播放", symbolName: "playpause.fill", width: .compact, action: .playPause),
                .init(label: "下一曲", symbolName: "forward.fill", width: .compact, action: .nextTrack)
            ],
            isBuiltIn: true
        )
    }
}
