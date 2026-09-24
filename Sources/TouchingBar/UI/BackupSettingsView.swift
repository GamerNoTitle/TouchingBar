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
                HStack {
                    SecureField("密码", text: $password)
                        .focused($passwordFocused)
                        .onSubmit {
                            passwordFocused = false
                        }
                    Button("清除已保存密码") {
                        store.clearWebDAVPassword()
                        password = ""
                        statusText = "已清除已保存的 WebDAV 密码。"
                    }
                    .buttonStyle(.bordered)
                }
                TextField("远程文件路径", text: webDAVBinding(\.remotePath))
                Text("密码不会在启动时读取。点击上传或从 WebDAV 恢复时，才会从 macOS 钥匙串读取；输入新密码并失焦后会更新钥匙串。")
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
        guard !password.isEmpty else { return }
        store.saveWebDAVPassword(password)
    }

    private func resolvedPassword() throws -> String {
        if !password.isEmpty {
            store.saveWebDAVPassword(password)
            return password
        }
        let storedPassword = store.loadWebDAVPassword()
        guard !storedPassword.isEmpty else {
            throw WebDAVPasswordError.missing
        }
        return storedPassword
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
        isWorking = true
        statusText = "正在上传…"
        Task {
            do {
                let password = try resolvedPassword()
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
        isWorking = true
        statusText = "正在下载…"
        Task {
            do {
                let password = try resolvedPassword()
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

private enum WebDAVPasswordError: LocalizedError {
    case missing

    var errorDescription: String? {
        "请输入 WebDAV 密码，或先在上传前保存密码。"
    }
}
