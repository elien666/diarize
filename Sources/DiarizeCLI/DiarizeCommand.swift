import ArgumentParser

@main
struct DiarizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diarize",
        abstract: "Transcribe audio recordings and identify speakers across recordings.",
        version: "0.1.0",
        subcommands: [
            TranscribeCommand.self,
            RecordCommand.self,
            SearchCommand.self,
            SpeakersCommand.self,
            ArchiveCommand.self,
            ConfigCommand.self,
        ],
        defaultSubcommand: nil
    )
}
