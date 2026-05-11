import ArgumentParser
import DiarizeCore
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Diarisiere und transkribiere eine Audiodatei (mp3, wav, m4a, …)."
    )

    @Argument(help: "Pfad zur Audiodatei.")
    var audio: String

    @Option(name: .long, help: "Sprache: de, en oder auto (Default aus Config).")
    var lang: String?

    @Option(name: .long, help: "Optionaler Titel für das Transkript.")
    var title: String?

    @Option(name: .long, help: "Override Archiv-Pfad.")
    var archive: String?

    func run() async throws {
        var config = AppConfigLoader.load()
        if let archive { config.archivePath = URL(fileURLWithPath: (archive as NSString).expandingTildeInPath) }
        try config.ensureDirectories()

        let language: AppConfig.Language?
        if let lang {
            guard let parsed = AppConfig.Language(rawValue: lang) else {
                throw ValidationError("Unbekannte Sprache '\(lang)'. Erlaubt: de, en, auto.")
            }
            language = parsed
        } else {
            language = nil
        }

        let store = try SpeakerStore(path: config.databasePath)
        let pipeline = TranscribePipeline(config: config, store: store)
        let url = URL(fileURLWithPath: (audio as NSString).expandingTildeInPath)
        let result = try await pipeline.run(audioPath: url, title: title, language: language)

        print("✓ Aufnahme: \(result.recording.id)")
        print("  Markdown: \(result.markdownPath.path)")
        print("  JSON:     \(result.jsonPath.path)")
        print("  Sprecher: \(result.matchedSpeakerIds.count) wiedererkannt, \(result.newSpeakerIds.count) neu")
        if !result.newSpeakerIds.isEmpty {
            print("  Neue IDs: \(result.newSpeakerIds.joined(separator: ", "))")
            print("  Tipp: 'diarize speakers label <id> <name>' um Sprecher zu benennen.")
        }
    }
}
