import AppKit
import SwiftUI
import DiarizeCore

struct SettingsView: View {
    @EnvironmentObject var library: LibraryViewModel

    @State private var selectedLanguage: AppConfig.Language = .auto
    @State private var threshold: Float = 0.5
    @State private var calibrationResult: String = ""
    @State private var calibrating = false
    @State private var dedupeResult: String = ""
    @State private var deduping = false
    @State private var backfillResult: String = ""
    @State private var backfilling = false
    @State private var showRestartAlert = false

    @AppStorage(AudioCleanupController.Defaults.autoCleanEnabled)
    private var autoCleanEnabled = true
    @AppStorage(AudioCleanupController.Defaults.audioRetentionDays)
    private var audioRetentionDays = AudioCleanupController.Defaults.fallbackRetentionDays

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Default Language", selection: $selectedLanguage) {
                    Text("Auto-detect").tag(AppConfig.Language.auto)
                    Text("English").tag(AppConfig.Language.en)
                    Text("Deutsch").tag(AppConfig.Language.de)
                }
                .onChange(of: selectedLanguage) { _, lang in
                    library.updateDefaultLanguage(lang)
                }
            }

            Section("Privacy") {
                Toggle("Suggest deleting old audio automatically", isOn: $autoCleanEnabled)
                Stepper("Keep audio for \(audioRetentionDays) day(s)",
                        value: $audioRetentionDays, in: 1...365)
                    .disabled(!autoCleanEnabled)
                Text("Only the audio file is deleted — transcripts and speaker assignments are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speaker Matching") {
                LabeledContent("Similarity Threshold") {
                    HStack(spacing: 8) {
                        Slider(value: $threshold, in: 0.3...0.95, step: 0.01)
                            .frame(minWidth: 160)
                            .onChange(of: threshold) { _, v in
                                library.updateSimilarityThreshold(v)
                            }
                        Text(String(format: "%.2f", threshold))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                HStack {
                    Button("Calibrate from Labeled Speakers") {
                        calibrating = true
                        calibrationResult = ""
                        Task {
                            if let result = await library.recalibrateThreshold() {
                                let rec = result.recommendedThreshold
                                let conf = result.confidence.rawValue
                                calibrationResult = "Recommended: \(String(format: "%.2f", rec)) (confidence: \(conf))"
                                await MainActor.run {
                                    threshold = rec
                                    library.updateSimilarityThreshold(rec)
                                }
                            } else {
                                calibrationResult = "Need ≥ 2 labeled speakers with embeddings."
                            }
                            calibrating = false
                        }
                    }
                    .disabled(calibrating)
                    if calibrating { ProgressView().controlSize(.small) }
                }
                if !calibrationResult.isEmpty {
                    Text(calibrationResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Archive") {
                LabeledContent("Path") {
                    Text(library.config.archivePath.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .font(.caption.monospaced())
                }
                Button("Change Archive Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.prompt = "Select"
                    if panel.runModal() == .OK, let url = panel.url {
                        library.updateArchivePath(url)
                        showRestartAlert = true
                    }
                }
                .alert("Restart Required", isPresented: $showRestartAlert) {
                    Button("OK") {}
                } message: {
                    Text("The archive path change takes effect after restarting the app.")
                }

                Divider()

                HStack {
                    Button("Remove Duplicates") {
                        deduping = true
                        dedupeResult = ""
                        Task {
                            let n = await library.deduplicateArchive()
                            dedupeResult = n == 0 ? "No duplicates found." : "Removed \(n) duplicate(s)."
                            deduping = false
                        }
                    }
                    .disabled(deduping)
                    if deduping { ProgressView().controlSize(.small) }
                }
                if !dedupeResult.isEmpty {
                    Text(dedupeResult).font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Button("Re-render All Transcripts") {
                        library.rerenderAllTranscripts()
                    }
                    .disabled(library.importInProgress)
                    if library.importInProgress { ProgressView().controlSize(.small) }
                }

                HStack {
                    Button("Backfill Audio Hashes") {
                        backfilling = true
                        backfillResult = ""
                        Task {
                            await library.backfillHashes()
                            backfillResult = "Done."
                            backfilling = false
                        }
                    }
                    .disabled(backfilling)
                    if backfilling { ProgressView().controlSize(.small) }
                }
                if !backfillResult.isEmpty {
                    Text(backfillResult).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .onAppear {
            selectedLanguage = library.config.defaultLanguage
            threshold = library.config.similarityThreshold
        }
    }
}
