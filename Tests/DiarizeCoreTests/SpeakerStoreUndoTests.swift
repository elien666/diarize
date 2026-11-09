import Testing
import Foundation
@testable import DiarizeCore

@Suite struct SpeakerStoreUndoTests {
    private func makeStore() throws -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
            .appendingPathComponent("speakers.sqlite")
        return try SpeakerStore(path: tmp)
    }

    private func seed(_ store: SpeakerStore) throws -> Int64 {
        try store.insertSpeaker(Speaker(id: "spk_a", label: "A"))
        try store.insertSpeaker(Speaker(id: "spk_b", label: "B"))
        let seg = RecordingSegment(recordingId: "rec_1", speakerId: "spk_a", startSec: 1, endSec: 3, text: "hi", confidence: 1)
        let rec = Recording(id: "rec_1", title: "t", sourcePath: "/dev/null", durationSec: 5, language: "en",
                            transcriptMd: "/tmp/x.md", transcriptJson: "/tmp/x.json")
        try store.insertRecording(rec, segments: [seg])
        try store.insertEmbedding(SpeakerEmbedding(speakerId: "spk_a", vector: [1, 0], recordingId: "rec_1", segmentStart: 1, segmentEnd: 3))
        return try store.segments(for: "rec_1")[0].id!
    }

    @Test func reassignUndoRestoresSegmentAndEmbedding() throws {
        let store = try makeStore()
        let segId = try seed(store)
        let snap = try #require(try store.reassignSnapshot(segmentId: segId, createdSpeakerId: nil))
        try store.reassignSegment(segmentId: segId, toSpeakerId: "spk_b")
        #expect(try store.embeddings(for: "spk_b").count == 1)
        try store.restoreReassign(snap)
        #expect(try store.segments(for: "rec_1")[0].speakerId == "spk_a")
        #expect(try store.embeddings(for: "spk_a").count == 1)
        #expect(try store.embeddings(for: "spk_b").isEmpty)
    }

    @Test func reassignUndoRemovesCreatedSpeaker() throws {
        let store = try makeStore()
        let segId = try seed(store)
        try store.insertSpeaker(Speaker(id: "spk_new"))
        let snap = try #require(try store.reassignSnapshot(segmentId: segId, createdSpeakerId: "spk_new"))
        try store.reassignSegment(segmentId: segId, toSpeakerId: "spk_new")
        try store.restoreReassign(snap)
        #expect(try store.allSpeakers().contains { $0.id == "spk_new" } == false)
    }

    @Test func mergeUndoRecreatesSpeakerWithData() throws {
        let store = try makeStore()
        _ = try seed(store)
        let snap = try #require(try store.mergeSnapshot(from: "spk_a", into: "spk_b"))
        try store.mergeSpeakers(from: "spk_a", into: "spk_b")
        #expect(try store.allSpeakers().contains { $0.id == "spk_a" } == false)
        try store.restoreMerge(snap)
        #expect(try store.allSpeakers().first { $0.id == "spk_a" }?.label == "A")
        #expect(try store.segments(for: "rec_1")[0].speakerId == "spk_a")
        #expect(try store.embeddings(for: "spk_a").count == 1)
        #expect(try store.embeddings(for: "spk_b").isEmpty)
    }
}
