import AppKit
import SwiftUI
import TouchingBarCore
import UniformTypeIdentifiers

/// Editing preview backed by existing runtime collectors; playback visibility is simulated.
struct TouchBarLayoutEditor: View {
    @EnvironmentObject private var store: AppStore
    let preset: TouchBarPreset
    @Binding var selectedItemID: UUID?
    @State private var draggedID: UUID?
    @State private var dragToken: UUID?
    @State private var resizeStart: CGFloat?
    @State private var draftWidth: CGFloat?
    @State private var previewIsPlaying = true

    private var canResize: Bool {
        [.components, .developerContext].contains(preset.content)
    }
    private var showsNowPlayingPanel: Bool {
        preset.content == .nowPlaying && (!preset.effectiveHideWhenNotPlaying || previewIsPlaying)
    }
    private var visibleItems: [TouchBarItemConfiguration] {
        if [.agentContext, .unreadMessages].contains(preset.content) { return [] }
        if preset.content == .nowPlaying && !showsNowPlayingPanel { return [] }
        return preset.items.filter { item in
            if item.isHidden || (item.hideWhenPlaying && previewIsPlaying) { return false }
            let musicRelated = item.action.kind == .media || ["nowPlaying", "lyric"].contains(item.contextKey ?? "")
            return !(item.hideWhenNotPlaying && musicRelated && !previewIsPlaying)
        }
    }
    private var totalWidth: CGFloat {
        visibleItems.reduce(0) { $0 + TouchBarLayoutMetrics.itemWidth($1, preset: preset) }
            + CGFloat(max(0, visibleItems.count - 1)) * (canResize ? 4 : 1)
            + (showsNowPlayingPanel ? TouchBarLayoutMetrics.lyricsWidth : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Touch Bar 布局预览", systemImage: "rectangle.topthird.inset.filled")
                    .font(.headline)
                Spacer()
                Toggle("播放中", isOn: $previewIsPlaying)
                    .toggleStyle(.switch)
                    .fixedSize()
                    .help("仅模拟预览中的播放状态，不控制真实播放器")
                Text("\(Int(totalWidth)) / \(Int(TouchBarLayoutMetrics.dashboardWidth)) pt")
                    .font(.caption.monospacedDigit())
            }
            GeometryReader { geometry in
                let scale: CGFloat = 2
                let contentWidth = max(TouchBarLayoutMetrics.displayWidth, totalWidth + 18)
                ScrollView(.horizontal) {
                    HStack(spacing: canResize ? 4 : 1) {
                        ForEach(visibleItems) { item in
                            previewItem(item, scale: scale)
                        }
                        if [.agentContext, .unreadMessages].contains(preset.content) {
                            Text("动态内容面板").foregroundStyle(.white).font(.system(size: 10))
                        }
                        if showsNowPlayingPanel {
                            Text("\(store.nowPlaying.compactTitle) · \(store.nowPlaying.currentLyricLine ?? "—")")
                                .foregroundStyle(.white).font(.system(size: 10))
                                .frame(width: TouchBarLayoutMetrics.lyricsWidth, height: 30)
                        }
                        Color.clear.frame(width: 18, height: 30)
                            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                drop(providers, before: nil)
                            }
                    }
                    .frame(width: contentWidth, height: TouchBarLayoutMetrics.displayHeight, alignment: .leading)
                    .background(.black)
                    .overlay(alignment: .leading) {
                        PhysicalDisplayBoundary()
                            .stroke(.white, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: 1, height: TouchBarLayoutMetrics.displayHeight)
                            .frame(width: 10)
                            .contentShape(Rectangle())
                            .help("位于此虚线右侧的部分将超出 touchbar 显示区域")
                            .offset(x: TouchBarLayoutMetrics.dashboardWidth - 5)
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: contentWidth * scale,
                           height: TouchBarLayoutMetrics.displayHeight * scale, alignment: .topLeading)
                }
                .frame(width: geometry.size.width, height: 80)
                .background(.black, in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 80)
            Text(totalWidth > TouchBarLayoutMetrics.dashboardWidth
                 ? "内容超出可视宽度，预览可横向滚动。点击选择 · 拖动排序\(canResize ? " · 拖动右侧蓝色边缘调宽" : "；此内容类型使用固定宽度")"
                 : "点击选择 · 拖动排序\(canResize ? " · 拖动右侧蓝色边缘调宽" : "；此内容类型使用固定宽度")")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("2 倍等比编辑预览，可横向滚动；白色纵向虚线标记 Touch Bar 显示边界。使用已有采集服务的实时数据，未取得的数据显示 —；播放开关仅模拟显示条件，不控制播放器。")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func previewItem(_ item: TouchBarItemConfiguration, scale: CGFloat) -> some View {
        let selected = selectedItemID == item.id
        let width = selected ? (draftWidth ?? TouchBarLayoutMetrics.itemWidth(item, preset: preset)) : TouchBarLayoutMetrics.itemWidth(item, preset: preset)
        return ZStack(alignment: .trailing) {
            tile(item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { selectedItemID = item.id }
                .onDrag {
                    draggedID = item.id
                    let token = UUID()
                    dragToken = token
                    return NSItemProvider(object: "touchingbar-layout:\(token.uuidString):\(item.id.uuidString)" as NSString)
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in drop(providers, before: item.id) }
            if selected && canResize {
                Capsule().fill(.blue).frame(width: 5, height: 28)
                    .padding(.trailing, 2)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if resizeStart == nil { resizeStart = TouchBarLayoutMetrics.itemWidth(item, preset: preset) }
                            draftWidth = max(40, min(1200, (resizeStart ?? width) + value.translation.width / scale))
                        }
                        .onEnded { _ in
                            if let draftWidth {
                                var updated = item
                                updated.width = .custom
                                updated.customWidth = Double(draftWidth.rounded())
                                store.updateItem(presetID: preset.id, item: updated)
                            }
                            resizeStart = nil
                            draftWidth = nil
                        })
            }
        }
        .frame(width: width, height: TouchBarLayoutMetrics.displayHeight)
        .background(selected ? Color.blue.opacity(0.22) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.blue : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
        .help("\(item.label) · \(Int(width)) pt")
        .onChange(of: selectedItemID) { _ in resizeStart = nil; draftWidth = nil }
    }

    @ViewBuilder
    private func tile(_ item: TouchBarItemConfiguration) -> some View {
        if item.presentation == .image {
            if let image = previewImage(item) {
                Image(nsImage: image).resizable().scaledToFit().padding(3)
            } else {
                Image(systemName: "pawprint.fill").foregroundStyle(.pink).font(.title3)
            }
        } else if item.presentation == .context && isChartMetric(item)
                    && (store.systemMetrics.history(for: item.contextKey ?? "")?.count ?? 0) >= 2 {
            VStack(alignment: .leading, spacing: 2) {
                if item.showsLabel {
                    Text("\(item.label)  \(liveValue(item))")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                PreviewSparkline(values: store.systemMetrics.history(for: item.contextKey ?? "") ?? [],
                                 range: store.systemMetrics.chartRange(for: item.contextKey ?? "", history: store.systemMetrics.history(for: item.contextKey ?? "") ?? []))
                    .stroke(chartColor(item), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .frame(height: 12)
            }
            .padding(.horizontal, 4)
        } else if item.presentation == .context {
            VStack(alignment: .leading, spacing: 2) {
                if item.showsLabel && !item.dualLineLyrics {
                    Text(item.label.uppercased()).font(.system(size: 8, weight: .semibold))
                }
                Text(liveValue(item)).font(.system(size: 10, design: .monospaced))
                if item.dualLineLyrics {
                    Text(store.nowPlaying.currentDualLineLyricPair?.secondary ?? "—").font(.system(size: 8)).foregroundStyle(.gray)
                }
            }
            .foregroundStyle(.white).lineLimit(1).padding(.horizontal, 4)
        } else {
            HStack(spacing: 3) {
                if let symbol = item.symbolName { Image(systemName: symbol) }
                if item.symbolName == nil || preset.kind == .functionKeys { Text(item.label) }
            }
            .font(.system(size: 10)).foregroundStyle(.white).lineLimit(1).padding(3)
        }
    }

    private func isChartMetric(_ item: TouchBarItemConfiguration) -> Bool {
        ["cpu", "gpu", "memory", "disk", "cpuTemperature", "fanRPM",
         "networkDownload", "networkUpload", "battery", "batteryPower", "batteryTime"]
            .contains(item.contextKey ?? "")
    }

    private func chartColor(_ item: TouchBarItemConfiguration) -> Color {
        if let hex = item.chartColorHex, let color = NSColor(hexRGB: hex) { return Color(nsColor: color) }
        switch item.contextKey {
        case "cpu", "battery": return Color(nsColor: .systemGreen)
        case "gpu": return Color(nsColor: .systemPurple)
        case "memory", "batteryTime": return Color(nsColor: .systemBlue)
        case "disk": return Color(nsColor: .systemTeal)
        case "cpuTemperature", "batteryPower": return Color(nsColor: .systemOrange)
        case "fanRPM": return Color(nsColor: .systemPink)
        case "networkDownload": return Color(nsColor: .systemCyan)
        case "networkUpload": return Color(nsColor: .systemYellow)
        default: return .accentColor
        }
    }

    private func previewImage(_ item: TouchBarItemConfiguration) -> NSImage? {
        if let path = item.imagePath { return NSImage(contentsOfFile: NSString(string: path).expandingTildeInPath) }
        if let petID = item.petID, let pet = CodexPetStore.shared.pet(id: petID),
           let sheet = try? CodexPetSpritesheet(pet: pet),
           let frame = sheet.frames(count: 1).first {
            return NSImage(cgImage: frame, size: NSSize(width: pet.frameWidth, height: pet.frameHeight))
        }
        return nil
    }

    private func liveValue(_ item: TouchBarItemConfiguration) -> String {
        let key = item.contextKey ?? ""
        if NetworkStatusSnapshot.contextKeys.contains(key) {
            return store.networkStatus.value(for: key, host: item.networkProbeHost) ?? "—"
        }
        if let value = store.runtime.value(for: key) { return value }
        if let value = store.systemMetrics.value(for: key) { return value }
        switch key {
        case "nowPlaying": return store.nowPlaying.compactTitle
        case "lyric":
            return item.dualLineLyrics
                ? store.nowPlaying.currentDualLineLyricPair?.original ?? "—"
                : store.nowPlaying.currentLyricLine ?? "—"
        case "date": return formattedDate(item.dateFormat, fallback: "M月d日 EEE")
        case "time": return formattedDate(item.timeFormat, fallback: "HH:mm:ss")
        case "dateTime":
            return "\(formattedDate(item.dateFormat, fallback: "M月d日 EEE")) \(formattedDate(item.timeFormat, fallback: "HH:mm:ss"))"
        default: return "—"
        }
    }

    private func formattedDate(_ pattern: String?, fallback: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = pattern?.isEmpty == false ? pattern : fallback
        return formatter.string(from: Date())
    }

    private func drop(_ providers: [NSItemProvider], before target: UUID?) -> Bool {
        guard let draggedID, let dragToken,
              let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        let expected = "touchingbar-layout:\(dragToken.uuidString):\(draggedID.uuidString)"
        provider.loadObject(ofClass: NSString.self) { object, _ in
            let payload = object as? String
            DispatchQueue.main.async {
                guard payload == expected, self.dragToken == dragToken,
                      var updated = store.configuration.presets.first(where: { $0.id == preset.id }),
                      updated.items.contains(where: { $0.id == draggedID }) else { return }
                updated.items = TouchBarLayoutMetrics.movingItem(in: updated.items, id: draggedID, before: target)
                store.replacePreset(updated)
                selectedItemID = draggedID
                self.draggedID = nil
                self.dragToken = nil
            }
        }
        return true
    }
}

private struct PhysicalDisplayBoundary: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Uses the same collected history and value range as the physical renderer.
private struct PreviewSparkline: Shape {
    let values: [Double]
    let range: ClosedRange<Double>?

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2, let range else { return Path() }
        let span = max(0.0001, range.upperBound - range.lowerBound)
        var path = Path()
        for (index, value) in values.enumerated() {
            let normalized = CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                                y: rect.maxY - normalized * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
