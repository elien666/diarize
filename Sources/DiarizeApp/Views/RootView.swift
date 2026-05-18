import SwiftUI
import DiarizeCore

struct RootView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var searchQuery: String = ""
    @State private var showingSearch = false

    var body: some View {
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

    var body: some View {
        HStack(spacing: 6) {
            if library.importInProgress {
                ProgressView().controlSize(.small)
            }
            Text(library.statusMessage.isEmpty ? " " : library.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
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
