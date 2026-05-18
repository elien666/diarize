import Foundation
import FluidAudio

public struct TranscribeOutput: Sendable {
    public let recording: Recording
    public let segments: [RecordingSegment]
    public let markdownPath: URL
    public let jsonPath: URL
    public let newSpeakerIds: [String]
    public let matchedSpeakerIds: [String]
    public let skipped: Bool        // true if existing recording with same hash was returned
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
    public enum DuplicatePolicy: Sendable {
        case skip       // return existing recording, do nothing
        case force      // ignore existing, transcribe again
    }

    private let config: AppConfig
    private let store: SpeakerStore
    private let progress: ProgressReporter

    public init(config: AppConfig, store: SpeakerStore, progress: ProgressReporter = ConsoleProgress()) {
        self.config = config
        self.store = store
        self.progress = progress
    }

    public func run(
        audioPath: URL,
        title: String?,
        language: AppConfig.Language?,
        duplicatePolicy: DuplicatePolicy = .skip
    ) async throws -> TranscribeOutput {
        try config.ensureDirectories()
        let lang = language ?? config.defaultLanguage

        progress.step("Computing source hash …")
        let hash = try AudioHasher.sha256(of: audioPath)
        progress.step("Hash: \(String(hash.prefix(12))) …")

        if duplicatePolicy == .skip, let existing = try store.recording(sourceHash: hash) {
            progress.step("Already transcribed (\(existing.id)) — skipping.")
            let segs = try store.segments(for: existing.id)
            return TranscribeOutput(
                recording: existing,
                segments: segs,
                markdownPath: URL(fileURLWithPath: existing.transcriptMd),
                jsonPath: URL(fileURLWithPath: existing.transcriptJson),
                newSpeakerIds: [],
                matchedSpeakerIds: Array(Set(segs.compactMap { $0.speakerId })),
                skipped: true
            )
        }

        // Create stub recording up-front so it appears in the UI immediately.
        let createdAt = Date()
        let baseName = makeFileBaseName(title: title, date: createdAt)
        let mdPath = config.transcriptsDir.appendingPathComponent("\(baseName).md")
        let jsonPath = config.transcriptsDir.appendingPathComponent("\(baseName).json")
        let recordingId = "rec_" + UUID().uuidString

        let stub = Recording(
            id: recordingId,
            title: title,
            sourcePath: audioPath.path,
            durationSec: 0,
            language: lang.rawValue,
            transcriptMd: mdPath.path,
            transcriptJson: jsonPath.path,
            createdAt: createdAt,
            sourceHash: hash,
            processingState: .analyzing
        )
        try store.upsertRecording(stub)

        return try await analyze(
            existingRecording: stub,
            audioPath: audioPath,
            language: lang,
            mdPath: mdPath,
            jsonPath: jsonPath,
            title: title
        )
    }

    /// Re-analyze a recording row that was created up-front (e.g. by the live-record flow).
    /// The audio file at `recording.sourcePath` must exist; sourceHash is recomputed.
    public func analyzeExisting(recordingId: String, language: AppConfig.Language?) async throws -> TranscribeOutput {
        guard let recording = try store.recording(id: recordingId) else {
            throw RerenderError.recordingNotFound(recordingId)
        }
        try config.ensureDirectories()
        let lang = language ?? AppConfig.Language(rawValue: recording.language) ?? config.defaultLanguage
        let audioPath = URL(fileURLWithPath: recording.sourcePath)

        try store.setProcessingState(recordingId: recordingId, state: .analyzing)

        // Recompute hash for the now-finished file (live recording grows during capture).
        progress.step("Computing source hash …")
        if let hash = try? AudioHasher.sha256(of: audioPath) {
            try store.setSourceHash(recordingId: recordingId, hash: hash)
        }

        let mdPath = URL(fileURLWithPath: recording.transcriptMd)
        let jsonPath = URL(fileURLWithPath: recording.transcriptJson)

        // Reload to get the latest hash etc.
        let refreshed = try store.recording(id: recordingId) ?? recording

        return try await analyze(
            existingRecording: refreshed,
            audioPath: audioPath,
            language: lang,
            mdPath: mdPath,
            jsonPath: jsonPath,
            title: refreshed.title
        )
    }

