import SwiftUI
import UniformTypeIdentifiers
import DiarizeCore

struct RootView: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var permissions: PermissionsManager
    @EnvironmentObject var autoMode: AutoModeController
    @EnvironmentObject var cleanup: AudioCleanupController
    @State private var searchQuery: String = ""
    @State private var showingSearch = false
    @State private var dropTargeted = false

    var body: some View {
        libraryView
            .onAppear {
                autoMode.attach(library: library, permissions: permissions)
                cleanup.attach(library: library)
                cleanup.start()
            }
            .sheet(item: $library.newFolderRequest) { request in
                NewFolderSheet(request: request)
            }
            .sheet(isPresented: Binding(
                get: { !cleanup.pendingCleanup.isEmpty },
                set: { if !$0 { cleanup.dismiss() } }
            )) {
                AudioCleanupSheet()
            }
    }

    private var libraryView: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 230, ideal: 260)
            } detail: {
                DetailRouter()
            }
            .toolbar {
                // In the toolbar, not the sidebar, so recording stays reachable with the sidebar hidden.
                ToolbarItemGroup(placement: .navigation) {
                    CaptureControls()
                    AutoModeToggle()
                }
                // Flexible item that fills the gap, so the options button sits at the right end,
                // next to the search field.
                ToolbarItem(placement: .principal) {
                    HStack {
                        Spacer(minLength: 0)
                        RecordingOptionsButton()
                    }
                    .padding(.trailing, 44) // keep the button inside the list column, off the divider
                    .frame(maxWidth: .infinity)
                }
            }
            .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search transcripts")
            .onSubmit(of: .search) { showingSearch = !searchQuery.isEmpty }
            .sheet(isPresented: $showingSearch) {
                SearchSheet(query: searchQuery, isPresented: $showingSearch)
            }
            .onChange(of: searchQuery) { _, new in
                if new.isEmpty { showingSearch = false }
            }
            .alert(item: $library.errorAlert) { err in
                Alert(
                    title: Text(err.title),
                    message: Text(err.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                importDropped(providers)
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .background(Color.accentColor.opacity(0.06))
                        .overlay {
                            Label("Drop audio to transcribe", systemImage: "square.and.arrow.down")
                                .font(.title3)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }

            StatusBar()
        }
    }

    /// Import audio dropped onto the window. The import is a rare case, so it has no
    /// toolbar button; dropping a file or File > Open Recording … (⌘O) is enough.
    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        guard !library.importInProgress, !library.isRecording,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") })
        else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
            else { return }
            Task { @MainActor in library.transcribe(audioURL: url, title: nil) }
        }
        return true
    }
}

struct StatusBar: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        HStack(spacing: 8) {
            if !permissions.allGranted {
                permissionWarning
            } else {
                if library.importInProgress {
                    if let progress = library.analysisProgress, let fraction = progress.fraction {
                        ProgressView(value: fraction, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                            .controlSize(.small)
                    } else if library.importInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var permissionWarning: some View {
        let missing = permissions.missing
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
        Text(missingLabel(missing))
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(1)
        ForEach(missing) { permission in
            Button {
                permissions.request(permission)
            } label: {
                Text("Grant \(shortName(permission))")
                    .font(.caption)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
    }

    private func missingLabel(_ missing: [PermissionsManager.Permission]) -> String {
        if missing.count == 1 {
            return "\(missing[0].displayName) permission required"
        }
        return "Permissions required for recording"
    }

    private func shortName(_ permission: PermissionsManager.Permission) -> String {
        switch permission {
        case .microphone: return "Microphone"
        case .screenRecording: return "Screen Recording"
        case .systemAudio: return "System Audio"
        }
    }

    private var label: String {
        if let progress = library.analysisProgress {
            return progress.phase
        }
        return library.statusMessage.isEmpty ? " " : library.statusMessage
    }
}

struct DetailRouter: View {
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        switch library.destination {
        case .allRecordings, .unfiled, .folder:
            HSplitView {
                RecordingListView()
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
                recordingDetail
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
        case .speakers:
            SpeakersView()
        case .agents:
            AgentsView()
        }
    }

    @ViewBuilder
    private var recordingDetail: some View {
        if let id = library.selectedRecordingId,
           let recording = library.recordings.first(where: { $0.id == id }) {
            RecordingDetailView(recording: recording)
        } else {
            EmptyDetail(text: "Select a recording from the list.")
        }
    }
}

struct EmptyDetail: View {
    let text: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
