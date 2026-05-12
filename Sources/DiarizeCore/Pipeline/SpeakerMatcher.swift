import Foundation

public struct SpeakerMatchResult: Sendable {
    public let speakerId: String
    public let isNew: Bool
    public let similarity: Float    // 1.0 for new speakers
    public let embeddingId: Int64
}

/// Matches new embeddings against the speaker library using k-nearest-neighbor voting
/// over all stored embeddings (not just per-speaker centroids). This catches speakers
/// whose centroid has drifted across recordings (different acoustics, mood, mic).
public final class SpeakerMatcher {
    public struct Config: Sendable {
        public let threshold: Float
        public let k: Int                  // number of nearest neighbors to consider
        public let minVotesRatio: Float    // fraction of K that must agree for a match
        public init(threshold: Float, k: Int = 5, minVotesRatio: Float = 0.6) {
            self.threshold = threshold
            self.k = k
            self.minVotesRatio = minVotesRatio
        }
    }

    private let store: SpeakerStore
    private let config: Config
    private var cache: [(speakerId: String, embedding: [Float])]

    public convenience init(store: SpeakerStore, threshold: Float) throws {
        try self.init(store: store, config: Config(threshold: threshold))
    }

    public init(store: SpeakerStore, config: Config) throws {
        self.store = store
        self.config = config
        self.cache = try Self.loadAllEmbeddings(from: store)
    }

    private static func loadAllEmbeddings(from store: SpeakerStore) throws -> [(String, [Float])] {
        var out: [(String, [Float])] = []
        for s in try store.allSpeakers() {
            for e in try store.embeddings(for: s.id) {
                out.append((s.id, e.asFloats))
            }
        }
        return out
    }

    public func matchOrCreate(centroid: [Float], recordingId: String?, segmentRange: (Double, Double)?) throws -> SpeakerMatchResult {
        let decision = decide(for: centroid)

        switch decision {
        case .match(let speakerId, let similarity):
            let embId = try store.insertEmbedding(SpeakerEmbedding(
                speakerId: speakerId,
                vector: centroid,
                recordingId: recordingId,
                segmentStart: segmentRange?.0,
                segmentEnd: segmentRange?.1
            ))
            cache.append((speakerId, centroid))
            return SpeakerMatchResult(speakerId: speakerId, isNew: false, similarity: similarity, embeddingId: embId)

        case .newSpeaker:
            let newSpeaker = Speaker()
            try store.insertSpeaker(newSpeaker)
            let embId = try store.insertEmbedding(SpeakerEmbedding(
                speakerId: newSpeaker.id,
                vector: centroid,
                recordingId: recordingId,
                segmentStart: segmentRange?.0,
                segmentEnd: segmentRange?.1
            ))
            cache.append((newSpeaker.id, centroid))
            return SpeakerMatchResult(speakerId: newSpeaker.id, isNew: true, similarity: 1.0, embeddingId: embId)
        }
    }

    enum Decision {
        case match(speakerId: String, similarity: Float)
        case newSpeaker
    }

    /// Compute (but don't persist) the decision for a centroid. Public so the recalibrate
    /// command can simulate matches.
    func decide(for centroid: [Float]) -> Decision {
        guard !cache.isEmpty else { return .newSpeaker }

        // Find top-K most similar embeddings.
        var scored: [(speakerId: String, sim: Float)] = cache.map { (id, vec) in
            (id, MathUtil.cosineSimilarity(centroid, vec))
        }
        scored.sort { $0.sim > $1.sim }
        let topK = Array(scored.prefix(config.k))

        // Only candidates that pass the threshold get to vote.
        let qualified = topK.filter { $0.sim >= config.threshold }
        guard !qualified.isEmpty else { return .newSpeaker }

        // Count votes per speaker, weighted by similarity (so very close matches dominate).
        var weighted: [String: Float] = [:]
        for entry in qualified { weighted[entry.speakerId, default: 0] += entry.sim }
        let winner = weighted.max(by: { $0.value < $1.value })!

        // Require a minimum share of K votes (or qualified count) to agree, otherwise
        // it's likely an ambiguous case → safer to start a new speaker.
        let speakerVotes = qualified.filter { $0.speakerId == winner.key }.count
        let minVotes = max(1, Int(Float(config.k) * config.minVotesRatio))
        guard speakerVotes >= minVotes else { return .newSpeaker }

        let bestSimForWinner = qualified.first { $0.speakerId == winner.key }?.sim ?? config.threshold
        return .match(speakerId: winner.key, similarity: bestSimForWinner)
    }
}
