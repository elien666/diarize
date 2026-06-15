import Foundation
import Testing
@testable import DiarizeCore

@Suite struct MicUsageMonitorTests {
    /// Smoke test: the HAL probes must return a value without crashing, regardless
    /// of whether a call is active or the per-process API is available.
    @Test func probesReturnWithoutCrashing() {
        // Device-wide flag is always answerable (returns a Bool).
        _ = MicUsageMonitor.defaultInputIsRunningSomewhere()

        // Per-process count is nil on < macOS 14.4, otherwise a non-negative count.
        let count = MicUsageMonitor.foreignMicInputCount(excludingPID: getpid())
        if let count {
            #expect(count >= 0)
        }
    }
}
