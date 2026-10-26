// SystemAudioPermission.swift
// The Core Audio process tap (ProcessAudioTap) is gated by its own TCC service,
// kTCCServiceAudioCapture ("System Audio Recording Only" in System Settings) —
// separate from Screen Recording. Without it coreaudiod refuses IO on the tap
// ("Client is not granted access to the tap") and the engine fails to start.
//
// There is no public API to query or request it, so this goes through the
// private TCC framework, same as Apple's tap sample code and AudioCap. The
// system prompt only appears if Info.plist carries NSAudioCaptureUsageDescription.

import Foundation

public enum SystemAudioPermission {
    public enum Status: Sendable {
        case granted
        case denied
        case notDetermined
        /// The TCC SPI couldn't be loaded — status can't be determined.
        case unknown
    }

    private static let service = "kTCCServiceAudioCapture"
    private static let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"

    private typealias PreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunc = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    public static func status() -> Status {
        guard let handle = dlopen(tccPath, RTLD_NOW),
              let sym = dlsym(handle, "TCCAccessPreflight") else {
            return .unknown
        }
        let preflight = unsafeBitCast(sym, to: PreflightFunc.self)
        switch preflight(service as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Shows the system prompt if the permission was never decided. The completion
    /// runs on an arbitrary queue.
    public static func request(completion: @escaping @Sendable (Bool) -> Void) {
        guard let handle = dlopen(tccPath, RTLD_NOW),
              let sym = dlsym(handle, "TCCAccessRequest") else {
            completion(false)
            return
        }
        let request = unsafeBitCast(sym, to: RequestFunc.self)
        request(service as CFString, nil) { granted in completion(granted) }
    }
}
