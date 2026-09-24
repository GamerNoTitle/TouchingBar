import AppKit
import Combine
import Foundation
import TouchingBarCore
import TouchingBarDFR

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private static let actionDashboardIdentifier = NSTouchBarItem.Identifier("app.touchingbar.action-dashboard")
    private static let systemTrayIdentifier = NSTouchBarItem.Identifier("app.touchingbar.system-tray")
    private static let nowPlayingIdentifier = NSTouchBarItem.Identifier("app.touchingbar.now-playing")
    private static let messagesIdentifier = NSTouchBarItem.Identifier("app.touchingbar.messages")

    private let store: AppStore
    private let actionExecutor = TouchBarActionExecutor()
    private let nowPlayingService = NowPlayingService()
    private let badgeReader = DockBadgeReader()

    private var touchBar: NSTouchBar?
    private var systemTrayItem: NSCustomTouchBarItem?
    private var configurationCancellable: AnyCancellable?
    private var runtimeCancellable: AnyCancellable?
    private var badgeTimer: Timer?
    private var presentationTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var contextViews: [UUID: ContextTouchBarView] = [:]
    private var contextConfigurations: [UUID: TouchBarItemConfiguration] = [:]
    private var actionConfigurations: [String: TouchBarItemConfiguration] = [:]
    private var nowPlayingViews: [NowPlayingTouchBarView] = []
    private var messageViews: [MessagesTouchBarView] = []
    private var latestNowPlaying: NowPlayingSnapshot?
    private var badgeCounts: [ApplicationUnreadCount] = []
    private var isStarted = false
    private var cancellables: Set<AnyCancellable> = []
    private var expectedItemCount = 0
    private var lastRebuildSignature: String?
    private var didTriggerDashboardSwipe = false
    private var createdItemIdentifiers: Set<String> = []

    init(store: AppStore) {
        self.store = store
        super.init()
        configurationCancellable = store.$configuration
            .receive(on: RunLoop.main)
            .sink { [weak self] configuration in
                self?.nowPlayingService.setLyricsOffset(configuration.effectiveLyricsOffset)
                self?.rebuildTouchBar()
            }
        runtimeCancellable = store.$runtime
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.updateRuntime(snapshot) }
        store.$systemMetrics
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateContextValues() }
            .store(in: &cancellables)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.store.configuration.alwaysOccupyTouchBar else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.present()
                }
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        nowPlayingService.setLyricsOffset(store.configuration.effectiveLyricsOffset)
        nowPlayingService.start()
        nowPlayingService.observe { [weak self] snapshot in
            self?.latestNowPlaying = snapshot
            self?.nowPlayingViews.forEach { $0.update(snapshot) }
            self?.updateContextValues()
        }
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDockBadges() }
        }
        presentationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.store.configuration.alwaysOccupyTouchBar else { return }
                guard self.touchBar?.isVisible != true else { return }
                self.present()
            }
        }
        refreshDockBadges()
        createSystemTrayItem()
        rebuildTouchBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.store.configuration.alwaysOccupyTouchBar else { return }
            if let systemTrayItem = self.systemTrayItem {
                TBSetControlStripPresence(systemTrayItem.identifier.rawValue, true)
            }
            self.present()
        }
        updateTouchBarStatus()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        dismiss()
        if let systemTrayItem {
            TBSetControlStripPresence(systemTrayItem.identifier.rawValue, false)
            TBSystemTrayRemoveItem(systemTrayItem)
        }
        nowPlayingService.stop()
        badgeTimer?.invalidate()
        badgeTimer = nil
        presentationTimer?.invalidate()
        presentationTimer = nil
    }

    func updateOccupancy() {
        if store.configuration.alwaysOccupyTouchBar {
            present()
        } else {
            dismiss()
        }
    }

    func present() {
        guard let touchBar else { return }
        TBSetSystemModalShowsCloseBoxWhenFrontMost(!store.configuration.hideTouchBarCloseButton)
        TBPresentSystemModalTouchBar(touchBar, nil, true)
        if ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1" {
            NSLog(
                "TouchBar system modal presented isVisible=%@ identifiers=%ld",
                touchBar.isVisible ? "true" : "false",
                touchBar.itemIdentifiers.count
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self,
                      let item = self.touchBar?.item(forIdentifier: Self.actionDashboardIdentifier),
                      let view = item.view else { return }
                NSLog(
                    "TouchBar allocated dashboard frame=%@ superview=%@",
                    NSStringFromRect(view.frame),
                    view.superview.map { NSStringFromRect($0.frame) } ?? "nil"
                )
            }
        }
    }

    func dismiss() {
        guard let touchBar else { return }
        TBDismissSystemModalTouchBar(touchBar)
    }

    private func createSystemTrayItem() {
        guard systemTrayItem == nil else { return }
        let item = NSCustomTouchBarItem(identifier: Self.systemTrayIdentifier)
        let image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "TouchingBar"
        )
        image?.isTemplate = true
        let button = NSButton(
            title: "",
            image: image ?? NSImage(),
            target: self,
            action: #selector(systemTrayButtonPressed)
        )
        button.imagePosition = .imageOnly
        item.view = button
        systemTrayItem = item
        TBSystemTrayAddItem(item)
        TBSetControlStripPresence(item.identifier.rawValue, true)
    }

    @objc private func systemTrayButtonPressed() {
        present()
    }

    private func rebuildTouchBar() {
        guard isStarted else { return }
        guard let activePreset = store.configuration.activePreset else { return }
        let signature = rebuildSignature(for: activePreset)
        guard signature != lastRebuildSignature else { return }
        lastRebuildSignature = signature

        actionConfigurations.removeAll()
        contextViews.removeAll()
        contextConfigurations.removeAll()
        nowPlayingViews.removeAll()
        messageViews.removeAll()
        createdItemIdentifiers.removeAll()

        let identifiers: [NSTouchBarItem.Identifier] = [Self.actionDashboardIdentifier]

        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("app.touchingbar.main")
        touchBar.defaultItemIdentifiers = identifiers
        touchBar.customizationAllowedItemIdentifiers = identifiers
        self.touchBar = touchBar
        expectedItemCount = identifiers.count
        if ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1" {
            NSLog("TouchingBar rebuilt preset=%@ identifiers=%@", activePreset.name, identifiers.map(\.rawValue).joined(separator: ", "))
        }
        updateTouchBarStatus()
        if store.configuration.alwaysOccupyTouchBar {
            present()
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item: NSCustomTouchBarItem?
        if identifier == Self.actionDashboardIdentifier {
            item = makePresetDashboardItem()
        } else {
            item = nil
        }

        if item != nil {
            createdItemIdentifiers.insert(identifier.rawValue)
            updateTouchBarStatus()
        }
        if ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1" {
            let viewDescription: String
            if let view = item?.view {
                viewDescription = "frame=\(NSStringFromRect(view.frame)) intrinsic=\(NSStringFromSize(view.intrinsicContentSize)) class=\(type(of: view))"
            } else {
                viewDescription = "view=nil"
            }
            NSLog(
                "TouchBar makeItem id=%@ created=%@ %@",
                identifier.rawValue,
                item == nil ? "false" : "true",
                viewDescription
            )
        }
        return item
    }

    private func makePresetDashboardItem() -> NSCustomTouchBarItem? {
        guard let preset = store.configuration.activePreset else { return nil }
        let item = NSCustomTouchBarItem(identifier: Self.actionDashboardIdentifier)
        let dashboard = TouchBarDashboardStackView()
        dashboard.frame = NSRect(
            x: 0,
            y: 0,
            width: TouchBarLayoutMetrics.dashboardWidth,
            height: 30
        )
        dashboard.autoresizingMask = [.width, .height]
        dashboard.orientation = .horizontal
        dashboard.alignment = .centerY
        dashboard.spacing = TouchBarLayoutMetrics.dashboardSpacing
        dashboard.distribution = .fillEqually

        switch preset.content {
        case .actions:
            addActionButtons(
                from: preset,
                to: dashboard,
                width: TouchBarLayoutMetrics.actionButtonWidth
            )
        case .nowPlaying:
            dashboard.distribution = .fill
            addActionButtons(
                from: preset,
                to: dashboard,
                width: TouchBarLayoutMetrics.mediaControlWidth
            )
            let nowPlaying = NowPlayingTouchBarView(width: TouchBarLayoutMetrics.lyricsWidth)
            nowPlayingViews.append(nowPlaying)
            dashboard.addArrangedSubview(nowPlaying)
        case .developerContext, .agentContext, .components:
            addContextViews(from: preset, to: dashboard)
        case .unreadMessages:
            let messages = MessagesTouchBarView(width: 970)
            messages.update(badges: badgeCounts, latestMessage: store.runtime.messages.first)
            messageViews.append(messages)
            dashboard.addArrangedSubview(messages)
        }

        if preset.content != .developerContext && preset.content != .agentContext && preset.content != .components {
            let swipe = NSPanGestureRecognizer(target: self, action: #selector(dashboardPan(_:)))
            dashboard.addGestureRecognizer(swipe)
        }
        item.view = dashboard
        item.customizationLabel = "Touch Bar 控制面板"
        item.visibilityPriority = .high

        if ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1" {
            dashboard.frame = NSRect(origin: .zero, size: dashboard.intrinsicContentSize)
            dashboard.layoutSubtreeIfNeeded()
            let childWidths = dashboard.arrangedSubviews.map { Int($0.frame.width.rounded()) }
            NSLog(
                "TouchBar dashboard controls=%ld totalWidth=%d childWidths=%@",
                dashboard.arrangedSubviews.count,
                childWidths.reduce(0, +),
                childWidths.map(String.init).joined(separator: ",")
            )
        }
        return item
    }

    private func addActionButtons(
        from preset: TouchBarPreset,
        to dashboard: NSStackView,
        width: CGFloat
    ) {
        for configuration in preset.items {
            dashboard.addArrangedSubview(
                makeActionButtonView(configuration, preset: preset, width: width)
            )
        }
    }

    private func makeActionButtonView(
        _ configuration: TouchBarItemConfiguration,
        preset: TouchBarPreset,
        width: CGFloat
    ) -> NSView {
        let image = configuration.symbolName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: configuration.label)
        }
        image?.isTemplate = true
        let iconOnly = preset.kind == .systemFunctions && image != nil
        let button = NSButton(
            title: iconOnly ? "" : configuration.label,
            image: image ?? NSImage(),
            target: self,
            action: #selector(actionButtonPressed(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(configuration.id.uuidString)
        button.imagePosition = image == nil
            ? NSControl.ImagePosition.noImage
            : (iconOnly ? .imageOnly : .imageLeading)
        button.bezelColor = NSColor.controlColor
        button.toolTip = configuration.label
        actionConfigurations[button.identifier!.rawValue] = configuration

        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        button.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(greaterThanOrEqualToConstant: width),
            button.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            button.topAnchor.constraint(equalTo: wrapper.topAnchor),
            button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func addContextViews(from preset: TouchBarPreset, to dashboard: NSStackView) {
        let widths = preset.items.map { configuration in
            contextWidth(for: configuration, preset: preset)
        }
        let spacing: CGFloat = 4
        let contentWidth = widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * spacing
        let scrollView = ContextTouchBarScrollView(
            contentWidth: contentWidth,
            spacing: spacing
        )
        scrollView.onVerticalSwipe = { [weak self] direction in
            self?.store.selectAdjacentPreset(offset: direction)
        }

        for (index, configuration) in preset.items.enumerated() {
            let width = widths[index]
            let view = ContextTouchBarView(title: configuration.label, width: width)
            view.update(value: store.runtime.value(for: configuration.contextKey ?? "") ?? "—")
            view.frame = NSRect(x: 0, y: 0, width: width, height: 30)
            contextViews[configuration.id] = view
            contextConfigurations[configuration.id] = configuration
            scrollView.addContentView(view, width: width)
        }
        scrollView.finishLayout()
        dashboard.addArrangedSubview(scrollView)
    }

    private func contextWidth(
        for configuration: TouchBarItemConfiguration,
        preset: TouchBarPreset
    ) -> CGFloat {
        if preset.kind == .developer {
            switch configuration.width {
            case .compact: return 120
            case .regular: return 220
            case .wide: return 360
            }
        }
        if preset.kind == .agents {
            switch configuration.width {
            case .compact: return 120
            case .regular: return 220
            case .wide: return 420
            }
        }
        if preset.kind == .metrics {
            switch configuration.width {
            case .compact: return 120
            case .regular: return 160
            case .wide: return 260
            }
        }
        switch configuration.width {
        case .compact: return 120
        case .regular: return 220
        case .wide: return 360
        }
    }

    @objc private func dashboardPan(_ sender: NSPanGestureRecognizer) {
        switch sender.state {
        case .began:
            didTriggerDashboardSwipe = false
        case .changed:
            guard !didTriggerDashboardSwipe else { return }
            let translation = sender.translation(in: sender.view)
            guard abs(translation.x) >= 34 || abs(translation.y) >= 20 else { return }
            didTriggerDashboardSwipe = true
            if translation.x < 0 || translation.y < 0 {
                store.selectAdjacentPreset(offset: 1)
            } else {
                store.selectAdjacentPreset(offset: -1)
            }
        case .ended, .cancelled, .failed:
            didTriggerDashboardSwipe = false
        default:
            break
        }
    }

    @objc private func actionButtonPressed(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let configuration = actionConfigurations[identifier] else { return }
        actionExecutor.execute(configuration.action, buttonTitle: sender.title)
    }

    private func updateRuntime(_ snapshot: RuntimeContextSnapshot) {
        updateContextValues()
        if let latest = snapshot.messages.first {
            messageViews.forEach { $0.update(badges: badgeCounts, latestMessage: latest) }
        }
    }

    private func updateContextValues() {
        for (id, view) in contextViews {
            guard let configuration = contextConfigurations[id] else { continue }
            view.update(value: contextValue(for: configuration.contextKey ?? "") ?? "—")
        }
    }

    private func contextValue(for key: String) -> String? {
        if let value = store.runtime.value(for: key) {
            return value
        }
        if let value = store.systemMetrics.value(for: key) {
            return value
        }
        switch key {
        case "nowPlaying":
            return latestNowPlaying?.compactTitle
        case "lyric":
            return latestNowPlaying?.currentLyricLine
        case "unreadSummary":
            let total = store.runtime.messages.reduce(0) { $0 + $1.unreadCount }
            return total > 0 ? "\(total) 条未读" : "无未读"
        case "latestMessage":
            guard let message = store.runtime.messages.first else { return "暂无消息" }
            let sender = message.sender.map { "\($0): " } ?? ""
            return "\(message.application) · \(sender)\(message.body)"
        case "messageBadges":
            guard !badgeCounts.isEmpty else { return "无未读" }
            return badgeCounts.map { "\($0.applicationName) \($0.count)" }.joined(separator: " · ")
        default:
            return nil
        }
    }

    private func refreshDockBadges() {
        badgeCounts = badgeReader
            .read(bundleIdentifiers: store.configuration.messages.monitoredApplications)
            .filter { $0.count > 0 }
        messageViews.forEach { $0.update(badges: badgeCounts, latestMessage: store.runtime.messages.first) }
    }

    private func applyWidth(_ width: TouchBarItemWidth, to view: NSView) {
        let value = widthValue(width)
        view.frame = NSRect(x: 0, y: 0, width: value, height: 30)
    }

    private func rebuildSignature(for preset: TouchBarPreset) -> String {
        let items = preset.items.map { item in
            [
                item.id.uuidString,
                item.label,
                item.symbolName ?? "",
                item.width.rawValue,
                item.presentation.rawValue,
                item.contextKey ?? "",
                item.action.kind.rawValue,
                item.action.value ?? "",
                item.action.media?.rawValue ?? "",
                item.action.volume?.rawValue ?? ""
            ].joined(separator: ":")
        }.joined(separator: "|")
        return [
            preset.id.uuidString,
            preset.name,
            preset.kind.rawValue,
            preset.content.rawValue,
            items,
            store.configuration.hideTouchBarCloseButton ? "hide-close" : "show-close"
        ].joined(separator: "::")
    }

    private func widthValue(_ width: TouchBarItemWidth) -> CGFloat {
        switch width {
        case .compact: return 36
        case .regular: return 100
        case .wide: return 230
        }
    }

    private func updateTouchBarStatus() {
        let presetName = store.configuration.activePreset?.name ?? "无配置"
        let created = createdItemIdentifiers.count
        let expected = expectedItemCount
        if created > 0 {
            store.touchBarStatus = "Touch Bar：\(presetName)（\(created)/\(expected)）"
        } else if let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            store.touchBarStatus = "Touch Bar：等待系统请求（\(bundleIdentifier)）"
        } else {
            store.touchBarStatus = "Touch Bar：等待系统请求"
        }
    }
}

