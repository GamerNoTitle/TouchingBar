import Foundation

public struct LyricsDocumentLine: Equatable, Sendable {
    public let time: TimeInterval
    public let text: String
    public let translation: String?

    public init(time: TimeInterval, text: String, translation: String? = nil) {
        self.time = time
        self.text = text
        self.translation = translation
    }

    public var mergedText: String {
        [text, translation]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

public struct LyricsDocument: Equatable, Sendable {
    public let lines: [LyricsDocumentLine]

    public init(lines: [LyricsDocumentLine]) {
        self.lines = lines
    }

    public var text: String {
        lines.map { line in
            let minutes = Int(line.time) / 60
            let seconds = line.time.truncatingRemainder(dividingBy: 60)
            let secondsText = String(
                format: "%.2f",
                locale: Locale(identifier: "en_US_POSIX"),
                seconds
            )
            let paddedSeconds = seconds < 10 ? "0" + secondsText : secondsText
            return String(format: "[%02d:%@]%@", minutes, paddedSeconds, line.mergedText)
        }
        .joined(separator: "\n")
    }
}

public final class NetEaseLyricsProvider: @unchecked Sendable {
    private struct Candidate {
        var id: Int
        var title: String
        var artists: [String]
        var album: String?
        var duration: TimeInterval?
    }

    private let lock = NSLock()
    private var cache: [String: LyricsDocument] = [:]
    private var failedUntil: [String: Date] = [:]
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.httpAdditionalHeaders = [
            "Referer": "https://music.163.com/",
            "User-Agent": "Mozilla/5.0 TouchingBar/1.0"
        ]
        session = URLSession(configuration: configuration)
    }

    public func lyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?
    ) -> String? {
        lyricDocument(title: title, artist: artist, album: album, duration: duration)?.text
    }

    public func lyricDocument(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?
    ) -> LyricsDocument? {
        let key = [title.lowercased(), artist.lowercased(), album.lowercased()].joined(separator: "|")
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        if let retryAt = failedUntil[key], retryAt > Date() {
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard let candidate = search(title: title, artist: artist, album: album, duration: duration),
              let fetched = fetchLyrics(songID: candidate.id) else {
            lock.lock()
            failedUntil[key] = Date().addingTimeInterval(30)
            lock.unlock()
            return nil
        }

        lock.lock()
        cache[key] = fetched
        if cache.count > 80 {
            cache = Dictionary(uniqueKeysWithValues: cache.suffix(40))
        }
        lock.unlock()
        return fetched
    }

    private func search(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?
    ) -> Candidate? {
        let query = artist.isEmpty ? title : "\(artist) \(title)"
        guard var components = URLComponents(string: "https://music.163.com/api/search/get") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url,
              let data = request(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else {
            return nil
        }

        let candidates = songs.compactMap { song -> Candidate? in
            guard let id = song["id"] as? Int,
                  let name = song["name"] as? String else { return nil }
            let artistNames = (song["artists"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
            let albumName = (song["album"] as? [String: Any])?["name"] as? String
            let durationMilliseconds = song["duration"] as? Double ?? (song["duration"] as? NSNumber)?.doubleValue
            return Candidate(
                id: id,
                title: name,
                artists: artistNames,
                album: albumName,
                duration: durationMilliseconds.map { $0 / 1000 }
            )
        }

        return candidates.max { lhs, rhs in
            score(lhs, title: title, artist: artist, duration: duration)
                < score(rhs, title: title, artist: artist, duration: duration)
        }
    }

    private func score(
        _ candidate: Candidate,
        title: String,
        artist: String,
        duration: TimeInterval?
    ) -> Double {
        let candidateTitle = normalize(candidate.title)
        let wantedTitle = normalize(title)
        var value = candidateTitle == wantedTitle ? 100 : similarity(candidateTitle, wantedTitle) * 60

        let wantedArtist = normalize(artist)
        if !wantedArtist.isEmpty {
            let artistMatch = candidate.artists.map(normalize).contains { candidateArtist in
                candidateArtist == wantedArtist
                    || candidateArtist.contains(wantedArtist)
                    || wantedArtist.contains(candidateArtist)
            }
            value += artistMatch ? 35 : -15
        }

        if let duration, let candidateDuration = candidate.duration {
            let difference = abs(duration - candidateDuration)
            value += max(-20, 15 - difference)
        }
        return value
    }

    private func fetchLyrics(songID: Int) -> LyricsDocument? {
        guard let url = URL(string: "https://music.163.com/api/song/lyric?id=\(songID)&lv=-1&kv=-1&tv=-1&rv=-1"),
              let data = request(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if root["pureMusic"] as? Bool == true { return nil }
        guard let lyric = ((root["lrc"] as? [String: Any])?["lyric"] as? String)
            ?? (root["lyric"] as? String),
              !lyric.isEmpty else { return nil }
        let translation = ((root["tlyric"] as? [String: Any])?["lyric"] as? String)
            ?? ((root["romalrc"] as? [String: Any])?["lyric"] as? String)
        return makeDocument(lyric: lyric, translation: translation)
    }

    private func makeDocument(lyric: String, translation: String?) -> LyricsDocument {
        let translations = parseLRC(translation ?? "")
        let lines = lyric.components(separatedBy: .newlines).compactMap { line -> LyricsDocumentLine? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = parseTimestampedLine(trimmed) else { return nil }
            guard !isCreditLine(parsed.text) else { return nil }
            let translated = translations[parsed.time]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LyricsDocumentLine(
                time: parsed.time,
                text: parsed.text,
                translation: translated?.isEmpty == true ? nil : translated
            )
        }
        .sorted { $0.time < $1.time }
        return LyricsDocument(lines: lines)
    }

    private func parseLRC(_ text: String) -> [TimeInterval: String] {
        var result: [TimeInterval: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let parsed = parseTimestampedLine(line) else { continue }
            result[parsed.time] = parsed.text
        }
        return result
    }

    private func parseTimestampedLine(_ line: String) -> (time: TimeInterval, text: String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let timestamp = line[line.index(after: line.startIndex)..<close]
        let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let components = timestamp.split(separator: ":")
        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]) else { return nil }
        return (minutes * 60 + seconds, text)
    }

    private func isCreditLine(_ text: String) -> Bool {
        let separators = ["作词", "作曲", "编曲", "制作人", "和声编写", "吉他", "贝斯", "鼓", "录音", "混音", "母带", "监制"]
        return separators.contains { text.contains($0) }
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let lhsSet = Set(lhs)
        let rhsSet = Set(rhs)
        let intersection = lhsSet.intersection(rhsSet).count
        let union = lhsSet.union(rhsSet).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func request(_ url: URL) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        var request = URLRequest(url: url)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return }
            result = data
        }.resume()
        _ = semaphore.wait(timeout: .now() + 6)
        return result
    }
}
