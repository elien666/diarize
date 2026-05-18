import ArgumentParser
import DiarizeCore
import Foundation

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Full-text search across all transcripts (FTS5)."
    )

    @Argument(parsing: .remaining, help: "Search term(s). Multiple words are AND-linked. Quotes allow FTS5 syntax (NEAR, OR, AND).")
    var query: [String]

    @Option(name: .long, help: "Maximum results (default 30).")
    var limit: Int = 30

    @Flag(name: .long, help: "Machine-readable JSON output instead of formatted list.")
    var json: Bool = false

    func run() throws {
        let q = query.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw ValidationError("Please provide a search term.") }

        let config = AppConfigLoader.load()
        try config.ensureDirectories()
        let store = try SpeakerStore(path: config.databasePath)
        let svc = SearchService(store: store)
        let hits = try svc.search(query: q, options: SearchOptions(limit: limit))

        if json {
            let payload = hits.map { hit -> [String: Any] in
                [
                    "recordingId": hit.recordingId,
                    "recordingTitle": hit.recordingTitle as Any,
                    "speakerLabel": hit.speakerLabel as Any,
                    "startSec": hit.startSec,
                    "endSec": hit.endSec,
                    "snippet": hit.snippet,
                    "rank": hit.rank,
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        if hits.isEmpty {
            print("No results for '\(q)'.")
            return
        }
        print("\(hits.count) results for '\(q)':\n")
        for hit in hits {
            let speaker = hit.speakerLabel ?? "—"
            let title = hit.recordingTitle ?? hit.recordingId
            let ts = MarkdownTimeFormatter.duration(hit.startSec)
            let snippet = AnsiHighlight.applyMarks(in: hit.snippet)
            print("\(speaker)  ·  \(title)  @  \(ts)")
            print("  \(snippet)")
            print("  → diarize archive show \(hit.recordingId)\n")
        }
    }
}

/// Convert FTS5 <mark>…</mark> tags to ANSI bold-yellow.
enum AnsiHighlight {
    static func applyMarks(in text: String) -> String {
        let bold = "\u{001B}[1;33m"
        let reset = "\u{001B}[0m"
        return text
            .replacingOccurrences(of: "<mark>", with: bold)
            .replacingOccurrences(of: "</mark>", with: reset)
    }
}
