import CoreGraphics
import Foundation
import ImageIO

public struct CodexPetManifest: Codable, Equatable, Sendable {
    public var id: String?
    public var displayName: String?
    public var name: String?
    public var description: String?
    public var spriteVersionNumber: Int?
    public var spritesheetPath: String?
    public var spritesheet: String?

    public init(
        id: String? = nil,
        displayName: String? = nil,
        name: String? = nil,
        description: String? = nil,
        spriteVersionNumber: Int? = nil,
        spritesheetPath: String? = nil,
        spritesheet: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.name = name
        self.description = description
        self.spriteVersionNumber = spriteVersionNumber
        self.spritesheetPath = spritesheetPath
        self.spritesheet = spritesheet
    }
}

public struct CodexPetAnimationState: Codable, Equatable, Sendable {
    public var row: Int?
    public var durationMs: Int?
    public var frameDurationMs: Int?
    public var frames: Int?
    public var label: String?

    public init(
        row: Int? = nil,
        durationMs: Int? = nil,
        frameDurationMs: Int? = nil,
        frames: Int? = nil,
        label: String? = nil
    ) {
        self.row = row
        self.durationMs = durationMs
        self.frameDurationMs = frameDurationMs
        self.frames = frames
        self.label = label
    }
}

public struct CodexPetAnimationTriggers: Codable, Equatable, Sendable {
    public var defaultState: String?
    public var states: [String: CodexPetAnimationState]?

    public init(defaultState: String? = nil, states: [String: CodexPetAnimationState]? = nil) {
        self.defaultState = defaultState
        self.states = states
    }
}

public struct CodexPetAsset: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case spriteRow
        case imageFile
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var row: Int?
    public var frameCount: Int?
    public var frameDuration: TimeInterval?
    public var relativePath: String?

    public init(
        id: String,
        name: String,
        kind: Kind,
        row: Int? = nil,
        frameCount: Int? = nil,
        frameDuration: TimeInterval? = nil,
        relativePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.row = row
        self.frameCount = frameCount
        self.frameDuration = frameDuration
        self.relativePath = relativePath
    }
}

public struct CodexPetImageFrame: @unchecked Sendable {
    public let image: CGImage
    public let duration: TimeInterval

    public init(image: CGImage, duration: TimeInterval) {
        self.image = image
        self.duration = duration
    }
}

public final class CodexPetImageSequence {
    public static func load(from url: URL) throws -> [CodexPetImageFrame] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw CodexPetStoreError.invalidSpritesheet(url.path)
        }

        return (0..<CGImageSourceGetCount(source)).compactMap { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                return nil
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                ?? 0.1
            return CodexPetImageFrame(image: image, duration: max(0.04, delay))
        }
    }
}

public struct CodexPet: Identifiable, Equatable, Sendable {
    public enum Source: String, Sendable {
        case installed
        case external
    }

    public var id: String
    public var displayName: String
    public var description: String?
    public var spriteVersionNumber: Int?
    public var directoryURL: URL
    public var manifestURL: URL
    public var spritesheetURL: URL
    public var animationTriggersURL: URL?
    public var columns: Int
    public var rows: Int
    public var frameWidth: Int
    public var frameHeight: Int
    public var defaultRow: Int
    public var defaultFrameCount: Int
    public var frameDuration: TimeInterval
    public var assets: [CodexPetAsset]
    public var defaultAssetID: String?
    public var source: Source

    public init(
        id: String,
        displayName: String,
        description: String? = nil,
        spriteVersionNumber: Int? = nil,
        directoryURL: URL,
        manifestURL: URL,
        spritesheetURL: URL,
        animationTriggersURL: URL? = nil,
        columns: Int,
        rows: Int,
        frameWidth: Int,
        frameHeight: Int,
        defaultRow: Int,
        defaultFrameCount: Int,
        frameDuration: TimeInterval,
        assets: [CodexPetAsset] = [],
        defaultAssetID: String? = nil,
        source: Source
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.spriteVersionNumber = spriteVersionNumber
        self.directoryURL = directoryURL
        self.manifestURL = manifestURL
        self.spritesheetURL = spritesheetURL
        self.animationTriggersURL = animationTriggersURL
        self.columns = columns
        self.rows = rows
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.defaultRow = defaultRow
        self.defaultFrameCount = defaultFrameCount
        self.frameDuration = frameDuration
        self.assets = assets
        self.defaultAssetID = defaultAssetID
        self.source = source
    }
}

public final class CodexPetSpritesheet: @unchecked Sendable {
    public let pet: CodexPet
    private let image: CGImage

    public init(pet: CodexPet) throws {
        guard let source = CGImageSourceCreateWithURL(pet.spritesheetURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CodexPetStoreError.invalidSpritesheet(pet.spritesheetURL.path)
        }
        self.pet = pet
        self.image = image
    }

    public func frames(row: Int? = nil, count: Int? = nil) -> [CGImage] {
        let requestedRow = max(0, min(pet.rows - 1, row ?? pet.defaultRow))
        let requestedCount = max(1, min(pet.columns, count ?? pet.defaultFrameCount))
        return (0..<requestedCount).compactMap { column in
            let rect = CGRect(
                x: column * pet.frameWidth,
                y: requestedRow * pet.frameHeight,
                width: pet.frameWidth,
                height: pet.frameHeight
            )
            return image.cropping(to: rect)
        }
    }
}