private final class TouchBarDashboardStackView: NSStackView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: TouchBarLayoutMetrics.dashboardWidth, height: 30)
    }
}

private final class ContextTouchBarScrollView: NSScrollView {
    var onVerticalSwipe: ((Int) -> Void)?

    private let contentStack = NSStackView()
    private var dragStartPoint = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var didTriggerVerticalSwipe = false

    init(contentWidth: CGFloat, spacing: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: TouchBarLayoutMetrics.dashboardWidth, height: 30))
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .none
        scrollerStyle = .overlay

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = spacing
        contentStack.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 30)
        documentView = contentStack

        let drag = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        addGestureRecognizer(drag)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: TouchBarLayoutMetrics.dashboardWidth, height: 30)
    }

    func addContentView(_ view: NSView, width: CGFloat) {
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        contentStack.addArrangedSubview(view)
    }

    func finishLayout() {
        contentStack.layoutSubtreeIfNeeded()
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
        if ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1" {
            NSLog(
                "TouchBar context scroll viewport=%.0f content=%.0f scrollable=%.0f",
                contentView.bounds.width,
                contentStack.frame.width,
                max(0, contentStack.frame.width - contentView.bounds.width)
            )
        }
    }

    @objc private func handleDrag(_ sender: NSPanGestureRecognizer) {
        let translation = sender.translation(in: self)
        switch sender.state {
        case .began:
            dragStartPoint = translation
            dragStartOrigin = contentView.bounds.origin
            didTriggerVerticalSwipe = false
        case .changed:
            if !didTriggerVerticalSwipe,
               abs(translation.y) > abs(translation.x),
               abs(translation.y) > 18 {
                didTriggerVerticalSwipe = true
                onVerticalSwipe?(translation.y < 0 ? 1 : -1)
                return
            }

            let documentWidth = contentStack.frame.width
            let maximumX = max(0, documentWidth - contentView.bounds.width)
            let proposedX = dragStartOrigin.x - (translation.x - dragStartPoint.x)
            let clampedX = min(maximumX, max(0, proposedX))
            contentView.scroll(to: NSPoint(x: clampedX, y: 0))
            reflectScrolledClipView(contentView)
        case .ended, .cancelled, .failed:
            didTriggerVerticalSwipe = false
        default:
            break
        }
    }
}

