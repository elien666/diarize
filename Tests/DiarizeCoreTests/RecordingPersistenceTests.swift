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
