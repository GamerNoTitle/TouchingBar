import Foundation

public enum PresetKind: String, Codable, CaseIterable, Sendable {
    case functionKeys
    case systemFunctions
    case developer
    case agents
    case messages
    case music
    case custom
}

public enum PresetContent: String, Codable, CaseIterable, Sendable {
    case actions
    case developerContext
    case agentContext
    case unreadMessages
    case nowPlaying
}

public enum TouchBarItemWidth: String, Codable, CaseIterable, Sendable {
    case compact
    case regular
    case wide
}

public enum TouchBarItemPresentation: String, Codable, CaseIterable, Sendable {
    case button
    case label
    case context
}

public struct TouchBarItemConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var symbolName: String?
    public var width: TouchBarItemWidth
    public var presentation: TouchBarItemPresentation
    public var action: ActionSpec
    public var contextKey: String?

    public init(
        id: UUID = UUID(),
        label: String,
        symbolName: String? = nil,
        width: TouchBarItemWidth = .regular,
        presentation: TouchBarItemPresentation = .button,
        action: ActionSpec = .none,
        contextKey: String? = nil
    ) {
        self.id = id
        self.label = label
        self.symbolName = symbolName
        self.width = width
        self.presentation = presentation
        self.action = action
        self.contextKey = contextKey
    }
}

public struct TouchBarPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: PresetKind
    public var content: PresetContent
    public var items: [TouchBarItemConfiguration]
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: PresetKind,
        content: PresetContent = .actions,
        items: [TouchBarItemConfiguration] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.content = content
        self.items = items
        self.isBuiltIn = isBuiltIn
    }
}
