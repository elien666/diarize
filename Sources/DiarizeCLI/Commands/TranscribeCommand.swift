import ArgumentParser
import DiarizeCore
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Diarize and transcribe an audio file (mp3, wav, m4a, …)."
    )

    @Argument(help: "Path to the audio file.")
    var audio: String

    @Option(name: .long, help: "Language: de, en, or auto (default from config).")
    var lang: String?

    @Option(name: .long, help: "Optional title for the transcript.")
    var title: String?

    @Option(name: .long, help: "Override archive path.")
    var archive: String?

    @Flag(name: .long, help: "Re-process the audio file even if the source hash is already archived.")
    var force: Bool = false

    func run() async throws {
        var config = AppConfigLoader.load()
        if let archive { config.archivePath = URL(fileURLWithPath: (archive as NSString).expandingTildeInPath) }
        try config.ensureDirectories()

        let language: AppConfig.Language?
        if let lang {
            guard let parsed = AppConfig.Language(rawValue: lang) else {
                throw ValidationError("Unknown language '\(lang)'. Allowed: de, en, auto.")
            }
            language = parsed
        } else {
            language = nil
        }

        let store = try SpeakerStore(path: config.databasePath)
        let pipeline = TranscribePipeline(config: config, store: store)
        let url = URL(fileURLWithPath: (audio as NSString).expandingTildeInPath)
        let result = try await pipeline.run(
            audioPath: url,
            title: title,
            language: language,
            duplicatePolicy: force ? .force : .skip
        )

        if result.skipped {
            print("↺ Skipped — recording \(result.recording.id) already exists.")
            print("  Markdown: \(result.markdownPath.path)")
            print("  Tip: 'diarize transcribe … --force' overwrites; 'diarize archive reprocess <id>' re-renders only.")
            return
        }

        print("✓ Recording: \(result.recording.id)")
        print("  Markdown: \(result.markdownPath.path)")
        print("  JSON:     \(result.jsonPath.path)")
        print("  Speakers: \(result.matchedSpeakerIds.count) matched, \(result.newSpeakerIds.count) new")
        if !result.newSpeakerIds.isEmpty {
            print("  New IDs: \(result.newSpeakerIds.joined(separator: ", "))")
            print("  Tip: 'diarize speakers label <id> <name>' to name speakers.")
        }
    }
}
