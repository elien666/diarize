import Foundation

public enum JSONRenderer {
    public struct SpeakerSummary: Codable {
        public let id: String
        public let label: String
        public let segmentCount: Int
    }

    public struct SegmentDTO: Codable {
        public let start: Double
        public let end: Double
        public let speakerId: String?
        public let speakerLabel: String?
        public let text: String
        public let confidence: Double?
    }

    public struct TranscriptDocument: Codable {
        public let recordingId: String
        public let title: String?
        public let language: String
        public let durationSec: Double
        public let createdAt: Date
        public let speakers: [SpeakerSummary]
        public let segments: [SegmentDTO]
    }

    public static func render(
        recording: Recording,
        segments: [RecordingSegment],
        speakerLabel: (String) -> String
    ) throws -> Data {
        var counts: [String: Int] = [:]
        for s in segments { if let id = s.speakerId { counts[id, default: 0] += 1 } }

        let speakers = counts
            .map { SpeakerSummary(id: $0.key, label: speakerLabel($0.key), segmentCount: $0.value) }
            .sorted { $0.segmentCount > $1.segmentCount }

        let segs = segments.map { s in
            SegmentDTO(
                start: s.startSec,
                end: s.endSec,
                speakerId: s.speakerId,
                speakerLabel: s.speakerId.map { speakerLabel($0) },
                text: s.text,
                confidence: s.confidence
            )
        }

        let doc = TranscriptDocument(
            recordingId: recording.id,
            title: recording.title,
            language: recording.language,
            durationSec: recording.durationSec,
            createdAt: recording.createdAt,
            speakers: speakers,
            segments: segs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(doc)
    }
}
