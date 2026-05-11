import Foundation
import GRDB

enum Migrations {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "speakers") { t in
                t.primaryKey("id", .text)
                t.column("label", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("notes", .text)
            }

            try db.create(table: "recordings") { t in
                t.primaryKey("id", .text)
                t.column("title", .text)
                t.column("sourcePath", .text).notNull()
                t.column("durationSec", .double).notNull()
                t.column("language", .text).notNull()
                t.column("transcriptMd", .text).notNull()
                t.column("transcriptJson", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "speaker_embeddings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("speakerId", .text).notNull().references("speakers", onDelete: .cascade)
                t.column("vector", .blob).notNull()
                t.column("recordingId", .text).references("recordings", onDelete: .setNull)
                t.column("segmentStart", .double)
                t.column("segmentEnd", .double)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_emb_speaker", on: "speaker_embeddings", columns: ["speakerId"])

            try db.create(table: "recording_segments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingId", .text).notNull().references("recordings", onDelete: .cascade)
                t.column("speakerId", .text).references("speakers", onDelete: .setNull)
                t.column("startSec", .double).notNull()
                t.column("endSec", .double).notNull()
                t.column("text", .text).notNull()
                t.column("confidence", .double)
            }
            try db.create(index: "idx_seg_recording", on: "recording_segments", columns: ["recordingId"])
        }
    }
}
