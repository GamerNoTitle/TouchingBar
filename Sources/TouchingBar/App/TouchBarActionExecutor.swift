import AppKit
import CoreGraphics
import Foundation
import TouchingBarCore
import TouchingBarDFR

@MainActor
final class TouchBarActionExecutor {
    typealias CommandHandler = (String, String?) -> Void

    private let commandHandler: CommandHandler

    init(commandHandler: @escaping CommandHandler = { command, directory in
        TouchBarActionExecutor.runShellCommand(command, directory: directory)
    }) {
        self.commandHandler = commandHandler
    }

    func execute(_ action: ActionSpec, buttonTitle: String? = nil) {
        switch action.kind {
        case .none:
            break
        case .functionKey:
            guard let number = Int(action.value ?? ""), (1...12).contains(number) else { return }
            sendFunctionKey(number)
        case .keyboardShortcut:
            guard let shortcut = action.shortcut else { return }
            sendShortcut(shortcut)
        case .launchApplication:
            launchApplication(action.value)
        case .openURL:
            openURL(action.value)
        case .runCommand:
            guard let command = action.value, !command.isEmpty else { return }
            commandHandler(command, nil)
        case .media:
            MediaPlaybackController.perform(action.media ?? .playPause)
        case .volume:
            SystemControlController.performVolume(action.volume ?? .up)
        case .brightness:
            SystemControlController.adjustBrightness(direction: action.value ?? "up")
        case .missionControl:
            if !SystemActionController.openMissionControl() {
                sendShortcut(KeyShortcut(key: "up", control: true))
            }
        case .spotlight:
            if !SystemActionController.openSpotlight() {
                sendShortcut(KeyShortcut(key: "space", command: true))
            }
        case .dictation:
            if !SystemActionController.toggleDictation() {
                sendFunctionKeyOnce()
            }
        case .doNotDisturb:
            SystemActionController.toggleDoNotDisturb()
        case .lockScreen:
            _ = TBLockScreen()
        case .keyboardBacklight:
            setKeyboardBacklight(direction: action.value ?? "up")
        }
    }

    private func setKeyboardBacklight(direction: String) {
        var current: Float = 0
        if TBGetKeyboardBacklight(&current) {
            let step: Float = 0.0625
            let isDown = direction == "down" || direction == "off"
            let target = isDown
                ? max(0, current - step)
                : min(1, current + step)
            _ = TBSetKeyboardBacklight(target)
        } else {
            // Legacy fallback for keyboards whose level cannot be read.
            _ = TBSetKeyboardBacklight(direction == "down" || direction == "off" ? 0 : 1)
        }
    }

    private func sendFunctionKey(_ number: Int) {
        let keyCodes: [Int: CGKeyCode] = [
            1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97,
            7: 98, 8: 100, 9: 101, 10: 109, 11: 103, 12: 111
        ]
        guard let keyCode = keyCodes[number] else { return }
        postKey(keyCode: keyCode, flags: [])
    }

    private func sendFunctionKeyOnce() {
        postKey(keyCode: 63, flags: [.maskSecondaryFn])
        postKey(keyCode: 63, flags: [.maskSecondaryFn])
    }

    private func sendShortcut(_ shortcut: KeyShortcut) {
        guard let keyCode = KeyCodeMap.keyCode(for: shortcut.key) else { return }
        var flags: CGEventFlags = []
        if shortcut.command { flags.insert(.maskCommand) }
        if shortcut.option { flags.insert(.maskAlternate) }
        if shortcut.control { flags.insert(.maskControl) }
        if shortcut.shift { flags.insert(.maskShift) }
        postKey(keyCode: keyCode, flags: flags)
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func launchApplication(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        if value.contains("."), !value.contains("/") {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
            if let url {
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                return
            }
        }
        let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openURL(_ value: String?) {
        guard let value, let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func runShellCommand(_ command: String, directory: String?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            if let directory {
                process.currentDirectoryURL = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
            }
            try? process.run()
        }
    }
}

private enum KeyCodeMap {
    private static let values: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "delete": 51, "escape": 53, "left": 123, "right": 124,
        "down": 125, "up": 126
    ]

    static func keyCode(for key: String) -> CGKeyCode? {
        let normalized = key.lowercased()
        if normalized.hasPrefix("f"), let number = Int(normalized.dropFirst()), (1...12).contains(number) {
            return keyCodeForFunction(number)
        }
        return values[normalized]
    }

    private static func keyCodeForFunction(_ number: Int) -> CGKeyCode? {
        [1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97, 7: 98,
         8: 100, 9: 101, 10: 109, 11: 103, 12: 111][number]
    }
}
