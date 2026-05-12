import Foundation

public struct CalibrationResult: Sendable {
    public let recommendedThreshold: Float
    public let intraSpeakerMin: Float       // worst (lowest) similarity within same speaker
    public let intraSpeakerMean: Float
    public let interSpeakerMax: Float       // best (highest) similarity across different speakers
    public let interSpeakerMean: Float
    public let labeledSpeakers: Int
    public let confidence: Confidence

    public enum Confidence: String, Sendable {
        case low        // bands overlap → recommendation is a heuristic
        case medium
        case high       // clean gap between intra and inter
    }
}

/// Computes a recommended similarity threshold from the labeled speakers in the store.
/// Idea: pairs of embeddings within the same labeled speaker should match (intra),
/// pairs across different labeled speakers should not (inter). The optimal threshold
/// sits between the two distributions.
public enum ThresholdCalibrator {

    public static func calibrate(store: SpeakerStore) throws -> CalibrationResult? {
        let labeled = try store.allSpeakers().filter { $0.label != nil }
        guard labeled.count >= 2 else { return nil }

        var perSpeaker: [(id: String, vectors: [[Float]])] = []
        for s in labeled {
            let embs = try store.embeddings(for: s.id).map { $0.asFloats }
            if embs.count >= 1 { perSpeaker.append((s.id, embs)) }
        }
        guard perSpeaker.count >= 2 else { return nil }

        var intra: [Float] = []
        for entry in perSpeaker where entry.vectors.count >= 2 {
            for i in 0..<entry.vectors.count {
                for j in (i + 1)..<entry.vectors.count {
                    intra.append(MathUtil.cosineSimilarity(entry.vectors[i], entry.vectors[j]))
                }
            }
        }

        var inter: [Float] = []
        for i in 0..<perSpeaker.count {
            for j in (i + 1)..<perSpeaker.count {
                for a in perSpeaker[i].vectors {
                    for b in perSpeaker[j].vectors {
                        inter.append(MathUtil.cosineSimilarity(a, b))
                    }
                }
            }
        }

        guard !inter.isEmpty else { return nil }

        let intraMin = intra.min() ?? 1.0
        let intraMean = intra.isEmpty ? 1.0 : intra.reduce(0, +) / Float(intra.count)
        let interMax = inter.max() ?? 0.0
        let interMean = inter.reduce(0, +) / Float(inter.count)

        // If bands are clean (intraMin > interMax), midpoint is ideal.
        // Otherwise fall back to mean-of-means (still better than a fixed default).
        let recommended: Float
        let confidence: CalibrationResult.Confidence
        if intraMin > interMax {
            recommended = (intraMin + interMax) / 2
            confidence = .high
        } else if intraMean > interMean {
            recommended = (intraMean + interMean) / 2
            confidence = .medium
        } else {
            // Bands fully overlap: data quality issue. Suggest a conservative value.
            recommended = max(0.55, interMean)
            confidence = .low
        }

        return CalibrationResult(
            recommendedThreshold: max(0.3, min(0.95, recommended)),
            intraSpeakerMin: intraMin,
            intraSpeakerMean: intraMean,
            interSpeakerMax: interMax,
            interSpeakerMean: interMean,
            labeledSpeakers: perSpeaker.count,
            confidence: confidence
        )
    }
}
