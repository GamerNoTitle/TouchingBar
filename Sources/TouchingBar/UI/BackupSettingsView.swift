import AppKit
import SwiftUI
import TouchingBarCore

struct BackupSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var password = ""
    @State private var statusText: String?
    @State private var isWorking = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("服务器 URL", text: webDAVBinding(\.serverURL), prompt: Text("https://dav.example.com/remote.php/dav/files/me"))
                TextField("用户名", text: webDAVBinding(\.username))
                SecureField("密码", text: $password)
                    .focused($passwordFocused)
                    .onSubmit {
                        savePassword()
                        passwordFocused = false
                    }
                Text("密码会在输入框失焦后自动保存到 macOS 钥匙串，不会写入配置文件或备份文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("WebDAV")
            }

            Section {
                HStack {
                    Button("上传到 WebDAV") {
                        uploadBackup()
                    }
                    Button("从 WebDAV 恢复") {
                        downloadBackup()
                    }
                }
                .disabled(isWorking)

                HStack {
                    Button("导出备份文件…") {
                        exportBackup()
                    }
                    Button("从备份文件恢复…") {
                        importBackup()
                    }
                }

                if let statusText {
                    Text(statusText)
                        .foregroundStyle(statusText.contains("失败") ? .red : .secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("备份与恢复")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            password = store.webDAVPassword
        }
        .onChange(of: passwordFocused) { focused in
            if !focused {
                savePassword()
            }
        }
        .onDisappear {
            if passwordFocused {
                savePassword()
            }
        }
    }

    private func savePassword() {
        store.saveWebDAVPassword(password)
    }

    private func webDAVBinding(_ keyPath: WritableKeyPath<WebDAVSettings, String>) -> Binding<String> {
        Binding(
            get: { store.configuration.webDAV[keyPath: keyPath] },
            set: { value in
                store.updateConfiguration { $0.webDAV[keyPath: keyPath] = value }
            }
        )
    }

    private func uploadBackup() {
        savePassword()
        isWorking = true
        statusText = "正在上传…"
        Task {
            do {
                let data = try store.backupService.encode(configuration: store.configuration)
                try await store.webDAVClient.upload(data, settings: store.configuration.webDAV, password: password)
                statusText = "上传成功。"
            } catch {
                statusText = "上传失败：\(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func downloadBackup() {
        savePassword()
        isWorking = true
        statusText = "正在下载…"
        Task {
            do {
                let data = try await store.webDAVClient.download(settings: store.configuration.webDAV, password: password)
                let configuration = try store.backupService.decode(data)
                store.configuration = configuration
                store.persist()
                statusText = "恢复成功。Touch Bar 已重新载入配置。"
            } catch {
                statusText = "恢复失败：\(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "导出 TouchingBar 配置"
        panel.nameFieldStringValue = "TouchingBar-backup.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.backupService.encode(configuration: store.configuration).write(to: url, options: .atomic)
            statusText = "已导出到 \(url.path)"
        } catch {
            statusText = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "恢复 TouchingBar 配置"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let configuration = try store.backupService.decode(data)
            store.configuration = configuration
            store.persist()
            statusText = "已从 \(url.path) 恢复配置。"
        } catch {
            statusText = "恢复失败：\(error.localizedDescription)"
        }
    }
}
