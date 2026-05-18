import ArgumentParser
import DiarizeCore
import Foundation

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Records microphone and/or system audio, transcribes automatically after stop."
    )

    @Flag(name: .long, help: "Record microphone only.")
    var micOnly: Bool = false

    @Flag(name: .long, help: "Record system audio only (e.g. online meetings).")
    var systemOnly: Bool = false

    @Option(name: .long, help: "Path for the WAV recording. Default: <archive>/recordings/<timestamp>.wav")
    var output: String?

    @Option(name: .long, help: "Optional title for the later transcript.")
    var title: String?

    @Option(name: .long, help: "Language: de, en, auto (default from config).")
    var lang: String?

    @Flag(name: .long, help: "Do not transcribe automatically — keep the WAV file only.")
    var noTranscribe: Bool = false

    func run() async throws {
        let config = AppConfigLoader.load()
        try config.ensureDirectories()

        var sources: Set<AudioRecorder.Source> = []
        if micOnly {
            sources = [.mic]
        } else if systemOnly {
            sources = [.system]
        } else {
            sources = [.mic, .system]
        }

        let outputURL: URL = {
            if let output { return URL(fileURLWithPath: (output as NSString).expandingTildeInPath) }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd-HHmmss"
            let name = "rec-\(f.string(from: Date())).wav"
            return config.recordingsDir.appendingPathComponent(name)
        }()
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let language: AppConfig.Language?
        if let lang {
            guard let parsed = AppConfig.Language(rawValue: lang) else {
                throw ValidationError("Unknown language '\(lang)'. Allowed: de, en, auto.")
            }
            language = parsed
        } else {
            language = nil
        }

        let recorder = try AudioRecorder(config: AudioRecorder.Config(sources: sources, outputURL: outputURL))

        let sourceLabel = sources.map { $0.rawValue }.sorted().joined(separator: "+")
        FileHandle.standardError.write(Data("[diarize] Starting recording: \(sourceLabel) → \(outputURL.path)\n".utf8))
        FileHandle.standardError.write(Data("[diarize] Stop with Ctrl-C. File will be closed cleanly and (unless --no-transcribe) transcribed immediately.\n".utf8))

        try await recorder.start()
        let started = Date()

        // Wait for SIGINT/SIGTERM
        await waitForShutdown()

        let duration = Date().timeIntervalSince(started)
        FileHandle.standardError.write(Data(String(format: "[diarize] Stopping recording after %.1fs …\n", duration).utf8))
        try await recorder.stop()

        if noTranscribe {
            print("✓ Recording saved: \(outputURL.path)")
            print("  Transcribe later with: diarize transcribe \"\(outputURL.path)\"")
            return
        }

        FileHandle.standardError.write(Data("[diarize] Starting transcription …\n".utf8))
        let store = try SpeakerStore(path: config.databasePath)
        let pipeline = TranscribePipeline(config: config, store: store)
        let result = try await pipeline.run(
            audioPath: outputURL,
            title: title,
            language: language,
            duplicatePolicy: .force
        )
        print("✓ Recording: \(result.recording.id)")
        print("  Markdown: \(result.markdownPath.path)")
        print("  Speakers: \(result.matchedSpeakerIds.count) matched, \(result.newSpeakerIds.count) new")
    }

    /// Suspends until the process receives SIGINT or SIGTERM.
    private func waitForShutdown() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "diarize.signal")
            // Ignore default SIGINT handler (which would kill the process before we close the WAV).
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            let int = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
            let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
            let fired = ContinuationBox(continuation)
            int.setEventHandler { fired.fire() }
            term.setEventHandler { fired.fire() }
            int.resume()
            term.resume()
        }
    }

    /// Wraps a CheckedContinuation so we can safely fire it once even if both signal sources race.
    private final class ContinuationBox: @unchecked Sendable {
        private let continuation: CheckedContinuation<Void, Never>
        private let lock = NSLock()
        private var done = false
        init(_ c: CheckedContinuation<Void, Never>) { self.continuation = c }
        func fire() {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            continuation.resume()
        }
    }
}
