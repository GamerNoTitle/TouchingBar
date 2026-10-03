import Foundation

public enum TouchBarLayoutMetrics {
    public static let functionKeyCount = 12
    public static let actionButtonWidth: CGFloat = 80
    public static let actionButtonSpacing: CGFloat = 1
    public static let mediaControlWidth: CGFloat = 72
    public static let lyricsWidth: CGFloat = 760
    public static let dashboardSpacing: CGFloat = 1
    public static let dashboardWidth: CGFloat = 986

    /// Shared by the hardware renderer and settings preview.
    public static func itemWidth(_ item: TouchBarItemConfiguration, preset: TouchBarPreset) -> CGFloat {
        if preset.content == .actions { return actionButtonWidth }
        if preset.content == .nowPlaying { return mediaControlWidth }
        let fallback: Double = item.presentation == .image ? 80 : (item.presentation == .context ? 360 : 100)
        if item.width == .custom { return CGFloat(max(40, min(1200, item.customWidth ?? fallback))) }
        let widths: [CGFloat]
        if item.presentation == .image {
            widths = [44, 80, 140]
        } else if item.presentation != .context && preset.kind == .custom {
            widths = item.symbolName == nil ? [80, 130, 220] : [44, 80, 140]
        } else if preset.kind == .custom && ["lyric", "nowPlaying"].contains(item.contextKey ?? "") {
            widths = [120, 240, 480]
        } else if preset.kind == .custom && ["batteryPower", "batteryTime"].contains(item.contextKey ?? "") {
            widths = [80, 150, 280]
        } else if preset.kind == .custom && ["latestMessage", "unreadSummary", "messageBadges"].contains(item.contextKey ?? "") {
            widths = [90, 180, 360]
        } else {
            widths = [60, 120, 240]
        }
        switch item.width {
        case .compact: return widths[0]
        case .regular: return widths[1]
        case .wide: return widths[2]
        case .custom: return CGFloat(fallback)
        }
    }

    public static func movingItem(in items: [TouchBarItemConfiguration], id: UUID, before target: UUID?) -> [TouchBarItemConfiguration] {
        guard id != target, let source = items.firstIndex(where: { $0.id == id }) else { return items }
        var result = items
        let item = result.remove(at: source)
        let destination = target.flatMap { target in result.firstIndex(where: { $0.id == target }) } ?? result.count
        result.insert(item, at: destination)
        return result
    }

    public static var actionDashboardContentWidth: CGFloat {
        let buttonRowWidth = CGFloat(functionKeyCount) * actionButtonWidth
            + CGFloat(functionKeyCount - 1) * actionButtonSpacing
        return buttonRowWidth
    }

    public static var actionDashboardFits: Bool {
        actionDashboardContentWidth <= dashboardWidth
    }
}
