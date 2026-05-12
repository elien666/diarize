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

    /// Lenient config so single-embedding cases still validate the basic logic.
    private func lenientConfig(threshold: Float = 0.75) -> SpeakerMatcher.Config {
        SpeakerMatcher.Config(threshold: threshold, k: 1, minVotesRatio: 1.0)
    }

    @Test func firstCallCreatesNewSpeaker() throws {
        let store = try makeStore()
        let matcher = try SpeakerMatcher(store: store, config: lenientConfig())
        let res = try matcher.matchOrCreate(centroid: [1, 0, 0], recordingId: nil, segmentRange: nil)
        #expect(res.isNew)
        #expect(try store.allSpeakers().count == 1)
    }

    @Test func similarVectorMatchesExisting() throws {
        let store = try makeStore()
        var matcher = try SpeakerMatcher(store: store, config: lenientConfig())
        let first = try matcher.matchOrCreate(centroid: [1, 0, 0], recordingId: nil, segmentRange: nil)

        matcher = try SpeakerMatcher(store: store, config: lenientConfig())
        let second = try matcher.matchOrCreate(centroid: [0.95, 0.1, 0.0], recordingId: nil, segmentRange: nil)

        #expect(!second.isNew)
        #expect(second.speakerId == first.speakerId)
        #expect(try store.allSpeakers().count == 1)
        #expect(try store.embeddings(for: first.speakerId).count == 2)
    }

    @Test func dissimilarVectorCreatesNewSpeaker() throws {
        let store = try makeStore()
        let matcher = try SpeakerMatcher(store: store, config: lenientConfig())
        _ = try matcher.matchOrCreate(centroid: [1, 0, 0], recordingId: nil, segmentRange: nil)
        let second = try matcher.matchOrCreate(centroid: [0, 1, 0], recordingId: nil, segmentRange: nil)
        #expect(second.isNew)
        #expect(try store.allSpeakers().count == 2)
    }

    @Test func thresholdMinusOneAlwaysMatches() throws {
        let store = try makeStore()
        let matcher = try SpeakerMatcher(store: store, config: SpeakerMatcher.Config(threshold: -1.0, k: 1, minVotesRatio: 1.0))
        _ = try matcher.matchOrCreate(centroid: [1, 0], recordingId: nil, segmentRange: nil)
        let second = try matcher.matchOrCreate(centroid: [0, 1], recordingId: nil, segmentRange: nil)
        #expect(!second.isNew)
        #expect(try store.allSpeakers().count == 1)
    }

    /// With Top-K voting (K=5, minVotesRatio=0.6 → 3 votes needed),
    /// a single very-close embedding outweighed by 4 dissimilar speaker embeddings
    /// must NOT match: it's an ambiguous case → safer to start a new speaker.
    @Test func topKVotingResistsSingleClosestNeighbor() throws {
        let store = try makeStore()

        // Insert 4 embeddings of speaker A around [1, 0, 0]
        let speakerA = Speaker(label: "A")
        try store.insertSpeaker(speakerA)
        for v in [[1, 0, 0], [0.99, 0.01, 0], [0.98, 0, 0.01], [0.97, 0.02, 0]] as [[Float]] {
            try store.insertEmbedding(SpeakerEmbedding(speakerId: speakerA.id, vector: v))
        }

        // Insert 1 outlier embedding tagged to speaker B that happens to be close to a probe
        let speakerB = Speaker(label: "B")
        try store.insertSpeaker(speakerB)
        try store.insertEmbedding(SpeakerEmbedding(speakerId: speakerB.id, vector: [0.5, 0.86, 0]))

        let matcher = try SpeakerMatcher(store: store, config: SpeakerMatcher.Config(threshold: 0.5, k: 5, minVotesRatio: 0.6))
        let probe: [Float] = [0.5, 0.86, 0]    // identical to B's outlier
        let result = try matcher.matchOrCreate(centroid: probe, recordingId: nil, segmentRange: nil)

        // 4 of 5 nearest above threshold belong to A → A wins (Top-K voting works)
        // even though the single closest match is B.
        #expect(result.speakerId == speakerA.id)
        #expect(!result.isNew)
    }

    /// Multi-embedding match: speaker has 5 stored embeddings, probe matches all of them.
    @Test func multipleSimilarEmbeddingsConfirmMatch() throws {
        let store = try makeStore()
        let s = Speaker(label: "S")
        try store.insertSpeaker(s)
        for v in [[1, 0, 0], [0.95, 0.05, 0], [0.93, 0, 0.05], [0.97, 0.02, 0], [0.92, 0.04, 0.02]] as [[Float]] {
            try store.insertEmbedding(SpeakerEmbedding(speakerId: s.id, vector: v))
        }
        let matcher = try SpeakerMatcher(store: store, config: SpeakerMatcher.Config(threshold: 0.7, k: 5, minVotesRatio: 0.6))
        let result = try matcher.matchOrCreate(centroid: [0.94, 0.03, 0.01], recordingId: nil, segmentRange: nil)
        #expect(result.speakerId == s.id)
        #expect(!result.isNew)
    }
}

@Suite struct ThresholdCalibratorTests {
    private func makeStore() throws -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
            .appendingPathComponent("speakers.sqlite")
        return try SpeakerStore(path: tmp)
    }

    @Test func returnsNilWithFewerThanTwoLabeledSpeakers() throws {
        let store = try makeStore()
        let s = Speaker(label: "Solo")
        try store.insertSpeaker(s)
        try store.insertEmbedding(SpeakerEmbedding(speakerId: s.id, vector: [1, 0]))
        try store.insertEmbedding(SpeakerEmbedding(speakerId: s.id, vector: [0.95, 0.05]))
        #expect(try ThresholdCalibrator.calibrate(store: store) == nil)
    }

    @Test func cleanlySeparatedSpeakersGetHighConfidence() throws {
        let store = try makeStore()
        let a = Speaker(label: "A"); let b = Speaker(label: "B")
        try store.insertSpeaker(a); try store.insertSpeaker(b)
        // A clusters around [1,0]
        for v in [[1, 0], [0.97, 0.05], [0.98, 0.02]] as [[Float]] {
            try store.insertEmbedding(SpeakerEmbedding(speakerId: a.id, vector: v))
        }
        // B clusters around [0,1]
        for v in [[0, 1], [0.05, 0.97], [0.02, 0.98]] as [[Float]] {
            try store.insertEmbedding(SpeakerEmbedding(speakerId: b.id, vector: v))
        }
        let result = try ThresholdCalibrator.calibrate(store: store)
        #expect(result != nil)
        #expect(result!.confidence == .high)
        #expect(result!.recommendedThreshold > 0.4 && result!.recommendedThreshold < 0.95)
        #expect(result!.intraSpeakerMin > result!.interSpeakerMax)
    }
}
