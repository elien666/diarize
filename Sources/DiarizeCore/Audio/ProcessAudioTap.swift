// ProcessAudioTap.swift
// Uses CoreAudio CATapDescription + AudioHardwareCreateProcessTap to capture
// audio from ALL processes regardless of which output device they use.
// This fixes the case where e.g. Teams is routed to a dedicated audio device
// rather than the system default — SCStream only sees the default device, but
// a global process tap sees every process.
//
// Requires macOS 14.2+.

@preconcurrency import AVFoundation
import CoreAudio
import Foundation

@available(macOS 14.2, *)
final class ProcessAudioTap: @unchecked Sendable {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    private let onSamples: ([Float]) -> Void
    private let queue = DispatchQueue(label: "diarize.processaudiotap")

    init(targetFormat: AVAudioFormat, onSamples: @escaping ([Float]) -> Void) {
        self.targetFormat = targetFormat
        self.onSamples = onSamples
    }

    func start() throws {
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.muteBehavior = .unmuted
        tapDesc.isPrivate = true

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapStatus == noErr else {
            throw ProcessAudioTapError.tapCreationFailed(tapStatus)
        }
        tapID = newTapID

        let tapUID = tapDesc.uuid.uuidString
        let aggregateUID = "diarize-aggregate-\(UUID().uuidString)"

        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Diarize Process Tap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true,
                 kAudioSubTapUIDKey: tapUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        var newAggregateID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &newAggregateID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw ProcessAudioTapError.aggregateDeviceCreationFailed(aggStatus)
        }
        aggregateDeviceID = newAggregateID

        try startEngine(deviceID: aggregateDeviceID)
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private func startEngine(deviceID: AudioObjectID) throws {
        let inputNode = engine.inputNode

        var deviceIDVar = deviceID
        // Point this AVAudioEngine's I/O unit at our aggregate device so the tap
        // reads from the process tap rather than the system default input.
        AudioUnitSetProperty(
            inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw ProcessAudioTapError.invalidFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.resample(buffer: buffer, inputFormat: inputFormat)
            if !samples.isEmpty {
                self.onSamples(samples)
            }
        }

        try engine.start()
    }

    private func resample(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> [Float] {
        if converter?.inputFormat.sampleRate != inputFormat.sampleRate
            || converter?.inputFormat.channelCount != inputFormat.channelCount {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        guard let conv = converter else { return [] }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return [] }

        var error: NSError?
        let state = ConvertState(buffer: buffer)
        conv.convert(to: out, error: &error) { _, status in
            if state.fed { status.pointee = .noDataNow; return nil }
            state.fed = true
            status.pointee = .haveData
            return state.buffer
        }
        if error != nil { return [] }

        guard let channels = out.floatChannelData else { return [] }
        let count = Int(out.frameLength)
        return Array(UnsafeBufferPointer(start: channels[0], count: count))
    }

    enum ProcessAudioTapError: Error, LocalizedError {
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let s): return "CATap creation failed: \(s)"
            case .aggregateDeviceCreationFailed(let s): return "Aggregate device creation failed: \(s)"
            case .invalidFormat: return "Process tap returned invalid audio format"
            }
        }
    }
}

private final class ConvertState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var fed = false
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
