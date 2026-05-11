import ArgumentParser
import DiarizeCore
import Foundation

struct SpeakersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speakers",
        abstract: "Verwaltet die Sprecher-Bibliothek.",
        subcommands: [List.self, Label.self, Show.self, Merge.self, Delete.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Listet alle bekannten Sprecher.")

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let speakers = try store.allSpeakers()
            if speakers.isEmpty {
                print("Keine Sprecher in der Bibliothek. Verarbeite zuerst eine Aufnahme mit 'diarize transcribe'.")
                return
            }
            print(TableRow.format(["ID", "Label", "Segmente", "Sprechzeit"], widths: [40, 20, 10, 0]))
            for s in speakers {
                let count = (try? store.segmentCount(speakerId: s.id)) ?? 0
                let time = (try? store.totalSpeechTime(speakerId: s.id)) ?? 0
                print(TableRow.format([s.id, s.label ?? "—", "\(count)", String(format: "%.1fs", time)], widths: [40, 20, 10, 0]))
            }
        }
    }

    struct Label: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "label", abstract: "Setzt oder überschreibt den Namen eines Sprechers.")
        @Argument var speakerId: String
        @Argument var name: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard try store.speaker(id: speakerId) != nil else {
                throw ValidationError("Sprecher '\(speakerId)' nicht gefunden.")
            }
            try store.updateLabel(id: speakerId, label: name)
            print("✓ \(speakerId) → '\(name)'")
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Details zu einem Sprecher.")
        @Argument var speakerId: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard let s = try store.speaker(id: speakerId) else {
                throw ValidationError("Sprecher '\(speakerId)' nicht gefunden.")
            }
            print("ID:         \(s.id)")
            print("Label:      \(s.label ?? "—")")
            print("Erstellt:   \(s.createdAt)")
            print("Segmente:   \(try store.segmentCount(speakerId: s.id))")
            print(String(format: "Sprechzeit: %.1fs", try store.totalSpeechTime(speakerId: s.id)))
            print("Embeddings: \(try store.embeddings(for: s.id).count)")
        }
    }

    struct Merge: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "merge", abstract: "Führt zwei Sprecher zusammen (Quelle wird in Ziel überführt).")
        @Argument(help: "Quell-ID (wird gelöscht).") var from: String
        @Argument(help: "Ziel-ID (übernimmt alle Embeddings & Segmente).") var into: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard try store.speaker(id: from) != nil else { throw ValidationError("Quelle '\(from)' nicht gefunden.") }
            guard try store.speaker(id: into) != nil else { throw ValidationError("Ziel '\(into)' nicht gefunden.") }
            try store.mergeSpeakers(from: from, into: into)
            print("✓ \(from) → \(into) zusammengeführt.")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete", abstract: "Löscht einen Sprecher und alle zugehörigen Embeddings.")
        @Argument var speakerId: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard try store.speaker(id: speakerId) != nil else { throw ValidationError("Sprecher '\(speakerId)' nicht gefunden.") }
            try store.deleteSpeaker(id: speakerId)
            print("✓ \(speakerId) gelöscht.")
        }
    }
}
