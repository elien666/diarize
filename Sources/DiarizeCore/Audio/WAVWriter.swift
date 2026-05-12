import Foundation

/// Streaming WAV writer for 32-bit float mono PCM. Header is written at open;
/// chunk sizes are patched on close.
public final class WAVWriter {
    private let handle: FileHandle
    private let sampleRate: UInt32
    private let channels: UInt16
    private var dataBytesWritten: UInt32 = 0
    private var closed = false

    /// Mixing mode: append new samples to the existing tail by summation, instead of
    /// concatenating. Used when both mic and system audio write to the same file
    /// concurrently. With concatenation the streams interleave wrongly.
    /// For simplicity v1 uses concatenation only; both streams are written sequentially
    /// in the order their callbacks fire — acoustically inferior to true mixing but
    /// good enough as a first cut. A future version can buffer and mix.
    public init(url: URL, sampleRate: Int, channels: Int) throws {
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        self.sampleRate = UInt32(sampleRate)
        self.channels = UInt16(channels)
        try writeHeaderPlaceholder()
    }

    public func append(samples: [Float]) throws {
        guard !closed else { return }
        guard !samples.isEmpty else { return }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try handle.write(contentsOf: data)
        dataBytesWritten &+= UInt32(data.count)
    }

    public func close() throws {
        guard !closed else { return }
        closed = true
        try patchHeader()
        try handle.close()
    }

    deinit { try? close() }

    // MARK: - Header

    private func writeHeaderPlaceholder() throws {
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(uint32LE(0))                      // ChunkSize (patched)
        header.append("WAVE".data(using: .ascii)!)

        header.append("fmt ".data(using: .ascii)!)
        header.append(uint32LE(16))                     // Subchunk1Size
        header.append(uint16LE(3))                      // AudioFormat = IEEE float
        header.append(uint16LE(channels))               // NumChannels
        header.append(uint32LE(sampleRate))             // SampleRate
        let byteRate = sampleRate * UInt32(channels) * 4
        header.append(uint32LE(byteRate))               // ByteRate
        header.append(uint16LE(channels * 4))           // BlockAlign
        header.append(uint16LE(32))                     // BitsPerSample

        header.append("data".data(using: .ascii)!)
        header.append(uint32LE(0))                      // Subchunk2Size (patched)

        try handle.write(contentsOf: header)
    }

    private func patchHeader() throws {
        let chunkSize = 36 + dataBytesWritten
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: uint32LE(chunkSize))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: uint32LE(dataBytesWritten))
    }

    private func uint32LE(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }
    private func uint16LE(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 2)
    }
}
