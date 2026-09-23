import Foundation

public enum TouchBarLayoutMetrics {
    public static let functionKeyCount = 12
    public static let actionButtonWidth: CGFloat = 80
    public static let actionButtonSpacing: CGFloat = 1
    public static let mediaControlWidth: CGFloat = 72
    public static let lyricsWidth: CGFloat = 760
    public static let dashboardSpacing: CGFloat = 1
    public static let dashboardWidth: CGFloat = 986

    public static var actionDashboardContentWidth: CGFloat {
        let buttonRowWidth = CGFloat(functionKeyCount) * actionButtonWidth
            + CGFloat(functionKeyCount - 1) * actionButtonSpacing
        return buttonRowWidth
    }

    public static var actionDashboardFits: Bool {
        actionDashboardContentWidth <= dashboardWidth
    }
}
