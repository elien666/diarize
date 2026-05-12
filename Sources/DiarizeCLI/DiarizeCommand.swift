import ArgumentParser

@main
struct DiarizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diarize",
        abstract: "Transkribiere Audio-Aufnahmen und erkenne Sprecher über Aufnahmen hinweg.",
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
