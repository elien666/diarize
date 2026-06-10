import Foundation

/// Lock-free live level meter for the active recording, one slot per source.
///
/// Audio callbacks call `feed(_:channel:)` from real-time threads; the UI polls
/// `level(_:)` at its own cadence (a TimelineView tick). There is intentionally
/// no `@Published` / Combine here: republishing a level 20×/s through the shared
/// view model would re-render the whole NavigationSplitView (the same trap the
/// elapsed-time TimelineView avoids). Instead each channel keeps an atomic
/// `Double` that the meter writes and the UI reads — at most a torn read of a
/// smoothed value, which is harmless for a VU display.
public final class AudioLevelMeter: @unchecked Sendable {
    public enum Channel: Int, Sendable, CaseIterable {
        case mic = 0
        case system = 1
    }

    /// Smoothed, normalized level per channel in 0...1 (perceptual, dB-mapped).
    private let levels: UnsafeMutablePointer<Double>
    /// Wall-clock (timeIntervalSinceReferenceDate) of the last fed buffer per
    /// channel; lets the UI tell "silent" apart from "no longer capturing".
    private let lastFeed: UnsafeMutablePointer<Double>

    /// Attack/release smoothing. Fast attack so peaks register, slower release
    /// so the bar decays visibly instead of flickering.
    private let attack = 0.5
    private let release = 0.15
    /// Floor of the dB→0...1 mapping. Anything quieter than this maps to 0.
    private let floorDB = -60.0

    public init() {
        levels = .allocate(capacity: Channel.allCases.count)
        lastFeed = .allocate(capacity: Channel.allCases.count)
        levels.initialize(repeating: 0, count: Channel.allCases.count)
        lastFeed.initialize(repeating: 0, count: Channel.allCases.count)
    }

    deinit {
        levels.deallocate()
        lastFeed.deallocate()
    }

    /// Feed a buffer of mono Float samples for one channel. Computes RMS, maps to
    /// a perceptual 0...1 level and smooths it. Called from the audio thread.
    public func feed(_ samples: [Float], channel: Channel) {
        guard !samples.isEmpty else { return }
        var sumSquares: Double = 0
        for s in samples {
            let v = Double(s)
            sumSquares += v * v
        }
        let rms = (sumSquares / Double(samples.count)).squareRoot()
        let db = rms > 0 ? 20 * log10(rms) : floorDB
        let norm = max(0, min(1, (db - floorDB) / -floorDB))

        let i = channel.rawValue
        let prev = levels[i]
        let coeff = norm > prev ? attack : release
        levels[i] = prev + (norm - prev) * coeff
        lastFeed[i] = Date.timeIntervalSinceReferenceDate
    }

    /// Current smoothed level in 0...1 for the UI. Applies a release decay based
    /// on elapsed time since the last feed so the bar falls to zero when a source
    /// stops delivering (rather than freezing at its last value).
    public func level(_ channel: Channel) -> Double {
        let i = channel.rawValue
        let raw = levels[i]
        let age = Date.timeIntervalSinceReferenceDate - lastFeed[i]
        if age > 0.25 {
            // No fresh audio for a while — decay toward zero so a paused/ended
            // source visibly drops out.
            let decay = max(0, 1 - (age - 0.25) / 0.5)
            return raw * decay
        }
        return raw
    }

    /// Whether this channel has received any audio in the recent past.
    public func isActive(_ channel: Channel) -> Bool {
        let age = Date.timeIntervalSinceReferenceDate - lastFeed[channel.rawValue]
        return age < 1.0
    }
}
