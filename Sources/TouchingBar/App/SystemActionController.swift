import AppKit
import ApplicationServices
import Foundation
import TouchingBarCore

enum SystemActionController {
    static func openMissionControl() -> Bool {
        openSystemApplication(path: "/System/Applications/Mission Control.app")
    }

    static func openSpotlight() -> Bool {
        openSystemApplication(path: "/System/Library/CoreServices/Spotlight.app")
    }

    static func toggleDictation() -> Bool {
        guard ensureAccessibilityPermission() else { return true }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        let terms = ["start dictation", "dictation", "开始听写", "听写"]
        guard let item = findElement(in: root, matching: terms) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    static func toggleDoNotDisturb() {
        guard ensureAccessibilityPermission() else { return }
        if runFocusShortcut() { return }
        if toggleFocusFromControlCenter() { return }
        openFocusSettings()
    }

    private static func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }

        let promptKey = "app.touchingbar.accessibilityPrompted"
        if !UserDefaults.standard.bool(forKey: promptKey) {
            UserDefaults.standard.set(true, forKey: promptKey)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return false
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private static func openSystemApplication(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }

    private static func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func runFocusShortcut() -> Bool {
        let result = CommandRunner.run("/usr/bin/shortcuts", arguments: ["list"])
        guard result.exitCode == 0 else { return false }
        let names = result.standardOutput.components(separatedBy: .newlines)
        let exactNames = [
            "Toggle Do Not Disturb",
            "Toggle Focus",
            "切换勿扰模式",
            "切换专注模式"
        ]
        guard let shortcut = exactNames.first(where: names.contains) else { return false }
        return CommandRunner.run("/usr/bin/shortcuts", arguments: ["run", shortcut]).exitCode == 0
    }

    private static func toggleFocusFromControlCenter() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let bundleIdentifiers = [
            "com.apple.controlcenter",
            "com.apple.ControlCenter"
        ]
        let terms = ["do not disturb", "focus", "勿扰", "专注"]
        for bundleIdentifier in bundleIdentifiers {
            for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                let root = AXUIElementCreateApplication(application.processIdentifier)
                if let item = findElement(in: root, matching: terms),
                   AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                    return true
                }
            }
        }
        return false
    }

    private static func findElement(
        in root: AXUIElement,
        matching terms: [String]
    ) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count {
            let (element, depth) = queue[index]
            index += 1
            if depth > 8 { continue }

            let values = ["AXTitle", "AXDescription", "AXValue", "AXHelp", "AXIdentifier"]
                .compactMap { attribute(element, $0) as? String }
            let searchable = values.joined(separator: " ").lowercased()
            if terms.contains(where: { searchable.contains($0.lowercased()) }) {
                return element
            }

            if let children = attribute(element, "AXChildren") as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }
}
