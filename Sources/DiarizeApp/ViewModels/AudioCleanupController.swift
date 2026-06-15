import Foundation
import DiarizeCore

/// GDPR auto-clean: periodically looks for recordings whose raw audio is older
/// than the retention period and, if any are found, surfaces a single summary
/// prompt offering to delete the audio files (transcripts are always kept).
///
/// Nothing is ever deleted automatically — the controller only proposes; the
/// user confirms in the summary sheet. Runs once at app start and then on a
/// 24-hour timer while the app stays open.
///
/// `library` is injected via `attach(...)` from the view layer because SwiftUI
/// `@StateObject` cross-references can't be wired up in `init`.
@MainActor
final class AudioCleanupController: ObservableObject {

    /// UserDefaults keys, shared with SettingsView so both read/write the same prefs.
    enum Defaults {
        static let autoCleanEnabled = "autoCleanEnabled"
        static let audioRetentionDays = "audioRetentionDays"
        static let fallbackRetentionDays = 7
    }

    /// Non-empty drives the summary sheet in the UI.
    @Published var pendingCleanup: [Recording] = []

    private weak var library: LibraryViewModel?
    private var timer: Timer?

    private let checkInterval: TimeInterval = 24 * 60 * 60

    /// Effective retention in days, defaulting to 7 when unset.
    static var retentionDays: Int {
        let stored = UserDefaults.standard.integer(forKey: Defaults.audioRetentionDays)
        return stored > 0 ? stored : Defaults.fallbackRetentionDays
    }

    static var autoCleanEnabled: Bool {
        // Default to enabled when the user has never touched the setting.
        UserDefaults.standard.object(forKey: Defaults.autoCleanEnabled) == nil
            || UserDefaults.standard.bool(forKey: Defaults.autoCleanEnabled)
    }

    func attach(library: LibraryViewModel) {
        guard self.library == nil else { return }
        self.library = library
    }

    /// Run the first check immediately and start the recurring 24h timer.
    func start() {
        checkNow()
        startTimer()
    }

    func dismiss() {
        pendingCleanup = []
    }

    /// Delete the audio for all currently-pending candidates, then clear the prompt.
    func confirmDeleteAll() {
        library?.deleteAudioForRecordings(pendingCleanup.map(\.id))
        pendingCleanup = []
    }

    private func checkNow() {
        guard Self.autoCleanEnabled, pendingCleanup.isEmpty, let library else { return }
        pendingCleanup = library.audioCleanupCandidates(olderThanDays: Self.retentionDays)
    }

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
        t.tolerance = 60 * 60
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
