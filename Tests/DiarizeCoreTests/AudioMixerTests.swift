import Foundation
import Testing
@testable import DiarizeCore

@Suite struct AudioMixerTests {
    /// Read back the float32 PCM samples from a WAV produced by WAVWriter.
    private func readSamples(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        // Header is 44 bytes (RIFF + fmt(16) + data), payload is float32 LE.
        let payload = data.subdata(in: 44..<data.count)
        return payload.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    private func makeMixer(_ enabled: Set<AudioMixer.Channel>, name: String) throws -> (AudioMixer, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixer-test-\(name)-\(UUID().uuidString).wav")
        let writer = try WAVWriter(url: url, sampleRate: 16000, channels: 1)
        return (AudioMixer(writer: writer, enabled: enabled), url)
    }

    @Test func singleChannelPassesThrough() throws {
        let (mixer, url) = try makeMixer([.mic], name: "single")
        let input: [Float] = (0..<1000).map { Float($0) / 1000.0 }
        mixer.append(input, channel: .mic)
        try mixer.flushAndClose()
        let out = try readSamples(url)
        #expect(out.count == input.count)
        #expect(out == input)
    }

    @Test func twoChannelsSumAndClip() throws {
        let (mixer, url) = try makeMixer([.mic, .system], name: "sum")
        let a: [Float] = [0.2, 0.8, -0.9, 0.5]
        let b: [Float] = [0.1, 0.6, -0.5, 0.5]  // sums: 0.3, 1.4->1.0, -1.4->-1.0, 1.0
        mixer.append(a, channel: .mic)
        mixer.append(b, channel: .system)
        try mixer.flushAndClose()
        let out = try readSamples(url)
        let expected: [Float] = [0.3, 1.0, -1.0, 1.0]
        #expect(out.count == expected.count)
        for (o, e) in zip(out, expected) { #expect(abs(o - e) < 1e-5) }
    }

    @Test func disableChannelPreservesOtherChannel() throws {
        // After a channel is disabled mid-recording (the mic+system -> mic-only path),
        // the surviving channel's stream must be written losslessly. System data queued
        // before disable is cleared, so the output is exactly the mic stream.
        let (mixer, url) = try makeMixer([.mic, .system], name: "disable")
        mixer.disableChannel(.system)
        let mic: [Float] = (0..<2048).map { Float($0 % 100) / 100.0 }
        mixer.append(mic, channel: .mic)
        try mixer.flushAndClose()
        let out = try readSamples(url)
        #expect(out.count == mic.count)
        #expect(out == mic)
    }

    @Test func crossesCompactionThresholdLosslessly() throws {
        // Feed well past compactThreshold (16384) in many small flushes so the read
        // head crosses the compaction point repeatedly. Output must equal input.
        let (mixer, url) = try makeMixer([.mic], name: "compact")
        var input: [Float] = []
        for chunk in 0..<60 {
            let buf = (0..<512).map { Float((chunk * 512 + $0) % 100) / 100.0 }
            input.append(contentsOf: buf)
            mixer.append(buf, channel: .mic)
        }
        try mixer.flushAndClose()
        let out = try readSamples(url)
        #expect(out.count == input.count)
        #expect(out == input)
    }
}
