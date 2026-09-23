import Foundation

public struct ShellHookInstallation: Equatable, Sendable {
    public var scriptURL: URL
    public var shellConfigurationURL: URL
    public var controlExecutablePath: String

    public init(scriptURL: URL, shellConfigurationURL: URL, controlExecutablePath: String) {
        self.scriptURL = scriptURL
        self.shellConfigurationURL = shellConfigurationURL
        self.controlExecutablePath = controlExecutablePath
    }
}

public struct ShellHookInstaller: Sendable {
    public static let beginMarker = "# >>> TouchingBar shell integration >>>"
    public static let endMarker = "# <<< TouchingBar shell integration <<<"

    public init() {}

    public func install(
        controlExecutablePath: String,
        shell: String = "zsh",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL? = nil
    ) throws -> ShellHookInstallation {
        guard shell == "zsh" else {
            throw ShellHookError.unsupportedShell(shell)
        }
        guard controlExecutablePath.hasPrefix("/") else {
            throw ShellHookError.controlExecutableMustBeAbsolute(controlExecutablePath)
        }

        let applicationSupport = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let scriptURL = applicationSupport
            .appendingPathComponent("TouchingBar", isDirectory: true)
            .appendingPathComponent("shell-integration.zsh", isDirectory: false)
        let configurationURL = homeDirectory.appendingPathComponent(".zshrc", isDirectory: false)

        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try script(controlExecutablePath: controlExecutablePath).write(to: scriptURL, atomically: true, encoding: .utf8)

        let sourceLine = #"[ -f "\#(scriptURL.path)" ] && source "\#(scriptURL.path)""#
        let managedBlock = """
        \(Self.beginMarker)
        \(sourceLine)
        \(Self.endMarker)
        """

        let existing = (try? String(contentsOf: configurationURL, encoding: .utf8)) ?? ""
        let updated = replacingManagedBlock(in: existing, with: managedBlock)
        try updated.write(to: configurationURL, atomically: true, encoding: .utf8)

        return ShellHookInstallation(
            scriptURL: scriptURL,
            shellConfigurationURL: configurationURL,
            controlExecutablePath: controlExecutablePath
        )
    }

    public func uninstall(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL? = nil
    ) throws {
        let applicationSupport = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let scriptURL = applicationSupport
            .appendingPathComponent("TouchingBar", isDirectory: true)
            .appendingPathComponent("shell-integration.zsh", isDirectory: false)
        let configurationURL = homeDirectory.appendingPathComponent(".zshrc", isDirectory: false)

        if FileManager.default.fileExists(atPath: scriptURL.path) {
            try FileManager.default.removeItem(at: scriptURL)
        }
        guard let existing = try? String(contentsOf: configurationURL, encoding: .utf8) else { return }
        let updated = replacingManagedBlock(in: existing, with: nil)
        try updated.write(to: configurationURL, atomically: true, encoding: .utf8)
    }

    public func isInstalled(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let configurationURL = homeDirectory.appendingPathComponent(".zshrc", isDirectory: false)
        guard let content = try? String(contentsOf: configurationURL, encoding: .utf8) else { return false }
        return content.contains(Self.beginMarker) && content.contains(Self.endMarker)
    }

    private func replacingManagedBlock(in content: String, with replacement: String?) -> String {
        guard let start = content.range(of: Self.beginMarker),
              let end = content.range(of: Self.endMarker, range: start.upperBound..<content.endIndex) else {
            guard let replacement else { return content }
            let separator = content.isEmpty || content.hasSuffix("\n") ? "" : "\n"
            return content + separator + "\n" + replacement + "\n"
        }

        let trailingRange = end.upperBound..<content.endIndex
        let trailing = content[trailingRange].drop(while: { $0 == "\n" })
        var result = String(content[..<start.lowerBound])
        if let replacement {
            result += replacement + "\n"
        }
        if !trailing.isEmpty {
            result += String(trailing)
        }
        return result
    }

    private func script(controlExecutablePath: String) -> String {
        let escapedPath = controlExecutablePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return #"""
        # Generated by TouchingBar. Edit through the app instead of modifying this file directly.
        typeset -g _TOUCHINGBAR_CTL="\#(escapedPath)"
        typeset -g _TOUCHINGBAR_LAST_PWD=""

        _touchingbar_precmd() {
            [[ -x "$_TOUCHINGBAR_CTL" ]] || return
            [[ "$PWD" == "$_TOUCHINGBAR_LAST_PWD" ]] && return
            _TOUCHINGBAR_LAST_PWD="$PWD"

            local python_version=""
            local node_version=""
            local node_manager=""

            if [[ -n "${VIRTUAL_ENV:-}" && -x "$VIRTUAL_ENV/bin/python" ]]; then
                python_version="$("$VIRTUAL_ENV/bin/python" --version 2>&1)"
                python_version="${python_version#Python }"
            fi

            if command -v node >/dev/null 2>&1; then
                node_version="$(node --version 2>/dev/null)"
                [[ -n "${PNPM_HOME:-}" ]] && node_manager="pnpm"
                [[ -n "${NVM_BIN:-}" ]] && node_manager="${node_manager:-nvm}"
            fi

            local terminal_name="${TERM_PROGRAM:-${TERM:-zsh}}"
            (
                args=(
                    developer
                    --directory "$PWD"
                    --terminal "$terminal_name"
                )
                [[ -n "${VIRTUAL_ENV:-}" ]] && args+=(--python-env "${VIRTUAL_ENV:t}")
                [[ -n "$python_version" ]] && args+=(--python-version "$python_version")
                [[ -n "$node_version" ]] && args+=(--node-version "$node_version")
                [[ -n "$node_manager" ]] && args+=(--node-manager "$node_manager")
                "$_TOUCHINGBAR_CTL" "${args[@]}" >/dev/null 2>&1
            ) &!
        }

        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _touchingbar_precmd
        """#
    }
}

public enum ShellHookError: Error, LocalizedError {
    case unsupportedShell(String)
    case controlExecutableMustBeAbsolute(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedShell(let shell):
            return "暂不支持 \(shell)，当前仅支持 zsh。"
        case .controlExecutableMustBeAbsolute(let path):
            return "TouchingBarCtl 必须使用绝对路径：\(path)"
        }
    }
}
