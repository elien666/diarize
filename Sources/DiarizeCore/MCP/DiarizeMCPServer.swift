import Foundation
import MCP

/// Serializes recording re-analysis. Model loading is heavy, so at most one analysis
/// runs at a time; additional requests queue. Each id can be in flight only once.
/// `analyzeExisting` itself persists `.analyzing` while it runs and `.failed` +
/// errorMessage on error, so callers just poll the recording's state afterward.
actor AnalysisRunner {
    private let config: AppConfig
    private let store: SpeakerStore
    private var inFlight: Set<String> = []
    private var queue: [String] = []
    private var draining = false

    init(config: AppConfig, store: SpeakerStore) {
        self.config = config
        self.store = store
    }

    /// Returns true if the id was accepted (newly queued), false if already in flight.
    func enqueue(_ id: String) -> Bool {
        guard !inFlight.contains(id) else { return false }
        inFlight.insert(id)
        queue.append(id)
        if !draining {
            draining = true
            Task { await self.drain() }
        }
        return true
    }

    private func drain() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            let pipeline = TranscribePipeline(config: config, store: store) // ConsoleProgress -> stderr
            do {
                _ = try await pipeline.analyzeExisting(recordingId: id, language: nil)
            } catch {
                // analyzeExisting already recorded .failed + errorMessage in the DB.
                FileHandle.standardError.write(Data("[diarize mcp] retry \(id) failed: \(error.localizedDescription)\n".utf8))
            }
            inFlight.remove(id)
        }
        draining = false
    }
}

/// Model Context Protocol server exposing the diarize library over stdio. Wraps a
/// `SpeakerStore` and `AppConfig`; reusable from any host (the `diarize mcp`
/// subcommand today, an in-app or HTTP host later).
public final class DiarizeMCPServer: @unchecked Sendable {
    private let store: SpeakerStore
    private let config: AppConfig
    private let runner: AnalysisRunner
    private let resourceListLimit = 100

    private static let recordingURIPrefix = "diarize://recording/"
    private static let statusURI = "diarize://status"

    public init(store: SpeakerStore, config: AppConfig) {
        self.store = store
        self.config = config
        self.runner = AnalysisRunner(config: config, store: store)
    }

