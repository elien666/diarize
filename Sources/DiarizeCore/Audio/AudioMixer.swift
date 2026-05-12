import Foundation

/// Sample-accurate mixer for two source streams writing to a single timeline.
/// Each source has its own write head; the mixer summed-writes to a backing WAV
/// writer in chunks, advancing a global "committed" head when both sources have
/// data past it (or one source has been silent for the silence-window).
///
/// Strategy: keep a per-source ring of pending samples plus a "lastActivity" timestamp.
/// Periodically (called from a timer or on each append), commit all samples up to
/// `min(headA, headB)` of the global timeline by summing.
///
/// Simplification for v1: assume both sources start at roughly the same wall-clock
/// time (no large skew correction). For Mic+System recorded by the same process this
/// is acceptable — both feeds are driven by AudioUnits with similar latency.
public final class AudioMixer: @unchecked Sendable {
    public enum Channel: Int, Sendable, CaseIterable {
        case mic = 0
        case system = 1
    }

    private let writer: WAVWriter
    private let queue = DispatchQueue(label: "diarize.mixer")
    private var buffers: [[Float]] = [[], []]
    private var enabledChannels: Set<Channel>
    /// Wall-clock of last sample arrival per channel; used to detect that a channel
    /// is silent (e.g. system audio with nothing playing) so we don't stall.
    private var lastActivity: [Date] = [Date.distantPast, Date.distantPast]
    private let silenceTimeoutSeconds: Double = 0.25

    public init(writer: WAVWriter, enabled: Set<Channel>) {
        self.writer = writer
        self.enabledChannels = enabled
    }

    public func append(_ samples: [Float], channel: Channel) {
        guard enabledChannels.contains(channel) else { return }
        queue.async {
            self.buffers[channel.rawValue].append(contentsOf: samples)
            self.lastActivity[channel.rawValue] = Date()
            self.flushIfPossible()
        }
    }

    public func flushAndClose() throws {
        try queue.sync {
            // Commit whatever's left (zero-pad shorter channel).
            self.flushAll()
            try self.writer.close()
        }
    }

    /// Commits the longest prefix that all enabled channels have, mixed by simple sum.
    /// If one enabled channel is silent past timeout, treat its missing samples as zero.
    private func flushIfPossible() {
        let now = Date()
        let counts = enabledChannels.map { ch -> Int in
            let raw = buffers[ch.rawValue].count
            let silent = now.timeIntervalSince(lastActivity[ch.rawValue]) > silenceTimeoutSeconds
            return silent ? Int.max : raw
        }
        let commit = counts.min() ?? 0
        guard commit > 0, commit != Int.max else { return }
        commitPrefix(length: commit)
    }

    private func flushAll() {
        let maxLen = enabledChannels.map { buffers[$0.rawValue].count }.max() ?? 0
        if maxLen > 0 { commitPrefix(length: maxLen) }
    }

    private func commitPrefix(length: Int) {
        var mixed = [Float](repeating: 0, count: length)
        for ch in enabledChannels {
            let buf = buffers[ch.rawValue]
            let take = min(length, buf.count)
            for i in 0..<take { mixed[i] += buf[i] }
            buffers[ch.rawValue].removeFirst(take)
        }
        // Soft clip to [-1, 1]
        for i in 0..<mixed.count {
            if mixed[i] > 1 { mixed[i] = 1 } else if mixed[i] < -1 { mixed[i] = -1 }
        }
        try? writer.append(samples: mixed)
    }
}
