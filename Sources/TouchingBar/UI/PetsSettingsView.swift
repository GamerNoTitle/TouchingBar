import AppKit
import SwiftUI
import TouchingBarCore
import UniformTypeIdentifiers

struct PetsSettingsView: View {
    @State private var installedPets: [CodexPet] = []
    @State private var externalPets: [CodexPet] = []
    @State private var errorMessage: String?

    private let petStore = CodexPetStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("宠物")
                        .font(.title2.bold())
                    Text("安装 Codex 宠物包后，可以在自定义 Touch Bar 配置中添加「宠物」组件。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("从文件夹安装…") {
                    installFromFolder()
                }
                Button("扫描 Codex Pets") {
                    refresh()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            List {
                Section("已安装") {
                    if installedPets.isEmpty {
                        Text("还没有安装宠物")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(installedPets) { pet in
                            PetSettingsRow(pet: pet) {
                                remove(pet)
                            }
                        }
                    }
                }

                Section {
                    if externalPets.isEmpty {
                        Text("未发现 ~/.codex/pets 中的宠物")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(externalPets) { pet in
                            HStack(spacing: 12) {
                                PetPreview(pet: pet)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pet.displayName)
                                    Text(pet.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if installedPets.contains(where: { $0.id == pet.id }) {
                                    Text("已安装")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("安装") {
                                        install(pet)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text("发现 Codex Pets")
                }
            }
            .listStyle(.inset)

            Text("Codex 宠物使用 `pet.json` + 精灵图。官方格式是 8×9 格、每格 192×208；兼容带方向帧的 8×11 格式。安装会复制到 TouchingBar 的 Application Support/Pets。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(4)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        installedPets = petStore.installedPets()
        externalPets = petStore.externalPets().filter { external in
            !installedPets.contains(where: { $0.id == external.id })
        }
        errorMessage = nil
    }

    private func install(_ pet: CodexPet) {
        do {
            _ = try petStore.install(pet, replacing: true)
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installFromFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 宠物目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "安装宠物"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try petStore.install(from: url, replacing: true)
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ pet: CodexPet) {
        do {
            try petStore.remove(petID: pet.id)
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PetSettingsRow: View {
    let pet: CodexPet
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PetPreview(pet: pet)
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.displayName)
                HStack(spacing: 6) {
                    Text(pet.id)
                    if let version = pet.spriteVersionNumber {
                        Text("v\(version)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("删除", role: .destructive, action: remove)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 3)
    }
}

private struct PetPreview: View {
    let pet: CodexPet

    var body: some View {
        Group {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }

    private var previewImage: NSImage? {
        guard let spritesheet = try? CodexPetSpritesheet(pet: pet),
              let frame = spritesheet.frames(count: 1).first else {
            return nil
        }
        return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }
}
