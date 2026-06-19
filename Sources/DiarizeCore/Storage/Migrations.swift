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

        migrator.registerMigration("v2_recording_source_hash") { db in
            try db.alter(table: "recordings") { t in
                t.add(column: "sourceHash", .text)
            }
            try db.create(index: "idx_rec_source_hash", on: "recordings", columns: ["sourceHash"])
        }

        migrator.registerMigration("v3_segments_fts") { db in
            // External-content FTS5 mirroring recording_segments. We populate it on
            // insert/update/delete via triggers. unicode61 with diacritic-stripping is a
            // good default for German+English.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE recording_segments_fts USING fts5(
                    text,
                    content='recording_segments',
                    content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                );
            """)
            try db.execute(sql: """
                INSERT INTO recording_segments_fts(rowid, text)
                SELECT id, text FROM recording_segments;
            """)
            try db.execute(sql: """
                CREATE TRIGGER recording_segments_ai AFTER INSERT ON recording_segments BEGIN
                    INSERT INTO recording_segments_fts(rowid, text) VALUES (new.id, new.text);
                END;
            """)
            try db.execute(sql: """
                CREATE TRIGGER recording_segments_ad AFTER DELETE ON recording_segments BEGIN
                    INSERT INTO recording_segments_fts(recording_segments_fts, rowid, text) VALUES('delete', old.id, old.text);
                END;
            """)
            try db.execute(sql: """
                CREATE TRIGGER recording_segments_au AFTER UPDATE ON recording_segments BEGIN
                    INSERT INTO recording_segments_fts(recording_segments_fts, rowid, text) VALUES('delete', old.id, old.text);
                    INSERT INTO recording_segments_fts(rowid, text) VALUES (new.id, new.text);
                END;
            """)
        }

        migrator.registerMigration("v4_recording_processing_state") { db in
            try db.alter(table: "recordings") { t in
                t.add(column: "processingState", .text).notNull().defaults(to: "done")
                t.add(column: "errorMessage", .text)
            }
        }

        migrator.registerMigration("v5_folders") { db in
            try db.create(table: "recording_folders") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("parentId", .text).references("recording_folders", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "recordings") { t in
                t.add(column: "folderId", .text).references("recording_folders", onDelete: .setNull)
            }
        }

        migrator.registerMigration("v6_audio_deleted_at") { db in
            // GDPR: the raw audio (biometric voice data) can be removed while keeping
            // the derived transcript. Non-nil = audio was deliberately deleted; this
            // distinguishes intentional deletion from a WAV that's missing for other
            // reasons, and stops auto-clean from re-proposing the same recording.
            try db.alter(table: "recordings") { t in
                t.add(column: "audioDeletedAt", .datetime)
            }
        }

        migrator.registerMigration("v7_recording_processed_at") { db in
            // Agent-facing "processed" flag for the MCP server. Stored as a nullable
            // timestamp rather than a BOOL: NULL is the natural default for the entire
            // existing backlog (no rewrite), the hot "find unprocessed" query is a cheap
            // `processedAt IS NULL`, and we keep WHEN it was marked for free. Agents see
            // it as a boolean: processed == (processedAt != nil).
            try db.alter(table: "recordings") { t in
                t.add(column: "processedAt", .datetime)
            }
            try db.create(index: "idx_rec_processed_at", on: "recordings", columns: ["processedAt"])
        }
    }
}
