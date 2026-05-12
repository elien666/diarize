import Foundation
import GRDB

public final class SpeakerStore: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        self.dbQueue = try DatabaseQueue(path: path.path, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        Migrations.register(on: &migrator)
        try migrator.migrate(dbQueue)
    }

    // MARK: - Speakers

    public func allSpeakers() throws -> [Speaker] {
        try dbQueue.read { db in
            try Speaker.order(Column("createdAt").asc).fetchAll(db)
        }
    }

    public func speaker(id: String) throws -> Speaker? {
        try dbQueue.read { db in try Speaker.fetchOne(db, key: id) }
    }

    public func insertSpeaker(_ speaker: Speaker) throws {
        try dbQueue.write { db in
            var s = speaker
            try s.insert(db)
        }
    }

    public func updateLabel(id: String, label: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE speakers SET label = ? WHERE id = ?", arguments: [label, id])
        }
    }

    public func deleteSpeaker(id: String) throws {
        try dbQueue.write { db in
            _ = try Speaker.deleteOne(db, key: id)
        }
    }

    /// Move all embeddings + segment refs from `from` to `into`, then delete `from`.
    public func mergeSpeakers(from: String, into: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE speaker_embeddings SET speakerId = ? WHERE speakerId = ?", arguments: [into, from])
            try db.execute(sql: "UPDATE recording_segments SET speakerId = ? WHERE speakerId = ?", arguments: [into, from])
            try db.execute(sql: "DELETE FROM speakers WHERE id = ?", arguments: [from])
        }
    }

    // MARK: - Embeddings

    @discardableResult
    public func insertEmbedding(_ embedding: SpeakerEmbedding) throws -> Int64 {
        try dbQueue.write { db in
            var e = embedding
            try e.insert(db)
            return e.id ?? 0
        }
    }

    /// Backfill recording reference on embeddings that were inserted before the recording row existed.
    public func annotateEmbeddings(ids: [Int64], recordingId: String) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let args: [DatabaseValueConvertible] = [recordingId] + ids.map { $0 as DatabaseValueConvertible }
            try db.execute(sql: "UPDATE speaker_embeddings SET recordingId = ? WHERE id IN (\(placeholders))", arguments: StatementArguments(args))
        }
    }

    public func embeddings(for speakerId: String) throws -> [SpeakerEmbedding] {
        try dbQueue.read { db in
            try SpeakerEmbedding
                .filter(Column("speakerId") == speakerId)
                .fetchAll(db)
        }
    }

    /// Returns one (speakerId, centroid) per known speaker. Centroid = mean of all embedding vectors.
    public func speakerCentroids() throws -> [(speakerId: String, centroid: [Float])] {
        try dbQueue.read { db in
            let speakers = try Speaker.fetchAll(db)
            var result: [(String, [Float])] = []
            for s in speakers {
                let embs = try SpeakerEmbedding
                    .filter(Column("speakerId") == s.id)
                    .fetchAll(db)
                guard !embs.isEmpty else { continue }
                let vectors = embs.map { $0.asFloats }
                if let centroid = MathUtil.mean(of: vectors) {
                    result.append((s.id, centroid))
                }
            }
            return result
        }
    }

    public func segmentCount(speakerId: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recording_segments WHERE speakerId = ?", arguments: [speakerId]) ?? 0
        }
    }

    public func totalSpeechTime(speakerId: String) throws -> Double {
        try dbQueue.read { db in
            try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(endSec - startSec), 0.0) FROM recording_segments WHERE speakerId = ?", arguments: [speakerId]) ?? 0
        }
    }

    public struct RecordingAppearance: Sendable {
        public let recording: Recording
        public let segmentCount: Int
        public let speechTime: Double
        public let firstAppearance: Double
    }

    /// Returns the recordings that contain this speaker, with per-recording stats.
    /// Sorted by recording date (newest first).
    public func recordings(for speakerId: String) throws -> [RecordingAppearance] {
        try dbQueue.read { db in
            let sql = """
                SELECT r.*, COUNT(rs.id) AS segCount,
                       COALESCE(SUM(rs.endSec - rs.startSec), 0.0) AS speechTime,
                       COALESCE(MIN(rs.startSec), 0.0) AS firstAppearance
                FROM recordings r
                JOIN recording_segments rs ON rs.recordingId = r.id
                WHERE rs.speakerId = ?
                GROUP BY r.id
                ORDER BY r.createdAt DESC
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [speakerId])
            return try rows.map { row in
                let recording = try Recording(row: row)
                return RecordingAppearance(
                    recording: recording,
                    segmentCount: row["segCount"] ?? 0,
                    speechTime: row["speechTime"] ?? 0,
                    firstAppearance: row["firstAppearance"] ?? 0
                )
            }
        }
    }

    // MARK: - Recordings & Segments

    public func insertRecording(_ recording: Recording, segments: [RecordingSegment]) throws {
        try dbQueue.write { db in
            var r = recording
            try r.insert(db)
            // Belt-and-suspenders: GRDB Codable encoding has historically dropped
            // late-added optional fields in some setups. Set sourceHash explicitly.
            if let hash = recording.sourceHash {
                try db.execute(
                    sql: "UPDATE recordings SET sourceHash = ? WHERE id = ?",
                    arguments: [hash, recording.id]
                )
            }
            for seg in segments {
                var s = seg
                try s.insert(db)
            }
        }
    }

    public func allRecordings() throws -> [Recording] {
        try dbQueue.read { db in
            try Recording.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func recording(id: String) throws -> Recording? {
        try dbQueue.read { db in try Recording.fetchOne(db, key: id) }
    }

    public func recording(sourceHash: String) throws -> Recording? {
        try dbQueue.read { db in
            try Recording.filter(Column("sourceHash") == sourceHash).fetchOne(db)
        }
    }

    public func segments(for recordingId: String) throws -> [RecordingSegment] {
        try dbQueue.read { db in
            try RecordingSegment
                .filter(Column("recordingId") == recordingId)
                .order(Column("startSec").asc)
                .fetchAll(db)
        }
    }

    public func replaceSegments(recordingId: String, with segments: [RecordingSegment]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM recording_segments WHERE recordingId = ?", arguments: [recordingId])
            for seg in segments {
                var s = seg
                try s.insert(db)
            }
        }
    }

    public func deleteRecording(id: String) throws {
        try dbQueue.write { db in
            _ = try Recording.deleteOne(db, key: id)
        }
    }

    public func insertEmptyRecording(_ recording: Recording) throws {
        try dbQueue.write { db in
            var r = recording
            try r.insert(db)
        }
    }

    public func upsertRecording(_ recording: Recording) throws {
        try dbQueue.write { db in
            var r = recording
            try r.save(db)
            // Belt-and-suspenders for sourceHash (see insertRecording)
            if let hash = recording.sourceHash {
                try db.execute(
                    sql: "UPDATE recordings SET sourceHash = ? WHERE id = ?",
                    arguments: [hash, recording.id]
                )
            }
        }
    }

    public func setProcessingState(recordingId: String, state: RecordingProcessingState, errorMessage: String? = nil) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recordings SET processingState = ?, errorMessage = ? WHERE id = ?",
                arguments: [state.rawValue, errorMessage, recordingId]
            )
        }
    }

    public func updateRecordingDuration(id: String, durationSec: Double) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recordings SET durationSec = ? WHERE id = ?",
                arguments: [durationSec, id]
            )
        }
    }

    public func setSourceHash(recordingId: String, hash: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recordings SET sourceHash = ? WHERE id = ?",
                arguments: [hash, recordingId]
            )
        }
    }

    /// Returns groups of recordings that share a sourceHash, sorted newest first within each group.
    /// Only groups with ≥ 2 recordings are returned.
    public func duplicateRecordings() throws -> [(hash: String, recordings: [Recording])] {
        try dbQueue.read { db in
            let recs = try Recording.filter(Column("sourceHash") != nil)
                .order(Column("createdAt").desc)
                .fetchAll(db)
            var grouped: [String: [Recording]] = [:]
            for r in recs {
                guard let h = r.sourceHash else { continue }
                grouped[h, default: []].append(r)
            }
            return grouped
                .filter { $0.value.count >= 2 }
                .map { ($0.key, $0.value) }
                .sorted { $0.recordings.first!.createdAt > $1.recordings.first!.createdAt }
        }
    }

    public func updateRecordingTranscriptPaths(id: String, mdPath: String, jsonPath: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recordings SET transcriptMd = ?, transcriptJson = ? WHERE id = ?",
                arguments: [mdPath, jsonPath, id]
            )
        }
    }
}
