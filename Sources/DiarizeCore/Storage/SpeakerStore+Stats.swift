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
    public func sampleSegments(speakerId: String, limit: Int, requireAudio: Bool = false) throws -> [RecordingSegment] {
        let playable: [String]? = requireAudio ? Array(try recordingIdsWithAudioFile()) : nil
        return try dbQueue.read { db in
            var sql = "SELECT * FROM recording_segments WHERE speakerId = ?"
            var args: [DatabaseValueConvertible] = [speakerId]
            if let playable {
                guard !playable.isEmpty else { return [] }
                sql += " AND recordingId IN (\(playable.map { _ in "?" }.joined(separator: ",")))"
                args += playable
            }
            sql += " ORDER BY (endSec - startSec) DESC LIMIT ?"
            args.append(max(1, limit))
            return try RecordingSegment.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Recordings whose audio file still exists on disk. `audioDeletedAt` alone is not enough:
    /// files can be missing (moved archive, manual deletion) without being marked deleted.
    public func recordingIdsWithAudioFile() throws -> Set<String> {
        let rows: [(String, String)] = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, sourcePath FROM recordings WHERE audioDeletedAt IS NULL")
                .map { ($0["id"], $0["sourcePath"]) }
        }
        let fm = FileManager.default
        return Set(rows.filter { fm.fileExists(atPath: $0.1) }.map(\.0))
    }

    /// Speakers with at least one segment in a recording whose audio file still exists.
    public func speakerIdsWithAudio() throws -> Set<String> {
        let playable = Array(try recordingIdsWithAudioFile())
        guard !playable.isEmpty else { return [] }
        return try dbQueue.read { db in
            Set(try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT speakerId FROM recording_segments
                    WHERE speakerId IS NOT NULL
                    AND recordingId IN (\(playable.map { _ in "?" }.joined(separator: ",")))
                    """,
                arguments: StatementArguments(playable)
            ))
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
