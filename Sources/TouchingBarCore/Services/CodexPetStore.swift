import CoreGraphics
import Foundation
import ImageIO

public enum CodexPetStoreError: Error, LocalizedError {
    case manifestNotFound(String)
    case invalidManifest(String)
    case spritesheetNotFound(String)
    case invalidSpritesheet(String)
    case invalidDimensions(width: Int, height: Int)
    case alreadyInstalled(String)
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .manifestNotFound(let path):
            return "没有找到 pet.json：\(path)"
        case .invalidManifest(let message):
            return "pet.json 无效：\(message)"
        case .spritesheetNotFound(let path):
            return "没有找到 pet 精灵图：\(path)"
        case .invalidSpritesheet(let path):
            return "无法读取 pet 精灵图：\(path)"
        case .invalidDimensions(let width, let height):
            return "精灵图尺寸 \(width)×\(height) 不符合 Codex pet 的 8 列、每格 192×208 网格。"
        case .alreadyInstalled(let id):
            return "已安装同 ID 的宠物：\(id)"
        case .copyFailed(let message):
            return "安装宠物失败：\(message)"
        }
    }
}

public final class CodexPetStore: @unchecked Sendable {
    public static let shared = CodexPetStore()

    public let petsDirectoryURL: URL
    public let codexPetsDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        applicationSupportDirectory: URL? = nil,
        codexPetsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let support = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        petsDirectoryURL = support
            .appendingPathComponent("TouchingBar", isDirectory: true)
            .appendingPathComponent("Pets", isDirectory: true)
        codexPetsDirectoryURL = codexPetsDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("pets", isDirectory: true)
    }

    public func installedPets() -> [CodexPet] {
        pets(in: petsDirectoryURL, source: .installed)
    }

    public func externalPets() -> [CodexPet] {
        pets(in: codexPetsDirectoryURL, source: .external)
    }

    public func pet(id: String) -> CodexPet? {
        installedPets().first(where: { $0.id == id })
    }

    public func install(from sourceURL: URL, replacing: Bool = true) throws -> [CodexPet] {
        let candidates = pets(in: sourceURL, source: .external)
        guard !candidates.isEmpty else {
            throw CodexPetStoreError.manifestNotFound(sourceURL.path)
        }
        return try candidates.map { try install($0, replacing: replacing) }
    }

    @discardableResult
    public func install(_ sourcePet: CodexPet, replacing: Bool = true) throws -> CodexPet {
        let destination = petsDirectoryURL.appendingPathComponent(sourcePet.id, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            guard replacing else { throw CodexPetStoreError.alreadyInstalled(sourcePet.id) }
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let spritesheetName = sourcePet.spritesheetURL.lastPathComponent
            let destinationSpritesheet = destination.appendingPathComponent(spritesheetName)
            try fileManager.copyItem(at: sourcePet.spritesheetURL, to: destinationSpritesheet)

            var manifest = try decodeManifest(at: sourcePet.manifestURL)
            manifest.spritesheetPath = spritesheetName
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: destination.appendingPathComponent("pet.json"), options: .atomic)

            if let animationSource = sourcePet.animationTriggersURL,
               fileManager.fileExists(atPath: animationSource.path) {
                try fileManager.copyItem(
                    at: animationSource,
                    to: destination.appendingPathComponent(animationSource.lastPathComponent)
                )
            }

            for asset in sourcePet.assets where asset.kind == .imageFile {
                guard let relativePath = asset.relativePath else { continue }
                let source = sourcePet.directoryURL.appendingPathComponent(relativePath)
                let target = destination.appendingPathComponent(relativePath)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: source, to: target)
            }

            guard let installed = try? loadPet(
                at: destination.appendingPathComponent("pet.json"),
                source: .installed
            ) else {
                throw CodexPetStoreError.invalidManifest("安装后的 pet.json 无法重新读取")
            }
            return installed
        } catch let error as CodexPetStoreError {
            throw error
        } catch {
            throw CodexPetStoreError.copyFailed(error.localizedDescription)
        }
    }

    public func remove(petID: String) throws {
        let directory = petsDirectoryURL.appendingPathComponent(petID, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func decodeManifest(at url: URL) throws -> CodexPetManifest {
        do {
            return try JSONDecoder().decode(CodexPetManifest.self, from: Data(contentsOf: url))
        } catch {
            throw CodexPetStoreError.invalidManifest(error.localizedDescription)
        }
    }

    private func pets(in root: URL, source: CodexPet.Source) -> [CodexPet] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        var found: [CodexPet] = []
        var seen: Set<String> = []
        for manifestURL in manifestURLs(in: root) {
            guard let pet = try? loadPet(at: manifestURL, source: source),
                  seen.insert(pet.id).inserted else { continue }
            found.append(pet)
        }
        return found.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func manifestURLs(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if enumerator.level > 4 {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent.lowercased() == "pet.json" else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path.count < $1.path.count }
    }

    private func loadPet(at manifestURL: URL, source: CodexPet.Source) throws -> CodexPet {
        let manifest = try decodeManifest(at: manifestURL)
        let directory = manifestURL.deletingLastPathComponent()
        let manifestStem = directory.lastPathComponent
        let petID = sanitizeID(manifest.id ?? directory.lastPathComponent)
        guard !petID.isEmpty else {
            throw CodexPetStoreError.invalidManifest("id 不能为空")
        }

        let spritesheetName = manifest.spritesheetPath ?? manifest.spritesheet ?? "spritesheet.webp"
        let spritesheetURL = resolvedURL(spritesheetName, relativeTo: directory)
        guard fileManager.fileExists(atPath: spritesheetURL.path) else {
            throw CodexPetStoreError.spritesheetNotFound(spritesheetURL.path)
        }

        guard let sourceImage = CGImageSourceCreateWithURL(spritesheetURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(sourceImage, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw CodexPetStoreError.invalidSpritesheet(spritesheetURL.path)
        }

        let columns = 8
        guard width % columns == 0 else {
            throw CodexPetStoreError.invalidDimensions(width: width, height: height)
        }
        let frameWidth = width / columns
        let frameHeight = Int((Double(frameWidth) * 208.0 / 192.0).rounded())
        guard frameWidth > 0, frameHeight > 0, height % frameHeight == 0 else {
            throw CodexPetStoreError.invalidDimensions(width: width, height: height)
        }
        let rows = height / frameHeight
        guard rows > 0 else {
            throw CodexPetStoreError.invalidDimensions(width: width, height: height)
        }

        let triggersURL = directory.appendingPathComponent("animation-triggers.json")
        let triggers = (try? JSONDecoder().decode(
            CodexPetAnimationTriggers.self,
            from: Data(contentsOf: triggersURL)
        )) ?? nil
        let defaultState = triggers?.defaultState ?? "idle"
        let defaultDefinition = triggers?.states?[defaultState]
        let defaultRow = max(0, min(rows - 1, defaultDefinition?.row ?? 0))
        let defaultFrameCount = max(1, min(columns, defaultDefinition?.frames ?? columns))
        let frameDuration = frameDuration(for: defaultDefinition, frameCount: defaultFrameCount)
        let assetResult = petAssets(
            directory: directory,
            spritesheetURL: spritesheetURL,
            triggers: triggers,
            columns: columns,
            defaultState: defaultState,
            defaultFrameCount: defaultFrameCount,
            defaultFrameDuration: frameDuration
        )

        return CodexPet(
            id: petID,
            displayName: manifest.displayName ?? manifest.name ?? manifestStem,
            description: manifest.description,
            spriteVersionNumber: manifest.spriteVersionNumber,
            directoryURL: directory,
            manifestURL: manifestURL,
            spritesheetURL: spritesheetURL,
            animationTriggersURL: fileManager.fileExists(atPath: triggersURL.path) ? triggersURL : nil,
            columns: columns,
            rows: rows,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            defaultRow: defaultRow,
            defaultFrameCount: defaultFrameCount,
            frameDuration: frameDuration,
            assets: assetResult.assets,
            defaultAssetID: assetResult.defaultID,
            source: source
        )
    }

    private func frameDuration(
        for definition: CodexPetAnimationState?,
        frameCount: Int
    ) -> TimeInterval {
        if let frameDurationMs = definition?.frameDurationMs {
            return max(0.04, Double(frameDurationMs) / 1000.0)
        }
        if let durationMs = definition?.durationMs {
            return max(0.04, Double(durationMs) / 1000.0 / Double(max(1, frameCount)))
        }
        return 0.16
    }

    private func petAssets(
        directory: URL,
        spritesheetURL: URL,
        triggers: CodexPetAnimationTriggers?,
        columns: Int,
        defaultState: String,
        defaultFrameCount: Int,
        defaultFrameDuration: TimeInterval
    ) -> (assets: [CodexPetAsset], defaultID: String?) {
        var assets: [CodexPetAsset] = []

        if let states = triggers?.states, !states.isEmpty {
            for key in states.keys.sorted() {
                guard let definition = states[key], let row = definition.row else { continue }
                let frameCount = max(1, min(columns, definition.frames ?? columns))
                assets.append(
                    CodexPetAsset(
                        id: "state:\(key)",
                        name: definition.label ?? key,
                        kind: .spriteRow,
                        row: row,
                        frameCount: frameCount,
                        frameDuration: frameDuration(for: definition, frameCount: frameCount)
                    )
                )
            }
        }

        if assets.isEmpty {
            assets.append(
                CodexPetAsset(
                    id: "row:0",
                    name: "默认动作",
                    kind: .spriteRow,
                    row: 0,
                    frameCount: defaultFrameCount,
                    frameDuration: defaultFrameDuration
                )
            )
        }

        let spritesheetPath = spritesheetURL.standardizedFileURL.path
        let imageExtensions: Set<String> = ["gif", "png", "jpg", "jpeg", "webp", "heic", "bmp", "tiff"]
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                if enumerator.level > 5 {
                    enumerator.skipDescendants()
                    continue
                }
                let extensionName = url.pathExtension.lowercased()
                guard imageExtensions.contains(extensionName),
                      url.standardizedFileURL.path != spritesheetPath else {
                    continue
                }
                if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   fileSize > 40 * 1024 * 1024 {
                    continue
                }
                let relative = relativePath(of: url, relativeTo: directory)
                guard !relative.isEmpty else { continue }
                assets.append(
                    CodexPetAsset(
                        id: "file:\(relative)",
                        name: relative,
                        kind: .imageFile,
                        relativePath: relative
                    )
                )
            }
        }

        assets.sort { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .spriteRow
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let defaultID = assets.first(where: { $0.id == "state:\(defaultState)" })?.id
            ?? assets.first(where: { $0.kind == .spriteRow })?.id
        return (assets, defaultID)
    }

    private func relativePath(of url: URL, relativeTo directory: URL) -> String {
        let root = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return "" }
        return String(path.dropFirst(root.count + 1))
    }

    private func resolvedURL(_ path: String, relativeTo directory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return directory.appendingPathComponent(path).standardizedFileURL
    }

    private func sanitizeID(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }
}
