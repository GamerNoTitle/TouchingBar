import AppKit
import ApplicationServices
import Foundation
import TouchingBarCore
import UserNotifications

struct ApplicationUnreadCount: Identifiable, Equatable {
    var id: String { bundleIdentifier }
    var bundleIdentifier: String
    var applicationName: String
    var count: Int
}

final class DockBadgeReader {
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    private let displayNameOverrides: [String: String] = [
        "com.tencent.xinWeChat": "WeChat",
        "com.tencent.qq": "QQ",
        "ru.keepcoder.Telegram": "Telegram",
        "com.tencent.WeWorkMac": "企业微信",
        "WeWorkMac": "企业微信",
        "com.electron.lark": "Lark",
        "com.bytedance.lark": "Lark",
        "com.bytedance.feishu": "飞书"
    ]

    func read(bundleIdentifiers: [String]) -> [ApplicationUnreadCount] {
        guard AXIsProcessTrusted() else { return [] }
        let dockApplications = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
        guard let dock = dockApplications.first else { return [] }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        let elements = collectElements(from: dockElement, depth: 0, maximumDepth: 7)

        var seen = Set<String>()
        return bundleIdentifiers.compactMap { bundleIdentifier -> ApplicationUnreadCount? in
            guard seen.insert(bundleIdentifier).inserted else { return nil }
            let runningApplication = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first
            let displayName = runningApplication?.localizedName
                ?? displayNameOverrides[bundleIdentifier]
                ?? bundleIdentifier
            let matched = elements.first { element in
                let label = stringAttribute(element, "AXLabel") ?? ""
                let title = stringAttribute(element, "AXTitle") ?? ""
                return label.localizedCaseInsensitiveContains(displayName)
                    || title.localizedCaseInsensitiveContains(displayName)
            }
            let status = matched.flatMap { stringAttribute($0, "AXStatusLabel") } ?? ""
            let count = Int(status.filter(\.isNumber)) ?? 0
            return ApplicationUnreadCount(
                bundleIdentifier: bundleIdentifier,
                applicationName: displayName,
                count: count
            )
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func collectElements(from element: AXUIElement, depth: Int, maximumDepth: Int) -> [AXUIElement] {
        guard depth <= maximumDepth else { return [] }
        var result = [element]
        guard let children = attribute(element, "AXChildren") as? [AXUIElement] else { return result }
        for child in children {
            result.append(contentsOf: collectElements(from: child, depth: depth + 1, maximumDepth: maximumDepth))
        }
        return result
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        self.attribute(element, attribute) as? String
    }

    private func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }
}

final class MessageNotificationController: NSObject, UNUserNotificationCenterDelegate {
    private var lastSeenIDs: Set<UUID> = []
    private var hasSeededExistingMessages = false

    func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func process(_ messages: [MessageContext], enabled: Bool) {
        let currentIDs = Set(messages.map(\.id))
        let newMessages = messages.filter { !lastSeenIDs.contains($0.id) }
        lastSeenIDs.formUnion(currentIDs)
        guard hasSeededExistingMessages else {
            hasSeededExistingMessages = true
            return
        }
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }

        for message in newMessages.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = message.sender.map { "\(message.application) · \($0)" } ?? message.application
            content.body = message.body
            if let conversation = message.conversation, !conversation.isEmpty {
                content.subtitle = conversation
            }
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: message.id.uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}


final class MessageBannerMonitor {
    typealias MessageHandler = (MessageContext) -> Void

    private var timer: Timer?
    private var monitoredBundleIdentifiers: [String] = []
    private var handler: MessageHandler?
    private var seenKeys: Set<String> = []
    private var hasSeededExistingBanners = false

