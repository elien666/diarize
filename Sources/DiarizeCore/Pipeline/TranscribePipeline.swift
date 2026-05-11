import Foundation
import FluidAudio

public struct TranscribeOutput: Sendable {
    public let recording: Recording
    public let segments: [RecordingSegment]
    public let markdownPath: URL
    public let jsonPath: URL
    public let newSpeakerIds: [String]
    public let matchedSpeakerIds: [String]
}

public protocol ProgressReporter: AnyObject {
    func step(_ message: String)
}

public final class ConsoleProgress: ProgressReporter {
    public init() {}
    public func step(_ message: String) {
        FileHandle.standardError.write(Data("[diarize] \(message)\n".utf8))
    }
}

public final class TranscribePipeline {
    private let config: AppConfig
    private let store: SpeakerStore
    private let progress: ProgressReporter

    public init(config: AppConfig, store: SpeakerStore, progress: ProgressReporter = ConsoleProgress()) {
        self.config = config
        self.store = store
        self.progress = progress
    }

    public func run(audioPath: URL, title: String?, language: AppConfig.Language?) async throws -> TranscribeOutput {
        try config.ensureDirectories()
        let lang = language ?? config.defaultLanguage

        progress.step("Lade Audio …")
        let audio = try AudioLoader.load(url: audioPath)

        progress.step("Lade Diarization-Modelle …")
        let diarizer = DiarizationPipeline()
        try await diarizer.prepareModels()

        progress.step("Diarisierung läuft …")
        let diarization = try await diarizer.diarize(samples: audio.samples)
        progress.step("Diarisiert: \(diarization.segments.count) Segmente, \(diarization.speakerCentroids.count) lokale Sprecher")

        progress.step("Sprecher-Matching …")
        let matcher = try SpeakerMatcher(store: store, threshold: config.similarityThreshold)
        var localToGlobal: [String: String] = [:]
        var newIds: [String] = []
        var matchedIds: [String] = []
        var pendingEmbeddingIds: [Int64] = []
        let recordingId = "rec_" + UUID().uuidString

        // Embeddings get linked to the recording later (after the Recording row is inserted),
        // to avoid a FK violation against the not-yet-existing recordings row.
        for (localId, centroid) in diarization.speakerCentroids {
            let result = try matcher.matchOrCreate(centroid: centroid, recordingId: nil, segmentRange: nil)
            localToGlobal[localId] = result.speakerId
            pendingEmbeddingIds.append(result.embeddingId)
            if result.isNew {
                newIds.append(result.speakerId)
            } else {
                matchedIds.append(result.speakerId)
            }
        }

        progress.step("Lade ASR-Modelle …")
        let asr = TranscriptionPipeline()
        let modelVersion: AsrModelVersion = (lang == .en) ? .v2 : .v3
        try await asr.loadModels(version: modelVersion)

        progress.step("Transkribiere \(diarization.segments.count) Segmente …")
        // v2 is English-only and doesn't accept the script-filter `language` hint;
        // only pass it to the multilingual v3 model.
        let asrLang: Language? = (modelVersion == .v3) ? TranscriptionPipeline.language(for: lang) : nil
        let transcribed = try await asr.transcribe(
            diarized: diarization.segments,
            samples: audio.samples,
            sampleRate: audio.sampleRate,
            language: asrLang
        )

        let segments: [RecordingSegment] = transcribed.map { seg in
            RecordingSegment(
                recordingId: recordingId,
                speakerId: localToGlobal[seg.localSpeakerId],
                startSec: seg.startSec,
                endSec: seg.endSec,
                text: seg.text,
                confidence: seg.confidence
            )
        }

        let createdAt = Date()
        let baseName = makeFileBaseName(title: title, date: createdAt)
        let mdPath = config.transcriptsDir.appendingPathComponent("\(baseName).md")
        let jsonPath = config.transcriptsDir.appendingPathComponent("\(baseName).json")

        let labels = try currentLabels()
        let labelFn: (String) -> String = { id in labels[id] ?? "Unbekannt-\(String(id.suffix(6)))" }

        let recording = Recording(
            id: recordingId,
            title: title,
            sourcePath: audioPath.path,
            durationSec: audio.durationSec,
            language: lang.rawValue,
            transcriptMd: mdPath.path,
            transcriptJson: jsonPath.path,
            createdAt: createdAt
        )

        progress.step("Persistiere & rendere Transkripte …")
        let md = MarkdownRenderer.render(
            title: title,
            date: createdAt,
            durationSec: audio.durationSec,
            language: lang.rawValue,
            segments: segments,
            speakerLabel: labelFn
        )
        try md.write(to: mdPath, atomically: true, encoding: .utf8)

        let jsonData = try JSONRenderer.render(recording: recording, segments: segments, speakerLabel: labelFn)
        try jsonData.write(to: jsonPath)

        try store.insertRecording(recording, segments: segments)
        try store.annotateEmbeddings(ids: pendingEmbeddingIds, recordingId: recordingId)

        return TranscribeOutput(
            recording: recording,
            segments: segments,
            markdownPath: mdPath,
            jsonPath: jsonPath,
            newSpeakerIds: newIds,
            matchedSpeakerIds: matchedIds
        )
    }

    private func currentLabels() throws -> [String: String] {
        var map: [String: String] = [:]
        for s in try store.allSpeakers() {
            if let label = s.label { map[s.id] = label }
        }
        return map
    }

    private func makeFileBaseName(title: String?, date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let ts = f.string(from: date)
        let slug = (title ?? "aufnahme")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return "\(ts)-\(slug.isEmpty ? "aufnahme" : slug)"
    }
}
