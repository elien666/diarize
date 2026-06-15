import CoreAudio
import Foundation

/// Read-only CoreAudio probes for detecting whether *some* process is currently
/// capturing from the microphone. Used by the app's auto-recording mode to infer
/// "a call is running" without any app-specific knowledge (Zoom, Teams, Meet,
/// FaceTime, Discord… all hold the input device while in a call).
///
/// All calls hit the HAL synchronously and hold no state — cheap to poll every
/// few seconds and trivially unit-testable.
public enum MicUsageMonitor {

    /// Whether the system default input device reports that *something* is actively
    /// running input on it. This is device-wide: it is also `true` while diarize
    /// itself records, so it is only a coarse pre-filter for *starting* detection —
    /// it cannot tell our own capture apart from a foreign one. Available on all
    /// supported macOS versions.
    public static func defaultInputIsRunningSomewhere() -> Bool {
        guard let device = defaultInputDeviceID() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    /// Bundle IDs of system daemons that hold microphone input open continuously
    /// (Siri / dictation), independent of any actual call. They must be ignored or
    /// they would both trigger a false auto-start and prevent auto-stop (the count
    /// would never reach zero).
    private static let ignoredInputBundleIDs: Set<String> = [
        "com.apple.CoreSpeech",      // Siri / "Hey Siri" / dictation daemon
        "com.apple.SpeechRecognitionCore",
        "com.apple.accessibility.AXVisualSupportAgent",
    ]

    /// Number of *foreign* processes (PID ≠ `excludingPID`) that are currently
    /// running audio input, i.e. capturing from a microphone — excluding always-on
    /// system daemons (see `ignoredInputBundleIDs`). Pass `getpid()` to exclude
    /// diarize's own capture so this stays meaningful while we record.
    ///
    /// Returns `nil` when the per-process input API is unavailable (< macOS 14.4),
    /// in which case callers should fall back to `defaultInputIsRunningSomewhere()`
    /// for start detection and disable foreign-process-based auto-stop.
    public static func foreignMicInputCount(excludingPID excluded: pid_t) -> Int? {
        guard #available(macOS 14.4, *) else { return nil }
        guard let processes = processObjectIDs() else { return nil }

        var count = 0
        for process in processes {
            guard isRunningInput(process) else { continue }
            guard let pid = pid(of: process), pid != excluded else { continue }
            if let bundle = bundleID(of: process), ignoredInputBundleIDs.contains(bundle) { continue }
            count += 1
        }
        return count
    }

    // MARK: - HAL helpers

    private static func defaultInputDeviceID() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    @available(macOS 14.4, *)
    private static func processObjectIDs() -> [AudioObjectID]? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else {
            return nil
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids) == noErr else {
            return nil
        }
        return ids
    }

    @available(macOS 14.4, *)
    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    @available(macOS 14.4, *)
    private static func bundleID(of process: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &value) == noErr,
              let cf = value?.takeRetainedValue() else {
            return nil
        }
        let s = cf as String
        return s.isEmpty ? nil : s
    }

    @available(macOS 14.4, *)
    private static func pid(of process: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }
}
