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
}
