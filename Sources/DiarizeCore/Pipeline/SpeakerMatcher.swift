import Foundation

public struct SpeakerMatchResult: Sendable {
    public let speakerId: String
    public let isNew: Bool
    public let similarity: Float    // 1.0 for new speakers
    public let embeddingId: Int64
}

public final class SpeakerMatcher {
    private let store: SpeakerStore
    private let threshold: Float
    private var cachedCentroids: [(speakerId: String, centroid: [Float])]

    public init(store: SpeakerStore, threshold: Float) throws {
        self.store = store
        self.threshold = threshold
        self.cachedCentroids = try store.speakerCentroids()
    }

    /// Match `centroid` against existing speakers; if no match exceeds the threshold,
    /// create a new speaker and return its id.
    public func matchOrCreate(centroid: [Float], recordingId: String?, segmentRange: (Double, Double)?) throws -> SpeakerMatchResult {
        var bestId: String?
        var bestSim: Float = -1

        for (id, c) in cachedCentroids {
            let sim = MathUtil.cosineSimilarity(centroid, c)
            if sim > bestSim {
                bestSim = sim
                bestId = id
            }
        }

        if let id = bestId, bestSim >= threshold {
            let embId = try store.insertEmbedding(SpeakerEmbedding(
                speakerId: id,
                vector: centroid,
                recordingId: recordingId,
                segmentStart: segmentRange?.0,
                segmentEnd: segmentRange?.1
            ))
            // Update cache: simple invalidation of this speaker's centroid
            try refreshCentroid(for: id)
            return SpeakerMatchResult(speakerId: id, isNew: false, similarity: bestSim, embeddingId: embId)
        }

        // New speaker
        let newSpeaker = Speaker()
        try store.insertSpeaker(newSpeaker)
        let embId = try store.insertEmbedding(SpeakerEmbedding(
            speakerId: newSpeaker.id,
            vector: centroid,
            recordingId: recordingId,
            segmentStart: segmentRange?.0,
            segmentEnd: segmentRange?.1
        ))
        cachedCentroids.append((newSpeaker.id, centroid))
        return SpeakerMatchResult(speakerId: newSpeaker.id, isNew: true, similarity: 1.0, embeddingId: embId)
    }

    private func refreshCentroid(for speakerId: String) throws {
        let embs = try store.embeddings(for: speakerId)
        guard let centroid = MathUtil.mean(of: embs.map { $0.asFloats }) else { return }
        if let idx = cachedCentroids.firstIndex(where: { $0.speakerId == speakerId }) {
            cachedCentroids[idx] = (speakerId, centroid)
        } else {
            cachedCentroids.append((speakerId, centroid))
        }
    }
}
