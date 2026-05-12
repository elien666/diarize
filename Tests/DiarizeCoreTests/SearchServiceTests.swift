import Testing
import Foundation
@testable import DiarizeCore

@Suite struct SearchServiceTests {

    private func makeStoreWithFixture() throws -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
            .appendingPathComponent("speakers.sqlite")
        let store = try SpeakerStore(path: tmp)

        let bjorn = Speaker(label: "Björn"); try store.insertSpeaker(bjorn)
        let bauer = Speaker(label: "Bauer"); try store.insertSpeaker(bauer)

        let rec = Recording(
            id: "rec_test",
            title: "Test Meeting",
            sourcePath: "/dev/null",
            durationSec: 120,
            language: "de",
            transcriptMd: "/tmp/x.md",
            transcriptJson: "/tmp/x.json"
        )
        let segs = [
            RecordingSegment(recordingId: rec.id, speakerId: bjorn.id, startSec: 0, endSec: 5,
                             text: "Lass uns über die Stripe API reden.", confidence: 0.9),
            RecordingSegment(recordingId: rec.id, speakerId: bauer.id, startSec: 5, endSec: 12,
                             text: "Ja klar, der Wrapper ist sowieso veraltet.", confidence: 0.8),
            RecordingSegment(recordingId: rec.id, speakerId: bjorn.id, startSec: 12, endSec: 18,
                             text: "Wir migrieren also direkt auf die Stripe Schnittstelle.", confidence: 0.92),
        ]
        try store.insertRecording(rec, segments: segs)
        return store
    }

    @Test func findsSegmentByKeyword() throws {
        let store = try makeStoreWithFixture()
        let svc = SearchService(store: store)
        let hits = try svc.search(query: "stripe")
        #expect(hits.count == 2)
        #expect(hits.allSatisfy { $0.snippet.contains("<mark>") })
    }

    @Test func multiWordIsAndJoined() throws {
        let store = try makeStoreWithFixture()
        let svc = SearchService(store: store)
        let hits = try svc.search(query: "stripe schnittstelle")
        #expect(hits.count == 1)
        #expect(hits.first?.startSec == 12)
    }

    @Test func noResultsReturnsEmpty() throws {
        let store = try makeStoreWithFixture()
        let svc = SearchService(store: store)
        #expect(try svc.search(query: "kubernetes").isEmpty)
    }

    @Test func emptyQueryReturnsEmpty() throws {
        let store = try makeStoreWithFixture()
        let svc = SearchService(store: store)
        #expect(try svc.search(query: "   ").isEmpty)
    }

    @Test func diacriticsAreStripped() throws {
        let store = try makeStoreWithFixture()
        let svc = SearchService(store: store)
        // "über" should be findable with "uber"
        let hits = try svc.search(query: "uber")
        #expect(hits.count == 1)
    }
}
