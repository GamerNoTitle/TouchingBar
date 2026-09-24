import Combine
import ServiceManagement

/// Keeps the macOS login-item registration and the settings UI in sync.
///
/// `SMAppService.mainApp` is the source of truth so changes made in
/// System Settings are reflected the next time the app becomes active.
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            errorMessage = "无法更新开机启动设置：\(error.localizedDescription)。请先把 TouchingBar 放入“应用程序”文件夹，再重试。"
            refresh()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
