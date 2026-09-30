import Foundation

/// Maps the progress of a timed lyric to its horizontal scroll position.
public enum LyricsScrollTiming {
    public static func fraction(
        progress: Double,
        duration: TimeInterval,
        lead: Double
    ) -> Double {
        let safeDuration = max(0.5, duration)
        let safeLead = min(0.5, max(0, lead))
        // Lyrics switch 0.35 seconds before the next timestamp. Finish the
        // scroll before that switch, reserving the requested fraction to read
        // the end of the line.
        let completion = max(0.01, (1 - 0.35 / safeDuration) * (1 - safeLead))
        return min(1, max(0, progress / completion))
    }
}
