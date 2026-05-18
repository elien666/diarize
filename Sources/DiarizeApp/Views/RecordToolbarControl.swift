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
                Label("Microphone + System Audio", systemImage: "person.wave.2")
            }
            Button {
                library.startRecording(sources: [.mic])
            } label: {
                Label("Microphone Only", systemImage: "mic")
            }
            Button {
                library.startRecording(sources: [.system])
            } label: {
                Label("System Audio Only", systemImage: "speaker.wave.3")
            }
        } label: {
            Label("Start Recording", systemImage: "record.circle")
                .foregroundStyle(library.isRecording ? Color.secondary : Color.red)
        }
        .help(library.isRecording
              ? "A recording is already in progress"
              : "Start a live recording")
        .disabled(library.importInProgress || library.isRecording)
    }
}
