import Testing
import Foundation
@testable import DiarizeCore

@Suite struct RecordingPersistenceTests {
    private func makeStore() throws -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
            .appendingPathComponent("speakers.sqlite")
        return try SpeakerStore(path: tmp)
    }

    @Test func sourceHashRoundtrip() throws {
        let store = try makeStore()
        let r = Recording(
            id: "rec_x",
            title: "Test",
            sourcePath: "/dev/null",
            durationSec: 12.3,
            language: "de",
            transcriptMd: "/tmp/x.md",
            transcriptJson: "/tmp/x.json",
            sourceHash: "deadbeef"
        )
        try store.insertRecording(r, segments: [])
        let back = try store.recording(id: "rec_x")
        #expect(back?.sourceHash == "deadbeef")
    }

    @Test func updateSegmentSpeakerWorks() throws {
        let store = try makeStore()
        let bjorn = Speaker(label: "Björn"); try store.insertSpeaker(bjorn)
        let bauer = Speaker(label: "Bauer"); try store.insertSpeaker(bauer)
        let r = Recording(id: "rec_seg", title: nil, sourcePath: "/dev/null", durationSec: 10,
                          language: "de", transcriptMd: "/tmp/m.md", transcriptJson: "/tmp/j.json")
        let seg = RecordingSegment(recordingId: r.id, speakerId: bjorn.id, startSec: 0, endSec: 5,
                                   text: "Hi", confidence: 0.9)
        try store.insertRecording(r, segments: [seg])
        let segId = try store.segments(for: r.id).first!.id!
        try store.updateSegmentSpeaker(segmentId: segId, speakerId: bauer.id)
        #expect(try store.segment(id: segId)?.speakerId == bauer.id)
    }

    @Test func splitSegmentInsertsHalves() throws {
        let store = try makeStore()
        let s = Speaker(label: "S"); try store.insertSpeaker(s)
        let r = Recording(id: "rec_split", title: nil, sourcePath: "/dev/null", durationSec: 10,
                          language: "de", transcriptMd: "/tmp/m.md", transcriptJson: "/tmp/j.json")
        let seg = RecordingSegment(recordingId: r.id, speakerId: s.id, startSec: 0, endSec: 10,
                                   text: "eins zwei drei vier fünf sechs", confidence: 0.9)
        try store.insertRecording(r, segments: [seg])
        let segId = try store.segments(for: r.id).first!.id!
        let newId = try store.splitSegment(segmentId: segId, at: 5.0)
        let segs = try store.segments(for: r.id)
        #expect(segs.count == 2)
        #expect(segs.first!.endSec == 5.0)
        #expect(segs.last!.id == newId)
        #expect(segs.last!.startSec == 5.0)
        #expect(segs.last!.endSec == 10.0)
        #expect(!segs.first!.text.isEmpty)
        #expect(!segs.last!.text.isEmpty)
    }

    @Test func markAudioDeletedSetsTimestampAndKeepsTranscript() throws {
        let store = try makeStore()
        let s = Speaker(label: "S"); try store.insertSpeaker(s)
        let r = Recording(id: "rec_gdpr", title: nil, sourcePath: "/dev/null", durationSec: 10,
                          language: "de", transcriptMd: "/tmp/m.md", transcriptJson: "/tmp/j.json")
        let seg = RecordingSegment(recordingId: r.id, speakerId: s.id, startSec: 0, endSec: 5,
                                   text: "Hallo", confidence: 0.9)
        try store.insertRecording(r, segments: [seg])

        #expect(try store.recording(id: "rec_gdpr")?.hasAudio == true)
        try store.markAudioDeleted(id: "rec_gdpr")

        let back = try store.recording(id: "rec_gdpr")
        #expect(back?.audioDeletedAt != nil)
        #expect(back?.hasAudio == false)
        // Transcript + segments are untouched.
        #expect(try store.segments(for: "rec_gdpr").count == 1)
    }

    @Test func lookupByHashFindsRecording() throws {
        let store = try makeStore()
        let r = Recording(
            id: "rec_y",
            title: nil,
            sourcePath: "/dev/null",
            durationSec: 1,
            language: "en",
            transcriptMd: "/tmp/y.md",
            transcriptJson: "/tmp/y.json",
            sourceHash: "cafebabe"
        )
        try store.insertRecording(r, segments: [])
        #expect(try store.recording(sourceHash: "cafebabe")?.id == "rec_y")
        #expect(try store.recording(sourceHash: "nope") == nil)
    }
}
