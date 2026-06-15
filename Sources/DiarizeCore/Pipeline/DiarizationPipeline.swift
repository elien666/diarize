import Foundation
import FluidAudio

public struct LocalDiarizedSegment: Sendable {
    public let localSpeakerId: String       // diarizer-internal id (e.g. "Speaker 1")
    public let startSec: Double
    public let endSec: Double
    public let qualityScore: Float
    public let embedding: [Float]           // 256-dim, per-segment

    public var durationSec: Double { endSec - startSec }
}

public struct DiarizationOutput: Sendable {
    public let segments: [LocalDiarizedSegment]
    /// Diarizer-internal speaker id → centroid embedding (mean across segments).
    public let speakerCentroids: [String: [Float]]

    /// Merge diarization results from two separate channels (mic + system) into one
    /// timeline, prefixing speaker IDs to keep them distinct across channels.
    public static func merged(mic: DiarizationOutput, system: DiarizationOutput, micPrefix: String, systemPrefix: String) -> DiarizationOutput {
        let micSegments = mic.segments.map { seg in
            LocalDiarizedSegment(
                localSpeakerId: "\(micPrefix)-\(seg.localSpeakerId)",
                startSec: seg.startSec,
                endSec: seg.endSec,
                qualityScore: seg.qualityScore,
                embedding: seg.embedding
            )
        }
        let sysSegments = system.segments.map { seg in
            LocalDiarizedSegment(
                localSpeakerId: "\(systemPrefix)-\(seg.localSpeakerId)",
                startSec: seg.startSec,
                endSec: seg.endSec,
                qualityScore: seg.qualityScore,
                embedding: seg.embedding
            )
        }
        let allSegments = (micSegments + sysSegments).sorted { $0.startSec < $1.startSec }

        var centroids: [String: [Float]] = [:]
        for (id, emb) in mic.speakerCentroids { centroids["\(micPrefix)-\(id)"] = emb }
        for (id, emb) in system.speakerCentroids { centroids["\(systemPrefix)-\(id)"] = emb }

        return DiarizationOutput(segments: allSegments, speakerCentroids: centroids)
    }
}

public final class DiarizationPipeline {
    private let manager: OfflineDiarizerManager

    public init(config: OfflineDiarizerConfig = .default) {
        self.manager = OfflineDiarizerManager(config: config)
    }

    public func prepareModels() async throws {
        try await manager.prepareModels()
    }

    public func diarize(samples: [Float]) async throws -> DiarizationOutput {
        let result = try await manager.process(audio: samples)

        let segments = result.segments.map { seg in
            LocalDiarizedSegment(
                localSpeakerId: seg.speakerId,
                startSec: Double(seg.startTimeSeconds),
                endSec: Double(seg.endTimeSeconds),
                qualityScore: seg.qualityScore,
                embedding: seg.embedding
            )
        }

        // Prefer the diarizer's own speakerDatabase (cluster centroids); fall back to per-segment mean.
        let centroids: [String: [Float]]
        if let db = result.speakerDatabase, !db.isEmpty {
            centroids = db
        } else {
            var grouped: [String: [[Float]]] = [:]
            for seg in segments where !seg.embedding.isEmpty {
                grouped[seg.localSpeakerId, default: []].append(seg.embedding)
            }
            centroids = grouped.compactMapValues { MathUtil.mean(of: $0) }
        }

        return DiarizationOutput(segments: segments, speakerCentroids: centroids)
    }
}