    /// Build the server, register handlers, and serve over stdio until the client
    /// disconnects. Logs go to stderr only — stdout is the JSON-RPC channel.
    public func run() async throws {
        let server = Server(
            name: "diarize",
            version: "0.1.0",
            instructions: """
                Read and curate the local diarize transcription library: speakers, \
                folders, recordings and live recording status. Find the latest or \
                unprocessed recordings, mark them processed (bulk), read failed \
                recordings' error messages and retry their analysis, and manage \
                titles, folders and GDPR audio deletion. Recording analysis is \
                long-running: retry_analysis returns immediately; poll get_recording \
                until processingState is done/empty/failed. \
                You can also assess and correct diarization quality: get_transcript \
                returns per-segment ids, speaker labels and confidence; fix mistakes \
                with reassign_segment (wrong speaker), split_segment (one turn bundled \
                two speakers), rename_speaker (name an unknown speaker) and \
                merge_speakers (same person split in two). Corrections also move voice \
                embeddings, so future recordings get matched better.
                """,
            capabilities: .init(
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        // Capture self strongly: `server` retains these handlers and `self` does not
        // retain `server`, so there is no cycle. A weak capture would let `self`
        // deallocate while a request is still being handled.
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: Self.toolDefinitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await self.callTool(name: params.name, arguments: params.arguments)
        }
        await server.withMethodHandler(ListResources.self) { _ in
            try self.listResources()
        }
        await server.withMethodHandler(ReadResource.self) { params in
            try self.readResource(uri: params.uri)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Tool dispatch

    /// Dispatches a tool call and wraps success/failure into a `CallTool.Result`.
    /// Exposed for tests so tool behavior can be checked without a live transport.
    func callTool(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        let args = ToolArgs(arguments)
        do {
            switch name {
            case "list_speakers": return Self.ok(try listSpeakersJSON())
            case "list_folders": return Self.ok(try listFoldersJSON())
            case "list_recordings": return Self.ok(try listRecordingsJSON(args))
            case "get_recording": return Self.ok(try getRecordingJSON(args))
            case "get_transcript": return Self.ok(try getTranscriptJSON(args))
            case "recording_status": return Self.ok(try recordingStatusJSON())
            case "set_title": return Self.ok(try setTitle(args))
            case "move_recording": return Self.ok(try moveRecording(args))
            case "create_folder": return Self.ok(try createFolder(args))
            case "rename_folder": return Self.ok(try renameFolder(args))
            case "delete_folder": return Self.ok(try deleteFolder(args))
            case "set_processed": return Self.ok(try setProcessed(args))
            case "delete_audio": return Self.ok(try deleteAudio(args))
            case "retry_analysis": return Self.ok(try await retryAnalysis(args))
            case "reassign_segment": return Self.ok(try reassignSegment(args))
            case "create_speaker": return Self.ok(try createSpeaker(args))
            case "rename_speaker": return Self.ok(try renameSpeaker(args))
            case "merge_speakers": return Self.ok(try mergeSpeakers(args))
            case "split_segment": return Self.ok(try splitSegment(args))
            default: return Self.err("Unknown tool: \(name)")
            }
        } catch let error as MCPToolError {
            return Self.err(error.message)
        } catch {
            return Self.err(error.localizedDescription)
        }
    }

    // MARK: - Read tools

    func listSpeakersJSON() throws -> String {
        try MCPJSON.string(try store.allSpeakers().map(SpeakerDTO.init))
    }

    func listFoldersJSON() throws -> String {
        try MCPJSON.string(try store.allFolders().map(FolderDTO.init))
    }

    func listRecordingsJSON(_ args: ToolArgs) throws -> String {
        var query = RecordingQuery(limit: args.int("limit") ?? 50)
        query.processed = args.bool("processed")
        if let raw = args.string("state") {
            guard let state = RecordingProcessingState(rawValue: raw) else {
                throw MCPToolError("Unknown state '\(raw)'. Allowed: \(RecordingProcessingState.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            query.state = state
        }
        query.searchText = args.string("search")
        // folderId: a string filters to that folder; explicit null filters to root
        // (unfiled); absent means any folder.
        if args.isExplicitNull("folderId") {
            query.folderFilterActive = true
            query.folderId = nil
        } else if let folderId = args.string("folderId") {
            query.folderFilterActive = true
            query.folderId = folderId
        }
        return try MCPJSON.string(try store.recordings(matching: query).map(RecordingSummaryDTO.init))
    }

    func getRecordingJSON(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        guard let recording = try store.recording(id: id) else {
            throw MCPToolError("No recording with id '\(id)'")
        }
        let count = try store.segments(for: id).count
        return try MCPJSON.string(RecordingDetailDTO(recording, segmentCount: count))
    }

    func getTranscriptJSON(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        guard let recording = try store.recording(id: id) else {
            throw MCPToolError("No recording with id '\(id)'")
        }
        let labelById = Dictionary(
            try store.allSpeakers().map { ($0.id, $0.displayName) },
            uniquingKeysWith: { a, _ in a }
        )
        let segments = try store.segments(for: id).map { seg in
            TranscriptSegmentDTO(
                id: seg.id ?? 0,
                startSec: seg.startSec,
                endSec: seg.endSec,
                speakerId: seg.speakerId,
                speakerLabel: seg.speakerId.flatMap { labelById[$0] },
                text: seg.text,
                confidence: seg.confidence
            )
        }
        return try MCPJSON.string(TranscriptDTO(
            recordingId: recording.id,
            title: recording.title,
            language: recording.language,
            durationSec: recording.durationSec,
            segments: segments
        ))
    }

    func recordingStatusJSON() throws -> String {
        let active = try store.recordingInProgress().map(RecordingSummaryDTO.init)
        return try MCPJSON.string(StatusDTO(isRecording: try store.isRecordingNow(), active: active))
    }

    // MARK: - Write tools

    func setTitle(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        let title = try args.requiredString("title")
        try requireRecording(id)
        try store.updateRecordingTitle(id: id, title: title)
        return try MCPJSON.string(Value.object(["ok": true, "id": .string(id)]))
    }

    func moveRecording(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        try requireRecording(id)
        // Omitted / null folderId moves the recording to the root (unfiled).
        let folderId = args.string("folderId")
        try store.moveRecording(id: id, toFolderId: folderId)
        return try MCPJSON.string(Value.object([
            "ok": true, "id": .string(id), "folderId": folderId.map(Value.string) ?? .null,
        ]))
    }

    func createFolder(_ args: ToolArgs) throws -> String {
        let name = try args.requiredString("name")
        let parentId = args.string("parentId")
        let folder = try store.insertFolder(RecordingFolder(name: name, parentId: parentId))
        return try MCPJSON.string(FolderDTO(folder))
    }

    func renameFolder(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        let name = try args.requiredString("name")
        try store.renameFolder(id: id, name: name)
        return try MCPJSON.string(Value.object(["ok": true, "id": .string(id)]))
    }

    func deleteFolder(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        try store.deleteFolder(id: id)
        return try MCPJSON.string(Value.object(["ok": true, "id": .string(id)]))
    }

    func setProcessed(_ args: ToolArgs) throws -> String {
        let ids = try args.requiredStringArray("ids")
        let processed = try args.requiredBool("processed")
        let updated = try store.setProcessed(ids: ids, processedAt: processed ? Date() : nil)
        return try MCPJSON.string(Value.object(["updated": .int(updated)]))
    }

    func deleteAudio(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        guard let recording = try store.recording(id: id) else {
            throw MCPToolError("No recording with id '\(id)'")
        }
        try store.deleteAudio(id: id)
        let deletedAt = try store.recording(id: id)?.audioDeletedAt ?? recording.audioDeletedAt
        return try MCPJSON.string(Value.object([
            "ok": true, "id": .string(id),
            "audioDeletedAt": deletedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
        ]))
    }

    func retryAnalysis(_ args: ToolArgs) async throws -> String {
        let id = try args.requiredString("id")
        guard let recording = try store.recording(id: id) else {
            throw MCPToolError("No recording with id '\(id)'")
        }
        guard recording.hasAudio else {
            throw MCPToolError("Recording '\(id)' has no audio (it was deleted for privacy); analysis cannot be retried.")
        }
        switch recording.processingState {
        case .recording, .analyzing:
            throw MCPToolError("Recording '\(id)' is already \(recording.processingState.rawValue); nothing to retry.")
        case .done, .empty, .failed:
            break
        }
        let started = await runner.enqueue(id)
        return try MCPJSON.string(Value.object([
            "started": .bool(started),
            "id": .string(id),
            "note": started
                ? "Analysis queued. Poll get_recording until processingState is done/empty/failed."
                : "Analysis was already queued for this recording.",
        ]))
    }

    // MARK: - Diarization correction tools

    /// Move a mis-attributed segment to the correct (existing) speaker. Also moves the
    /// segment's voice embedding so the matcher learns from the correction.
    func reassignSegment(_ args: ToolArgs) throws -> String {
        let segmentId = Int64(try args.requiredInt("segmentId"))
        let speakerId = try args.requiredString("speakerId")
        guard let seg = try store.segment(id: segmentId) else {
            throw MCPToolError("No segment with id '\(segmentId)'")
        }
        guard try store.speaker(id: speakerId) != nil else {
            throw MCPToolError("No speaker with id '\(speakerId)'")
        }
        try store.reassignSegment(segmentId: segmentId, toSpeakerId: speakerId)
        try rerender(recordingId: seg.recordingId)
        return try MCPJSON.string(Value.object([
            "ok": true, "segmentId": .int(Int(segmentId)), "speakerId": .string(speakerId),
        ]))
    }

    /// Create a new speaker (e.g. to attribute a voice that isn't a known speaker yet).
    func createSpeaker(_ args: ToolArgs) throws -> String {
        let label = args.string("label")
        let speaker = Speaker(label: label?.isEmpty == true ? nil : label)
        try store.insertSpeaker(speaker)
        return try MCPJSON.string(SpeakerDTO(speaker))
    }

    /// Rename a speaker (or clear the label with an empty/null value). Re-renders every
    /// recording the speaker appears in so the new label shows up in the transcript files.
    func renameSpeaker(_ args: ToolArgs) throws -> String {
        let id = try args.requiredString("id")
        guard try store.speaker(id: id) != nil else {
            throw MCPToolError("No speaker with id '\(id)'")
        }
        let label = args.string("label")
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        try store.updateLabel(id: id, label: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        for appearance in try store.recordings(for: id) {
            try rerender(recordingId: appearance.recording.id)
        }
        return try MCPJSON.string(Value.object(["ok": true, "id": .string(id)]))
    }

    /// Merge two speaker identities that are the same person: all of `from`'s embeddings and
    /// segments move to `into`, then `from` is deleted.
    func mergeSpeakers(_ args: ToolArgs) throws -> String {
        let from = try args.requiredString("from")
        let into = try args.requiredString("into")
        guard from != into else { throw MCPToolError("'from' and 'into' must be different speakers") }
        guard try store.speaker(id: from) != nil else { throw MCPToolError("No speaker with id '\(from)'") }
        guard try store.speaker(id: into) != nil else { throw MCPToolError("No speaker with id '\(into)'") }
        // Capture affected recordings before the merge removes `from`.
        let affected = try store.recordings(for: from).map(\.recording.id)
        try store.mergeSpeakers(from: from, into: into)
        for recordingId in affected {
            try rerender(recordingId: recordingId)
        }
        return try MCPJSON.string(Value.object([
            "ok": true, "into": .string(into), "recordingsRerendered": .int(affected.count),
        ]))
    }

    /// Split one segment at an absolute timestamp so each half can be attributed separately.
    /// The first half keeps the original id; the second half is a new segment with the same
    /// speaker (reassign it afterwards). Returns the new segment id.
    func splitSegment(_ args: ToolArgs) throws -> String {
        let segmentId = Int64(try args.requiredInt("segmentId"))
        let atSec = try args.requiredDouble("atSec")
        guard let seg = try store.segment(id: segmentId) else {
            throw MCPToolError("No segment with id '\(segmentId)'")
        }
        let newId = try store.splitSegment(segmentId: segmentId, at: atSec)
        try rerender(recordingId: seg.recordingId)
        return try MCPJSON.string(Value.object([
            "ok": true, "segmentId": .int(Int(segmentId)), "newSegmentId": .int(Int(newId)),
        ]))
    }

    /// Re-render a recording's markdown + JSON transcript from the current DB state, so files
    /// stay consistent with diarization edits. Cheap — loads no models.
    private func rerender(recordingId: String) throws {
        let pipeline = TranscribePipeline(config: config, store: store)
        do {
            _ = try pipeline.rerender(recordingId: recordingId)
        } catch {
            throw MCPToolError("Edit saved, but re-rendering transcript files failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Resources

    func listResources() throws -> ListResources.Result {
        var resources: [Resource] = [
            Resource(
                name: "Recording status",
                uri: Self.statusURI,
                description: "Whether a recording is in progress, and which.",
                mimeType: "application/json"
            )
        ]
        let recordings = try store.recordings(matching: RecordingQuery(limit: resourceListLimit))
        resources += recordings.map { r in
            Resource(
                name: r.title ?? r.id,
                uri: Self.recordingURIPrefix + r.id,
                description: "Transcript (markdown) for recording \(r.id)",
                mimeType: "text/markdown"
            )
        }
        return ListResources.Result(resources: resources)
    }

    func readResource(uri: String) throws -> ReadResource.Result {
        if uri == Self.statusURI {
            return ReadResource.Result(contents: [
                .text(try recordingStatusJSON(), uri: uri, mimeType: "application/json")
            ])
        }
        guard uri.hasPrefix(Self.recordingURIPrefix) else {
            throw MCPToolError("Unknown resource URI: \(uri)")
        }
        let id = String(uri.dropFirst(Self.recordingURIPrefix.count))
        guard let recording = try store.recording(id: id) else {
            throw MCPToolError("No recording with id '\(id)'")
        }
        let markdown = (try? String(contentsOfFile: recording.transcriptMd, encoding: .utf8))
            ?? "# \(recording.title ?? recording.id)\n\n_(transcript file unavailable)_"
        return ReadResource.Result(contents: [.text(markdown, uri: uri, mimeType: "text/markdown")])
    }

    // MARK: - Helpers

    private func requireRecording(_ id: String) throws {
        guard try store.recording(id: id) != nil else {
            throw MCPToolError("No recording with id '\(id)'")
        }
    }

    private static func text(_ s: String) -> Tool.Content {
        .text(text: s, annotations: nil, _meta: nil)
    }

    private static func ok(_ json: String) -> CallTool.Result {
        CallTool.Result(content: [text(json)], isError: false)
    }

    private static func err(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [text(message)], isError: true)
    }
}
