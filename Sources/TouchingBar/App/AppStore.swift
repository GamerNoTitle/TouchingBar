import AppKit
import Combine
import Foundation
import TouchingBarCore

@MainActor
final class AppStore: ObservableObject {
    @Published var configuration: AppConfiguration {
        didSet {
            hasUnsavedChanges = configuration != savedConfiguration
        }
    }
    @Published private(set) var hasUnsavedChanges = false
    @Published var runtime: RuntimeContextSnapshot
    @Published var lastError: String?
    @Published var hookServerRunning = false
    @Published var activeApplicationName: String?
    @Published var touchBarStatus = "Touch Bar：等待启动"
    @Published var systemMetrics = SystemMetricsSnapshot.empty
    @Published private(set) var webDAVPassword = ""

    let configurationStore: ConfigurationStore
    let backupService: BackupService
    let contextStore: RuntimeContextStore
    let webDAVClient: WebDAVClient
    let developerContextProvider: DeveloperContextProvider
    let webDAVKeychain = WebDAVKeychain()

    private var savedConfiguration: AppConfiguration
    private let developerRefreshQueue = DispatchQueue(label: "app.touchingbar.developer-refresh", qos: .utility)
    private let systemMetricsService = SystemMetricsService()
    private var refreshTimer: Timer?
    private var lastDeveloperRefresh = Date.distantPast
    private var lastWorkingDirectory: String?
    private var cancellables: Set<AnyCancellable> = []

    init(
        configurationStore: ConfigurationStore = .shared,
        contextStore: RuntimeContextStore = .shared
    ) {
        self.configurationStore = configurationStore
        self.contextStore = contextStore
        backupService = BackupService()
        webDAVClient = WebDAVClient()
        developerContextProvider = DeveloperContextProvider()

        var loadedConfiguration = AppConfiguration()
        do {
            loadedConfiguration = try configurationStore.load()
        } catch {
            lastError = error.localizedDescription
        }
        configuration = loadedConfiguration
        savedConfiguration = loadedConfiguration
        runtime = contextStore.load()
        webDAVPassword = webDAVKeychain.loadPassword() ?? ""

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        startContextRefresh()
        systemMetricsService.start { [weak self] snapshot in
            self?.systemMetrics = snapshot
        }
        systemMetricsService.setHistoryDuration(seconds: configuration.effectiveMetricsHistorySeconds)
        $configuration
            .map(\.effectiveMetricsHistorySeconds)
            .removeDuplicates()
            .sink { [weak self] seconds in
                self?.systemMetricsService.setHistoryDuration(seconds: seconds)
            }
            .store(in: &cancellables)
    }

