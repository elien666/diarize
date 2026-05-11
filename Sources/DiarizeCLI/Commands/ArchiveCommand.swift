import ArgumentParser
import DiarizeCore
import Foundation

struct ArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Verwaltet das Aufnahme-Archiv.",
        subcommands: [List.self, Show.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Listet alle archivierten Aufnahmen.")
        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let recs = try store.allRecordings()
            if recs.isEmpty {
                print("Keine Aufnahmen im Archiv.")
                return
            }
            let widths = [40, 20, 6, 9, 0]
            print(TableRow.format(["ID", "Erstellt", "Lang", "Dauer", "Titel"], widths: widths))
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
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Zeigt Pfade & Eckdaten einer Aufnahme.")
        @Argument var recordingId: String
        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard let r = try store.recording(id: recordingId) else {
                throw ValidationError("Aufnahme '\(recordingId)' nicht gefunden.")
            }
            print("ID:        \(r.id)")
            print("Titel:     \(r.title ?? "—")")
            print("Quelle:    \(r.sourcePath)")
            print("Erstellt:  \(r.createdAt)")
            print("Sprache:   \(r.language)")
            print("Dauer:     \(MarkdownTimeFormatter.duration(r.durationSec))")
            print("Markdown:  \(r.transcriptMd)")
            print("JSON:      \(r.transcriptJson)")
        }
    }
}

enum MarkdownTimeFormatter {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
