import Foundation

public enum PresetKind: String, Codable, CaseIterable, Sendable {
    case functionKeys
    case systemFunctions
    case developer
    case agents
    case messages
    case metrics
    case music
    case custom
}

public enum PresetContent: String, Codable, CaseIterable, Sendable {
    case actions
    case developerContext
    case agentContext
    case unreadMessages
    case nowPlaying
    case components
}

public enum TouchBarItemWidth: String, Codable, CaseIterable, Sendable {
    case compact
    case regular
    case wide
    case custom
}

public enum TouchBarItemPresentation: String, Codable, CaseIterable, Sendable {
    case button
    case label
    case context
    case image
}

public struct TouchBarItemConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var symbolName: String?
    public var imagePath: String?
    public var petID: String?
    public var petAssetID: String?
    public var width: TouchBarItemWidth
    public var customWidth: Double?
    public var isHidden: Bool
    public var hideWhenNotPlaying: Bool
    public var showsLabel: Bool
    public var dualLineLyrics: Bool
    public var presentation: TouchBarItemPresentation
    public var action: ActionSpec
    public var contextKey: String?
    public var dateFormat: String?
    public var timeFormat: String?
    public var chartColorHex: String?

    public init(
        id: UUID = UUID(),
        label: String,
        symbolName: String? = nil,
        imagePath: String? = nil,
        petID: String? = nil,
        petAssetID: String? = nil,
        width: TouchBarItemWidth = .regular,
        customWidth: Double? = nil,
        isHidden: Bool = false,
        hideWhenNotPlaying: Bool = false,
        showsLabel: Bool = true,
        dualLineLyrics: Bool = false,
        presentation: TouchBarItemPresentation = .button,
        action: ActionSpec = .none,
        contextKey: String? = nil,
        dateFormat: String? = nil,
        timeFormat: String? = nil,
        chartColorHex: String? = nil
    ) {
        self.id = id
        self.label = label
        self.symbolName = symbolName
        self.imagePath = imagePath
        self.petID = petID
        self.petAssetID = petAssetID
        self.width = width
        self.customWidth = customWidth
        self.isHidden = isHidden
        self.hideWhenNotPlaying = hideWhenNotPlaying
        self.showsLabel = showsLabel
        self.dualLineLyrics = dualLineLyrics
        self.presentation = presentation
        self.action = action
        self.contextKey = contextKey
        self.dateFormat = dateFormat
        self.timeFormat = timeFormat
        self.chartColorHex = chartColorHex
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case symbolName
        case imagePath
        case petID
        case petAssetID
        case width
        case customWidth
        case isHidden
        case hideWhenNotPlaying
        case showsLabel
        case dualLineLyrics
        case presentation
        case action
        case contextKey
        case dateFormat
        case timeFormat
        case chartColorHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        petID = try container.decodeIfPresent(String.self, forKey: .petID)
        petAssetID = try container.decodeIfPresent(String.self, forKey: .petAssetID)
        width = try container.decodeIfPresent(TouchBarItemWidth.self, forKey: .width) ?? .regular
        customWidth = try container.decodeIfPresent(Double.self, forKey: .customWidth)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        hideWhenNotPlaying = try container.decodeIfPresent(Bool.self, forKey: .hideWhenNotPlaying) ?? false
        showsLabel = try container.decodeIfPresent(Bool.self, forKey: .showsLabel) ?? true
        dualLineLyrics = try container.decodeIfPresent(Bool.self, forKey: .dualLineLyrics) ?? false
        presentation = try container.decodeIfPresent(TouchBarItemPresentation.self, forKey: .presentation) ?? .button
        action = try container.decodeIfPresent(ActionSpec.self, forKey: .action) ?? .none
        contextKey = try container.decodeIfPresent(String.self, forKey: .contextKey)
        dateFormat = try container.decodeIfPresent(String.self, forKey: .dateFormat)
        timeFormat = try container.decodeIfPresent(String.self, forKey: .timeFormat)
        chartColorHex = try container.decodeIfPresent(String.self, forKey: .chartColorHex)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(symbolName, forKey: .symbolName)
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        try container.encodeIfPresent(petID, forKey: .petID)
        try container.encodeIfPresent(petAssetID, forKey: .petAssetID)
        try container.encode(width, forKey: .width)
        try container.encodeIfPresent(customWidth, forKey: .customWidth)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(hideWhenNotPlaying, forKey: .hideWhenNotPlaying)
        try container.encode(showsLabel, forKey: .showsLabel)
        try container.encode(dualLineLyrics, forKey: .dualLineLyrics)
        try container.encode(presentation, forKey: .presentation)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(contextKey, forKey: .contextKey)
        try container.encodeIfPresent(dateFormat, forKey: .dateFormat)
        try container.encodeIfPresent(timeFormat, forKey: .timeFormat)
        try container.encodeIfPresent(chartColorHex, forKey: .chartColorHex)
    }
}

public struct TouchBarPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: PresetKind
    public var content: PresetContent
    public var items: [TouchBarItemConfiguration]
    public var isBuiltIn: Bool
    public var hideWhenNotPlaying: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: PresetKind,
        content: PresetContent = .actions,
        items: [TouchBarItemConfiguration] = [],
        isBuiltIn: Bool = false,
        hideWhenNotPlaying: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.content = content
        self.items = items
        self.isBuiltIn = isBuiltIn
        self.hideWhenNotPlaying = hideWhenNotPlaying
    }

    public var effectiveHideWhenNotPlaying: Bool {
        hideWhenNotPlaying ?? false
    }
}
