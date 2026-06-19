import Foundation
import GRDB

public final class SpeakerStore: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        // WAL lets readers and the writer coexist across processes. The SwiftUI app and
        // one-or-more spawned `diarize mcp` processes open this same file; in the default
        // rollback-journal mode a writer would block all readers and yield SQLITE_BUSY.
        // The busy timeout makes the loser of a writer-vs-writer race wait instead of
        // failing immediately. (Sidecar -wal/-shm files appear next to the DB.)
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        self.dbQueue = try DatabaseQueue(path: path.path, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        Migrations.register(on: &migrator)
        try migrator.migrate(dbQueue)
    }

    /// SQLite's cross-process change counter. The returned value changes whenever
    /// *another* connection (e.g. a `diarize mcp` process) commits to the database;
    /// commits on this connection do not change it. Used to detect external edits.
    public func dataVersion() throws -> Int64 {
        try dbQueue.read { db in try Int64.fetchOne(db, sql: "PRAGMA data_version") ?? 0 }
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

    // MARK: - Folders

    public func allFolders() throws -> [RecordingFolder] {
        try dbQueue.read { db in
            try RecordingFolder.order(Column("name").asc).fetchAll(db)
        }
    }

    public func insertFolder(_ folder: RecordingFolder) throws -> RecordingFolder {
        try dbQueue.write { db in
            var f = folder
            try f.insert(db)
            return f
        }
    }

    public func renameFolder(id: String, name: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE recording_folders SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    public func deleteFolder(id: String) throws {
        try dbQueue.write { db in
            _ = try RecordingFolder.deleteOne(db, key: id)
        }
    }

    public func moveRecording(id: String, toFolderId: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE recordings SET folderId = ? WHERE id = ?", arguments: [toFolderId, id])
        }
    }

    public func updateRecordingTitle(id: String, title: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE recordings SET title = ? WHERE id = ?", arguments: [title, id])
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

    public func segment(id: Int64) throws -> RecordingSegment? {
        try dbQueue.read { db in try RecordingSegment.fetchOne(db, key: id) }
    }

    public func updateSegmentSpeaker(segmentId: Int64, speakerId: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recording_segments SET speakerId = ? WHERE id = ?",
                arguments: [speakerId, segmentId]
            )
        }
    }

    /// Move a segment to a different speaker AND move that segment's voice embedding(s) to the
    /// same speaker, so the k-NN matcher learns from the correction and future recordings match
    /// better. Embeddings are matched to the segment by (recordingId, time range) with a small
    /// tolerance; a segment may have no matching embedding (very short turns, or the new half of
    /// a split whose range no longer lines up) — then only the transcript label moves.
    public func reassignSegment(segmentId: Int64, toSpeakerId: String) throws {
        try dbQueue.write { db in
            guard let seg = try RecordingSegment.fetchOne(db, key: segmentId) else {
                throw SpeakerStoreError.segmentNotFound(segmentId)
            }
            try db.execute(
                sql: "UPDATE recording_segments SET speakerId = ? WHERE id = ?",
                arguments: [toSpeakerId, segmentId]
            )
            try db.execute(
                sql: """
                    UPDATE speaker_embeddings SET speakerId = ?
                    WHERE recordingId = ? AND ABS(segmentStart - ?) < 0.01 AND ABS(segmentEnd - ?) < 0.01
                """,
                arguments: [toSpeakerId, seg.recordingId, seg.startSec, seg.endSec]
            )
        }
    }

    /// Split a segment at `splitTimeSec` (absolute, in the original audio timeline).
    /// First half keeps the original id and ends at splitTimeSec; second half is a new
    /// segment with the same speaker (caller may reassign afterwards).
    /// Returns the new segment's id.
    @discardableResult
    public func splitSegment(segmentId: Int64, at splitTimeSec: Double) throws -> Int64 {
        try dbQueue.write { db in
            guard let original = try RecordingSegment.fetchOne(db, key: segmentId) else {
                throw SpeakerStoreError.segmentNotFound(segmentId)
            }
            guard splitTimeSec > original.startSec + 0.05 && splitTimeSec < original.endSec - 0.05 else {
                throw SpeakerStoreError.invalidSplitTime
            }

            // Split text proportionally so both halves get something readable.
            let totalDur = original.endSec - original.startSec
            let firstFrac = (splitTimeSec - original.startSec) / totalDur
            let (firstText, secondText) = Self.splitText(original.text, fraction: firstFrac)

            try db.execute(
                sql: "UPDATE recording_segments SET endSec = ?, text = ? WHERE id = ?",
                arguments: [splitTimeSec, firstText, segmentId]
            )

            var newSegment = RecordingSegment(
                recordingId: original.recordingId,
                speakerId: original.speakerId,
                startSec: splitTimeSec,
                endSec: original.endSec,
                text: secondText,
                confidence: original.confidence
            )
            try newSegment.insert(db)
            return newSegment.id ?? 0
        }
    }

    private static func splitText(_ text: String, fraction: Double) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2 else { return (trimmed, "") }
        let cut = max(1, min(words.count - 1, Int((Double(words.count) * fraction).rounded())))
        let first = words.prefix(cut).joined(separator: " ")
        let second = words.dropFirst(cut).joined(separator: " ")
        return (first, second)
    }

    public enum SpeakerStoreError: Error, LocalizedError {
        case segmentNotFound(Int64)
        case invalidSplitTime
        public var errorDescription: String? {
            switch self {
            case .segmentNotFound(let id): return "Segment \(id) nicht gefunden."
            case .invalidSplitTime: return "Split-Zeit liegt zu nah an den Segmentgrenzen."
            }
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

    /// GDPR: flag a recording's audio as deleted. The caller is responsible for
    /// removing the WAV file itself; this only records that it was intentional, so
    /// the player is hidden and auto-clean won't re-propose it.
    public func markAudioDeleted(id: String, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recordings SET audioDeletedAt = ? WHERE id = ?",
                arguments: [date, id]
            )
        }
    }

    /// GDPR: physically remove the WAV file AND flag the recording as audio-deleted,
    /// keeping the transcript and speaker data. Mirrors the app's `removeAudioFile`
    /// (LibraryViewModel) so headless callers (CLI, MCP server) behave identically.
    /// No-op-safe if the recording is missing or its audio was already deleted.
    /// Returns true if the recording exists and now has its audio deleted.
    @discardableResult
    public func deleteAudio(id: String, at date: Date = Date()) throws -> Bool {
        guard let recording = try recording(id: id) else { return false }
        guard recording.hasAudio else { return true }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: recording.sourcePath))
        try markAudioDeleted(id: id, at: date)
        return true
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
