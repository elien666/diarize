import Testing
import Foundation
@testable import DiarizeCore

@Suite struct SpeakerStoreMCPTests {
    private func makeStore() throws -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
            .appendingPathComponent("speakers.sqlite")
        return try SpeakerStore(path: tmp)
    }

    @discardableResult
    private func insert(
        _ store: SpeakerStore,
        id: String,
        createdAt: Date,
        folderId: String? = nil,
        state: RecordingProcessingState = .done,
        errorMessage: String? = nil,
        segments: [RecordingSegment] = []
    ) throws -> Recording {
        let r = Recording(
            id: id, title: id, sourcePath: "/dev/null", durationSec: 1,
            language: "en", transcriptMd: "/tmp/\(id).md", transcriptJson: "/tmp/\(id).json",
            createdAt: createdAt, processingState: state, errorMessage: errorMessage,
            folderId: folderId
        )
        try store.insertRecording(r, segments: segments)
        if state != .done || errorMessage != nil {
            try store.setProcessingState(recordingId: id, state: state, errorMessage: errorMessage)
        }
        return r
    }

    @Test func processedDefaultsToFalse() throws {
        let store = try makeStore()
        try insert(store, id: "rec_a", createdAt: Date())
        let r = try store.recording(id: "rec_a")
        #expect(r?.processed == false)
        #expect(r?.processedAt == nil)
    }

    @Test func setProcessedBulkMarksAndClears() throws {
        let store = try makeStore()
        try insert(store, id: "a", createdAt: Date(timeIntervalSince1970: 1))
        try insert(store, id: "b", createdAt: Date(timeIntervalSince1970: 2))
        try insert(store, id: "c", createdAt: Date(timeIntervalSince1970: 3))

        let updated = try store.setProcessed(ids: ["a", "b"], processedAt: Date())
        #expect(updated == 2)
        #expect(try store.recording(id: "a")?.processed == true)
        #expect(try store.recording(id: "b")?.processed == true)
        #expect(try store.recording(id: "c")?.processed == false)

        let cleared = try store.setProcessed(ids: ["a"], processedAt: nil)
        #expect(cleared == 1)
        #expect(try store.recording(id: "a")?.processed == false)
    }

    @Test func filterUnprocessedNewestFirst() throws {
        let store = try makeStore()
        try insert(store, id: "old", createdAt: Date(timeIntervalSince1970: 1))
        try insert(store, id: "new", createdAt: Date(timeIntervalSince1970: 2))
        try store.setProcessed(ids: ["old"], processedAt: Date())

        let unprocessed = try store.recordings(matching: RecordingQuery(processed: false))
        #expect(unprocessed.map(\.id) == ["new"])

        let all = try store.recordings(matching: RecordingQuery())
        #expect(all.map(\.id) == ["new", "old"])  // newest first
    }

    @Test func filterByFolderAndRoot() throws {
        let store = try makeStore()
        let folder = try store.insertFolder(RecordingFolder(name: "Work"))
        try insert(store, id: "infolder", createdAt: Date(timeIntervalSince1970: 1), folderId: folder.id)
        try insert(store, id: "atroot", createdAt: Date(timeIntervalSince1970: 2))

        let inFolder = try store.recordings(matching:
            RecordingQuery(folderId: folder.id, folderFilterActive: true))
        #expect(inFolder.map(\.id) == ["infolder"])

        let atRoot = try store.recordings(matching:
            RecordingQuery(folderId: nil, folderFilterActive: true))
        #expect(atRoot.map(\.id) == ["atroot"])
    }

    @Test func filterByStateFailed() throws {
        let store = try makeStore()
        try insert(store, id: "ok", createdAt: Date(timeIntervalSince1970: 1))
        try insert(store, id: "bad", createdAt: Date(timeIntervalSince1970: 2),
                   state: .failed, errorMessage: "boom")

        let failed = try store.recordings(matching: RecordingQuery(state: .failed))
        #expect(failed.map(\.id) == ["bad"])
        #expect(failed.first?.errorMessage == "boom")
    }

    @Test func searchNarrowsToMatchingSegments() throws {
        let store = try makeStore()
        let seg = RecordingSegment(recordingId: "hit", speakerId: nil, startSec: 0, endSec: 1,
                                   text: "the kangaroo jumped", confidence: nil)
        try insert(store, id: "hit", createdAt: Date(timeIntervalSince1970: 1), segments: [seg])
        try insert(store, id: "miss", createdAt: Date(timeIntervalSince1970: 2))

        let results = try store.recordings(matching: RecordingQuery(searchText: "kangaroo"))
        #expect(results.map(\.id) == ["hit"])
    }

    @Test func limitIsHonored() throws {
        let store = try makeStore()
        for i in 0..<5 { try insert(store, id: "r\(i)", createdAt: Date(timeIntervalSince1970: Double(i))) }
        #expect(try store.recordings(matching: RecordingQuery(limit: 2)).count == 2)
    }

    @Test func isRecordingNowReflectsState() throws {
        let store = try makeStore()
        try insert(store, id: "live", createdAt: Date(), state: .recording)
        #expect(try store.isRecordingNow() == true)
        #expect(try store.recordingInProgress().map(\.id) == ["live"])

        try store.setProcessingState(recordingId: "live", state: .done)
        #expect(try store.isRecordingNow() == false)
    }

    @Test func deleteAudioFlagsAndRemovesFile() throws {
        let store = try makeStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wav = dir.appendingPathComponent("audio.wav")
        try Data("fake".utf8).write(to: wav)

        let r = Recording(id: "rec_audio", title: nil, sourcePath: wav.path, durationSec: 1,
                          language: "en", transcriptMd: "/tmp/a.md", transcriptJson: "/tmp/a.json")
        try store.insertRecording(r, segments: [])

        try store.deleteAudio(id: "rec_audio")
        #expect(FileManager.default.fileExists(atPath: wav.path) == false)
        #expect(try store.recording(id: "rec_audio")?.hasAudio == false)
    }
}
