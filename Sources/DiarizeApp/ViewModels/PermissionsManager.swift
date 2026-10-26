import AppKit
import AVFoundation
import CoreGraphics
import DiarizeCore
import Foundation

/// Tracks the macOS privacy permissions diarize needs to record, and exposes
/// helpers to request them or jump the user to the relevant System Settings pane.
///
/// Three permissions matter:
///   • Microphone        — to capture mic audio (AVCaptureDevice / AVAudioEngine input)
///   • Screen Recording  — to capture system audio via ScreenCaptureKit (fallback path)
///   • System Audio      — to capture all apps via the Core Audio process tap (primary path)
@MainActor
final class PermissionsManager: ObservableObject {

    enum Status: Equatable {
        case granted
        case denied        // explicitly denied / restricted — must be fixed in System Settings
        case notDetermined // never asked — can prompt in-app

        var isGranted: Bool { self == .granted }
    }

    enum Permission: String, CaseIterable, Identifiable {
        case microphone
        case screenRecording
        case systemAudio

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .microphone: return "Microphone"
            case .screenRecording: return "Screen & System Audio Recording"
            case .systemAudio: return "System Audio Recording"
            }
        }

        /// Why diarize needs it — shown to the user.
        var rationale: String {
            switch self {
            case .microphone: return "Required to record your microphone."
            case .screenRecording: return "Required to record system audio (other apps, meeting audio)."
            case .systemAudio: return "Required to record audio from all apps, whichever output device they use."
            }
        }

        /// Deep link to the matching System Settings privacy pane.
        var settingsURL: URL {
            switch self {
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            case .screenRecording, .systemAudio:
                // "System Audio Recording Only" is listed at the bottom of the same pane.
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            }
        }
    }

    @Published private(set) var statuses: [Permission: Status] = [:]

    init() {
        refresh()
    }

    func status(for permission: Permission) -> Status {
        statuses[permission] ?? .notDetermined
    }

    /// True when every required permission is granted.
    var allGranted: Bool {
        Permission.allCases.allSatisfy { status(for: $0).isGranted }
    }

    /// Permissions that are not currently granted, in display order.
    var missing: [Permission] {
        Permission.allCases.filter { !status(for: $0).isGranted }
    }

    /// Re-read the current status of every permission from the system.
    func refresh() {
        statuses[.microphone] = Self.microphoneStatus()
        statuses[.screenRecording] = Self.screenRecordingStatus()
        statuses[.systemAudio] = Self.systemAudioStatus()
    }

    /// Request a permission. For not-yet-determined permissions this shows the
    /// system prompt; for already-denied ones it opens System Settings (the only
    /// place the user can change it). Refreshes status afterwards.
    func request(_ permission: Permission) {
        switch permission {
        case .microphone:
            if status(for: permission) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
            } else {
                openSettings(for: permission)
            }
        case .screenRecording:
            if status(for: permission) == .notDetermined {
                // Triggers the system prompt the first time it's called.
                _ = CGRequestScreenCaptureAccess()
                refresh()
            } else {
                openSettings(for: permission)
            }
        case .systemAudio:
            if status(for: permission) == .notDetermined {
                SystemAudioPermission.request { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
            } else {
                openSettings(for: permission)
            }
        }
    }

    func openSettings(for permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    // MARK: - Status probes

    private static func microphoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private static func screenRecordingStatus() -> Status {
        // CGPreflightScreenCaptureAccess returns false both when denied and when
        // never-requested; there is no API to distinguish them. We treat false as
        // .notDetermined so the first tap can attempt an in-app prompt, falling
        // back to System Settings if that does nothing.
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    private static func systemAudioStatus() -> Status {
        switch SystemAudioPermission.status() {
        case .granted: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        // Can't probe it — don't block recording on a permission we can't see.
        case .unknown: return .granted
        }
    }
}