    private func analyze(
        existingRecording stub: Recording,
        audioPath: URL,
        language lang: AppConfig.Language,
        mdPath: URL,
        jsonPath: URL,
        title: String?
    ) async throws -> TranscribeOutput {
        do {
            progress.step("Loading audio …")
            let audio = try AudioLoader.load(url: audioPath)
            try store.updateRecordingDuration(id: stub.id, durationSec: audio.durationSec)

            progress.step("Loading diarization models …")
            let diarizer = DiarizationPipeline()
            try await diarizer.prepareModels()

            progress.step("Running diarization …")
            let diarization = try await diarizer.diarize(samples: audio.samples)
            progress.step("Diarized: \(diarization.segments.count) segments, \(diarization.speakerCentroids.count) local speakers")

            // No speech → mark empty and write an empty transcript.
            guard !diarization.segments.isEmpty else {
                try store.setProcessingState(recordingId: stub.id, state: .empty)
                try writeTranscripts(
                    recording: stub,
                    segments: [],
                    durationSec: audio.durationSec,
                    lang: lang.rawValue,
                    title: title,
                    mdPath: mdPath,
                    jsonPath: jsonPath,
                    createdAt: stub.createdAt
                )
                return TranscribeOutput(
                    recording: try store.recording(id: stub.id) ?? stub,
                    segments: [],
                    markdownPath: mdPath,
                    jsonPath: jsonPath,
                    newSpeakerIds: [],
                    matchedSpeakerIds: [],
                    skipped: false
                )
            }

            progress.step("Speaker matching …")
            let matcher = try SpeakerMatcher(store: store, threshold: config.similarityThreshold)
            var localToGlobal: [String: String] = [:]
            var newIds: [String] = []
            var matchedIds: [String] = []
            var pendingEmbeddingIds: [Int64] = []

            // Group per-segment embeddings by local speaker id for bulk storage below.
            var segmentEmbeddingsByLocal: [String: [(embedding: [Float], start: Double, end: Double)]] = [:]
            for seg in diarization.segments where !seg.embedding.isEmpty {
                segmentEmbeddingsByLocal[seg.localSpeakerId, default: []].append(
                    (seg.embedding, seg.startSec, seg.endSec)
                )
            }

            for (localId, centroid) in diarization.speakerCentroids {
                let result = try matcher.matchOrCreate(centroid: centroid, recordingId: nil, segmentRange: nil)
                localToGlobal[localId] = result.speakerId
                pendingEmbeddingIds.append(result.embeddingId)
                if result.isNew { newIds.append(result.speakerId) } else { matchedIds.append(result.speakerId) }

                // Store individual segment embeddings so future recordings have more
                // data points for k-NN voting — a single centroid is too fragile.
                if let segs = segmentEmbeddingsByLocal[localId] {
                    for s in segs {
                        let embId = try store.insertEmbedding(SpeakerEmbedding(
                            speakerId: result.speakerId,
                            vector: s.embedding,
                            recordingId: stub.id,
                            segmentStart: s.start,
                            segmentEnd: s.end
                        ))
                        pendingEmbeddingIds.append(embId)
                    }
                }
            }

            progress.step("Loading ASR models …")
            let asr = TranscriptionPipeline(progress: progress)
            let modelVersion: AsrModelVersion = (lang == .en) ? .v2 : .v3
            try await asr.loadModels(version: modelVersion)

            progress.step("Transcribing \(diarization.segments.count) segments …")
            let asrLang: Language? = (modelVersion == .v3) ? TranscriptionPipeline.language(for: lang) : nil
            let transcribed = try await asr.transcribe(
                diarized: diarization.segments,
                samples: audio.samples,
                sampleRate: audio.sampleRate,
                language: asrLang
            )

            let segments: [RecordingSegment] = transcribed.map { seg in
                RecordingSegment(
                    recordingId: stub.id,
                    speakerId: localToGlobal[seg.localSpeakerId],
                    startSec: seg.startSec,
                    endSec: seg.endSec,
                    text: seg.text,
                    confidence: seg.confidence
                )
            }

            // Replace existing segments (idempotent re-analysis)
            try store.replaceSegments(recordingId: stub.id, with: segments)
            try store.annotateEmbeddings(ids: pendingEmbeddingIds, recordingId: stub.id)

            let finalState: RecordingProcessingState = segments.isEmpty ? .empty : .done
            try store.setProcessingState(recordingId: stub.id, state: finalState)

            let final = try store.recording(id: stub.id) ?? stub

            progress.step("Persisting & rendering transcripts …")
            try writeTranscripts(
                recording: final,
                segments: segments,
                durationSec: audio.durationSec,
                lang: lang.rawValue,
                title: title,
                mdPath: mdPath,
                jsonPath: jsonPath,
                createdAt: stub.createdAt
            )

            return TranscribeOutput(
                recording: final,
                segments: segments,
                markdownPath: mdPath,
                jsonPath: jsonPath,
                newSpeakerIds: newIds,
                matchedSpeakerIds: matchedIds,
                skipped: false
            )
        } catch let error as ASRError where error.localizedDescription.lowercased().contains("no speech") {
            // Treat "no speech" as empty, not failed — keeps the recording usable for playback.
            try? store.setProcessingState(recordingId: stub.id, state: .empty)
            return TranscribeOutput(
                recording: try store.recording(id: stub.id) ?? stub,
                segments: [],
                markdownPath: mdPath,
                jsonPath: jsonPath,
                newSpeakerIds: [],
                matchedSpeakerIds: [],
                skipped: false
            )
        } catch {
            try? store.setProcessingState(recordingId: stub.id, state: .failed, errorMessage: error.localizedDescription)
            throw error
        }
    }

