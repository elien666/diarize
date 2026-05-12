import AppKit
import Foundation
import DiarizeCore
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var speakers: [Speaker] = []
    @Published var selectedRecordingId: String?
    @Published var selectedSpeakerId: String?
    @Published var sidebarSection: SidebarSection = .recordings
    @Published var importInProgress: Bool = false
    @Published var statusMessage: String = ""

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
        reload()
    }

    private static func fallbackStore() -> SpeakerStore {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("diarize-fallback.sqlite")
        return try! SpeakerStore(path: tmp)
    }

    func reload() {
        recordings = (try? store.allRecordings()) ?? []
        speakers = (try? store.allSpeakers()) ?? []
    }

    func speakerLabel(for id: String?) -> String {
        guard let id else { return "—" }
        if let s = speakers.first(where: { $0.id == id }), let label = s.label {
            return label
        }
        return "Unbekannt-\(String(id.suffix(6)))"
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

    @Published var isRecording: Bool = false
    @Published var recordingElapsedSec: Double = 0
    @Published var recordingSourcesLabel: String = ""
    private var activeRecorder: AudioRecorder?
    private var recordingStartedAt: Date?
    private var recordingTimer: Timer?
    private var recordingOutputURL: URL?

    func startRecording(sources: Set<AudioRecorder.Source>) {
        guard !isRecording else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let outputURL = config.recordingsDir.appendingPathComponent("rec-\(f.string(from: Date())).wav")
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        do {
            let recorder = try AudioRecorder(config: AudioRecorder.Config(sources: sources, outputURL: outputURL))
            self.activeRecorder = recorder
            self.recordingOutputURL = outputURL
            self.recordingSourcesLabel = sources.map { $0.rawValue }.sorted().joined(separator: "+")
            self.statusMessage = "Aufnahme läuft (\(recordingSourcesLabel)) …"
            self.isRecording = true
            self.recordingStartedAt = Date()
            self.recordingElapsedSec = 0
            startTimer()

            Task {
                do {
                    try await recorder.start()
                } catch {
                    await MainActor.run {
                        self.statusMessage = "Aufnahme-Fehler: \(error.localizedDescription)"
                        self.cleanupRecorder()
                    }
                }
            }
        } catch {
            statusMessage = "Aufnahme-Fehler: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndTranscribe() {
        guard isRecording, let recorder = activeRecorder, let url = recordingOutputURL else { return }
        let title = "Aufnahme \(formatStartTime())"
        statusMessage = "Stoppe Aufnahme …"
        Task {
            try? await recorder.stop()
            await MainActor.run {
                self.cleanupRecorder()
                self.transcribe(audioURL: url, title: title)
            }
        }
    }

    func cancelRecording() {
        guard isRecording, let recorder = activeRecorder, let url = recordingOutputURL else { return }
        statusMessage = "Aufnahme verworfen."
        Task {
            try? await recorder.stop()
            try? FileManager.default.removeItem(at: url)
            await MainActor.run { self.cleanupRecorder() }
        }
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
        isRecording = false
    }

    private func formatStartTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: recordingStartedAt ?? Date())
    }

    // MARK: - Speaker delete (only if no segments)

    /// Returns true if the speaker has no segments referencing them and was deleted.
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
        statusMessage = "Transkribiere \(audioURL.lastPathComponent) …"
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
                    ? "Bereits archiviert (\(result.recording.id))"
                    : "✓ Fertig: \(result.recording.id)"
                self.reload()
                self.selectedRecordingId = result.recording.id
            } catch {
                self.importInProgress = false
                self.statusMessage = "Fehler: \(error.localizedDescription)"
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
