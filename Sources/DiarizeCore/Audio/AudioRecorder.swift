import AVFoundation
import Foundation
import ScreenCaptureKit

/// Records mic and/or system audio to a WAV file at 16 kHz mono Float32.
/// When both sources are active they are sample-accurately mixed (sum + soft-clip).
/// macOS only; system audio requires macOS 13+ and Screen Recording permission.
public final class AudioRecorder: NSObject, @unchecked Sendable {
    public enum Source: String, Sendable, CaseIterable {
        case mic
        case system
    }

    public struct Config: Sendable {
        public let sources: Set<Source>
        public let outputURL: URL
        public init(sources: Set<Source>, outputURL: URL) {
            self.sources = sources
            self.outputURL = outputURL
        }
    }

    public enum RecorderError: Error, LocalizedError {
        case noSourcesSelected
        case audioEngineFailedToStart(String)
        case writerFailedToOpen(String)
        case systemAudioUnavailable(String)
        public var errorDescription: String? {
            switch self {
            case .noSourcesSelected: return "Keine Audioquelle ausgewählt (mic und/oder system)."
            case .audioEngineFailedToStart(let msg): return "Audio-Engine konnte nicht starten: \(msg)"
            case .writerFailedToOpen(let msg): return "WAV-Writer konnte nicht öffnen: \(msg)"
            case .systemAudioUnavailable(let msg): return "System-Audio nicht verfügbar: \(msg). Brauchst du Bildschirmaufnahme-Berechtigung?"
            }
        }
    }

    public let config: Config
    private let writer: WAVWriter
    private let mixer: AudioMixer
    private let engine = AVAudioEngine()
    private var micConverter: AVAudioConverter?
    private var systemConverter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    private var systemStream: SCStream?
    private var systemOutput: SystemAudioOutput?

    public init(config: Config) throws {
        guard !config.sources.isEmpty else { throw RecorderError.noSourcesSelected }
        self.config = config
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        do {
            self.writer = try WAVWriter(url: config.outputURL, sampleRate: 16000, channels: 1)
        } catch {
            throw RecorderError.writerFailedToOpen(error.localizedDescription)
        }
        var enabled: Set<AudioMixer.Channel> = []
        if config.sources.contains(.mic) { enabled.insert(.mic) }
        if config.sources.contains(.system) { enabled.insert(.system) }
        self.mixer = AudioMixer(writer: writer, enabled: enabled)
        super.init()
    }

    public func start() async throws {
        if config.sources.contains(.mic) {
            try startMic()
        }
        if config.sources.contains(.system) {
            try await startSystem()
        }
    }

    public func stop() async throws {
        if config.sources.contains(.mic) {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if config.sources.contains(.system), let stream = systemStream {
            try? await stream.stopCapture()
            systemStream = nil
            systemOutput = nil
        }
        try mixer.flushAndClose()
    }

    // MARK: - Mic

    private func startMic() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw RecorderError.audioEngineFailedToStart("Mikrofon liefert keine gültige Sample-Rate (Berechtigung erteilt?)")
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.resample(buffer: buffer, inputFormat: inputFormat, converter: &self.micConverter)
            self.mixer.append(samples, channel: .mic)
        }

        do {
            try engine.start()
        } catch {
            throw RecorderError.audioEngineFailedToStart(error.localizedDescription)
        }
    }

    // MARK: - System Audio

    private func startSystem() async throws {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw RecorderError.systemAudioUnavailable("kein Display gefunden")
            }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 48000
            cfg.channelCount = 2
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
            let output = SystemAudioOutput { [weak self] sampleBuffer in
                guard let self, let pcm = self.pcmBuffer(from: sampleBuffer) else { return }
                let samples = self.resample(buffer: pcm, inputFormat: pcm.format, converter: &self.systemConverter)
                self.mixer.append(samples, channel: .system)
            }
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "diarize.recorder.system"))
            try await stream.startCapture()
            self.systemStream = stream
            self.systemOutput = output
        } catch let err as RecorderError {
            throw err
        } catch {
            throw RecorderError.systemAudioUnavailable(error.localizedDescription)
        }
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }
        var asbdMutable = asbd
        guard let format = AVAudioFormat(streamDescription: &asbdMutable) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let abl = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for i in 0..<min(abl.count, dst.count) {
            let srcBuf = abl[i]
            let dstBuf = dst[i]
            if let src = srcBuf.mData, let d = dstBuf.mData {
                memcpy(d, src, Int(srcBuf.mDataByteSize))
                dst[i].mDataByteSize = srcBuf.mDataByteSize
            }
        }
        return buffer
    }

    // MARK: - Format conversion

    private func resample(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, converter: inout AVAudioConverter?) -> [Float] {
        if converter?.inputFormat.sampleRate != inputFormat.sampleRate
            || converter?.inputFormat.channelCount != inputFormat.channelCount {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        guard let conv = converter else { return [] }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return [] }

        var error: NSError?
        var fed = false
        conv.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return [] }

        guard let channels = out.floatChannelData else { return [] }
        let count = Int(out.frameLength)
        return Array(UnsafeBufferPointer(start: channels[0], count: count))
    }
}

@available(macOS 13, *)
private final class SystemAudioOutput: NSObject, SCStreamOutput {
    let handler: (CMSampleBuffer) -> Void
    init(handler: @escaping (CMSampleBuffer) -> Void) { self.handler = handler }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        handler(sampleBuffer)
    }
}
