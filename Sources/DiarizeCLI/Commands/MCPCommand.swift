import ArgumentParser
import DiarizeCore
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run a Model Context Protocol server (stdio) exposing the diarize library to local agents."
    )

    @Option(name: .long, help: "Override archive path.")
    var archive: String?

    func run() async throws {
        var config = AppConfigLoader.load()
        if let archive {
            config.archivePath = URL(fileURLWithPath: (archive as NSString).expandingTildeInPath)
        }
        try config.ensureDirectories()
        let store = try SpeakerStore(path: config.databasePath)
        try await DiarizeMCPServer(store: store, config: config).run()
    }
}
