import ArgumentParser
import DiarizeCore
import Foundation

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show or change the configuration.",
        subcommands: [Show.self, Set.self]
    )

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show the current configuration.")
        func run() throws {
            let config = AppConfigLoader.load()
            print("archive.path:           \(config.archivePath.path)")
            print("default.language:       \(config.defaultLanguage.rawValue)")
            print("similarity.threshold:   \(config.similarityThreshold)")
            print("")
            print("Sources (override order): CLI flag > env var > ~/.config/diarize/config.json > default")
            print("Env-Vars: DIARIZE_ARCHIVE_PATH, DIARIZE_LANG_DEFAULT, DIARIZE_SIMILARITY_THRESHOLD")
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a value in ~/.config/diarize/config.json.")
        @Argument(help: "Key (currently supported: archive.path, default.language, similarity.threshold).") var key: String
        @Argument var value: String

        func run() throws {
            let configFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/diarize/config.json")
            try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)

            var json: [String: Any] = [:]
            if let data = try? Data(contentsOf: configFile),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = obj
            }

            switch key {
            case "archive.path":
                var archive = (json["archive"] as? [String: Any]) ?? [:]
                archive["path"] = (value as NSString).expandingTildeInPath
                json["archive"] = archive
            case "default.language":
                guard AppConfig.Language(rawValue: value) != nil else {
                    throw ValidationError("Invalid language. Allowed: de, en, auto.")
                }
                json["default.language"] = value
            case "similarity.threshold":
                guard let _ = Float(value) else { throw ValidationError("Value must be a number.") }
                json["similarity.threshold"] = value
            default:
                throw ValidationError("Unknown key '\(key)'.")
            }

            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configFile)
            print("✓ \(key) → \(value)  (\(configFile.path))")
        }
    }
}
