import SwiftUI
import DiarizeCore

struct RecordToolbarControl: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var showPopover = false
    @State private var pendingTitle = ""
    @State private var selectedLanguage: AppConfig.Language = .auto
    /// Persisted UID of the chosen mic. Empty string = follow the system default.
    @AppStorage("selectedMicDeviceUID") private var selectedMicUID = ""
    @State private var inputDevices: [AudioInputDevice] = []

    private var recordingDisabled: Bool {
        library.importInProgress || library.isRecording
    }

    var body: some View {
        HStack(spacing: 1) {
            // Quick record: start mic + system audio immediately, no menu.
            Button {
                library.startRecording(
                    sources: [.mic, .system],
                    title: "",
                    language: selectedLanguage,
                    micDeviceUID: selectedMicUID.isEmpty ? nil : selectedMicUID
                )
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .foregroundStyle(library.isRecording ? Color.secondary : Color.red)
            }
            .help(library.isRecording
                  ? "A recording is already in progress"
                  : "Start a live recording (microphone + system audio)")
            .disabled(recordingDisabled)

            // Caret: open the recording options menu.
            Button {
                showPopover = true
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(library.isRecording ? Color.secondary : Color.primary)
            }
            .help("Recording options")
            .disabled(recordingDisabled)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                recordPopover
                    .onAppear {
                        inputDevices = AudioInputDevices.all()
                        // Drop a stale selection (e.g. an unplugged USB mic) so the
                        // picker doesn't show a blank row.
                        if !selectedMicUID.isEmpty, !inputDevices.contains(where: { $0.uid == selectedMicUID }) {
                            selectedMicUID = ""
                        }
                    }
            }
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

            Picker("Microphone", selection: $selectedMicUID) {
                Text("System Default").tag("")
                ForEach(inputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .frame(minWidth: 240)

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
            library.startRecording(
                sources: sources,
                title: pendingTitle,
                language: selectedLanguage,
                micDeviceUID: sources.contains(.mic) && !selectedMicUID.isEmpty ? selectedMicUID : nil
            )
            pendingTitle = ""
        } label: {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }
}
