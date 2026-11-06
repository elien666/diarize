import SwiftUI
import DiarizeCore

/// The two ways to capture audio, kept in the window toolbar so they stay visible when the
/// sidebar is hidden: record now (this view), or let Auto mode record calls (`AutoModeToggle`).
/// Solid red capsule. Toolbar items ignore `.borderedProminent` tinting and render gray, so
/// the record button draws its own fill.
struct RedPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.red.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

struct CaptureControls: View {
    @EnvironmentObject var library: LibraryViewModel

    /// Shared with `RecordingOptionsButton`.
    @AppStorage("recordingLanguage") private var selectedLanguage: AppConfig.Language = .auto
    /// Persisted UID of the chosen mic. Empty string = follow the system default.
    @AppStorage("selectedMicDeviceUID") private var selectedMicUID = ""

    var body: some View {
        if library.isRecording {
            recordingState
        } else {
            idleState
        }
    }

    // MARK: Idle

    private var idleState: some View {
        Button {
            library.startRecording(
                sources: [.mic, .system],
                title: "",
                language: selectedLanguage,
                micDeviceUID: selectedMicUID.isEmpty ? nil : selectedMicUID
            )
        } label: {
            Label("Start Recording", systemImage: "record.circle")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(RedPillButtonStyle())
        .disabled(library.importInProgress)
        .help("Record microphone and system audio")
    }

    // MARK: Recording

    private var recordingState: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 9, height: 9)
            // Isolated TimelineView: only this text ticks, not the whole window.
            TimelineView(.periodic(from: library.recordingStartedAt ?? .now, by: 1)) { context in
                let elapsed = library.recordingStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
                Text(Self.formatDuration(max(0, elapsed)))
                    .monospacedDigit()
                    .font(.body.weight(.medium))
            }
            Button {
                library.stopRecordingAndTranscribe()
            } label: {
                Label("Stop & Analyze", systemImage: "stop.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(RedPillButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            .help(library.recordingSourcesLabel)

            Button(role: .destructive) {
                library.cancelRecording()
            } label: {
                Image(systemName: "trash")
            }
            .help("Discard this recording")
        }
    }

    static func formatDuration(_ seconds: Double) -> String {
        SidebarDurationFormat.string(seconds)
    }
}

/// Recording options (title, language, microphone, sources). Sits at the right end of the
/// toolbar; hidden while a recording runs.
struct RecordingOptionsButton: View {
    @EnvironmentObject var library: LibraryViewModel

    @State private var showOptions = false
    @State private var pendingTitle = ""
    @AppStorage("recordingLanguage") private var selectedLanguage: AppConfig.Language = .auto
    @AppStorage("selectedMicDeviceUID") private var selectedMicUID = ""
    @State private var inputDevices: [AudioInputDevice] = []

    var body: some View {
        if !library.isRecording {
            Button {
                showOptions = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .disabled(library.importInProgress)
            .help("Recording options: title, language, microphone, sources")
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                optionsPopover
                    .onAppear {
                        inputDevices = AudioInputDevices.all()
                        // Drop a stale selection (e.g. an unplugged USB mic).
                        if !selectedMicUID.isEmpty, !inputDevices.contains(where: { $0.uid == selectedMicUID }) {
                            selectedMicUID = ""
                        }
                    }
            }
        }
    }

    private var optionsPopover: some View {
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
                sourceButton(label: "Microphone Only", icon: "mic", sources: [.mic])
                sourceButton(label: "System Audio Only", icon: "speaker.wave.3", sources: [.system])
            }
        }
        .padding(16)
    }

    private func sourceButton(label: String, icon: String, sources: Set<AudioRecorder.Source>) -> some View {
        Button {
            showOptions = false
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

/// Auto mode switch with a one-line status next to it.
struct AutoModeToggle: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var permissions: PermissionsManager
    @EnvironmentObject var autoMode: AutoModeController

    var body: some View {
        HStack(spacing: 8) {
            Text("Auto mode")
                .font(.body.weight(.medium))
            Toggle(isOn: Binding(
                get: { autoMode.isActive },
                set: { $0 ? autoMode.enter() : autoMode.exit() }
            )) {
                Text("Auto mode")
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!autoMode.isActive && !permissions.allGranted)

            VStack(alignment: .leading, spacing: 0) {
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(autoMode.isActive ? Color.green : Color.secondary)
                }
                if autoMode.isActive, autoMode.autoStopUnavailable {
                    Text("Stop manually (needs macOS 14.4)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.leading, 12)
        .help(permissions.allGranted
              ? "Record calls automatically: starts when another app uses the microphone, stops and transcribes when it ends."
              : "Grant Microphone and Screen Recording permissions first.")
    }

    /// Only shown while Auto mode is on. Missing permissions are reported in the footer;
    /// the switch is simply disabled until they are granted.
    private var status: String? {
        guard autoMode.isActive else { return nil }
        return library.isRecording ? "Recording a call" : "Waiting for a call …"
    }
}
