import SwiftUI
import DiarizeCore

struct RecordToolbarControl: View {
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        if library.isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(blinkOpacity)
                    .animation(.easeInOut(duration: 0.7).repeatForever(), value: blinkOpacity)
                Text(formatElapsed(library.recordingElapsedSec))
                    .monospacedDigit()
                    .font(.caption.weight(.medium))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(library.recordingSourcesLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    library.stopRecordingAndTranscribe()
                } label: {
                    Label("Stop & Transkribieren", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .help("Aufnahme beenden und transkribieren")

                Button {
                    library.cancelRecording()
                } label: {
                    Label("Verwerfen", systemImage: "trash")
                }
                .help("Aufnahme verwerfen ohne Transkription")
            }
        } else {
            Menu {
                Button {
                    library.startRecording(sources: [.mic, .system])
                } label: {
                    Label("Mikrofon + System-Audio", systemImage: "person.wave.2")
                }
                Button {
                    library.startRecording(sources: [.mic])
                } label: {
                    Label("Nur Mikrofon", systemImage: "mic")
                }
                Button {
                    library.startRecording(sources: [.system])
                } label: {
                    Label("Nur System-Audio", systemImage: "speaker.wave.3")
                }
            } label: {
                Label("Aufnahme starten", systemImage: "record.circle")
                    .foregroundStyle(.red)
            }
            .help("Live-Aufnahme starten")
            .disabled(library.importInProgress)
        }
    }

    private var blinkOpacity: Double { library.isRecording ? 0.3 : 1.0 }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
