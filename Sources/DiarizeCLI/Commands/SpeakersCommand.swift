import ArgumentParser
import DiarizeCore
import Foundation

struct SpeakersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speakers",
        abstract: "Manage the speaker library.",
        subcommands: [List.self, Label.self, Show.self, Merge.self, Delete.self, Recalibrate.self, Diagnose.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List all known speakers.")

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let speakers = try store.allSpeakers()
            if speakers.isEmpty {
                print("No speakers in the library. Process a recording first with 'diarize transcribe'.")
                return
            }
            print(TableRow.format(["ID", "Label", "Segments", "Speech time"], widths: [40, 20, 10, 0]))
            for s in speakers {
                let count = (try? store.segmentCount(speakerId: s.id)) ?? 0
                let time = (try? store.totalSpeechTime(speakerId: s.id)) ?? 0
                print(TableRow.format([s.id, s.label ?? "—", "\(count)", String(format: "%.1fs", time)], widths: [40, 20, 10, 0]))
            }
        }
    }

    struct Label: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "label", abstract: "Set or overwrite a speaker's name.")
        @Argument var speakerId: String
        @Argument var name: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard try store.speaker(id: speakerId) != nil else {
                throw ValidationError("Speaker '\(speakerId)' not found.")
            }
            try store.updateLabel(id: speakerId, label: name)
            print("✓ \(speakerId) → '\(name)'")
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show details of a speaker.")
        @Argument var speakerId: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard let s = try store.speaker(id: speakerId) else {
                throw ValidationError("Speaker '\(speakerId)' not found.")
            }
            print("ID:         \(s.id)")
            print("Label:      \(s.label ?? "—")")
            print("Created:    \(s.createdAt)")
            print("Segments:   \(try store.segmentCount(speakerId: s.id))")
            print(String(format: "Speech time: %.1fs", try store.totalSpeechTime(speakerId: s.id)))
            print("Embeddings: \(try store.embeddings(for: s.id).count)")
        }
    }

    struct Merge: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "merge", abstract: "Merge two speakers (source is moved into target).")
        @Argument(help: "Source ID (will be deleted).") var from: String
        @Argument(help: "Target ID (takes over all embeddings & segments).") var into: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard try store.speaker(id: from) != nil else { throw ValidationError("Source '\(from)' not found.") }
            guard try store.speaker(id: into) != nil else { throw ValidationError("Target '\(into)' not found.") }
            try store.mergeSpeakers(from: from, into: into)
            print("✓ \(from) → \(into) merged.")
        }
    }

    struct Recalibrate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "recalibrate",
            abstract: "Compute a recommended similarity threshold from your labeled speakers."
        )

        @Flag(name: .long, help: "Write the recommended value directly to ~/.config/diarize/config.json.")
        var apply: Bool = false

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard let result = try ThresholdCalibrator.calibrate(store: store) else {
                print("Not enough labeled speakers for calibration — label at least 2 speakers with ≥1 embedding each.")
                return
            }

            print("Current threshold:      \(config.similarityThreshold)")
            print("Labeled speakers:       \(result.labeledSpeakers)")
            print(String(format: "Intra-speaker:          mean=%.3f  min=%.3f  (should be high)", result.intraSpeakerMean, result.intraSpeakerMin))
            print(String(format: "Inter-speaker:          mean=%.3f  max=%.3f  (should be low)", result.interSpeakerMean, result.interSpeakerMax))
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
                print("✓ saved to \(configFile.path).")
            } else {
                print("Tip: run again with --apply to persist the value.")
            }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a speaker and all associated embeddings.")
        @Argument var speakerId: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            guard try store.speaker(id: speakerId) != nil else { throw ValidationError("Speaker '\(speakerId)' not found.") }
            try store.deleteSpeaker(id: speakerId)
            print("✓ \(speakerId) deleted.")
        }
    }

    struct Diagnose: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "diagnose",
            abstract: "Show embedding similarities to all other speakers (helps with merge decisions)."
        )
        @Argument(help: "Speaker-ID oder Label-Substring.") var speakerRef: String

        func run() throws {
            let config = AppConfigLoader.load()
            try config.ensureDirectories()
            let store = try SpeakerStore(path: config.databasePath)
            let speakers = try store.allSpeakers()
            guard let target = speakers.first(where: { $0.id == speakerRef })
                ?? speakers.first(where: { ($0.label ?? "").localizedCaseInsensitiveContains(speakerRef) }) else {
                throw ValidationError("Speaker '\(speakerRef)' not found.")
            }
            let targetEmbeddings = try store.embeddings(for: target.id).map { $0.asFloats }
            guard let targetCentroid = MathUtil.mean(of: targetEmbeddings) else {
                print("No embedding available.")
                return
            }
            print("Target: \(target.label ?? target.id)  (\(targetEmbeddings.count) embeddings)")
            print("Current threshold: \(config.similarityThreshold)")
            print("")
            print("Similarity to other speakers (centroid cosine):")
            print(TableRow.format(["ID", "Label", "Sim"], widths: [44, 20, 0]))
            var rows: [(String, String, Float)] = []
            for s in speakers where s.id != target.id {
                let embs = try store.embeddings(for: s.id).map { $0.asFloats }
                guard let c = MathUtil.mean(of: embs) else { continue }
                let sim = MathUtil.cosineSimilarity(targetCentroid, c)
                rows.append((s.id, s.label ?? "—", sim))
            }
            for (id, label, sim) in rows.sorted(by: { $0.2 > $1.2 }) {
                let marker = sim >= config.similarityThreshold ? "  ← match" : ""
                print(TableRow.format([id, label, String(format: "%.3f", sim) + marker], widths: [44, 20, 0]))
            }
            print("")
            print("Tip: two speakers who are the same person should score ≥ \(config.similarityThreshold).")
            print("       'diarize speakers merge <source> <target>' merges them.")
        }
    }
}
