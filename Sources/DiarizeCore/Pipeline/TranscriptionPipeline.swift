import Foundation
import FluidAudio

public struct TranscribedSegment: Sendable {
    public let startSec: Double
    public let endSec: Double
    public let localSpeakerId: String
    public let text: String
    public let confidence: Double
}

public final class TranscriptionPipeline {
    private let manager: AsrManager
    private var loaded: Bool = false

    public init(config: ASRConfig = .default) {
        self.manager = AsrManager(config: config)
    }

    public func loadModels(version: AsrModelVersion = .v3) async throws {
        guard !loaded else { return }
        let models = try await AsrModels.downloadAndLoad(version: version)
        try await manager.loadModels(models)
        loaded = true
    }

    /// Transcribe each diarized segment using the segment's audio slice.
    /// Resets the decoder state per segment to avoid cross-speaker token leakage.
    public func transcribe(
        diarized: [LocalDiarizedSegment],
        samples: [Float],
        sampleRate: Int = 16000,
        language: Language? = nil
    ) async throws -> [TranscribedSegment] {
        var out: [TranscribedSegment] = []
        out.reserveCapacity(diarized.count)

        for seg in diarized {
            let startIdx = max(0, Int(seg.startSec * Double(sampleRate)))
            let endIdx = min(samples.count, Int(seg.endSec * Double(sampleRate)))
            guard endIdx > startIdx else { continue }
            let slice = Array(samples[startIdx..<endIdx])

            // Skip very short segments (< 0.2s) — Parakeet needs minimum samples.
            guard slice.count >= sampleRate / 5 else { continue }

            var decoder = try TdtDecoderState()
            let result = try await manager.transcribe(slice, decoderState: &decoder, language: language)
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            out.append(TranscribedSegment(
                startSec: seg.startSec,
                endSec: seg.endSec,
                localSpeakerId: seg.localSpeakerId,
                text: trimmed,
                confidence: Double(result.confidence)
            ))
        }

        return out
    }

    public static func language(for code: AppConfig.Language) -> Language? {
        switch code {
        case .de: return .german
        case .en: return .english
        case .auto: return nil
        }
    }
}
