import Foundation

public enum MathUtil {
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "vector dimensions must match")
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrtf(na) * sqrtf(nb)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    /// Returns nil for an empty input. Otherwise returns the elementwise mean. All vectors must share the same dimension.
    public static func mean(of vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first else { return nil }
        let dim = first.count
        var sum = [Float](repeating: 0, count: dim)
        for v in vectors {
            precondition(v.count == dim, "vector dimensions must match")
            for i in 0..<dim { sum[i] += v[i] }
        }
        let n = Float(vectors.count)
        return sum.map { $0 / n }
    }

    /// L2-normalize a vector. Returns the input unchanged if its magnitude is zero.
    public static func l2Normalized(_ v: [Float]) -> [Float] {
        var sq: Float = 0
        for x in v { sq += x * x }
        let mag = sqrtf(sq)
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }
}
