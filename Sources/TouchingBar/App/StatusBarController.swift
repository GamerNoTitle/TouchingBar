import AppKit
import Combine
import TouchingBarCore

@MainActor
final class StatusBarController: NSObject {
    private let store: AppStore
    private let openSettingsAction: () -> Void
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    init(
        store: AppStore,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        openSettingsAction = openSettings
        super.init()
        cancellable = store.$configuration
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
    }

    func update() {
        if store.configuration.menuBar.isEnabled {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
        rebuildMenu()
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "TouchingBar"
        )
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageOnly
        item.button?.contentTintColor = nil
        item.button?.toolTip = "TouchingBar"
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let isDebugMode = ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 260
        menu.font = .menuFont(ofSize: 0)

        let presetMenu = NSMenu()
        presetMenu.autoenablesItems = false
        presetMenu.minimumWidth = 220
        for preset in store.configuration.presets {
            let item = menuItem(
                title: preset.name,
                action: #selector(selectPreset(_:)),
                keyEquivalent: ""
            )
            item.representedObject = preset.id.uuidString
            item.state = preset.id == store.configuration.activePresetID ? .on : .off
            presetMenu.addItem(item)
        }
        let currentPreset = store.configuration.activePreset?.name ?? "未选择"
        let presetItem = menuItem(
            title: "当前配置：\(currentPreset)",
            action: nil,
            keyEquivalent: ""
        )
        presetItem.submenu = presetMenu
        menu.addItem(presetItem)

        if isDebugMode {
            let statusLineItem = menuItem(
                title: store.touchBarStatus,
                action: nil,
                keyEquivalent: ""
            )
            statusLineItem.isEnabled = false
            menu.addItem(statusLineItem)
        }

        menu.addItem(.separator())

        let settingsItem = menuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        let quitItem = menuItem(
            title: "退出 TouchingBar",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu

        if isDebugMode {
            NSLog(
                "TouchingBar menu titles: %@; status appearance=%@",
                menu.items.map(\.title).joined(separator: " | "),
                statusItem.button?.effectiveAppearance.name.rawValue ?? "nil"
            )
        }
    }

    private func menuItem(title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        store.selectPreset(id: id)
    }

    @objc private func openSettings() {
        openSettingsAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
