import Testing
@testable import DiarizeCore

@Suite struct MathUtilTests {
    @Test func cosineIdenticalVectors() {
        let a: [Float] = [1, 2, 3, 4]
        #expect(abs(MathUtil.cosineSimilarity(a, a) - 1.0) < 1e-6)
    }

    @Test func cosineOrthogonal() {
        #expect(abs(MathUtil.cosineSimilarity([1, 0], [0, 1])) < 1e-6)
    }

    @Test func cosineOppositeIsMinusOne() {
        let s = MathUtil.cosineSimilarity([1, 2, 3], [-1, -2, -3])
        #expect(abs(s + 1.0) < 1e-6)
    }

    @Test func cosineZeroVectorReturnsZero() {
        #expect(MathUtil.cosineSimilarity([0, 0, 0], [1, 2, 3]) == 0)
    }

    @Test func meanOfVectors() {
        let vs: [[Float]] = [[1, 2], [3, 4], [5, 6]]
        let m = MathUtil.mean(of: vs)
        #expect(m == [3, 4])
    }

    @Test func meanOfEmptyIsNil() {
        #expect(MathUtil.mean(of: []) == nil)
    }

    @Test func l2NormalizationProducesUnitVector() {
        let n = MathUtil.l2Normalized([3, 4])
        let mag = (n[0] * n[0] + n[1] * n[1]).squareRoot()
        #expect(abs(mag - 1.0) < 1e-6)
    }
}
