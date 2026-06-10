import CoreAudio
import Foundation

/// A selectable audio input device.
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// CoreAudio device UID — stable across reboots/reconnects, safe to persist.
    public let uid: String
    public let name: String
    /// The live AudioObjectID. NOT stable across reconnects — resolve from `uid`
    /// at use time rather than persisting this.
    public let deviceID: AudioObjectID

    public var id: String { uid }
}

/// Enumerates CoreAudio input devices and resolves persisted UIDs back to live
/// device IDs. All calls hit the HAL synchronously; cheap enough to call when the
/// record popover opens.
public enum AudioInputDevices {
    /// All devices that expose at least one input channel, in HAL order.
    public static func all() -> [AudioInputDevice] {
        deviceIDs().compactMap { id in
            guard hasInputChannels(id), let uid = uid(of: id) else { return nil }
            let name = name(of: id) ?? uid
            return AudioInputDevice(uid: uid, name: name, deviceID: id)
        }
    }

    /// The system default input device, if any.
    public static func systemDefault() -> AudioInputDevice? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown,
              let uid = uid(of: deviceID) else {
            return nil
        }
        return AudioInputDevice(uid: uid, name: name(of: deviceID) ?? uid, deviceID: deviceID)
    }

    /// Resolve a persisted UID to a currently-connected device. Returns nil if the
    /// device is no longer present (e.g. an unplugged USB mic).
    public static func device(forUID uid: String) -> AudioInputDevice? {
        all().first { $0.uid == uid }
    }

    // MARK: - HAL helpers

    private static func deviceIDs() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func hasInputChannels(_ deviceID: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }
        let bufList = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &dataSize, bufList) == noErr else {
            return false
        }
        let abl = UnsafeMutableAudioBufferListPointer(bufList.assumingMemoryBound(to: AudioBufferList.self))
        for buffer in abl where buffer.mNumberChannels > 0 {
            return true
        }
        return false
    }

    private static func uid(of deviceID: AudioObjectID) -> String? {
        stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func name(of deviceID: AudioObjectID) -> String? {
        stringProperty(deviceID, selector: kAudioObjectPropertyName)
    }

    private static func stringProperty(_ deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value) == noErr,
              let cf = value?.takeRetainedValue() else {
            return nil
        }
        let s = cf as String
        return s.isEmpty ? nil : s
    }
}
