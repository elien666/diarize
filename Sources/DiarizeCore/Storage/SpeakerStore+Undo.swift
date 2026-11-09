import Foundation
import GRDB

/// Everything needed to reverse `mergeSpeakers(from:into:)`.
public struct MergeSnapshot: Sendable {
    public let speaker: Speaker
    public let intoId: String
    public let segmentIds: [Int64]
    public let embeddingIds: [Int64]
}

/// Everything needed to reverse `reassignSegment(segmentId:toSpeakerId:)`.
public struct ReassignSnapshot: Sendable {
    public let segmentId: Int64
    public let fromSpeakerId: String?
    public let embeddingIds: [Int64]
    /// Set when the reassignment created the target speaker.
    public let createdSpeakerId: String?
}

extension SpeakerStore {
    /// Capture what a merge of `from` into `into` will move. Call before `mergeSpeakers`.
    public func mergeSnapshot(from: String, into: String) throws -> MergeSnapshot? {
        try dbQueue.read { db in
            guard let speaker = try Speaker.fetchOne(db, key: from) else { return nil }
            let segs = try Int64.fetchAll(db, sql: "SELECT id FROM recording_segments WHERE speakerId = ?", arguments: [from])
            let embs = try Int64.fetchAll(db, sql: "SELECT id FROM speaker_embeddings WHERE speakerId = ?", arguments: [from])
            return MergeSnapshot(speaker: speaker, intoId: into, segmentIds: segs, embeddingIds: embs)
        }
    }

    /// Recreate the merged-away speaker and give back its segments and embeddings.
    public func restoreMerge(_ snap: MergeSnapshot) throws {
        try dbQueue.write { db in
            if try Speaker.fetchOne(db, key: snap.speaker.id) == nil {
                var s = snap.speaker
                try s.insert(db)
            }
            for id in snap.segmentIds {
                try db.execute(sql: "UPDATE recording_segments SET speakerId = ? WHERE id = ?", arguments: [snap.speaker.id, id])
            }
            for id in snap.embeddingIds {
                try db.execute(sql: "UPDATE speaker_embeddings SET speakerId = ? WHERE id = ?", arguments: [snap.speaker.id, id])
            }
        }
    }

    /// Capture a segment's current speaker and embeddings. Call before `reassignSegment`.
    public func reassignSnapshot(segmentId: Int64, createdSpeakerId: String?) throws -> ReassignSnapshot? {
        try dbQueue.read { db in
            guard let seg = try RecordingSegment.fetchOne(db, key: segmentId) else { return nil }
            let embs = try Int64.fetchAll(
                db,
                sql: """
                    SELECT id FROM speaker_embeddings
                    WHERE recordingId = ? AND ABS(segmentStart - ?) < 0.01 AND ABS(segmentEnd - ?) < 0.01
                    """,
                arguments: [seg.recordingId, seg.startSec, seg.endSec]
            )
            return ReassignSnapshot(segmentId: segmentId, fromSpeakerId: seg.speakerId, embeddingIds: embs, createdSpeakerId: createdSpeakerId)
        }
    }

    /// Put the segment and its embeddings back; drop the speaker the move created if it is now empty.
    public func restoreReassign(_ snap: ReassignSnapshot) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE recording_segments SET speakerId = ? WHERE id = ?", arguments: [snap.fromSpeakerId, snap.segmentId])
            for id in snap.embeddingIds {
                try db.execute(sql: "UPDATE speaker_embeddings SET speakerId = ? WHERE id = ?", arguments: [snap.fromSpeakerId, id])
            }
            if let created = snap.createdSpeakerId {
                let left = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recording_segments WHERE speakerId = ?", arguments: [created]) ?? 0
                if left == 0 { _ = try Speaker.deleteOne(db, key: created) }
            }
        }
    }
}
