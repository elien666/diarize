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
    @Published var analysisProgress: ProgressState? = nil
    @Published var activeAnalysisId: String? = nil

    struct ProgressState {
        var phase: String
        var fraction: Double?   // 0.0–1.0, nil = indeterminate
    }

    struct ErrorAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func presentError(title: String, message: String) {
        errorAlert = ErrorAlert(title: title, message: message)
        statusMessage = title
    }

    @Published var config: AppConfig
    let store: SpeakerStore
    let searchService: SearchService

    enum SidebarSection: Hashable {
        case recordings
        case speakers
    }

    init() {
        let loadedConfig = AppConfigLoader.load()
        self.config = loadedConfig
        try? loadedConfig.ensureDirectories()
        self.store = (try? SpeakerStore(path: loadedConfig.databasePath)) ?? Self.fallbackStore()
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
    /// Wall-clock start of the live recording. Published once per recording (set on
    /// start, cleared on stop) — the live timer view derives elapsed time from this
    /// via TimelineView, so the ticking display does NOT republish through this model
    /// and re-render the whole window every second.
    @Published private(set) var recordingStartedAt: Date?
    @Published var recordingSourcesLabel: String = ""
    /// The live recorder's level meter + per-source device names, published once
    /// per recording (set on start, cleared on stop). The UI polls the meter via
    /// a TimelineView so the ticking level display does NOT republish through this
    /// model — same isolation as `recordingStartedAt`.
    @Published private(set) var recordingMeter: RecordingMeterHandle?
    private var activeRecorder: AudioRecorder?
    private var recordingOutputURL: URL?

    var isRecording: Bool { activeRecordingId != nil }

    func startRecording(
        sources: Set<AudioRecorder.Source>,
        title: String = "",
        language: AppConfig.Language? = nil,
        micDeviceUID: String? = nil
    ) {
        guard !isRecording else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = f.string(from: Date())
        let outputURL = config.recordingsDir.appendingPathComponent("rec-\(stamp).wav")
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let recorder: AudioRecorder
        do {
            recorder = try AudioRecorder(config: AudioRecorder.Config(sources: sources, outputURL: outputURL, micDeviceUID: micDeviceUID))
        } catch {
            presentError(
                title: "Recording could not be started",
                message: Self.formatRecorderError(error)
            )
            return
        }

        // Create the Recording row immediately so it appears in the sidebar.
        let recordingId = "rec_" + UUID().uuidString
        let resolvedTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Recording \(humanTimestamp(Date()))"
            : title.trimmingCharacters(in: .whitespaces)
        let resolvedLanguage = language ?? config.defaultLanguage
        let baseName = "\(stamp)-recording"
        let mdPath = config.transcriptsDir.appendingPathComponent("\(baseName).md")
        let jsonPath = config.transcriptsDir.appendingPathComponent("\(baseName).json")
        let stub = Recording(
            id: recordingId,
            title: resolvedTitle,
            sourcePath: outputURL.path,
            durationSec: 0,
            language: resolvedLanguage.rawValue,
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
        self.recordingMeter = RecordingMeterHandle(recorder: recorder, requestedSources: sources)
        self.recordingSourcesLabel = sources.map { $0.rawValue }.sorted().joined(separator: "+")
        self.statusMessage = "Recording (\(recordingSourcesLabel)) …"
        self.activeRecordingId = recordingId
        self.recordingStartedAt = Date()
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
        activeAnalysisId = recordingId
        statusMessage = "Analyzing …"
        let config = self.config
        let store = self.store
        let progress = AppProgress { [weak self] msg in
            Task { @MainActor in
                self?.statusMessage = msg
                self?.analysisProgress = Self.parseProgress(msg)
            }
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
                self.activeAnalysisId = nil
                self.analysisProgress = nil
                self.statusMessage = result.recording.processingState == .empty
                    ? "Recording done — no speech detected."
                    : "✓ Done: \(result.recording.id)"
                self.reload()
            } catch {
                self.importInProgress = false
                self.activeAnalysisId = nil
                self.analysisProgress = nil
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

    private func cleanupRecorder() {
        activeRecorder = nil
        recordingOutputURL = nil
        recordingStartedAt = nil
        recordingSourcesLabel = ""
        recordingMeter = nil
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

    /// Permanently delete a recording and all of its files (WAV + transcripts),
    /// not just the database row. Used by the auto-mode session list's "Delete"
    /// action to discard an unwanted automatic capture.
    func deleteRecordingAndFiles(_ recordingId: String) {
        if let r = try? store.recording(id: recordingId) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: r.sourcePath))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: r.transcriptMd))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: r.transcriptJson))
        }
        deleteRecording(recordingId)
    }

    // MARK: - GDPR: delete audio only, keep transcript

    /// Remove only the raw audio (WAV) for a recording while keeping the transcript,
    /// segments and speaker assignments. Used by the per-recording "Delete Audio"
    /// action and by the auto-clean batch.
    func deleteAudioOnly(_ recordingId: String) {
        removeAudioFile(recordingId)
        reload()
    }

    /// Same as `deleteAudioOnly` but without reloading after each item — the caller
    /// reloads once after the batch to avoid N redundant reloads.
    func deleteAudioForRecordings(_ ids: [String]) {
        for id in ids { removeAudioFile(id) }
        reload()
    }

    private func removeAudioFile(_ recordingId: String) {
        guard let r = try? store.recording(id: recordingId), r.hasAudio else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: r.sourcePath))
        try? store.markAudioDeleted(id: recordingId)
    }

    /// Recordings whose audio is older than `days`, still present on disk, and fully
    /// processed — i.e. candidates for the auto-clean privacy prompt.
    func audioCleanupCandidates(olderThanDays days: Int) -> [Recording] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return (try? store.allRecordings())?.filter {
            $0.audioDeletedAt == nil
                && $0.processingState == .done
                && $0.createdAt < cutoff
                && FileManager.default.fileExists(atPath: $0.sourcePath)
        } ?? []
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
            Task { @MainActor in
                self?.statusMessage = msg
                self?.analysisProgress = Self.parseProgress(msg)
            }
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
                self.analysisProgress = nil
                self.statusMessage = result.skipped
                    ? "Already archived (\(result.recording.id))"
                    : "✓ Done: \(result.recording.id)"
                self.reload()
                self.selectedRecordingId = result.recording.id
            } catch {
                self.importInProgress = false
                self.analysisProgress = nil
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

    // MARK: - Settings / Config

    func updateDefaultLanguage(_ lang: AppConfig.Language) {
        writeConfigValue(key: "default.language", value: lang.rawValue)
        config.defaultLanguage = lang
    }

    func updateSimilarityThreshold(_ value: Float) {
        writeConfigValue(key: "similarity.threshold", value: String(format: "%.2f", value))
        config.similarityThreshold = value
    }

    /// Writes `archive.path` to config.json. The change takes effect after restart
    /// because the SpeakerStore database connection cannot be hot-swapped.
    func updateArchivePath(_ url: URL) {
        let configFile = Self.configFileURL()
        var json = Self.readConfigJSON(from: configFile)
        var archive = (json["archive"] as? [String: Any]) ?? [:]
        archive["path"] = url.path
        json["archive"] = archive
        try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: configFile)
        // Don't update self.config.archivePath — needs restart to reinit the database.
    }

    func recalibrateThreshold() async -> CalibrationResult? {
        let store = self.store
        return try? ThresholdCalibrator.calibrate(store: store)
    }

    func rerenderAllTranscripts() {
        guard !importInProgress else { return }
        importInProgress = true
        statusMessage = "Re-rendering transcripts …"
        let config = self.config
        let store = self.store
        let ids = recordings.map { $0.id }
        Task {
            let pipeline = TranscribePipeline(config: config, store: store)
            for id in ids {
                _ = try? pipeline.rerender(recordingId: id)
            }
            await MainActor.run {
                self.importInProgress = false
                self.statusMessage = "✓ Re-rendered \(ids.count) recordings"
                self.reload()
            }
        }
    }

    func deduplicateArchive() async -> Int {
        let store = self.store
        let dupes = (try? store.allRecordings()) ?? []
        var seen: [String: String] = [:]  // hash → keep id (most recent)
        var toDelete: [String] = []
        // sort newest-first so the first occurrence we see is the keeper
        let sorted = dupes.compactMap { $0 }.sorted { $0.createdAt > $1.createdAt }
        for rec in sorted {
            guard let hash = rec.sourceHash else { continue }
            if seen[hash] != nil {
                toDelete.append(rec.id)
            } else {
                seen[hash] = rec.id
            }
        }
        for id in toDelete {
            try? store.deleteRecording(id: id)
        }
        await MainActor.run { self.reload() }
        return toDelete.count
    }

    func backfillHashes() async {
        let store = self.store
        let all = (try? store.allRecordings()) ?? []
        var count = 0
        for rec in all where rec.sourceHash == nil {
            let url = URL(fileURLWithPath: rec.sourcePath)
            guard let hash = try? AudioHasher.sha256(of: url) else { continue }
            try? store.setSourceHash(recordingId: rec.id, hash: hash)
            count += 1
        }
        await MainActor.run {
            self.statusMessage = "✓ Backfilled \(count) hashes"
            self.reload()
        }
    }

    func speakerSimilarities(for speakerId: String) async -> [(Speaker, Float)] {
        let store = self.store
        guard let targetEmbs = try? store.embeddings(for: speakerId), !targetEmbs.isEmpty else { return [] }
        guard let targetCentroid = MathUtil.mean(of: targetEmbs.map { $0.asFloats }) else { return [] }
        let allSpeakers = (try? store.allSpeakers()) ?? []
        var results: [(Speaker, Float)] = []
        for speaker in allSpeakers where speaker.id != speakerId {
            guard let embs = try? store.embeddings(for: speaker.id), !embs.isEmpty else { continue }
            guard let centroid = MathUtil.mean(of: embs.map { $0.asFloats }) else { continue }
            let sim = MathUtil.cosineSimilarity(targetCentroid, centroid)
            results.append((speaker, sim))
        }
        return results.sorted { $0.1 > $1.1 }
    }

    // MARK: - Progress parsing

    static func parseProgress(_ message: String) -> ProgressState {
        // ASR sub-progress: "Transcribing [12/48] 25%"
        if message.hasPrefix("Transcribing [") {
            let pct: Double? = message
                .components(separatedBy: "] ")
                .last
                .flatMap { $0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces) }
                .flatMap(Double.init)
            let fraction = pct.map { 0.60 + ($0 / 100.0) * 0.38 }
            return ProgressState(phase: "Transcribing", fraction: fraction)
        }
        switch true {
        case message.hasPrefix("Loading audio"):          return ProgressState(phase: "Loading audio",      fraction: 0.05)
        case message.hasPrefix("Loading diarization"):    return ProgressState(phase: "Loading models",     fraction: 0.10)
        case message.hasPrefix("Running diarization"):    return ProgressState(phase: "Diarizing",          fraction: nil)
        case message.hasPrefix("Diarized:"):              return ProgressState(phase: "Diarizing",          fraction: 0.35)
        case message.hasPrefix("Speaker matching"):       return ProgressState(phase: "Matching speakers",  fraction: 0.55)
        case message.hasPrefix("Loading ASR"):            return ProgressState(phase: "Loading ASR",        fraction: 0.60)
        case message.hasPrefix("Persisting"):             return ProgressState(phase: "Saving",             fraction: 0.98)
        default:                                          return ProgressState(phase: message,              fraction: nil)
        }
    }

    // MARK: - Config helpers

    private static func configFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/diarize/config.json")
    }

    private static func readConfigJSON(from url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private func writeConfigValue(key: String, value: String) {
        let configFile = Self.configFileURL()
        try? FileManager.default.createDirectory(
            at: configFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var json = Self.readConfigJSON(from: configFile)
        json[key] = value
        try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: configFile)
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
