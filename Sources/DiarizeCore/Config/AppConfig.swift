import Foundation

public struct AppConfig: Sendable {
    public var archivePath: URL
    public var defaultLanguage: Language
    public var similarityThreshold: Float

    public enum Language: String, Sendable, CaseIterable {
        case de
        case en
        case auto
    }

    public static let defaultArchiveSubpath = "Library/Application Support/diarize/archive"
    public static let defaultSimilarityThreshold: Float = 0.6

    public init(
        archivePath: URL,
        defaultLanguage: Language = .auto,
        similarityThreshold: Float = AppConfig.defaultSimilarityThreshold
    ) {
        self.archivePath = archivePath
        self.defaultLanguage = defaultLanguage
        self.similarityThreshold = similarityThreshold
    }

    public var recordingsDir: URL { archivePath.appendingPathComponent("recordings", isDirectory: true) }
    public var transcriptsDir: URL { archivePath.appendingPathComponent("transcripts", isDirectory: true) }
    public var databasePath: URL { archivePath.appendingPathComponent("speakers.sqlite") }

    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [archivePath, recordingsDir, transcriptsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

public enum AppConfigLoader {
    public static func load(env: [String: String] = ProcessInfo.processInfo.environment) -> AppConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let archivePath: URL
        if let raw = env["DIARIZE_ARCHIVE_PATH"], !raw.isEmpty {
            archivePath = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        } else if let configPath = readConfigArchivePath(home: home) {
            archivePath = configPath
        } else {
            archivePath = home.appendingPathComponent(AppConfig.defaultArchiveSubpath)
        }

        let language: AppConfig.Language = {
            if let raw = env["DIARIZE_LANG_DEFAULT"], let lang = AppConfig.Language(rawValue: raw) {
                return lang
            }
            return .auto
        }()

        let threshold: Float = {
            if let raw = env["DIARIZE_SIMILARITY_THRESHOLD"], let value = Float(raw) {
                return value
            }
            return AppConfig.defaultSimilarityThreshold
        }()

        return AppConfig(archivePath: archivePath, defaultLanguage: language, similarityThreshold: threshold)
    }

    private static func readConfigArchivePath(home: URL) -> URL? {
        let configFile = home.appendingPathComponent(".config/diarize/config.json")
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let archive = (json["archive"] as? [String: Any])?["path"] as? String else {
            return nil
        }
        return URL(fileURLWithPath: (archive as NSString).expandingTildeInPath)
    }
}
