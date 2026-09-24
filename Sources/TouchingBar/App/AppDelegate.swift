import AppKit
import Combine
import Foundation
import TouchingBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppStore()
    private var touchBarController: TouchBarController!
    private var statusBarController: StatusBarController!
    private var settingsWindowController: SettingsWindowController!
    private var hookServer: HookServer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        touchBarController = TouchBarController(store: store)
        statusBarController = StatusBarController(
            store: store,
            openSettings: { [weak self] in self?.showSettings() }
        )
        settingsWindowController = SettingsWindowController(store: store)

        observeStore()
        startHookServer()
        touchBarController.start()
        statusBarController.update()
        if !store.configuration.effectiveSilentLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookServer?.stop()
        touchBarController.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !store.configuration.effectiveSilentLaunch else { return true }
        showSettings()
        return true
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
    }

    private func observeStore() {
        store.$configuration
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] configuration in
                _ = configuration
                self?.statusBarController.update()
            }
            .store(in: &cancellables)

    }

    private func startHookServer() {
        let server = HookServer { [weak self] snapshot in
            Task { @MainActor in
                self?.store.apply(snapshot)
            }
        }
        server.onRunningStateChange = { [weak self] isRunning in
            Task { @MainActor in
                self?.store.hookServerRunning = isRunning
            }
        }
        do {
            try server.start()
            hookServer = server
        } catch {
            store.lastError = "Hook 服务启动失败：\(error.localizedDescription)"
            store.hookServerRunning = false
        }
    }
}