    deinit {
        refreshTimer?.invalidate()
        systemMetricsService.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func save() {
        do {
            try configurationStore.save(configuration)
            savedConfiguration = configuration
            hasUnsavedChanges = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveIfNeeded() {
        guard hasUnsavedChanges else { return }
        save()
    }

    func discardChanges() {
        configuration = savedConfiguration
        hasUnsavedChanges = false
    }

    /// Compatibility alias for callers that explicitly want to flush the
    /// current configuration, such as backup import.
    func persist() {
        save()
    }

    func saveWebDAVPassword(_ password: String) {
        do {
            try webDAVKeychain.savePassword(password)
            webDAVPassword = password
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearWebDAVPassword() {
        do {
            try webDAVKeychain.deletePassword()
            webDAVPassword = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reloadRuntimeContext() {
        runtime = contextStore.load()
    }

    func apply(_ snapshot: RuntimeContextSnapshot) {
        runtime = snapshot
    }

    func addIncomingMessage(_ message: MessageContext) {
        do {
            runtime = try contextStore.update { $0.messages.insert(message, at: 0) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateConfiguration(_ mutation: (inout AppConfiguration) -> Void) {
        mutation(&configuration)
        configuration.normalize()
    }

    func selectAdjacentPreset(offset: Int) {
        guard !configuration.presets.isEmpty else { return }
        let currentIndex = configuration.presets.firstIndex(where: { $0.id == configuration.activePresetID }) ?? 0
        let count = configuration.presets.count
        let target = (currentIndex + offset + count) % count
        updateConfiguration { $0.activePresetID = $0.presets[target].id }
        persistActivePresetSelection()
    }

    func selectPreset(id: UUID) {
        updateConfiguration { $0.activePresetID = id }
        persistActivePresetSelection()
    }

    private func persistActivePresetSelection() {
        guard savedConfiguration.activePresetID != configuration.activePresetID else { return }
        var persisted = savedConfiguration
        persisted.activePresetID = configuration.activePresetID
        do {
            try configurationStore.save(persisted)
            savedConfiguration = persisted
            hasUnsavedChanges = configuration != savedConfiguration
        } catch {
            lastError = error.localizedDescription
        }
    }

    func replacePreset(_ preset: TouchBarPreset) {
        updateConfiguration { configuration in
            guard let index = configuration.presets.firstIndex(where: { $0.id == preset.id }) else { return }
            configuration.presets[index] = preset
        }
    }

    func duplicatePreset(_ preset: TouchBarPreset) {
        var copy = preset
        copy.id = UUID()
        copy.name += " 副本"
        copy.isBuiltIn = false
        copy.items = copy.items.map { item in
            var itemCopy = item
            itemCopy.id = UUID()
            return itemCopy
        }
        updateConfiguration { configuration in
            configuration.presets.append(copy)
            configuration.activePresetID = copy.id
        }
    }

    func addPreset() {
        let preset = TouchBarPreset(name: "自定义配置", kind: .custom, content: .components)
        updateConfiguration { configuration in
            configuration.presets.append(preset)
            configuration.activePresetID = preset.id
        }
    }

    func deletePreset(id: UUID) {
        updateConfiguration { configuration in
            configuration.presets.removeAll { $0.id == id }
            configuration.normalize()
        }
    }

    func restoreBuiltInPreset(kind: PresetKind) {
        guard let preset = BuiltInPresets.preset(for: kind),
              !configuration.presets.contains(where: { $0.kind == kind }) else {
            return
        }
        updateConfiguration { configuration in
            configuration.presets.append(preset)
            configuration.activePresetID = preset.id
        }
    }

    func movePreset(id: UUID, offset: Int) {
        updateConfiguration { configuration in
            guard let source = configuration.presets.firstIndex(where: { $0.id == id }) else { return }
            let target = max(0, min(configuration.presets.count - 1, source + offset))
            guard source != target else { return }
            let preset = configuration.presets.remove(at: source)
            configuration.presets.insert(preset, at: target)
        }
    }

    func updateActivePreset(_ mutation: (inout TouchBarPreset) -> Void) {
        guard let activeID = configuration.activePresetID,
              let index = configuration.presets.firstIndex(where: { $0.id == activeID }) else { return }
        mutation(&configuration.presets[index])
        configuration.normalize()
    }

    func addItem(toPresetID presetID: UUID) {
        addItem(
            toPresetID: presetID,
            item: TouchBarItemConfiguration(label: "新按钮", symbolName: "circle", action: .none)
        )
    }

    func addItem(toPresetID presetID: UUID, item: TouchBarItemConfiguration) {
        updateConfiguration { configuration in
            guard let index = configuration.presets.firstIndex(where: { $0.id == presetID }) else { return }
            configuration.presets[index].items.append(item)
        }
    }

    func moveItems(presetID: UUID, fromOffsets: IndexSet, toOffset: Int) {
        updateConfiguration { configuration in
            guard let index = configuration.presets.firstIndex(where: { $0.id == presetID }) else { return }
            var items = configuration.presets[index].items
            let moving = fromOffsets.sorted().map { items[$0] }
            let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
            for source in fromOffsets.sorted(by: >) {
                items.remove(at: source)
            }
            let destination = max(0, min(items.count, toOffset - removedBeforeDestination))
            items.insert(contentsOf: moving, at: destination)
            configuration.presets[index].items = items
        }
    }

    func updateItem(presetID: UUID, item: TouchBarItemConfiguration) {
        updateConfiguration { configuration in
            guard let presetIndex = configuration.presets.firstIndex(where: { $0.id == presetID }),
                  let itemIndex = configuration.presets[presetIndex].items.firstIndex(where: { $0.id == item.id }) else {
                return
            }
            configuration.presets[presetIndex].items[itemIndex] = item
        }
    }

    func deleteItem(presetID: UUID, itemID: UUID) {
        updateConfiguration { configuration in
            guard let index = configuration.presets.firstIndex(where: { $0.id == presetID }) else { return }
            configuration.presets[index].items.removeAll { $0.id == itemID }
        }
    }

    func moveItem(presetID: UUID, itemID: UUID, offset: Int) {
        updateConfiguration { configuration in
            guard let presetIndex = configuration.presets.firstIndex(where: { $0.id == presetID }),
                  let source = configuration.presets[presetIndex].items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            let target = max(0, min(configuration.presets[presetIndex].items.count - 1, source + offset))
            guard source != target else { return }
            let item = configuration.presets[presetIndex].items.remove(at: source)
            configuration.presets[presetIndex].items.insert(item, at: target)
        }
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        activeApplicationName = application.localizedName
        refreshDeveloperContext(for: application, force: true)
    }

    private func startContextRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let application = NSWorkspace.shared.frontmostApplication {
                    self.refreshDeveloperContext(for: application, force: false)
                }
            }
        }
        if let application = NSWorkspace.shared.frontmostApplication {
            refreshDeveloperContext(for: application, force: true)
        }
    }

    private func refreshDeveloperContext(for application: NSRunningApplication, force: Bool) {
        guard let bundleIdentifier = application.bundleIdentifier,
              TerminalApplication.isSupported(bundleIdentifier: bundleIdentifier) else {
            return
        }

        if !force, Date().timeIntervalSince(lastDeveloperRefresh) < 3 {
            return
        }
        lastDeveloperRefresh = Date()

        let applicationPID = application.processIdentifier
        let applicationName = application.localizedName
        developerRefreshQueue.async { [weak self] in
            guard let self else { return }
            guard let directory = TerminalContextResolver.workingDirectory(for: applicationPID) else { return }
            let provider = self.developerContextProvider
            Task {
                let context = await provider.collect(at: directory, terminalName: applicationName)
                await MainActor.run {
                    self.lastWorkingDirectory = directory
                    self.updateDeveloperContext(context)
                }
            }
        }
    }

    private func updateDeveloperContext(_ context: DeveloperContext) {
        do {
            runtime = try contextStore.update { $0.developer = context }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private enum TerminalApplication {
    static let bundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.AppCode",
        "com.jetbrains.CLion",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.PyCharm",
        "com.jetbrains.PyCharm.ce",
        "com.jetbrains.rider",
        "com.jetbrains.WebStorm",
        "com.jetbrains.GoLand",
        "com.jetbrains.datagrip",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm"
    ]

    static func isSupported(bundleIdentifier: String) -> Bool {
        bundleIdentifiers.contains(bundleIdentifier) || bundleIdentifier.hasPrefix("com.jetbrains.")
    }
}

private enum TerminalContextResolver {
    private struct ProcessInfo {
        var pid: Int
        var parentPID: Int
        var command: String
    }

    static func workingDirectory(for rootPID: pid_t) -> String? {
        let result = CommandRunner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,comm="])
        guard result.exitCode == 0 else { return nil }

        let processes: [ProcessInfo] = result.standardOutput.split(separator: "\n").compactMap { line in
            let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 3, let pid = Int(parts[0]), let parentPID = Int(parts[1]) else { return nil }
            return ProcessInfo(pid: pid, parentPID: parentPID, command: parts[2])
        }

        var descendants = Set<Int>([Int(rootPID)])
        var changed = true
        while changed {
            changed = false
            for process in processes where descendants.contains(process.parentPID) && !descendants.contains(process.pid) {
                descendants.insert(process.pid)
                changed = true
            }
        }

        let shellNames = ["zsh", "bash", "fish", "nu", "pwsh", "sh"]
        let shellPIDs = processes
            .filter { process in
                guard descendants.contains(process.pid) else { return false }
                let executable = URL(fileURLWithPath: process.command).lastPathComponent
                return shellNames.contains(executable)
            }
            .map(\.pid)

        for pid in shellPIDs.reversed() {
            let lsof = CommandRunner.run("/usr/sbin/lsof", arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
            let paths = lsof.standardOutput
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard line.hasPrefix("n") else { return nil }
                    return String(line.dropFirst())
                }
            if let path = paths.first, FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}
