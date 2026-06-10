import SwiftUI
import DiarizeCore

// MARK: - SidebarItem

enum SidebarItem: Hashable {
    case recording(String)
    case speaker(String)
}

// MARK: - Drag/drop type

private let recordingUTI = "public.plain-text"

// MARK: - SidebarView

struct SidebarView: View {
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        List(selection: bindingForSelection()) {
            Section {
                RecordingTreeView()
            } header: {
                HStack {
                    Label("Recordings", systemImage: "waveform")
                    Spacer()
                    Button {
                        library.createFolder(name: "New Folder")
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Folder")
                    .padding(.trailing, 8)
                }
            }

            Section {
                ForEach(library.speakers, id: \.id) { sp in
                    NavigationLink(value: SidebarItem.speaker(sp.id)) {
                        SpeakerRow(speaker: sp)
                    }
                }
            } header: {
                Label("Speakers", systemImage: "person.2")
            }
        }
        .listStyle(.sidebar)
    }

    private func bindingForSelection() -> Binding<SidebarItem?> {
        Binding(
            get: {
                switch library.sidebarSection {
                case .recordings: return library.selectedRecordingId.map { .recording($0) }
                case .speakers: return library.selectedSpeakerId.map { .speaker($0) }
                }
            },
            set: { newValue in
                switch newValue {
                case .recording(let id):
                    library.sidebarSection = .recordings
                    library.selectedRecordingId = id
                case .speaker(let id):
                    library.sidebarSection = .speakers
                    library.selectedSpeakerId = id
                case nil:
                    break
                }
            }
        )
    }
}

// MARK: - RecordingTreeView

private struct RecordingTreeView: View {
    @EnvironmentObject var library: LibraryViewModel

    private var rootFolders: [RecordingFolder] {
        library.folders.filter { $0.parentId == nil }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var ungroupedRecordings: [Recording] {
        library.recordings.filter { $0.folderId == nil }
    }

    var body: some View {
        ForEach(rootFolders, id: \.id) { folder in
            FolderRow(folder: folder)
        }
        ForEach(ungroupedRecordings, id: \.id) { rec in
            RecordingRow(recording: rec)
        }
    }
}

// MARK: - FolderRow

private struct FolderRow: View {
    let folder: RecordingFolder
    @EnvironmentObject var library: LibraryViewModel
    @State private var isExpanded: Bool = true
    @State private var isRenaming: Bool = false
    @State private var renameDraft: String = ""
    @State private var isDropTarget: Bool = false
    @FocusState private var renameFocused: Bool

