import Foundation

public struct DeveloperContextProvider: Sendable {
    public init() {}

    public func collect(at directory: String, terminalName: String? = nil) async -> DeveloperContext {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: collectSynchronously(at: directory, terminalName: terminalName))
            }
        }
    }

    private func collectSynchronously(at directory: String, terminalName: String?) -> DeveloperContext {
        var context = DeveloperContext(
            workingDirectory: directory,
            terminalName: terminalName,
            updatedAt: Date()
        )

        collectGitInfo(at: directory, into: &context)
        collectPythonInfo(at: directory, into: &context)
        collectNodeInfo(at: directory, into: &context)
        collectAdditionalToolchains(at: directory, into: &context)
        return context
    }

    private func collectGitInfo(at directory: String, into context: inout DeveloperContext) {
        let git = "/usr/bin/git"
        let check = CommandRunner.run(git, arguments: ["-C", directory, "rev-parse", "--is-inside-work-tree"])
        guard check.exitCode == 0 else { return }

        let branch = CommandRunner.run(git, arguments: ["-C", directory, "symbolic-ref", "--quiet", "--short", "HEAD"])
        if branch.exitCode == 0 {
            context.branch = branch.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let detached = CommandRunner.run(git, arguments: ["-C", directory, "rev-parse", "--short", "HEAD"])
            context.branch = detached.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let status = CommandRunner.run(git, arguments: ["-C", directory, "status", "--porcelain=v2", "--branch"])
        for line in status.standardOutput.split(separator: "\n") {
            if line.hasPrefix("# branch.ab ") {
                let parts = line.split(separator: " ")
                for part in parts {
                    if part.hasPrefix("+") { context.ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { context.behind = Int(part.dropFirst()) ?? 0 }
                }
                continue
            }
            if line.hasPrefix("? ") {
                context.added += 1
                continue
            }
            if line.hasPrefix("! ") {
                continue
            }
            if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count > 1 else { continue }
                let xy = String(parts[1])
                let index = xy.first.map(String.init) ?? "."
                let worktree = xy.dropFirst().first.map(String.init) ?? "."
                countGitState(index, into: &context)
                countGitState(worktree, into: &context)
            }
        }
    }

    private func countGitState(_ state: String, into context: inout DeveloperContext) {
        switch state {
        case "A":
            context.added += 1
        case "D":
            context.deleted += 1
        case "M", "R", "C":
            context.modified += 1
        case "?":
            context.added += 1
        default:
            break
        }
    }

    private func collectPythonInfo(at directory: String, into context: inout DeveloperContext) {
        let candidates = [".venv", "venv", "env"]
        let fileManager = FileManager.default
        var environmentURL: URL?

        for candidate in candidates {
            let candidateURL = URL(fileURLWithPath: directory).appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: candidateURL.path) {
                environmentURL = candidateURL
                break
            }
        }

        if environmentURL == nil {
            let pyvenv = URL(fileURLWithPath: directory).appendingPathComponent("pyvenv.cfg")
            if fileManager.fileExists(atPath: pyvenv.path) {
                environmentURL = URL(fileURLWithPath: directory)
            }
        }

        if let environmentURL {
            context.pythonEnvironment = environmentURL.lastPathComponent == "." ? "Python" : environmentURL.lastPathComponent
            let python = environmentURL.appendingPathComponent("bin/python3").path
            guard fileManager.isExecutableFile(atPath: python) else { return }
            let result = CommandRunner.run(python, arguments: ["--version"])
            let version = (result.standardOutput + result.standardError)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "Python ", with: "")
            if !version.isEmpty { context.pythonVersion = version }
            return
        }

        let pythonMarkers = ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py", "setup.cfg"]
        let base = URL(fileURLWithPath: directory)
        guard pythonMarkers.contains(where: { fileManager.fileExists(atPath: base.appendingPathComponent($0).path) }) else {
            return
        }
        let result = CommandRunner.run("/usr/bin/env", arguments: ["python3", "--version"])
        let version = (result.standardOutput + result.standardError)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Python ", with: "")
        if !version.isEmpty {
            context.pythonEnvironment = "Python"
            context.pythonVersion = version
        }
    }

    private func collectNodeInfo(at directory: String, into context: inout DeveloperContext) {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: directory)
        let locks: [(String, String)] = [
            ("pnpm-lock.yaml", "pnpm"),
            ("yarn.lock", "yarn"),
            ("bun.lockb", "bun"),
            ("package-lock.json", "npm")
        ]

        for (file, manager) in locks where fileManager.fileExists(atPath: base.appendingPathComponent(file).path) {
            context.packageManager = manager
            break
        }

        let nodeVersionFile = [".nvmrc", ".node-version"]
            .map { base.appendingPathComponent($0) }
            .first(where: { fileManager.fileExists(atPath: $0.path) })
        if let nodeVersionFile, let contents = try? String(contentsOf: nodeVersionFile, encoding: .utf8) {
            let version = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { context.nodeVersion = version }
        }

        let nodeMarkers = ["package.json", "pnpm-workspace.yaml", "node_modules"]
        let hasNodeProject = nodeMarkers.contains {
            fileManager.fileExists(atPath: base.appendingPathComponent($0).path)
        }
        if context.packageManager == nil, hasNodeProject {
            context.packageManager = "node"
        }
        if context.nodeVersion == nil, hasNodeProject {
            let result = CommandRunner.run("/usr/bin/env", arguments: ["node", "--version"])
            let value = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0, !value.isEmpty {
                context.nodeVersion = value.hasPrefix("v") ? String(value.dropFirst()) : value
            }
        }
    }

    private func collectAdditionalToolchains(at directory: String, into context: inout DeveloperContext) {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
        var values = context.toolchains ?? [:]

        func hasAny(_ patterns: [String]) -> Bool {
            patterns.contains { pattern in
                if pattern.hasPrefix("*.") {
                    let suffix = String(pattern.dropFirst())
                    return names.contains { $0.hasSuffix(suffix) }
                }
                return names.contains(pattern)
            }
        }

        func probe(
            key: String,
            command: String,
            arguments: [String],
            markers: [String],
            parser: (String, String) -> String?
        ) {
            guard hasAny(markers) else { return }
            let result = CommandRunner.run("/usr/bin/env", arguments: [command] + arguments)
            guard result.exitCode == 0 else { return }
            let output = result.standardOutput + result.standardError
            if let value = parser(key, output), !value.isEmpty {
                values[key] = value
            }
        }

        probe(
            key: "java",
            command: "java",
            arguments: ["-version"],
            markers: ["pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
            parser: versionMatch
        )
        probe(
            key: "go",
            command: "go",
            arguments: ["version"],
            markers: ["go.mod", "go.sum"],
            parser: versionMatch
        )
        probe(
            key: "rust",
            command: "rustc",
            arguments: ["--version"],
            markers: ["Cargo.toml", "Cargo.lock"],
            parser: versionMatch
        )
        probe(
            key: "ruby",
            command: "ruby",
            arguments: ["--version"],
            markers: ["Gemfile", ".ruby-version", "*.gemspec"],
            parser: versionMatch
        )
        probe(
            key: "php",
            command: "php",
            arguments: ["-v"],
            markers: ["composer.json", "composer.lock"],
            parser: versionMatch
        )
        probe(
            key: "swift",
            command: "swift",
            arguments: ["--version"],
            markers: ["Package.swift", "*.xcodeproj", "*.xcworkspace"],
            parser: versionMatch
        )
        probe(
            key: "docker",
            command: "docker",
            arguments: ["--version"],
            markers: ["Dockerfile", "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"],
            parser: versionMatch
        )
        probe(
            key: "terraform",
            command: "terraform",
            arguments: ["version"],
            markers: ["*.tf", "*.tfvars"],
            parser: versionMatch
        )
        probe(
            key: "cmake",
            command: "cmake",
            arguments: ["--version"],
            markers: ["CMakeLists.txt"],
            parser: versionMatch
        )
        probe(
            key: "xcode",
            command: "xcodebuild",
            arguments: ["-version"],
            markers: ["*.xcodeproj", "*.xcworkspace"],
            parser: versionMatch
        )

        let kubeConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kube/config")
        let hasKubernetesProject = hasAny(["k8s", "kubernetes", "Chart.yaml", "helm"])
            || FileManager.default.fileExists(atPath: kubeConfig.path)
        if hasKubernetesProject {
            let result = CommandRunner.run(
                "/usr/bin/env",
                arguments: ["kubectl", "config", "current-context"]
            )
            let value = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0, !value.isEmpty {
                values["kubernetes"] = value
            }
        }

        context.toolchains = values.isEmpty ? nil : values
    }

    private func versionMatch(key: String, output: String) -> String? {
        let patterns: [String: String] = [
            "java": #"version "([^"]+)""#,
            "go": #"go([0-9][^\s]*)"#,
            "rust": #"rustc ([0-9][^\s]*)"#,
            "ruby": #"ruby ([0-9][^\s]*)"#,
            "php": #"PHP ([0-9][^\s]*)"#,
            "swift": #"(?:Apple )?Swift version ([0-9][^\s]*)"#,
            "docker": #"Docker version ([^,]+)"#,
            "terraform": #"Terraform v([0-9][^\s]*)"#,
            "cmake": #"cmake version ([0-9][^\s]*)"#,
            "xcode": #"Xcode ([0-9][^\s]*)"#
        ]
        guard let pattern = patterns[key],
              let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = expression.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[valueRange])
    }
}
