import Testing
import Foundation
@testable import DiarizeCore

@Suite struct SpeakerStoreTests {

    private func makeStore() throws -> (SpeakerStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize-test-\(UUID().uuidString)")
            .appendingPathComponent("speakers.sqlite")
        let store = try SpeakerStore(path: tmp)
        return (store, tmp)
    }

    @Test func roundTripSpeakerAndEmbedding() throws {
        let (store, _) = try makeStore()
        let s = Speaker(label: "Björn")
        try store.insertSpeaker(s)
        try store.insertEmbedding(SpeakerEmbedding(speakerId: s.id, vector: [1, 2, 3, 4]))

        let speakers = try store.allSpeakers()
        #expect(speakers.count == 1)
        #expect(speakers.first?.label == "Björn")

        let embs = try store.embeddings(for: s.id)
        #expect(embs.count == 1)
        #expect(embs.first?.asFloats == [1, 2, 3, 4])
    }

    @Test func centroidsAreMeanOfEmbeddings() throws {
        let (store, _) = try makeStore()
        let s = Speaker(label: "Anna")
        try store.insertSpeaker(s)
        try store.insertEmbedding(SpeakerEmbedding(speakerId: s.id, vector: [0, 0]))
        try store.insertEmbedding(SpeakerEmbedding(speakerId: s.id, vector: [2, 4]))

        let centroids = try store.speakerCentroids()
        #expect(centroids.count == 1)
        #expect(centroids.first?.centroid == [1, 2])
    }

    @Test func mergeMovesEmbeddingsAndDeletesSource() throws {
        let (store, _) = try makeStore()
        let a = Speaker(label: "A"); let b = Speaker(label: "B")
        try store.insertSpeaker(a); try store.insertSpeaker(b)
        try store.insertEmbedding(SpeakerEmbedding(speakerId: a.id, vector: [1, 0]))
        try store.insertEmbedding(SpeakerEmbedding(speakerId: b.id, vector: [0, 1]))

        try store.mergeSpeakers(from: a.id, into: b.id)
        #expect(try store.speaker(id: a.id) == nil)
        #expect(try store.embeddings(for: b.id).count == 2)
    }

    @Test func updateLabelChangesName() throws {
        let (store, _) = try makeStore()
        let s = Speaker(label: nil)
        try store.insertSpeaker(s)
        try store.updateLabel(id: s.id, label: "Renamed")
        #expect(try store.speaker(id: s.id)?.label == "Renamed")
    }

    @Test func deleteCascadesEmbeddings() throws {
        let (store, _) = try makeStore()
        let s = Speaker(label: "X")
        try store.insertSpeaker(s)
        try store.insertEmbedding(SpeakerEmbedding(speakerId: s.id, vector: [1, 1]))
        try store.deleteSpeaker(id: s.id)
        #expect(try store.embeddings(for: s.id).isEmpty)
    }
}
