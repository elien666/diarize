import SwiftUI
import DiarizeCore

struct RootView: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var permissions: PermissionsManager
    @EnvironmentObject var autoMode: AutoModeController
    @EnvironmentObject var cleanup: AudioCleanupController
    @State private var searchQuery: String = ""
    @State private var showingSearch = false

    var body: some View {
        Group {
            if autoMode.isActive {
                AutoModeView()
            } else {
                libraryView
            }
        }
        .onAppear {
            autoMode.attach(library: library, permissions: permissions)
            cleanup.attach(library: library)
            cleanup.start()
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
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            } detail: {
                DetailRouter()
            }
            .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search …")
            .onSubmit(of: .search) { showingSearch = !searchQuery.isEmpty }
            .sheet(isPresented: $showingSearch) {
                SearchSheet(query: searchQuery, isPresented: $showingSearch)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        library.openImportDialog()
                    } label: {
                        Label("Add Recording", systemImage: "plus")
                    }
                    .disabled(library.importInProgress || library.isRecording)
                }
                ToolbarItem(placement: .navigation) {
                    RecordToolbarControl()
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        autoMode.enter()
                    } label: {
                        Label("Auto Recording Mode", systemImage: "wand.and.stars")
                    }
                    .disabled(!permissions.allGranted)
                    .help(permissions.allGranted
                        ? "Automatically record when a call is detected"
                        : "Grant Microphone and Screen Recording permissions first")
                }
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

            StatusBar()
        }
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
        switch library.sidebarSection {
        case .recordings:
            if let id = library.selectedRecordingId,
               let recording = library.recordings.first(where: { $0.id == id }) {
                RecordingDetailView(recording: recording)
            } else {
                EmptyDetail(text: "Select a recording from the sidebar.")
            }
        case .speakers:
            if let id = library.selectedSpeakerId,
               let speaker = library.speakers.first(where: { $0.id == id }) {
                SpeakerDetailView(speaker: speaker)
            } else {
                EmptyDetail(text: "Select a speaker from the sidebar.")
            }
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
