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

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        return mainMenu
    }
}
