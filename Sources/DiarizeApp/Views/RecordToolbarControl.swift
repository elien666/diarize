import SwiftUI
import DiarizeCore

struct RecordToolbarControl: View {
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        // Live status & stop controls live in RecordingDetailView while recording.
        // The toolbar only offers to start a new recording.
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
                .foregroundStyle(library.isRecording ? Color.secondary : Color.red)
        }
        .help(library.isRecording
              ? "Eine Aufnahme läuft bereits"
              : "Live-Aufnahme starten")
        .disabled(library.importInProgress || library.isRecording)
    }
}
