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
