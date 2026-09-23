import AppKit
import Foundation
import TouchingBarCore

struct NowPlayingSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var lyrics: String?
    var player: String?
    var position: TimeInterval

    static let unavailable = NowPlayingSnapshot(
        title: "未在播放",
        artist: "",
        album: "",
        lyrics: nil,
        player: nil,
        position: 0
    )

    var compactTitle: String {
        if !artist.isEmpty {
            return "\(title) · \(artist)"
        }
        return title
    }

    var currentLyricLine: String? {
        guard let lyrics, !lyrics.isEmpty else { return nil }
        if let timedLine = timedLyrics(from: lyrics).last(where: { $0.time <= position + 0.35 }) {
            return timedLine.text
        }
        return lyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("[") })
    }

    private func timedLyrics(from lyrics: String) -> [(time: TimeInterval, text: String)] {
        lyrics.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("["),
                  let closing = trimmed.firstIndex(of: "]") else { return nil }
            let timestamp = trimmed[trimmed.index(after: trimmed.startIndex)..<closing]
            let text = trimmed[trimmed.index(after: closing)...].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let parts = timestamp.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (minutes * 60 + seconds, text)
        }
    }
}

final class NowPlayingService {
    private let queue = DispatchQueue(label: "app.touchingbar.now-playing", qos: .utility)
    private let mediaRemoteClient = MediaRemoteNowPlayingClient()
    private let netEaseLyricsProvider = NetEaseLyricsProvider()
    private var timer: DispatchSourceTimer?
    private var lastSnapshot: NowPlayingSnapshot = .unavailable
    private var handlers: [(NowPlayingSnapshot) -> Void] = []

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let snapshot = self.readSnapshot()
            guard snapshot != self.lastSnapshot else { return }
            self.lastSnapshot = snapshot
            if ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1" {
                NSLog(
                    "NowPlaying player=%@ title=%@ artist=%@ position=%.2f lyrics=%ld",
                    snapshot.player ?? "none",
                    snapshot.title,
                    snapshot.artist,
                    snapshot.position,
                    snapshot.lyrics?.count ?? 0
                )
                NSLog("NowPlaying lyric=%@", snapshot.currentLyricLine ?? "nil")
            }
            DispatchQueue.main.async {
                self.handlers.forEach { $0(snapshot) }
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    @discardableResult
    func observe(_ handler: @escaping (NowPlayingSnapshot) -> Void) -> UUID {
        let token = UUID()
        handlers.append { snapshot in
            handler(snapshot)
        }
        handler(lastSnapshot)
        return token
    }

    func removeObserver(_ token: UUID) {
        // Tokens are intentionally simple for now; handlers remain valid for
        // the lifetime of a Touch Bar item, which is the only consumer.
        _ = token
    }

    private func readSnapshot() -> NowPlayingSnapshot {
        if let remote = mediaRemoteClient.fetch(),
           remote.bundleIdentifier == "com.netease.163music" {
            let lyrics = netEaseLyricsProvider.lyrics(
                title: remote.title,
                artist: remote.artist,
                album: remote.album,
                duration: remote.duration
            )
            return NowPlayingSnapshot(
                title: remote.title,
                artist: remote.artist,
                album: remote.album,
                lyrics: lyrics,
                player: "网易云音乐",
                position: remote.position
            )
        }

        let runningNames = Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName))
        if runningNames.contains("Spotify") {
            return readSpotify()
        }
        if runningNames.contains("Music") {
            return readMusic()
        }
        return .unavailable
    }

    private func readSpotify() -> NowPlayingSnapshot {
        let script = #"""
        tell application "Spotify"
            if player state is stopped then return ""
            set delimiter to "|||"
            return name of current track & delimiter & artist of current track & delimiter & album of current track & delimiter & (player position as text)
        end tell
        """#
        return parse(script: script, player: "Spotify", hasLyrics: false)
    }

    private func readMusic() -> NowPlayingSnapshot {
        let script = #"""
        tell application "Music"
            if player state is stopped then return ""
            set delimiter to "|||"
            set lyricText to ""
            try
                set lyricText to lyrics of current track
            end try
            return name of current track & delimiter & artist of current track & delimiter & album of current track & delimiter & lyricText & delimiter & (player position as text)
        end tell
        """#
        return parse(script: script, player: "Music", hasLyrics: true)
    }

    private func parse(script: String, player: String, hasLyrics: Bool) -> NowPlayingSnapshot {
        let result = runAppleScript(script)
        let value = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .unavailable }
        let components = value.components(separatedBy: "|||")
        guard components.count >= 3 else { return .unavailable }
        let lyrics = hasLyrics && components.count > 3 ? components[3] : nil
        let positionIndex = hasLyrics ? 4 : 3
        let position = components.indices.contains(positionIndex)
            ? Double(components[positionIndex].replacingOccurrences(of: ",", with: ".")) ?? 0
            : 0
        return NowPlayingSnapshot(
            title: components[0],
            artist: components[1],
            album: components[2],
            lyrics: lyrics,
            player: player,
            position: position
        )
    }

    private func runAppleScript(_ script: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        guard process.terminationStatus == 0 else { return "" }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