    private var children: [RecordingFolder] {
        library.folders.filter { $0.parentId == folder.id }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var recordings: [Recording] {
        library.recordings.filter { $0.folderId == folder.id }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(children, id: \.id) { child in
                FolderRow(folder: child)
            }
            ForEach(recordings, id: \.id) { rec in
                RecordingRow(recording: rec)
            }
        } label: {
            folderLabel
        }
        .onDrop(
            of: [recordingUTI],
            delegate: RecordingDropDelegate(targetFolderId: folder.id, library: library, isTargeted: $isDropTarget)
        )
        .listRowBackground(isDropTarget ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            Button("Rename Folder") { beginRename() }
            Button("New Subfolder") {
                library.createFolder(name: "New Folder", parentId: folder.id)
                isExpanded = true
            }
            Divider()
            Button(role: .destructive) {
                library.deleteFolder(folder.id)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var folderLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            if isRenaming {
                TextField("", text: $renameDraft)
                    .focused($renameFocused)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    // clicking outside cancels
                    .onDisappear { cancelRename() }
            } else {
                Text(folder.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    library.createFolder(name: "New Folder", parentId: folder.id)
                    isExpanded = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Subfolder")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func beginRename() {
        renameDraft = folder.name
        isRenaming = true
        // delay focus so the TextField is in the hierarchy first
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        renameFocused = false
        if !trimmed.isEmpty { library.renameFolder(folder.id, name: trimmed) }
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
    }
}

// MARK: - RecordingRow

struct RecordingRow: View {
    let recording: Recording
    @EnvironmentObject var library: LibraryViewModel
    @State private var isRenaming: Bool = false
    @State private var renameDraft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        NavigationLink(value: SidebarItem.recording(recording.id)) {
            rowContent
        }
        .contextMenu { contextMenuItems }
        .draggable(recording.id)
    }

    @ViewBuilder
    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                stateIndicator
                if isRenaming {
                    TextField("", text: $renameDraft)
                        .focused($renameFocused)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                } else {
                    Text(recording.title ?? "Recording")
                        .font(.body)
                        .lineLimit(1)
                }
            }
            if !isRenaming {
                HStack(spacing: 8) {
                    Text(recording.createdAt, style: .date)
                    Text("·")
                    Text(formatDuration(recording.durationSec))
                    Text("·")
                    Text(recording.language.uppercased())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            beginRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        if !library.folders.isEmpty {
            Menu("Move to Folder") {
                Button("No Folder") {
                    library.moveRecording(recording.id, toFolder: nil)
                }
                Divider()
                let roots = library.folders
                    .filter { $0.parentId == nil }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                ForEach(roots, id: \.id) { folder in
                    MoveToFolderMenu(folder: folder, recordingId: recording.id)
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            library.deleteRecording(recording.id)
        } label: {
            Label("Delete Recording", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch recording.processingState {
        case .recording:
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
        case .analyzing:
            ProgressView().controlSize(.mini)
        case .empty:
            Image(systemName: "text.bubble").foregroundStyle(.tertiary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .done:
            EmptyView()
        }
    }

    private func beginRename() {
        renameDraft = recording.title ?? "Recording"
        isRenaming = true
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        renameFocused = false
        if !trimmed.isEmpty { library.renameRecording(recording.id, title: trimmed) }
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - MoveToFolderMenu

/// Recursive submenu for the "Move to Folder" context action so nested folders
/// keep their hierarchy. Each level offers "Move here" plus a submenu per child.
private struct MoveToFolderMenu: View {
    let folder: RecordingFolder
    let recordingId: String
    @EnvironmentObject var library: LibraryViewModel

    private var children: [RecordingFolder] {
        library.folders
            .filter { $0.parentId == folder.id }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu(folder.name) {
            Button("Move here") {
                library.moveRecording(recordingId, toFolder: folder.id)
            }
            if !children.isEmpty {
                Divider()
                ForEach(children, id: \.id) { child in
                    MoveToFolderMenu(folder: child, recordingId: recordingId)
                }
            }
        }
    }
}

// MARK: - Drag & Drop

private struct RecordingDropDelegate: DropDelegate {
    let targetFolderId: String?
    let library: LibraryViewModel
    var isTargeted: Binding<Bool>?

    init(targetFolderId: String?, library: LibraryViewModel, isTargeted: Binding<Bool>? = nil) {
        self.targetFolderId = targetFolderId
        self.library = library
        self.isTargeted = isTargeted
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [recordingUTI])
    }

    func dropEntered(info: DropInfo) { isTargeted?.wrappedValue = true }
    func dropExited(info: DropInfo) { isTargeted?.wrappedValue = false }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted?.wrappedValue = false
        guard let provider = info.itemProviders(for: [recordingUTI]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let recordingId = item as? String else { return }
            Task { @MainActor in
                library.moveRecording(recordingId, toFolder: targetFolderId)
            }
        }
        return true
    }
}

// MARK: - SpeakerRow

struct SpeakerRow: View {
    let speaker: Speaker
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        HStack {
            Circle()
                .fill(SpeakerColors.color(for: speaker.id))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(speaker.label ?? "Unknown-\(String(speaker.id.suffix(6)))")
                    .lineLimit(1)
                Text("\(library.segmentCount(speakerId: speaker.id)) segments")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if speaker.label == nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
                    .help("Unnamed — add a label")
            }
        }
    }
}