    /// Re-render Markdown + JSON for an existing recording using the current speaker labels.
    public func rerender(recordingId: String) throws -> TranscribeOutput {
        guard let recording = try store.recording(id: recordingId) else {
            throw RerenderError.recordingNotFound(recordingId)
        }
        let segments = try store.segments(for: recordingId)

        let mdPath = URL(fileURLWithPath: recording.transcriptMd)
        let jsonPath = URL(fileURLWithPath: recording.transcriptJson)

        try writeTranscripts(
            recording: recording,
            segments: segments,
            durationSec: recording.durationSec,
            lang: recording.language,
            title: recording.title,
            mdPath: mdPath,
            jsonPath: jsonPath,
            createdAt: recording.createdAt
        )

        return TranscribeOutput(
            recording: recording,
            segments: segments,
            markdownPath: mdPath,
            jsonPath: jsonPath,
            newSpeakerIds: [],
            matchedSpeakerIds: Array(Set(segments.compactMap { $0.speakerId })),
            skipped: false
        )
    }

    public enum RerenderError: Error, LocalizedError {
        case recordingNotFound(String)
        public var errorDescription: String? {
            switch self {
            case .recordingNotFound(let id): return "Recording '\(id)' not found."
            }
        }
    }

    private func writeTranscripts(
        recording: Recording,
        segments: [RecordingSegment],
        durationSec: Double,
        lang: String,
        title: String?,
        mdPath: URL,
        jsonPath: URL,
        createdAt: Date
    ) throws {
        let labels = try currentLabels()
        let labelFn: (String) -> String = { id in labels[id] ?? "Unknown-\(String(id.suffix(6)))" }

        let md = MarkdownRenderer.render(
            title: title,
            date: createdAt,
            durationSec: durationSec,
            language: lang,
            segments: segments,
            speakerLabel: labelFn
        )
        try md.write(to: mdPath, atomically: true, encoding: .utf8)

        let jsonData = try JSONRenderer.render(recording: recording, segments: segments, speakerLabel: labelFn)
        try jsonData.write(to: jsonPath)
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
        let slug = (title ?? "recording")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return "\(ts)-\(slug.isEmpty ? "recording" : slug)"
    }
}
