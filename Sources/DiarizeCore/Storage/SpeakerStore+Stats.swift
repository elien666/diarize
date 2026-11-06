import Foundation
import GRDB

/// Aggregate usage numbers for one speaker, computed in a single pass over the segments.
public struct SpeakerStats: Sendable {
    public let speakerId: String
    public let segmentCount: Int
    public let speechTimeSec: Double
    public let recordingCount: Int
    /// Creation date of the newest recording the speaker appears in.
    public let lastSeen: Date?
}

/// A pair of speakers whose voice centroids are close enough to be the same person.
public struct SpeakerMergeCandidate: Sendable {
    public let a: Speaker
    public let b: Speaker
    public let similarity: Float
}

extension SpeakerStore {
    /// Stats for every speaker that has at least one segment, keyed by speaker id.
    /// Speakers without segments are absent (callers treat that as zero).
    public func speakerStats() throws -> [String: SpeakerStats] {
        try dbQueue.read { db in
            let sql = """
                SELECT rs.speakerId AS speakerId,
                       COUNT(rs.id) AS segCount,
                       COALESCE(SUM(rs.endSec - rs.startSec), 0.0) AS speechTime,
                       COUNT(DISTINCT rs.recordingId) AS recCount,
                       MAX(r.createdAt) AS lastSeen
                FROM recording_segments rs
                JOIN recordings r ON r.id = rs.recordingId
                WHERE rs.speakerId IS NOT NULL
                GROUP BY rs.speakerId
            """
            var result: [String: SpeakerStats] = [:]
            for row in try Row.fetchAll(db, sql: sql) {
                let id: String = row["speakerId"]
                result[id] = SpeakerStats(
                    speakerId: id,
                    segmentCount: row["segCount"] ?? 0,
                    speechTimeSec: row["speechTime"] ?? 0,
                    recordingCount: row["recCount"] ?? 0,
                    lastSeen: row["lastSeen"]
                )
            }
            return result
        }
    }

    /// Longest segments of a speaker (most useful for identifying who it is), longest first.
    public func sampleSegments(speakerId: String, limit: Int) throws -> [RecordingSegment] {
        try dbQueue.read { db in
            try RecordingSegment.fetchAll(
                db,
                sql: """
                    SELECT * FROM recording_segments
                    WHERE speakerId = ?
                    ORDER BY (endSec - startSec) DESC
                    LIMIT ?
                    """,
                arguments: [speakerId, max(1, limit)]
            )
        }
    }

    public func updateNotes(id: String, notes: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE speakers SET notes = ? WHERE id = ?", arguments: [notes, id])
        }
    }

    /// Speaker pairs whose voice centroids have cosine similarity >= `minSimilarity`,
    /// most similar first. Only speakers with embeddings are considered, and by default
    /// only speakers that still appear in a recording: unused speakers are clean-up
    /// candidates, not merge candidates, and would drown the real suggestions.
    public func mergeCandidates(minSimilarity: Float, limit: Int, includeUnused: Bool = false) throws -> [SpeakerMergeCandidate] {
        let used = includeUnused ? nil : Set(try speakerStats().keys)
        let centroids = try speakerCentroids().filter { used?.contains($0.speakerId) ?? true }
        let byId = Dictionary(try allSpeakers().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var pairs: [SpeakerMergeCandidate] = []
        for i in 0..<centroids.count {
            for j in (i + 1)..<centroids.count {
                guard centroids[i].centroid.count == centroids[j].centroid.count,
                      let a = byId[centroids[i].speakerId], let b = byId[centroids[j].speakerId]
                else { continue }
                let sim = MathUtil.cosineSimilarity(centroids[i].centroid, centroids[j].centroid)
                if sim >= minSimilarity { pairs.append(SpeakerMergeCandidate(a: a, b: b, similarity: sim)) }
            }
        }
        return Array(pairs.sorted { $0.similarity > $1.similarity }.prefix(max(1, limit)))
    }
}
