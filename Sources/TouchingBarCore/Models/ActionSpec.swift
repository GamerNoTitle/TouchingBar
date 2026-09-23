import Foundation

public enum TouchBarActionKind: String, Codable, CaseIterable, Sendable {
    case none
    case functionKey
    case keyboardShortcut
    case launchApplication
    case openURL
    case runCommand
    case media
    case volume
    case brightness
    case missionControl
    case spotlight
    case dictation
    case doNotDisturb
    case lockScreen
    case keyboardBacklight
}

public enum MediaCommand: String, Codable, CaseIterable, Sendable {
    case previous
    case playPause
    case next
}

public enum VolumeCommand: String, Codable, CaseIterable, Sendable {
    case mute
    case down
    case up
}

public struct KeyShortcut: Codable, Equatable, Sendable {
    public var key: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(
        key: String,
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) {
        self.key = key
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }
}

public struct ActionSpec: Codable, Equatable, Sendable {
    public var kind: TouchBarActionKind
    public var value: String?
    public var media: MediaCommand?
    public var volume: VolumeCommand?
    public var shortcut: KeyShortcut?

    public init(
        kind: TouchBarActionKind = .none,
        value: String? = nil,
        media: MediaCommand? = nil,
        volume: VolumeCommand? = nil,
        shortcut: KeyShortcut? = nil
    ) {
        self.kind = kind
        self.value = value
        self.media = media
        self.volume = volume
        self.shortcut = shortcut
    }

    public static let none = ActionSpec()
    public static let playPause = ActionSpec(kind: .media, media: .playPause)
    public static let previousTrack = ActionSpec(kind: .media, media: .previous)
    public static let nextTrack = ActionSpec(kind: .media, media: .next)
}
