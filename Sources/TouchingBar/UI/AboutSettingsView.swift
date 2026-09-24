import AppKit
import SwiftUI

struct AboutSettingsView: View {
    private let repositoryURL = URL(string: "https://github.com/GamerNoTitle/TouchingBar")!

    var body: some View {
        VStack(spacing: 18) {
            if let applicationIcon = NSApp.applicationIconImage {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
            }

            VStack(spacing: 6) {
                Text("TouchingBar")
                    .font(.system(size: 26, weight: .bold))
                Text(versionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }

            Text("把 Touch Bar 变成可以自由组合的小工具面板。")
                .font(.body)
                .foregroundStyle(.secondary)

            Link(destination: repositoryURL) {
                Label("GitHub：GamerNoTitle/TouchingBar", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let shortVersion, let buildNumber else {
            return "开发版本"
        }
        return "版本 \(shortVersion)（Build \(buildNumber)）"
    }
}
