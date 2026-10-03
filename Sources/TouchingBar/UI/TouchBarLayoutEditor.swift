import AppKit
import SwiftUI
import TouchingBarCore
import UniformTypeIdentifiers

/// Editing preview; placeholder values are explicitly marked, not live hardware data.
struct TouchBarLayoutEditor: View {
    @EnvironmentObject private var store: AppStore
    let preset: TouchBarPreset
    @Binding var selectedItemID: UUID?
    @State private var draggedID: UUID?
    @State private var dragToken: UUID?
    @State private var resizeStart: CGFloat?
    @State private var draftWidth: CGFloat?

    private var canResize: Bool {
        [.components, .developerContext].contains(preset.content)
    }
    private var visibleItems: [TouchBarItemConfiguration] {
        [.agentContext, .unreadMessages].contains(preset.content) ? [] : preset.items.filter { !$0.isHidden }
    }
    private var totalWidth: CGFloat {
        visibleItems.reduce(0) { $0 + TouchBarLayoutMetrics.itemWidth($1, preset: preset) }
            + CGFloat(max(0, visibleItems.count - 1)) * (canResize ? 4 : 1)
            + (preset.content == .nowPlaying ? TouchBarLayoutMetrics.lyricsWidth : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Touch Bar 布局预览", systemImage: "rectangle.topthird.inset.filled")
                    .font(.headline)
                Spacer()
                Text("\(Int(totalWidth)) / \(Int(TouchBarLayoutMetrics.dashboardWidth)) pt")
                    .font(.caption.monospacedDigit())
            }
            GeometryReader { geometry in
                let scale = min(1, max(0.25, (geometry.size.width - 16) / TouchBarLayoutMetrics.dashboardWidth))
                ScrollView(.horizontal) {
                    HStack(spacing: (canResize ? 4 : 1) * scale) {
                        ForEach(visibleItems) { item in
                            previewItem(item, scale: scale)
                        }
                        if [.agentContext, .unreadMessages].contains(preset.content) {
                            Text("动态内容面板（不支持组件布局编辑）").foregroundStyle(.white).padding()
                        }
                        if preset.content == .nowPlaying {
                            Text("歌曲名称 · 歌词预览")
                                .foregroundStyle(.white)
                                .frame(width: TouchBarLayoutMetrics.lyricsWidth * scale, height: 44)
                        }
                        Color.clear.frame(width: 18, height: 44)
                            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                drop(providers, before: nil)
                            }
                    }
                    .padding(8)
                    .frame(minWidth: TouchBarLayoutMetrics.dashboardWidth * scale, alignment: .leading)
                }
                .frame(width: min(geometry.size.width, TouchBarLayoutMetrics.dashboardWidth * scale + 16))
                .background(.black, in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(height: 70)
            Text(totalWidth > TouchBarLayoutMetrics.dashboardWidth
                 ? "内容超出可视宽度，预览可横向滚动。点击选择 · 拖动排序\(canResize ? " · 拖动右侧蓝色边缘调宽" : "；此内容类型使用固定宽度")"
                 : "点击选择 · 拖动排序\(canResize ? " · 拖动右侧蓝色边缘调宽" : "；此内容类型使用固定宽度")")
                .font(.caption).foregroundStyle(.secondary)
            Text("示意预览：使用真实宽度比例；歌词、网络和宠物内容为示例。隐藏组件不占宽度，按播放状态/数据可用性隐藏的组件仍显示供编辑。")
                .font(.caption2).foregroundStyle(.secondary)
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
        .frame(width: width * scale, height: 44)
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
        } else if item.presentation == .context {
            VStack(alignment: .leading, spacing: 2) {
                if item.showsLabel && !item.dualLineLyrics {
                    Text(item.label.uppercased()).font(.system(size: 8, weight: .semibold))
                }
                Text(sampleValue(item)).font(.system(size: 10, design: .monospaced))
                if item.dualLineLyrics {
                    Text("Translation / 下一句示例").font(.system(size: 8)).foregroundStyle(.gray)
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

    private func previewImage(_ item: TouchBarItemConfiguration) -> NSImage? {
        if let path = item.imagePath { return NSImage(contentsOfFile: NSString(string: path).expandingTildeInPath) }
        if let petID = item.petID, let pet = CodexPetStore.shared.pet(id: petID),
           let sheet = try? CodexPetSpritesheet(pet: pet),
           let frame = sheet.frames(count: 1).first {
            return NSImage(cgImage: frame, size: NSSize(width: pet.frameWidth, height: pet.frameHeight))
        }
        return nil
    }

    private func sampleValue(_ item: TouchBarItemConfiguration) -> String {
        switch item.contextKey {
        case "wifiSSID": return "Home Wi-Fi"
        case "localIP": return "192.168.1.23"
        case "vpnStatus": return "隧道活动（示例）"
        case "networkLatency": return "18 ms"
        case "lyric": return "这是一句较长的歌词，用于查看组件宽度"
        case "nowPlaying": return "歌曲名称 · 歌手"
        case "time": return "12:34:56"
        case "date": return "9月25日 周五"
        case "dateTime": return "9月25日 12:34:56"
        case "networkDownload": return "↓ 2.4 MB/s"
        case "networkUpload": return "↑ 128 KB/s"
        case "path": return "~/Projects/TouchingBar"
        case "branch": return "master"
        default: return "42%"
        }
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
