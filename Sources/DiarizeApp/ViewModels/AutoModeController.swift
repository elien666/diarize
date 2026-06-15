import Combine
import Foundation
import DiarizeCore

/// Drives the dedicated "Auto Recording" mode: while active it polls the
/// microphone-usage state and, when it detects that another app has started
/// capturing the mic (i.e. a call started), it auto-starts a recording — then
/// auto-stops it once the foreign mic usage ends.
///
/// Dependencies (`library`, `permissions`) are injected via `attach(...)` from
/// the view layer because SwiftUI `@StateObject` cross-references can't be wired
/// up in `init`.
@MainActor
final class AutoModeController: ObservableObject {

    /// One row in the session list — a recording captured during this auto-mode run.
    struct SessionItem: Identifiable {
        let recordingId: String
        let startedAt: Date
        var durationSec: Double
        var state: RecordingProcessingState
        /// Distinct speaker labels, filled in once analysis completes.
        var speakers: [String]

        var id: String { recordingId }
    }

    @Published var isActive = false
    @Published private(set) var sessionItems: [SessionItem] = []

    /// True when the OS can't report per-process mic input (< macOS 14.4), so
    /// reliable auto-stop is unavailable. Surfaced as a hint in the UI.
    @Published private(set) var autoStopUnavailable = false

    private weak var library: LibraryViewModel?
    private weak var permissions: PermissionsManager?

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// recordingId of the capture this controller started (nil = none of ours live).
    private var autoStartedRecordingId: String?
    /// Debounce counters so a single noisy sample can't flip start/stop.
    private var positiveSamples = 0
    private var negativeSamples = 0

    private let pollInterval: TimeInterval = 2.5
    private let triggerThreshold = 2   // consecutive samples needed to act

    func attach(library: LibraryViewModel, permissions: PermissionsManager) {
        guard self.library == nil else { return }
        self.library = library
        self.permissions = permissions

        // Keep session items in sync with the library as analysis progresses.
        library.$recordings
            .sink { [weak self] recordings in
                self?.refreshSessionItems(from: recordings)
            }
            .store(in: &cancellables)
    }

    // MARK: - Mode lifecycle

    func enter() {
        guard !isActive else { return }
        isActive = true
        autoStopUnavailable = MicUsageMonitor.foreignMicInputCount(excludingPID: getpid()) == nil
        positiveSamples = 0
        negativeSamples = 0
        startTimer()
    }

    func exit() {
        guard isActive else { return }
        isActive = false
        stopTimer()
        // Leave any in-flight recording running; the user explicitly left the mode.
        autoStartedRecordingId = nil
    }

    // MARK: - Polling

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.5
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isActive, let library, let permissions else { return }

        let myPID = getpid()
        let foreign = MicUsageMonitor.foreignMicInputCount(excludingPID: myPID)

        if autoStartedRecordingId == nil {
            // Looking to START. Don't trigger if we (or anyone via library) are
            // already recording, or if permissions are missing.
            guard permissions.allGranted, !library.isRecording else {
                positiveSamples = 0
                return
            }
            let callActive = foreign.map { $0 > 0 }
                ?? MicUsageMonitor.defaultInputIsRunningSomewhere()
            if callActive {
                positiveSamples += 1
                if positiveSamples >= triggerThreshold { autoStart() }
            } else {
                positiveSamples = 0
            }
        } else {
            // We have a live auto-recording. Looking to STOP. Only the foreign
            // (per-process) count is meaningful here — the device-wide flag is
            // masked by our own capture, so without it we can't auto-stop.
            guard let foreign else { return }
            if foreign == 0 {
                negativeSamples += 1
                if negativeSamples >= triggerThreshold { autoStop() }
            } else {
                negativeSamples = 0
            }
        }
    }

    private func autoStart() {
        startRecording()
    }

    private func autoStop() {
        negativeSamples = 0
        autoStartedRecordingId = nil
        library?.stopRecordingAndTranscribe()
    }

    /// Shared start path for both auto-detection and the manual button. Tracks the
    /// new recording as the auto-started one so it appears in the session list and
    /// is eligible for auto-stop.
    private func startRecording() {
        guard let library, !library.isRecording else { return }
        positiveSamples = 0
        let micUID = UserDefaults.standard.string(forKey: "selectedMicDeviceUID")
        library.startRecording(
            sources: [.mic, .system],
            micDeviceUID: (micUID?.isEmpty ?? true) ? nil : micUID
        )
        guard let id = library.activeRecordingId else { return }
        autoStartedRecordingId = id
        negativeSamples = 0
        let item = SessionItem(
            recordingId: id,
            startedAt: library.recordingStartedAt ?? Date(),
            durationSec: 0,
            state: .recording,
            speakers: []
        )
        sessionItems.insert(item, at: 0)
    }

    /// Manual fallback: start a recording now, or stop the current one, regardless
    /// of detection. Useful when auto-detection misses or misfires.
    func manualToggleRecording() {
        guard let library else { return }
        if library.isRecording {
            autoStop()
        } else {
            startRecording()
        }
    }

    // MARK: - Session list maintenance

    private func refreshSessionItems(from recordings: [Recording]) {
        guard let library else { return }
        for index in sessionItems.indices {
            let id = sessionItems[index].recordingId
            guard let rec = recordings.first(where: { $0.id == id }) else { continue }
            sessionItems[index].durationSec = rec.durationSec
            sessionItems[index].state = rec.processingState
            if rec.processingState == .done || rec.processingState == .empty {
                sessionItems[index].speakers = distinctSpeakers(for: id, library: library)
            }
        }
    }

    private func distinctSpeakers(for recordingId: String, library: LibraryViewModel) -> [String] {
        let segments = library.segments(for: recordingId)
        var seen = Set<String>()
        var labels: [String] = []
        for seg in segments {
            guard let sid = seg.speakerId, !seen.contains(sid) else { continue }
            seen.insert(sid)
            labels.append(library.speakerLabel(for: sid))
        }
        return labels
    }

    // MARK: - Row actions

    /// "Keep" — remove the row from the session list only; the recording stays in
    /// the normal library.
    func keep(_ recordingId: String) {
        sessionItems.removeAll { $0.recordingId == recordingId }
    }

    /// "Delete" — permanently remove the recording (DB + WAV + transcripts) and
    /// drop it from the session list.
    func delete(_ recordingId: String) {
        library?.deleteRecordingAndFiles(recordingId)
        sessionItems.removeAll { $0.recordingId == recordingId }
    }
}