    func start(
        bundleIdentifiers: [String],
        handler: @escaping MessageHandler
    ) {
        self.monitoredBundleIdentifiers = bundleIdentifiers
        self.handler = handler
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func update(bundleIdentifiers: [String]) {
        monitoredBundleIdentifiers = bundleIdentifiers
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard AXIsProcessTrusted(), !monitoredBundleIdentifiers.isEmpty else { return }
        let applicationBundleIdentifiers = [
            "com.apple.notificationcenterui",
            "com.apple.UserNotificationCenter",
            "com.apple.notificationcenterui.agent"
        ]
        var discovered: [MessageContext] = []

        for processBundleIdentifier in applicationBundleIdentifiers {
            for application in NSRunningApplication.runningApplications(withBundleIdentifier: processBundleIdentifier) {
                let root = AXUIElementCreateApplication(application.processIdentifier)
                discovered.append(contentsOf: scan(root: root))
            }
        }

        guard hasSeededExistingBanners else {
            seenKeys.formUnion(discovered.map(key(for:)))
            hasSeededExistingBanners = true
            return
        }

        for message in discovered {
            let messageKey = key(for: message)
            guard !seenKeys.contains(messageKey) else { continue }
            seenKeys.insert(messageKey)
            if seenKeys.count > 200 {
                seenKeys = Set(seenKeys.suffix(100))
            }
            handler?(message)
        }
    }

    private func scan(root: AXUIElement) -> [MessageContext] {
        let windows = attribute(root, "AXWindows") as? [AXUIElement] ?? []
        return windows.compactMap { window in
            let elements = collectElements(from: window, depth: 0, maximumDepth: 6)
            let texts = elements.flatMap(textValues).filter { !$0.isEmpty }
            guard !texts.isEmpty else { return nil }
            guard let displayName = monitoredApplications.first(where: { _, appName in
                texts.contains(where: { $0.localizedCaseInsensitiveContains(appName) })
            }) else { return nil }

            let appName = displayName.appName
            let contentTexts = texts.filter {
                !$0.localizedCaseInsensitiveContains(appName)
            }
            let body = contentTexts.max(by: { $0.count < $1.count }) ?? texts.last ?? ""
            guard body.count > 1 else { return nil }
            let sender = contentTexts.first(where: { $0 != body && $0.count <= 80 })
            return MessageContext(
                application: appName,
                bundleIdentifier: displayName.bundleIdentifier,
                sender: sender,
                body: body,
                conversation: nil,
                unreadCount: 0
            )
        }
    }

    private var monitoredApplications: [(bundleIdentifier: String, appName: String)] {
        monitoredBundleIdentifiers.compactMap { bundleIdentifier in
            let appName = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?
                .localizedName
                ?? displayNameOverrides[bundleIdentifier]
                ?? bundleIdentifier
            return (bundleIdentifier, appName)
        }
    }

    private let displayNameOverrides: [String: String] = [
        "com.tencent.xinWeChat": "WeChat",
        "com.tencent.qq": "QQ",
        "ru.keepcoder.Telegram": "Telegram",
        "com.tencent.WeWorkMac": "企业微信",
        "WeWorkMac": "企业微信",
        "com.electron.lark": "Lark",
        "com.bytedance.lark": "Lark",
        "com.bytedance.feishu": "飞书"
    ]

    private func collectElements(from element: AXUIElement, depth: Int, maximumDepth: Int) -> [AXUIElement] {
        guard depth <= maximumDepth else { return [] }
        var result = [element]
        if let children = attribute(element, "AXChildren") as? [AXUIElement] {
            for child in children {
                result.append(contentsOf: collectElements(from: child, depth: depth + 1, maximumDepth: maximumDepth))
            }
        }
        return result
    }

    private func textValues(from element: AXUIElement) -> [String] {
        ["AXTitle", "AXDescription", "AXValue", "AXHelp"]
            .compactMap { attribute(element, $0) as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private func key(for message: MessageContext) -> String {
        "\(message.bundleIdentifier ?? message.application)|\(message.sender ?? "")|\(message.body)"
    }
}
