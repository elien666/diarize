import Foundation
import GRDB

public struct SearchHit: Sendable {
    public let recordingId: String
    public let recordingTitle: String?
    public let recordingDate: Date
    public let segmentId: Int64
    public let speakerId: String?
    public let speakerLabel: String?
    public let startSec: Double
    public let endSec: Double
    public let snippet: String        // FTS5-snippet with <mark>…</mark> around hits
    public let rank: Double
}

public struct SearchOptions: Sendable {
    public let limit: Int
    public let snippetTokens: Int     // 8 ≈ ~16 words context around hit
    public init(limit: Int = 50, snippetTokens: Int = 8) {
        self.limit = limit
        self.snippetTokens = snippetTokens
    }
}

public final class SearchService {
    private let store: SpeakerStore

    public init(store: SpeakerStore) {
        self.store = store
    }

    public func search(query: String, options: SearchOptions = SearchOptions()) throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let ftsQuery = Self.escapeForFts5(trimmed)
        let limit = max(1, options.limit)
        let snippetCtx = max(1, min(64, options.snippetTokens))

        return try store.dbQueue.read { db in
            // snippet(table, col, mark_open, mark_close, ellipsis, num_tokens)
            let sql = """
                SELECT
                    rs.id,
                    rs.recordingId,
                    rs.speakerId,
                    rs.startSec,
                    rs.endSec,
                    sp.label AS speakerLabel,
                    r.title AS recordingTitle,
                    r.createdAt AS recordingDate,
                    snippet(recording_segments_fts, 0, '<mark>', '</mark>', '…', ?) AS snippet,
                    rank
                FROM recording_segments_fts
                JOIN recording_segments rs ON rs.id = recording_segments_fts.rowid
                JOIN recordings r ON r.id = rs.recordingId
                LEFT JOIN speakers sp ON sp.id = rs.speakerId
                WHERE recording_segments_fts MATCH ?
                ORDER BY rank
                LIMIT ?;
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [snippetCtx, ftsQuery, limit])
            return rows.map { row in
                SearchHit(
                    recordingId: row["recordingId"],
                    recordingTitle: row["recordingTitle"],
                    recordingDate: row["recordingDate"] ?? Date(),
                    segmentId: row["id"],
                    speakerId: row["speakerId"],
                    speakerLabel: row["speakerLabel"],
                    startSec: row["startSec"],
                    endSec: row["endSec"],
                    snippet: row["snippet"] ?? "",
                    rank: row["rank"] ?? 0
                )
            }
        }
    }

    /// Wrap each token in double-quotes so FTS5 doesn't choke on punctuation, and
    /// AND-join them. Bare tokens that already look like an FTS5 query (have ",
    /// AND/OR, NEAR, *) are passed through unchanged.
    public static func escapeForFts5(_ raw: String) -> String {
        if raw.contains("\"") || raw.uppercased().contains(" AND ") || raw.uppercased().contains(" OR ") || raw.uppercased().contains("NEAR(") {
            return raw
        }
        let tokens = raw.split(whereSeparator: { $0.isWhitespace })
        let quoted = tokens.map { token -> String in
            let cleaned = token.replacingOccurrences(of: "\"", with: "")
            return "\"\(cleaned)\""
        }
        return quoted.joined(separator: " ")
    }
}