private final class ContextTouchBarView: NSView {
    private let valueLabel = NSTextField(labelWithString: "—")
    private let preferredWidth: CGFloat

    init(title: String, width: CGFloat) {
        preferredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1

        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 0, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        valueLabel.font = .monospacedSystemFont(ofSize: 0, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.maximumNumberOfLines = 1

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 30)
    }

    func update(value: String) {
        valueLabel.stringValue = value
    }
}

private final class NowPlayingTouchBarView: NSView {
    private let titleLabel = NSTextField(labelWithString: "未在播放")
    private let lyricsLabel = NSTextField(labelWithString: "")
    private let preferredWidth: CGFloat

    init(width: CGFloat) {
        preferredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1

        titleLabel.font = .systemFont(ofSize: 0, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        lyricsLabel.font = .systemFont(ofSize: 0)
        lyricsLabel.textColor = .secondaryLabelColor
        lyricsLabel.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(lyricsLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 30)
    }

    func update(_ snapshot: NowPlayingSnapshot) {
        titleLabel.stringValue = snapshot.compactTitle
        lyricsLabel.stringValue = snapshot.currentLyricLine ?? snapshot.album
    }
}

private final class MessagesTouchBarView: NSView {
    private let stack = NSStackView()
    private let latestLabel = NSTextField(labelWithString: "暂无未读消息")
    private let preferredWidth: CGFloat

