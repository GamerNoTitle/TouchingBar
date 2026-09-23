import Foundation
import TouchingBarCore
import TouchingBarMediaRemote

struct MediaRemoteNowPlayingSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    var position: TimeInterval
    var isPlaying: Bool
    var bundleIdentifier: String?
}

final class MediaRemoteNowPlayingClient {
    private struct AdapterPayload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let elapsedTimeNow: Double?
        let playing: Bool?
        let playbackRate: Double?
        let bundleIdentifier: String?
    }

    func fetch() -> MediaRemoteNowPlayingSnapshot? {
        if let snapshot = fetchThroughAdapter() {
            return snapshot
        }
        return fetchDirect()
    }

    func send(command: Int) -> Bool {
        if let paths = adapterPaths {
            let result = CommandRunner.run(
                "/usr/bin/perl",
                arguments: [paths.script, paths.framework, "send", "\(command)"]
            )
            if result.exitCode == 0 { return true }
        }
        return TBMediaRemoteSendCommand(Int32(command))
    }

    private func fetchThroughAdapter() -> MediaRemoteNowPlayingSnapshot? {
        guard let paths = adapterPaths else { return nil }
        let result = CommandRunner.run(
            "/usr/bin/perl",
            arguments: [paths.script, paths.framework, "get", "--now", "--no-artwork"]
        )
        guard result.exitCode == 0,
              let data = result.standardOutput.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AdapterPayload.self, from: data),
              let title = payload.title,
              !title.isEmpty else {
            return nil
        }

        let playing = payload.playing ?? ((payload.playbackRate ?? 0) > 0)
        let position: Double
        if playing, let elapsedTimeNow = payload.elapsedTimeNow {
            position = elapsedTimeNow
        } else {
            position = payload.elapsedTime ?? 0
        }

        return MediaRemoteNowPlayingSnapshot(
            title: title,
            artist: payload.artist ?? "",
            album: payload.album ?? "",
            duration: payload.duration,
            position: max(0, position),
            isPlaying: playing,
            bundleIdentifier: payload.bundleIdentifier
        )
    }

    private func fetchDirect() -> MediaRemoteNowPlayingSnapshot? {
        let semaphore = DispatchSemaphore(value: 0)
        var snapshot: MediaRemoteNowPlayingSnapshot?
        TBMediaRemoteFetchNowPlaying { information, bundleIdentifier in
            defer { semaphore.signal() }
            guard let information else { return }
            let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            guard !title.isEmpty else { return }
            let artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            let duration = self.number(information["kMRMediaRemoteNowPlayingInfoDuration"])
            var position = self.number(information["kMRMediaRemoteNowPlayingInfoElapsedTime"]) ?? 0
            let playbackRate = self.number(information["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?? 1
            let isPlaying = playbackRate > 0
            if isPlaying, let timestamp = information["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                position += Date().timeIntervalSince(timestamp) * playbackRate
            }

            snapshot = MediaRemoteNowPlayingSnapshot(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                position: max(0, position),
                isPlaying: isPlaying,
                bundleIdentifier: bundleIdentifier
            )
        }
        _ = semaphore.wait(timeout: .now() + 2.5)
        return snapshot
    }

    private var adapterPaths: (script: String, framework: String)? {
        guard let resourcePath = Bundle.main.resourcePath,
              let frameworksPath = Bundle.main.privateFrameworksPath else { return nil }
        let script = resourcePath + "/mediaremote-adapter.pl"
        let framework = frameworksPath + "/MediaRemoteAdapter.framework"
        guard FileManager.default.fileExists(atPath: script),
              FileManager.default.fileExists(atPath: framework) else { return nil }
        return (script, framework)
    }

    private func number(_ value: Any?) -> TimeInterval? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
