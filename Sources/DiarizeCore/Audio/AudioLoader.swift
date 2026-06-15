import AVFoundation
import FluidAudio
import Foundation

public struct LoadedAudio: Sendable {
    public let samples: [Float]    // 16 kHz mono Float32 (downmixed if stereo)
    public let sampleRate: Int     // always 16000
    /// If source was stereo mic+system: left channel (mic) samples.
    public let micChannel: [Float]?
    /// If source was stereo mic+system: right channel (system) samples.
    public let systemChannel: [Float]?
    public var durationSec: Double { Double(samples.count) / Double(sampleRate) }
    public var isStereoSplit: Bool { micChannel != nil && systemChannel != nil }
}

public enum AudioLoader {
    /// Load and resample any AVFoundation-supported audio file (mp3, wav, m4a, …) to 16 kHz mono Float32.
    /// If the file is stereo (recorded with mic+system), also returns the individual channels.
    public static func load(url: URL) throws -> LoadedAudio {
        let channelCount = Self.channelCount(of: url)

        let converter = AudioConverter()    // defaults: 16 kHz mono Float32
        let samples = try converter.resampleAudioFile(url)

        if channelCount == 2 {
            let (left, right) = try deinterleave(url: url)
            return LoadedAudio(samples: samples, sampleRate: 16000, micChannel: left, systemChannel: right)
        }
        return LoadedAudio(samples: samples, sampleRate: 16000, micChannel: nil, systemChannel: nil)
    }

    private static func channelCount(of url: URL) -> Int {
        guard let file = try? AVAudioFile(forReading: url) else { return 1 }
        return Int(file.processingFormat.channelCount)
    }

    /// De-interleave a stereo file into two mono 16kHz Float32 arrays.
    private static func deinterleave(url: URL) throws -> (left: [Float], right: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let srcFormat = file.processingFormat
        guard srcFormat.channelCount == 2 else { return ([], []) }

        let frameCount = AVAudioFrameCount(file.length)
        guard let readBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
            return ([], [])
        }
        try file.read(into: readBuf)

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        // Extract each channel separately and resample to 16kHz
        let left = resampleChannel(readBuf, channelIndex: 0, srcFormat: srcFormat, targetFormat: targetFormat)
        let right = resampleChannel(readBuf, channelIndex: 1, srcFormat: srcFormat, targetFormat: targetFormat)
        return (left, right)
    }

    private static func resampleChannel(
        _ buffer: AVAudioPCMBuffer,
        channelIndex: Int,
        srcFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) -> [Float] {
        let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: srcFormat.sampleRate, channels: 1, interleaved: false)!
        guard let monoBuf = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength) else { return [] }
        monoBuf.frameLength = buffer.frameLength

        if let src = buffer.floatChannelData?[channelIndex], let dst = monoBuf.floatChannelData?[0] {
            memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }

        guard let conv = AVAudioConverter(from: monoFormat, to: targetFormat) else { return [] }
        let ratio = targetFormat.sampleRate / monoFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(monoBuf.frameLength) * ratio + 32)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return [] }

        var error: NSError?
        var fed = false
        conv.convert(to: outBuf, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return monoBuf
        }
        if error != nil { return [] }

        guard let ch = outBuf.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
    }
}
