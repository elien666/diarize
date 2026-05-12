import SwiftUI
import DiarizeCore

struct RootView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var searchQuery: String = ""
    @State private var showingSearch = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            DetailRouter()
        }
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Suchen …")
        .onSubmit(of: .search) { showingSearch = !searchQuery.isEmpty }
        .sheet(isPresented: $showingSearch) {
            SearchSheet(query: searchQuery, isPresented: $showingSearch)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    library.openImportDialog()
                } label: {
                    Label("Aufnahme hinzufügen", systemImage: "plus")
                }
                .disabled(library.importInProgress)
            }
            ToolbarItem(placement: .status) {
                HStack(spacing: 6) {
                    if library.importInProgress {
                        ProgressView().controlSize(.small)
                    }
                    Text(library.statusMessage.isEmpty ? " " : library.statusMessage)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(minWidth: 200, alignment: .leading)
                }
            }
        }
        .onChange(of: searchQuery) { _, new in
            if new.isEmpty { showingSearch = false }
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
                EmptyDetail(text: "Wähle eine Aufnahme aus der Sidebar.")
            }
        case .speakers:
            if let id = library.selectedSpeakerId,
               let speaker = library.speakers.first(where: { $0.id == id }) {
                SpeakerDetailView(speaker: speaker)
            } else {
                EmptyDetail(text: "Wähle einen Sprecher aus der Sidebar.")
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
