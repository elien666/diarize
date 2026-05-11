import Foundation
import FluidAudio

public struct LoadedAudio: Sendable {
    public let samples: [Float]    // 16 kHz mono Float32
    public let sampleRate: Int     // always 16000
    public var durationSec: Double { Double(samples.count) / Double(sampleRate) }
}

public enum AudioLoader {
    /// Load and resample any AVFoundation-supported audio file (mp3, wav, m4a, …) to 16 kHz mono Float32.
    public static func load(url: URL) throws -> LoadedAudio {
        let converter = AudioConverter()    // defaults: 16 kHz mono Float32
        let samples = try converter.resampleAudioFile(url)
        return LoadedAudio(samples: samples, sampleRate: 16000)
    }
}
