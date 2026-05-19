import AppKit
import Foundation
import DiarizeCore
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var speakers: [Speaker] = []
    @Published var folders: [RecordingFolder] = []
    @Published var selectedRecordingId: String?
    @Published var selectedSpeakerId: String?
    @Published var sidebarSection: SidebarSection = .recordings
    @Published var importInProgress: Bool = false
    @Published var statusMessage: String = ""
    @Published var errorAlert: ErrorAlert?

    struct ErrorAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func presentError(title: String, message: String) {
        errorAlert = ErrorAlert(title: title, message: message)
        statusMessage = title
    }

    let config: AppConfig
    let store: SpeakerStore
    let searchService: SearchService

    enum SidebarSection: Hashable {
        case recordings
        case speakers
    }

    init() {
        self.config = AppConfigLoader.load()
        try? config.ensureDirectories()
        self.store = (try? SpeakerStore(path: config.databasePath)) ?? Self.fallbackStore()
        self.searchService = SearchService(store: store)
        recoverOrphanedRecordings()
        reload()
    }

    /// On launch, recover recordings stuck in `recording`/`analyzing` state from a previous
    /// session (app crashed or got force-quit by macOS during a permission prompt).
    /// Strategy: tiny WAVs (< 8 KB, just header) → delete. Anything bigger → mark as failed
    /// so the user can either retry analysis or play it back.
    private func recoverOrphanedRecordings() {
        guard let recs = try? store.allRecordings() else { return }
        for r in recs where r.processingState == .recording || r.processingState == .analyzing {
            let url = URL(fileURLWithPath: r.sourcePath)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int) ?? 0
            if size < 8_192 {
                // Empty / header-only WAV — drop the row and the file.
                try? store.deleteRecording(id: r.id)
                try? FileManager.default.removeItem(at: url)
            } else {
                try? store.setProcessingState(
                    recordingId: r.id,
                    state: .failed,
                    errorMessage: "Recording was interrupted by an app restart. You can play it back or retry analysis."
                )
            }
        }
    }

    private static func fallbackStore() -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("diarize-fallback.sqlite")
        return try! SpeakerStore(path: tmp)
    }

    func reload() {
        recordings = (try? store.allRecordings()) ?? []
        speakers = (try? store.allSpeakers()) ?? []
        folders = (try? store.allFolders()) ?? []
    }

    func speakerLabel(for id: String?) -> String {
        guard let id else { return "—" }
        if let s = speakers.first(where: { $0.id == id }), let label = s.label {
            return label
        }
        return "Unknown-\(String(id.suffix(6)))"
    }

    func segmentCount(speakerId: String) -> Int { (try? store.segmentCount(speakerId: speakerId)) ?? 0 }
    func speechTime(speakerId: String) -> Double { (try? store.totalSpeechTime(speakerId: speakerId)) ?? 0 }

    func segments(for recordingId: String) -> [RecordingSegment] {
        (try? store.segments(for: recordingId)) ?? []
    }

    func recordings(for speakerId: String) -> [SpeakerStore.RecordingAppearance] {
        (try? store.recordings(for: speakerId)) ?? []
    }

    func openRecording(_ recordingId: String, jumpToSec: Double? = nil) {
        sidebarSection = .recordings
        selectedRecordingId = recordingId
        if let jumpToSec {
            pendingJumpSec = jumpToSec
        }
    }

    @Published var pendingJumpSec: Double?

    // MARK: - Live recording state

    @Published var activeRecordingId: String?      // recording row id while live
    @Published var recordingElapsedSec: Double = 0
    @Published var recordingSourcesLabel: String = ""
    private var activeRecorder: AudioRecorder?
    private var recordingStartedAt: Date?
    private var recordingTimer: Timer?
    private var recordingOutputURL: URL?

    var isRecording: Bool { activeRecordingId != nil }

    func startRecording(sources: Set<AudioRecorder.Source>) {
        guard !isRecording else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = f.string(from: Date())
        let outputURL = config.recordingsDir.appendingPathComponent("rec-\(stamp).wav")
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let recorder: AudioRecorder
        do {
            recorder = try AudioRecorder(config: AudioRecorder.Config(sources: sources, outputURL: outputURL))
        } catch {
            presentError(
                title: "Recording could not be started",
                message: Self.formatRecorderError(error)
            )
            return
        }

        // Create the Recording row immediately so it appears in the sidebar.
        let recordingId = "rec_" + UUID().uuidString
        let title = "Recording \(humanTimestamp(Date()))"
        let baseName = "\(stamp)-recording"
        let mdPath = config.transcriptsDir.appendingPathComponent("\(baseName).md")
        let jsonPath = config.transcriptsDir.appendingPathComponent("\(baseName).json")
        let stub = Recording(
            id: recordingId,
            title: title,
            sourcePath: outputURL.path,
            durationSec: 0,
            language: config.defaultLanguage.rawValue,
            transcriptMd: mdPath.path,
            transcriptJson: jsonPath.path,
            createdAt: Date(),
            sourceHash: nil,
            processingState: .recording
        )
        do {
            try store.insertEmptyRecording(stub)
        } catch {
            presentError(
                title: "Could not create recording in database",
                message: error.localizedDescription
            )
            return
        }

        self.activeRecorder = recorder
        self.recordingOutputURL = outputURL
        self.recordingSourcesLabel = sources.map { $0.rawValue }.sorted().joined(separator: "+")
        self.statusMessage = "Recording (\(recordingSourcesLabel)) …"
        self.activeRecordingId = recordingId
        self.recordingStartedAt = Date()
        self.recordingElapsedSec = 0
        startTimer()
        reload()
        openRecording(recordingId)

        Task {
            do {
                try await recorder.start()
            } catch {
                await MainActor.run {
                    let id = self.activeRecordingId
                    self.cleanupRecorder()
                    if let id { try? self.store.deleteRecording(id: id) }
                    self.reload()
                    self.presentError(
                        title: "Recording could not be started",
                        message: Self.formatRecorderError(error)
                    )
                }
            }
        }
    }

    private static func formatRecorderError(_ error: Error) -> String {
        let base = error.localizedDescription
        let hint = """

        Possible causes:
        • Microphone permission not granted → System Settings → Privacy & Security → Microphone
        • Screen Recording permission not granted (for system audio) → System Settings → Privacy & Security → Screen & System Audio Recording
        • Running as a swift-run binary instead of a .app bundle — macOS cannot assign permanent permissions to unbundled binaries. Build the .app with ./Scripts/build-app.sh.
        """
        return base + hint
    }

    func stopRecordingAndTranscribe() {
        // Orphaned-recording recovery: detail view may show stop buttons for a recording
        // whose recorder is gone (app restart). In that case just try analysis on the file.
        if activeRecorder == nil, let id = selectedRecordingId,
           let r = try? store.recording(id: id),
           r.processingState == .recording {
            try? store.setProcessingState(recordingId: id, state: .analyzing)
            reload()
            analyzeRecording(recordingId: id)
            return
        }
        guard let recorder = activeRecorder, let recordingId = activeRecordingId else { return }
        statusMessage = "Stopping recording …"
        // Flip the row to analyzing right away so the controls disappear immediately,
        // before the async stop/analysis chain finishes.
        try? store.setProcessingState(recordingId: recordingId, state: .analyzing)
        reload()
        Task {
            try? await recorder.stop()
            let received = recorder.samplesReceived
            await MainActor.run {
                self.cleanupRecorder()
                self.reload()
                let totalSamples = (received[.mic] ?? 0) + (received[.system] ?? 0)
                if totalSamples == 0 {
                    try? self.store.setProcessingState(
                        recordingId: recordingId,
                        state: .failed,
                        errorMessage: "No audio samples were received during recording.\n\nPossible causes:\n• Microphone permission denied (System Settings → Privacy & Security → Microphone)\n• Screen & System Audio permission denied (for system audio)\n• Wrong input device\n\nThe WAV file is empty — you can delete the recording and start again."
                    )
                    self.reload()
                    return
                }
                self.analyzeRecording(recordingId: recordingId)
            }
        }
    }

    func cancelRecording() {
        // Orphaned recording: no active recorder but DB row says we're recording.
        if activeRecorder == nil, let id = selectedRecordingId,
           let r = try? store.recording(id: id),
           r.processingState == .recording {
            try? store.deleteRecording(id: id)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: r.sourcePath))
            if selectedRecordingId == id { selectedRecordingId = nil }
            reload()
            return
        }
        guard let recorder = activeRecorder, let url = recordingOutputURL, let recordingId = activeRecordingId else { return }
        statusMessage = "Recording discarded."
        Task {
            try? await recorder.stop()
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                self.cleanupRecorder()
                try? self.store.deleteRecording(id: recordingId)
                if self.selectedRecordingId == recordingId { self.selectedRecordingId = nil }
                self.reload()
            }
        }
    }

    /// Run the analysis pipeline against an existing recording row (created during live capture).
    private func analyzeRecording(recordingId: String) {
        importInProgress = true
        statusMessage = "Analyzing …"
        let config = self.config
        let store = self.store
        let progress = AppProgress { [weak self] msg in
            Task { @MainActor in self?.statusMessage = msg }
        }
        Task { @MainActor in
            do {
                let result = try await Self.runAnalyze(
                    config: config,
                    store: store,
                    progress: progress,
                    recordingId: recordingId
                )
                self.importInProgress = false
                self.statusMessage = result.recording.processingState == .empty
                    ? "Recording done — no speech detected."
                    : "✓ Done: \(result.recording.id)"
                self.reload()
            } catch {
                self.importInProgress = false
                self.statusMessage = "Analysis error: \(error.localizedDescription)"
                self.reload()
                self.presentError(
                    title: "Analysis failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func retryAnalysis(recordingId: String) {
        analyzeRecording(recordingId: recordingId)
    }

    private nonisolated static func runAnalyze(
        config: AppConfig,
        store: SpeakerStore,
        progress: ProgressReporter,
        recordingId: String
    ) async throws -> TranscribeOutput {
        let pipeline = TranscribePipeline(config: config, store: store, progress: progress)
        return try await pipeline.analyzeExisting(recordingId: recordingId, language: nil)
    }

    private func startTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartedAt else { return }
                self.recordingElapsedSec = Date().timeIntervalSince(start)
            }
        }
    }

    private func cleanupRecorder() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        activeRecorder = nil
        recordingOutputURL = nil
        recordingStartedAt = nil
        recordingSourcesLabel = ""
        recordingElapsedSec = 0
        activeRecordingId = nil
    }

    private func humanTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    // MARK: - Speaker delete (only if no segments)

    /// Returns true if the speaker has no segments referencing them and was deleted.
    func deleteRecording(_ recordingId: String) {
        try? store.deleteRecording(id: recordingId)
        if selectedRecordingId == recordingId { selectedRecordingId = nil }
        reload()
    }

    /// Reassign a segment to a different (or new) speaker. When `speakerId` is nil,
    /// a brand new speaker is created.
    func setSegmentSpeaker(segmentId: Int64, to speakerId: String?) {
        let targetId: String
        if let id = speakerId {
            targetId = id
        } else {
            let newSpeaker = Speaker()
            try? store.insertSpeaker(newSpeaker)
            targetId = newSpeaker.id
        }
        try? store.updateSegmentSpeaker(segmentId: segmentId, speakerId: targetId)
        reload()
        rerenderRecording(containingSegmentId: segmentId)
    }

    /// Split a segment at the given absolute time.
    func splitSegment(segmentId: Int64, atSec: Double) {
        do {
            _ = try store.splitSegment(segmentId: segmentId, at: atSec)
            reload()
            rerenderRecording(containingSegmentId: segmentId)
        } catch {
            presentError(title: "Segment kann nicht geteilt werden", message: error.localizedDescription)
        }
    }

    private func rerenderRecording(containingSegmentId segmentId: Int64) {
        guard let seg = try? store.segment(id: segmentId) else { return }
        let pipeline = TranscribePipeline(config: config, store: store, progress: SilentProgress())
        _ = try? pipeline.rerender(recordingId: seg.recordingId)
    }

    @discardableResult
    func deleteSpeakerIfEmpty(_ speakerId: String) -> Bool {
        let count = segmentCount(speakerId: speakerId)
        guard count == 0 else { return false }
        try? store.deleteSpeaker(id: speakerId)
        if selectedSpeakerId == speakerId { selectedSpeakerId = nil }
        reload()
        return true
    }

    func updateLabel(speakerId: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try? store.updateLabel(id: speakerId, label: trimmed.isEmpty ? nil : trimmed)
        reload()
        rerenderAll()
    }

    func merge(from: String, into: String) {
        try? store.mergeSpeakers(from: from, into: into)
        reload()
    }

    func rerenderAll() {
        let pipeline = TranscribePipeline(config: config, store: store, progress: SilentProgress())
        for r in recordings {
            _ = try? pipeline.rerender(recordingId: r.id)
        }
    }

    func search(_ query: String) -> [SearchHit] {
        (try? searchService.search(query: query, options: SearchOptions(limit: 50))) ?? []
    }

    // MARK: - Rename & Folders

    func renameRecording(_ recordingId: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.updateRecordingTitle(id: recordingId, title: trimmed)
        reload()
    }

    @discardableResult
    func createFolder(name: String, parentId: String? = nil) -> RecordingFolder? {
        let folder = RecordingFolder(name: name, parentId: parentId)
        let inserted = try? store.insertFolder(folder)
        reload()
        return inserted
    }

    func renameFolder(_ folderId: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.renameFolder(id: folderId, name: trimmed)
        reload()
    }

    func deleteFolder(_ folderId: String) {
        try? store.deleteFolder(id: folderId)
        reload()
    }

    func moveRecording(_ recordingId: String, toFolder folderId: String?) {
        try? store.moveRecording(id: recordingId, toFolderId: folderId)
        reload()
    }

    // MARK: - Import

    func openImportDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio]
        if panel.runModal() == .OK, let url = panel.url {
            transcribe(audioURL: url, title: nil)
        }
    }

    func transcribe(audioURL: URL, title: String?) {
        importInProgress = true
        statusMessage = "Transcribing \(audioURL.lastPathComponent) …"
        let config = self.config
        let store = self.store
        let progress = AppProgress { [weak self] msg in
            Task { @MainActor in self?.statusMessage = msg }
        }

        Task { @MainActor in
            do {
                let result = try await Self.runPipeline(
                    config: config,
                    store: store,
                    progress: progress,
                    audioURL: audioURL,
                    title: title
                )
                self.importInProgress = false
                self.statusMessage = result.skipped
                    ? "Already archived (\(result.recording.id))"
                    : "✓ Done: \(result.recording.id)"
                self.reload()
                self.selectedRecordingId = result.recording.id
            } catch {
                self.importInProgress = false
                self.statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private nonisolated static func runPipeline(
        config: AppConfig,
        store: SpeakerStore,
        progress: ProgressReporter,
        audioURL: URL,
        title: String?
    ) async throws -> TranscribeOutput {
        let pipeline = TranscribePipeline(config: config, store: store, progress: progress)
        return try await pipeline.run(audioPath: audioURL, title: title, language: nil, duplicatePolicy: .skip)
    }
}

private final class SilentProgress: ProgressReporter, @unchecked Sendable {
    func step(_ message: String) {}
}

private final class AppProgress: ProgressReporter, @unchecked Sendable {
    let handler: @Sendable (String) -> Void
    init(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }
    func step(_ message: String) { handler(message) }
}
