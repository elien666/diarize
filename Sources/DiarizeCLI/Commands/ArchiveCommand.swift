import ArgumentParser
import DiarizeCore
import Foundation

struct ArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Manage the recording archive.",
        subcommands: [List.self, Show.self, Reprocess.self, ReprocessAll.self, Backfill.self, Dedupe.self, Delete.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List all archived recordings.")
        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let recs = try store.allRecordings()
            if recs.isEmpty {
                print("No recordings in the archive.")
                return
            }
            let widths = [40, 20, 6, 9, 0]
            print(TableRow.format(["ID", "Created", "Lang", "Duration", "Title"], widths: widths))
            let f = ISO8601DateFormatter()
            for r in recs {
                print(TableRow.format([
                    r.id,
                    f.string(from: r.createdAt),
                    r.language,
                    MarkdownTimeFormatter.duration(r.durationSec),
                    r.title ?? "—",
                ], widths: widths))
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show paths & key data of a recording.")
        @Argument var recordingId: String
        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard let r = try store.recording(id: recordingId) else {
                throw ValidationError("Recording '\(recordingId)' not found.")
            }
            print("ID:        \(r.id)")
            print("Title:     \(r.title ?? "—")")
            print("Source:    \(r.sourcePath)")
            print("Created:   \(r.createdAt)")
            print("Language:  \(r.language)")
            print("Duration:  \(MarkdownTimeFormatter.duration(r.durationSec))")
            print("Markdown:  \(r.transcriptMd)")
            print("JSON:      \(r.transcriptJson)")
        }
    }

    struct Reprocess: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reprocess",
            abstract: "Re-render Markdown + JSON of a recording with current speaker labels (no model run)."
        )
        @Argument var recordingId: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let pipeline = TranscribePipeline(config: config, store: store)
            let result = try pipeline.rerender(recordingId: recordingId)
            print("✓ \(result.recording.id) re-rendered.")
            print("  Markdown: \(result.markdownPath.path)")
            print("  JSON:     \(result.jsonPath.path)")
        }
    }

    struct ReprocessAll: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reprocess-all",
            abstract: "Re-render ALL archived recordings with current speaker labels."
        )

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let pipeline = TranscribePipeline(config: config, store: store)
            let recs = try store.allRecordings()
            print("Re-rendering \(recs.count) recordings …")
            for r in recs {
                _ = try pipeline.rerender(recordingId: r.id)
                print("  ✓ \(r.id)  \(r.title ?? "—")")
            }
            print("Done.")
        }
    }

    struct Backfill: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "backfill-hashes",
            abstract: "Compute sourceHash for all recordings that are missing it (after migration / old bug)."
        )

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            var fixed = 0, missing = 0
            for r in try store.allRecordings() where r.sourceHash == nil {
                let url = URL(fileURLWithPath: r.sourcePath)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("⚠ Source missing for \(r.id): \(r.sourcePath)")
                    missing += 1
                    continue
                }
                let hash = try AudioHasher.sha256(of: url)
                try store.setSourceHash(recordingId: r.id, hash: hash)
                print("✓ \(r.id) → \(String(hash.prefix(12)))…")
                fixed += 1
            }
            print("Done. \(fixed) hashes backfilled, \(missing) sources missing.")
        }
    }

    struct Dedupe: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dedupe",
            abstract: "Find duplicate recordings (same sourceHash) and delete all but the most recent per hash."
        )
        @Flag(name: .long, help: "Show only, delete nothing.")
        var dryRun: Bool = false

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let groups = try store.duplicateRecordings()
            if groups.isEmpty {
                print("No duplicates found.")
                return
            }
            for (hash, recs) in groups {
                let keep = recs.first!
                let drop = Array(recs.dropFirst())
                print("Hash \(String(hash.prefix(12)))…  keeping \(keep.id) (\(keep.createdAt))")
                for d in drop {
                    print("  ✗ \(d.id) (\(d.createdAt))")
                    if !dryRun {
                        try store.deleteRecording(id: d.id)
                    }
                }
            }
            if dryRun { print("(dry-run — nothing deleted. Run again without --dry-run.)") }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a recording from the archive (source file is left untouched)."
        )
        @Argument var recordingId: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard try store.recording(id: recordingId) != nil else {
                throw ValidationError("Recording '\(recordingId)' not found.")
            }
            try store.deleteRecording(id: recordingId)
            print("✓ \(recordingId) deleted.")
        }
    }
}

enum MarkdownTimeFormatter {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