    init(width: CGFloat) {
        preferredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        stack.orientation = .horizontal
        stack.spacing = 7
        stack.alignment = .centerY

        latestLabel.font = .systemFont(ofSize: 0, weight: .medium)
        latestLabel.textColor = .labelColor
        latestLabel.lineBreakMode = .byTruncatingTail

        let outer = NSStackView(views: [stack, latestLabel])
        outer.orientation = .horizontal
        outer.spacing = 10
        outer.alignment = .centerY
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            outer.centerYAnchor.constraint(equalTo: centerYAnchor),
            latestLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 30)
    }

    func update(badges: [ApplicationUnreadCount], latestMessage: MessageContext?) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for badge in badges.prefix(8) {
            stack.addArrangedSubview(makeBadgeView(badge))
        }
        latestLabel.stringValue = latestMessage.map {
            let sender = $0.sender.map { "\($0): " } ?? ""
            return "\($0.application) · \(sender)\($0.body)"
        } ?? "暂无未读消息"
    }

    private func makeBadgeView(_ badge: ApplicationUnreadCount) -> NSView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: badge.bundleIdentifier) {
            imageView.image = NSWorkspace.shared.icon(forFile: url.path)
        }
        let countLabel = NSTextField(labelWithString: "\(badge.count)")
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        countLabel.textColor = .systemRed
        let stack = NSStackView(views: [imageView, countLabel])
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY
        return stack
    }
}
