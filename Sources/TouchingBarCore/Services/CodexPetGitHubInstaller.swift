import Foundation

public struct CodexPetGitHubReference: Equatable, Sendable {
    public var owner: String
    public var repository: String
    public var branch: String?
    public var subpath: String?

    public init(owner: String, repository: String, branch: String? = nil, subpath: String? = nil) {
        self.owner = owner
        self.repository = repository
        self.branch = branch
        self.subpath = subpath
    }

    public var displayName: String {
        "\(owner)/\(repository)"
    }

    public var candidateBranches: [String] {
        if let branch, !branch.isEmpty {
            return [branch]
        }
        return ["main", "master"]
    }

    public static func parse(_ rawValue: String) -> CodexPetGitHubReference? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("git@github.com:") {
            value = "https://github.com/" + value.dropFirst("git@github.com:".count)
        } else if !value.contains("://") {
            value = "https://github.com/" + value
        }

        guard var components = URLComponents(string: value),
              components.host?.lowercased() == "github.com" else {
            return nil
        }
        components.query = nil
        components.fragment = nil

        let parts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count >= 2 else { return nil }

        let owner = parts[0]
        let repository = parts[1].replacingOccurrences(of: ".git", with: "")
        guard isSafeComponent(owner), isSafeComponent(repository) else { return nil }

        var branch: String?
        var subpath: String?
        if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
            branch = parts[3]
            if parts.count > 4 {
                let pathComponents = Array(parts.dropFirst(4))
                guard pathComponents.allSatisfy({ $0 != "." && $0 != ".." }) else {
                    return nil
                }
                subpath = pathComponents.joined(separator: "/")
            }
        }

        return CodexPetGitHubReference(
            owner: owner,
            repository: repository,
            branch: branch,
            subpath: subpath
        )
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }
}

public enum CodexPetGitHubInstallerError: Error, LocalizedError {
    case invalidURL(String)
    case gitUnavailable
    case cloneFailed(String)
    case petNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "不是有效的 GitHub 仓库地址：\(value)"
        case .gitUnavailable:
            return "没有找到 git 命令，请先安装 Xcode Command Line Tools。"
        case .cloneFailed(let message):
            return "git clone 失败：\(message)"
        case .petNotFound(let value):
            return "仓库中没有找到可安装的 Codex pet：\(value)"
        }
    }
}

public final class CodexPetGitHubInstaller: @unchecked Sendable {
    public static let shared = CodexPetGitHubInstaller()

    private let store: CodexPetStore
    private let fileManager: FileManager

    public init(
        store: CodexPetStore = .shared,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.fileManager = fileManager
    }

    public func install(from rawURL: String, replacing: Bool = true) async throws -> [CodexPet] {
        guard let reference = CodexPetGitHubReference.parse(rawURL) else {
            throw CodexPetGitHubInstallerError.invalidURL(rawURL)
        }
        guard fileManager.isExecutableFile(atPath: "/usr/bin/git") else {
            throw CodexPetGitHubInstallerError.gitUnavailable
        }

        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TouchingBar-GitHub-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        } catch {
            throw CodexPetGitHubInstallerError.cloneFailed(error.localizedDescription)
        }
        defer { try? fileManager.removeItem(at: workDirectory) }

        var lastError: Error?
        for branch in reference.candidateBranches {
            let cloneDirectory = workDirectory.appendingPathComponent(branch, isDirectory: true)
            do {
                try clone(reference: reference, branch: branch, to: cloneDirectory)
                let searchRoot = try searchRoot(in: cloneDirectory, subpath: reference.subpath)
                let installed = try store.install(from: searchRoot, replacing: replacing)
                if !installed.isEmpty {
                    return installed
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw CodexPetGitHubInstallerError.petNotFound(reference.displayName)
    }

    private func clone(reference: CodexPetGitHubReference, branch: String, to destination: URL) throws {
        guard let repositoryURL = URL(string: "https://github.com/\(reference.owner)/\(reference.repository).git") else {
            throw CodexPetGitHubInstallerError.invalidURL(reference.displayName)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "clone",
            "--depth", "1",
            "--branch", branch,
            "--single-branch",
            repositoryURL.absoluteString,
            destination.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CodexPetGitHubInstallerError.cloneFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexPetGitHubInstallerError.cloneFailed(
                message?.isEmpty == false ? message! : "git exit \(process.terminationStatus)"
            )
        }
    }

    private func searchRoot(in repositoryRoot: URL, subpath: String?) throws -> URL {
        guard let subpath, !subpath.isEmpty else {
            return repositoryRoot
        }
        let target = repositoryRoot.appendingPathComponent(subpath).standardizedFileURL
        let standardizedRoot = repositoryRoot.standardizedFileURL
        guard target.path == standardizedRoot.path || target.path.hasPrefix(standardizedRoot.path + "/") else {
            throw CodexPetGitHubInstallerError.petNotFound(subpath)
        }
        guard fileManager.fileExists(atPath: target.path) else {
            throw CodexPetGitHubInstallerError.petNotFound(subpath)
        }
        return target
    }
}
