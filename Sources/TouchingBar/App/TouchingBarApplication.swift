import AppKit

@main
struct TouchingBarApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.mainMenu = MainMenuBuilder.make(target: delegate)
        application.delegate = delegate
        application.run()
    }
}


@MainActor
private enum MainMenuBuilder {
    static func make(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu(title: "TouchingBar")
        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)

        let applicationMenu = NSMenu(title: "TouchingBar")
        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(AppDelegate.showSettings),
            keyEquivalent: ","
        )
        let quitItem = NSMenuItem(
            title: "退出 TouchingBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        settingsItem.target = target
        quitItem.target = target
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(quitItem)
        applicationMenuItem.submenu = applicationMenu
        return mainMenu
    }
}
