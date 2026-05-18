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
    private weak var progress: ProgressReporter?

    public init(config: ASRConfig = .default, progress: ProgressReporter? = nil) {
        self.manager = AsrManager(config: config)
        self.progress = progress
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
        let total = diarized.count

        // Throttled progress: report every N segments or every 2 seconds, whichever comes first.
        var lastReported = Date(timeIntervalSince1970: 0)
        let reportEvery = max(1, total / 50)

        for (idx, seg) in diarized.enumerated() {
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

            let now = Date()
            let shouldReport = (idx + 1) == total
                || (idx + 1) % reportEvery == 0
                || now.timeIntervalSince(lastReported) >= 2.0
            if shouldReport {
                let pct = Int((Double(idx + 1) / Double(total)) * 100)
                progress?.step("Transcribing [\(idx + 1)/\(total)] \(pct)%")
                lastReported = now
            }
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
