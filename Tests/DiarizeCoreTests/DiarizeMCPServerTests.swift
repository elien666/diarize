import Testing
import Foundation
import MCP
@testable import DiarizeCore

@Suite struct DiarizeMCPServerTests {
    private func makeServer() throws -> (DiarizeMCPServer, SpeakerStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
        let config = AppConfig(archivePath: dir)
        let store = try SpeakerStore(path: config.databasePath)
        return (DiarizeMCPServer(store: store, config: config), store)
    }

    @discardableResult
    private func insert(
        _ store: SpeakerStore, id: String, createdAt: Date,
        state: RecordingProcessingState = .done, errorMessage: String? = nil,
        sourcePath: String = "/dev/null", audioDeletedAt: Date? = nil
    ) throws -> Recording {
        let r = Recording(
            id: id, title: id, sourcePath: sourcePath, durationSec: 1, language: "en",
            transcriptMd: "/tmp/\(id).md", transcriptJson: "/tmp/\(id).json",
            createdAt: createdAt, processingState: state, errorMessage: errorMessage,
            audioDeletedAt: audioDeletedAt
        )
        try store.insertRecording(r, segments: [])
        if state != .done || errorMessage != nil {
            try store.setProcessingState(recordingId: id, state: state, errorMessage: errorMessage)
        }
        if let audioDeletedAt { try store.markAudioDeleted(id: id, at: audioDeletedAt) }
        return r
    }

    private func text(_ result: CallTool.Result) -> String {
        for content in result.content {
            if case let .text(t, _, _) = content { return t }
        }
        return ""
    }

