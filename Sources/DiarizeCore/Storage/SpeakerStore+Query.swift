import Foundation
import GRDB

/// Filters for listing recordings, tuned for the MCP server's "find the latest /
/// unprocessed / failed recordings" access patterns. All filters are ANDed; the
/// result is always ordered newest-first and capped by `limit`.
public struct RecordingQuery: Sendable {
    public var limit: Int
    /// The folder to filter by. Only consulted when `folderFilterActive` is true; a
    /// nil `folderId` with `folderFilterActive == true` means "root (folderId IS NULL)".
    public var folderId: String?
    /// Distinguishes "any folder" (false) from "this specific folder / root" (true).
    public var folderFilterActive: Bool
    /// nil = any; true = processedAt IS NOT NULL; false = processedAt IS NULL.
    public var processed: Bool?
    /// nil = any processing state; e.g. `.failed` to find retry candidates.
    public var state: RecordingProcessingState?
    /// nil/empty = no full-text filter; otherwise restricts to recordings with at
    /// least one segment matching the FTS query.
    public var searchText: String?

    public init(
        limit: Int = 50,
        folderId: String? = nil,
        folderFilterActive: Bool = false,
        processed: Bool? = nil,
        state: RecordingProcessingState? = nil,
        searchText: String? = nil
    ) {
        self.limit = limit
        self.folderId = folderId
        self.folderFilterActive = folderFilterActive
        self.processed = processed
        self.state = state
        self.searchText = searchText
    }
}

extension SpeakerStore {
    /// Latest recordings (createdAt DESC) matching the given filters.
    public func recordings(matching query: RecordingQuery) throws -> [Recording] {
        let limit = max(1, query.limit)
        var clauses: [String] = []
        var args: [DatabaseValueConvertible] = []

        if let searchText = query.searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !searchText.isEmpty {
            // Restrict to recordings that have a matching segment. The FTS table is
            // joined in a subquery so we keep one row per recording.
            clauses.append("""
                r.id IN (
                    SELECT DISTINCT rs.recordingId
                    FROM recording_segments_fts
                    JOIN recording_segments rs ON rs.id = recording_segments_fts.rowid
                    WHERE recording_segments_fts MATCH ?
                )
                """)
            args.append(SearchService.escapeForFts5(searchText))
        }

        if let processed = query.processed {
            clauses.append(processed ? "r.processedAt IS NOT NULL" : "r.processedAt IS NULL")
        }

        if let state = query.state {
            clauses.append("r.processingState = ?")
            args.append(state.rawValue)
        }

        if query.folderFilterActive {
            if let folderId = query.folderId {
                clauses.append("r.folderId = ?")
                args.append(folderId)
            } else {
                clauses.append("r.folderId IS NULL")
            }
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
            SELECT r.* FROM recordings r
            \(whereClause)
            ORDER BY r.createdAt DESC
            LIMIT ?
            """
        args.append(limit)

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try rows.map { try Recording(row: $0) }
        }
    }

    /// Bulk set/clear the processed flag in a single UPDATE. `processedAt == nil`
    /// clears the flag (processed = false). Returns the number of rows changed.
    @discardableResult
    public func setProcessed(ids: [String], processedAt: Date?) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try dbQueue.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let args: [DatabaseValueConvertible] = [processedAt as DatabaseValueConvertible]
                + ids.map { $0 as DatabaseValueConvertible }
            try db.execute(
                sql: "UPDATE recordings SET processedAt = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments(args)
            )
            return db.changesCount
        }
    }

    /// Recordings currently being captured (processingState == .recording). This is the
    /// cross-process source of truth for "is recording" — the app's in-memory flag is
    /// not visible to other processes. A row left in `.recording` by a crashed process
    /// would linger here until recovered.
    public func recordingInProgress() throws -> [Recording] {
        try dbQueue.read { db in
            try Recording
                .filter(Column("processingState") == RecordingProcessingState.recording.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Whether any recording is currently being captured.
    public func isRecordingNow() throws -> Bool {
        try dbQueue.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM recordings WHERE processingState = ?)",
                arguments: [RecordingProcessingState.recording.rawValue]
            ) ?? false
        }
    }
}
