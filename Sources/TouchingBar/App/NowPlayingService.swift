import AppKit
import Foundation
import TouchingBarCore

struct NowPlayingSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var lyrics: String?
    var lyricDocument: LyricsDocument? = nil
    var player: String?
    var position: TimeInterval
    var lyricsOffset: TimeInterval = 0

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

    var currentLyricPair: (original: String, translation: String?)? {
        let effectivePosition = position - lyricsOffset
        if let lyricDocument, !lyricDocument.lines.isEmpty {
            if let line = lyricDocument.lines.last(where: { $0.time <= effectivePosition + 0.35 }) {
                return (line.text, line.translation)
            }
            if let first = lyricDocument.lines.first {
                return (first.text, first.translation)
            }
        }
        guard let lyrics, !lyrics.isEmpty else { return nil }
        if let timedLine = timedLyrics(from: lyrics).last(where: { $0.time <= effectivePosition + 0.35 }) {
            return (timedLine.text, nil)
        }
        guard let plain = lyrics
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("[") }) else {
            return nil
        }
        return (plain, nil)
    }

    var currentDualLineLyricPair: (original: String, secondary: String?)? {
        let effectivePosition = position - lyricsOffset
        if let lyricDocument, !lyricDocument.lines.isEmpty {
            let lines = lyricDocument.lines
            guard let index = lines.lastIndex(where: { $0.time <= effectivePosition + 0.35 })
                ?? lines.indices.first else {
                return nil
            }
            let line = lines[index]
            if let translation = nonEmpty(line.translation) {
                return (line.text, translation)
            }
            let next = index + 1 < lines.count ? nonEmpty(lines[index + 1].text) : nil
            return (line.text, next)
        }

        guard let lyrics, !lyrics.isEmpty else { return nil }
        let timedLines = timedLyrics(from: lyrics)
        if let index = timedLines.lastIndex(where: { $0.time <= effectivePosition + 0.35 })
            ?? timedLines.indices.first {
            let next = index + 1 < timedLines.count ? nonEmpty(timedLines[index + 1].text) : nil
            return (timedLines[index].text, next)
        }

        let plainLines = lyrics
            .components(separatedBy: .newlines)
            .compactMap { nonEmpty($0) }
            .filter { !$0.hasPrefix("[") }
        guard let first = plainLines.first else { return nil }
        return (first, plainLines.dropFirst().first)
    }

    var currentLyricLine: String? {
        guard let pair = currentLyricPair else { return nil }
        return [pair.original, pair.translation]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var currentLyricProgress: Double? {
        let effectivePosition = position - lyricsOffset
        if let lyricDocument, !lyricDocument.lines.isEmpty {
            let lines = lyricDocument.lines
            guard let index = lines.lastIndex(where: { $0.time <= effectivePosition + 0.35 }) else {
                return nil
            }
            let start = lines[index].time
            let end = index + 1 < lines.count ? lines[index + 1].time : start + 4
            return min(1, max(0, (effectivePosition - start) / max(0.5, end - start)))
        }
        guard let lyrics, !lyrics.isEmpty else { return nil }
        let lines = timedLyrics(from: lyrics)
        guard let index = lines.lastIndex(where: { $0.time <= effectivePosition + 0.35 }) else {
            return nil
        }
        let start = lines[index].time
        let end = index + 1 < lines.count ? lines[index + 1].time : start + 4
        return min(1, max(0, (effectivePosition - start) / max(0.5, end - start)))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    private var lyricsOffset: TimeInterval = 0

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.pollOnce()
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

    func setLyricsOffset(_ offset: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lyricsOffset = max(-10, min(10, offset))
            self.pollOnce()
        }
    }

    private func pollOnce() {
        var snapshot = self.readSnapshot()
        snapshot.lyricsOffset = lyricsOffset
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        if ProcessInfo.processInfo.environment["TOUCHINGBAR_DEBUG"] == "1" {
            NSLog(
                "NowPlaying player=%@ title=%@ artist=%@ position=%.2f offset=%.2f lyrics=%ld",
                snapshot.player ?? "none",
                snapshot.title,
                snapshot.artist,
                snapshot.position,
                snapshot.lyricsOffset,
                snapshot.lyrics?.count ?? 0
            )
            NSLog("NowPlaying lyric=%@", snapshot.currentLyricLine ?? "nil")
        }
        DispatchQueue.main.async { [weak self] in
            self?.handlers.forEach { $0(snapshot) }
        }
    }

    private func readSnapshot() -> NowPlayingSnapshot {
        if let remote = mediaRemoteClient.fetch(),
           remote.bundleIdentifier == "com.netease.163music" {
            let lyricDocument = netEaseLyricsProvider.lyricDocument(
                title: remote.title,
                artist: remote.artist,
                album: remote.album,
                duration: remote.duration
            )
            return NowPlayingSnapshot(
                title: remote.title,
                artist: remote.artist,
                album: remote.album,
                lyrics: lyricDocument?.text,
                lyricDocument: lyricDocument,
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
