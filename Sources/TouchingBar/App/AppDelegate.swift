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
    private let notificationController = MessageNotificationController()
    private let agentNotificationController = AgentNotificationController()
    private let messageBannerMonitor = MessageBannerMonitor()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        touchBarController = TouchBarController(store: store)
        statusBarController = StatusBarController(
            store: store,
            openSettings: { [weak self] in self?.showSettings() }
        )
        settingsWindowController = SettingsWindowController(store: store)

        notificationController.requestAuthorization()
        messageBannerMonitor.start(
            bundleIdentifiers: store.configuration.messages.monitoredApplications
        ) { [weak self] message in
            Task { @MainActor in
                self?.store.addIncomingMessage(message)
            }
        }
        observeStore()
        startHookServer()
        touchBarController.start()
        statusBarController.update()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookServer?.stop()
        messageBannerMonitor.stop()
        touchBarController.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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
                self?.statusBarController.update()
                self?.messageBannerMonitor.update(
                    bundleIdentifiers: configuration.messages.monitoredApplications
                )
            }
            .store(in: &cancellables)

        store.$runtime
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.notificationController.process(
                    snapshot.messages,
                    enabled: self.store.configuration.messages.showNotificationBanners
                )
                self.agentNotificationController.process(
                    snapshot.agents ?? snapshot.agent.map { [$0] } ?? [],
                    enabled: self.store.configuration.effectiveShowAgentNotifications
                )
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
