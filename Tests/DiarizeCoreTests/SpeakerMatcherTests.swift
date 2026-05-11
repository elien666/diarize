import Testing
import Foundation
@testable import DiarizeCore

@Suite struct SpeakerMatcherTests {

    private func makeStore() throws -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
            .appendingPathComponent("speakers.sqlite")
        return try SpeakerStore(path: tmp)
    }

    @Test func firstCallCreatesNewSpeaker() throws {
        let store = try makeStore()
        let matcher = try SpeakerMatcher(store: store, threshold: 0.75)
        let res = try matcher.matchOrCreate(centroid: [1, 0, 0], recordingId: nil, segmentRange: nil)
        #expect(res.isNew)
        #expect(try store.allSpeakers().count == 1)
    }

    @Test func similarVectorMatchesExisting() throws {
        let store = try makeStore()
        var matcher = try SpeakerMatcher(store: store, threshold: 0.75)
        let first = try matcher.matchOrCreate(centroid: [1, 0, 0], recordingId: nil, segmentRange: nil)

        // Re-init matcher to test cache rebuild
        matcher = try SpeakerMatcher(store: store, threshold: 0.75)
        let second = try matcher.matchOrCreate(centroid: [0.95, 0.1, 0.0], recordingId: nil, segmentRange: nil)

        #expect(!second.isNew)
        #expect(second.speakerId == first.speakerId)
        #expect(try store.allSpeakers().count == 1)
        // Centroid should now have two embeddings stored
        #expect(try store.embeddings(for: first.speakerId).count == 2)
    }

    @Test func dissimilarVectorCreatesNewSpeaker() throws {
        let store = try makeStore()
        let matcher = try SpeakerMatcher(store: store, threshold: 0.75)
        _ = try matcher.matchOrCreate(centroid: [1, 0, 0], recordingId: nil, segmentRange: nil)
        let second = try matcher.matchOrCreate(centroid: [0, 1, 0], recordingId: nil, segmentRange: nil)
        #expect(second.isNew)
        #expect(try store.allSpeakers().count == 2)
    }

    @Test func thresholdZeroAlwaysMatches() throws {
        let store = try makeStore()
        let matcher = try SpeakerMatcher(store: store, threshold: -1.0)
        _ = try matcher.matchOrCreate(centroid: [1, 0], recordingId: nil, segmentRange: nil)
        let second = try matcher.matchOrCreate(centroid: [0, 1], recordingId: nil, segmentRange: nil)
        #expect(!second.isNew)
        #expect(try store.allSpeakers().count == 1)
    }
}