    private func json(_ result: CallTool.Result) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text(result).utf8))
    }

    @Test func listRecordingsNewestFirst() async throws {
        let (server, store) = try makeServer()
        try insert(store, id: "old", createdAt: Date(timeIntervalSince1970: 1))
        try insert(store, id: "new", createdAt: Date(timeIntervalSince1970: 2))

        let result = await server.callTool(name: "list_recordings", arguments: nil)
        #expect(result.isError != true)
        let arr = try #require(try json(result) as? [[String: Any]])
        #expect(arr.map { $0["id"] as? String } == ["new", "old"])
    }

    @Test func listRecordingsFailedFilterExposesErrorMessage() async throws {
        let (server, store) = try makeServer()
        try insert(store, id: "ok", createdAt: Date(timeIntervalSince1970: 1))
        try insert(store, id: "bad", createdAt: Date(timeIntervalSince1970: 2),
                   state: .failed, errorMessage: "model load failed")

        let result = await server.callTool(name: "list_recordings", arguments: ["state": "failed"])
        let arr = try #require(try json(result) as? [[String: Any]])
        #expect(arr.count == 1)
        #expect(arr.first?["id"] as? String == "bad")
        #expect(arr.first?["errorMessage"] as? String == "model load failed")
    }

    @Test func setProcessedReportsCount() async throws {
        let (server, store) = try makeServer()
        try insert(store, id: "a", createdAt: Date(timeIntervalSince1970: 1))
        try insert(store, id: "b", createdAt: Date(timeIntervalSince1970: 2))

        let result = await server.callTool(
            name: "set_processed",
            arguments: ["ids": .array(["a", "b"]), "processed": true]
        )
        let obj = try #require(try json(result) as? [String: Any])
        #expect(obj["updated"] as? Int == 2)
        #expect(try store.recording(id: "a")?.processed == true)
    }

    @Test func createAndMoveRecording() async throws {
        let (server, store) = try makeServer()
        try insert(store, id: "rec", createdAt: Date())

        let folderResult = await server.callTool(name: "create_folder", arguments: ["name": "Work"])
        let folder = try #require(try json(folderResult) as? [String: Any])
        let folderId = try #require(folder["id"] as? String)

        let moveResult = await server.callTool(
            name: "move_recording", arguments: ["id": "rec", "folderId": .string(folderId)])
        #expect(moveResult.isError != true)
        #expect(try store.recording(id: "rec")?.folderId == folderId)
    }

    @Test func deleteAudioSetsAudioDeletedAt() async throws {
        let (server, store) = try makeServer()
        try insert(store, id: "rec", createdAt: Date())

        let result = await server.callTool(name: "delete_audio", arguments: ["id": "rec"])
        #expect(result.isError != true)
        #expect(try store.recording(id: "rec")?.hasAudio == false)
    }

    @Test func retryRejectsGdprDeletedAudio() async throws {
        let (server, store) = try makeServer()
        try insert(store, id: "rec", createdAt: Date(), state: .failed,
                   errorMessage: "x", audioDeletedAt: Date())

        let result = await server.callTool(name: "retry_analysis", arguments: ["id": "rec"])
        #expect(result.isError == true)
        #expect(text(result).contains("no audio"))
    }

    @Test func unknownToolIsError() async throws {
        let (server, _) = try makeServer()
        let result = await server.callTool(name: "does_not_exist", arguments: nil)
        #expect(result.isError == true)
    }

    @Test func missingRequiredArgIsError() async throws {
        let (server, _) = try makeServer()
        let result = await server.callTool(name: "get_recording", arguments: nil)
        #expect(result.isError == true)
        #expect(text(result).contains("id"))
    }

    @Test func recordingStatusReportsLive() async throws {
        let (server, store) = try makeServer()
        try insert(store, id: "live", createdAt: Date(), state: .recording)
        let result = await server.callTool(name: "recording_status", arguments: nil)
        let obj = try #require(try json(result) as? [String: Any])
        #expect(obj["isRecording"] as? Bool == true)
    }

    // MARK: - Diarization correction

    /// Insert a recording whose transcript files live in a writable temp dir, with one
    /// segment for `speakerId` plus an embedding aligned to that segment's time range.
    @discardableResult
    private func insertWithSegment(
        _ store: SpeakerStore, recId: String, speakerId: String
    ) throws -> Int64 {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rec = Recording(
            id: recId, title: recId, sourcePath: "/dev/null", durationSec: 10, language: "en",
            transcriptMd: dir.appendingPathComponent("\(recId).md").path,
            transcriptJson: dir.appendingPathComponent("\(recId).json").path,
            createdAt: Date()
        )
        let seg = RecordingSegment(recordingId: recId, speakerId: speakerId, startSec: 1, endSec: 3, text: "hello there", confidence: 0.9)
        try store.insertRecording(rec, segments: [seg])
        try store.insertEmbedding(SpeakerEmbedding(speakerId: speakerId, vector: [1, 0], recordingId: recId, segmentStart: 1, segmentEnd: 3))
        return try #require(try store.segments(for: recId).first?.id)
    }

    @Test func transcriptIncludesSegmentId() async throws {
        let (server, store) = try makeServer()
        let a = Speaker(label: "A"); try store.insertSpeaker(a)
        let segId = try insertWithSegment(store, recId: "rec", speakerId: a.id)

        let result = await server.callTool(name: "get_transcript", arguments: ["id": "rec"])
        let obj = try #require(try json(result) as? [String: Any])
        let segs = try #require(obj["segments"] as? [[String: Any]])
        #expect(segs.first?["id"] as? Int == Int(segId))
    }

    @Test func reassignSegmentMovesSpeakerAndEmbedding() async throws {
        let (server, store) = try makeServer()
        let a = Speaker(label: "A"); let b = Speaker(label: "B")
        try store.insertSpeaker(a); try store.insertSpeaker(b)
        let segId = try insertWithSegment(store, recId: "rec", speakerId: a.id)

        let result = await server.callTool(
            name: "reassign_segment", arguments: ["segmentId": .int(Int(segId)), "speakerId": .string(b.id)])
        #expect(result.isError != true)
        #expect(try store.segments(for: "rec").first?.speakerId == b.id)
        #expect(try store.embeddings(for: a.id).isEmpty)
        #expect(try store.embeddings(for: b.id).count == 1)
    }

    @Test func reassignSegmentRejectsUnknownSpeaker() async throws {
        let (server, store) = try makeServer()
        let a = Speaker(label: "A"); try store.insertSpeaker(a)
        let segId = try insertWithSegment(store, recId: "rec", speakerId: a.id)

        let result = await server.callTool(
            name: "reassign_segment", arguments: ["segmentId": .int(Int(segId)), "speakerId": "spk_missing"])
        #expect(result.isError == true)
        #expect(text(result).contains("speaker"))
    }

    @Test func createSpeakerReturnsNewSpeaker() async throws {
        let (server, store) = try makeServer()
        let result = await server.callTool(name: "create_speaker", arguments: ["label": "Anna"])
        let obj = try #require(try json(result) as? [String: Any])
        let id = try #require(obj["id"] as? String)
        #expect(obj["label"] as? String == "Anna")
        #expect(try store.speaker(id: id)?.label == "Anna")
    }

    @Test func renameSpeakerSetsLabel() async throws {
        let (server, store) = try makeServer()
        let s = Speaker(label: nil); try store.insertSpeaker(s)
        try insertWithSegment(store, recId: "rec", speakerId: s.id)

        let result = await server.callTool(name: "rename_speaker", arguments: ["id": .string(s.id), "label": "Björn"])
        #expect(result.isError != true)
        #expect(try store.speaker(id: s.id)?.label == "Björn")
    }

    @Test func mergeSpeakersCollapsesIdentity() async throws {
        let (server, store) = try makeServer()
        let a = Speaker(label: "A"); let b = Speaker(label: "B")
        try store.insertSpeaker(a); try store.insertSpeaker(b)
        try insertWithSegment(store, recId: "rec", speakerId: a.id)

        let result = await server.callTool(name: "merge_speakers", arguments: ["from": .string(a.id), "into": .string(b.id)])
        #expect(result.isError != true)
        #expect(try store.speaker(id: a.id) == nil)
        #expect(try store.segments(for: "rec").first?.speakerId == b.id)
    }

    @Test func mergeSpeakersRejectsSameId() async throws {
        let (server, store) = try makeServer()
        let a = Speaker(label: "A"); try store.insertSpeaker(a)
        let result = await server.callTool(name: "merge_speakers", arguments: ["from": .string(a.id), "into": .string(a.id)])
        #expect(result.isError == true)
    }

    @Test func splitSegmentReturnsNewId() async throws {
        let (server, store) = try makeServer()
        let a = Speaker(label: "A"); try store.insertSpeaker(a)
        let segId = try insertWithSegment(store, recId: "rec", speakerId: a.id)

        let result = await server.callTool(
            name: "split_segment", arguments: ["segmentId": .int(Int(segId)), "atSec": .double(2.0)])
        #expect(result.isError != true)
        let obj = try #require(try json(result) as? [String: Any])
        #expect(obj["newSegmentId"] as? Int != nil)
        #expect(try store.segments(for: "rec").count == 2)
    }
}
