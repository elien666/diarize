import SwiftUI
import DiarizeCore

struct RecordToolbarControl: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var showPopover = false
    @State private var pendingTitle = ""
    @State private var selectedLanguage: AppConfig.Language = .auto

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Label("Start Recording", systemImage: "record.circle")
                .foregroundStyle(library.isRecording ? Color.secondary : Color.red)
        }
        .help(library.isRecording
              ? "A recording is already in progress"
              : "Start a live recording")
        .disabled(library.importInProgress || library.isRecording)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            recordPopover
        }
    }

    private var recordPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title (optional)", text: $pendingTitle)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240)

            Picker("Language", selection: $selectedLanguage) {
                Text("Auto").tag(AppConfig.Language.auto)
                Text("English").tag(AppConfig.Language.en)
                Text("Deutsch").tag(AppConfig.Language.de)
            }
            .pickerStyle(.segmented)

            Divider()

            VStack(spacing: 4) {
                sourceButton(label: "Microphone + System Audio", icon: "person.wave.2", sources: [.mic, .system])
                sourceButton(label: "Microphone Only",           icon: "mic",           sources: [.mic])
                sourceButton(label: "System Audio Only",         icon: "speaker.wave.3", sources: [.system])
            }
        }
        .padding(16)
    }

    private func sourceButton(label: String, icon: String, sources: Set<AudioRecorder.Source>) -> some View {
        Button {
            showPopover = false
            library.startRecording(sources: sources, title: pendingTitle, language: selectedLanguage)
            pendingTitle = ""
        } label: {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }
}
