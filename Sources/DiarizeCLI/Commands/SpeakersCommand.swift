import ArgumentParser
import DiarizeCore
import Foundation

struct SpeakersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speakers",
        abstract: "Verwaltet die Sprecher-Bibliothek.",
        subcommands: [List.self, Label.self, Show.self, Merge.self, Delete.self, Recalibrate.self]
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

    struct Recalibrate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "recalibrate",
            abstract: "Berechnet einen empfohlenen Similarity-Threshold aus deinen gelabelten Sprechern."
        )

        @Flag(name: .long, help: "Setzt den empfohlenen Wert direkt in ~/.config/diarize/config.json.")
        var apply: Bool = false

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard let result = try ThresholdCalibrator.calibrate(store: store) else {
                print("Nicht genug gelabelte Sprecher für Kalibrierung — labele zuerst mindestens 2 Sprecher mit je ≥1 Embedding.")
                return
            }

            print("Aktueller Threshold:    \(config.similarityThreshold)")
            print("Gelabelte Sprecher:     \(result.labeledSpeakers)")
            print(String(format: "Intra-Speaker:          mean=%.3f  min=%.3f  (sollte hoch sein)", result.intraSpeakerMean, result.intraSpeakerMin))
            print(String(format: "Inter-Speaker:          mean=%.3f  max=%.3f  (sollte niedrig sein)", result.interSpeakerMean, result.interSpeakerMax))
            print("Konfidenz:              \(result.confidence.rawValue)")
            print(String(format: "Empfohlener Threshold:  %.3f", result.recommendedThreshold))

            if apply {
                let configFile = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config/diarize/config.json")
                try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                var json: [String: Any] = [:]
                if let data = try? Data(contentsOf: configFile),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    json = obj
                }
                json["similarity.threshold"] = String(format: "%.3f", result.recommendedThreshold)
                let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: configFile)
                print("✓ in \(configFile.path) gespeichert.")
            } else {
                print("Tipp: erneut mit --apply ausführen, um den Wert dauerhaft zu setzen.")
            }
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
