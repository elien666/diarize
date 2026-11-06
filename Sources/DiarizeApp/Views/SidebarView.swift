import SwiftUI
import DiarizeCore

// MARK: - SidebarView

/// Navigation only: capture controls on top, then where to look (recordings, speakers,
/// agents) and the folder tree. Lists of individual recordings live in the middle column.
struct SidebarView: View {
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        List(selection: selection) {
                Section {
                    Label("All Recordings", systemImage: "waveform")
                        .badge(library.recordings.count)
                        .tag(SidebarDestination.allRecordings)
                    Label("Speakers", systemImage: "person.2")
                        .badge(library.speakers.count)
                        .tag(SidebarDestination.speakers)
                    Label("Agents", systemImage: "sparkles")
                        .tag(SidebarDestination.agents)
                }

                Section {
                    UnfiledRow()
                        .tag(SidebarDestination.unfiled)
                    ForEach(folderRows, id: \.folder.id) { row in
                        FolderRow(folder: row.folder, depth: row.depth, hasChildren: row.hasChildren)
                            .tag(SidebarDestination.folder(row.folder.id))
                    }
                } header: {
                    HStack {
                        Text("Folders")
                        Spacer()
                        Button {
                            library.requestNewFolder()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("New folder")
                    }
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        handleDrop(items, into: nil, library: library)
                    }
                    .contextMenu {
                        Button {
                            library.requestNewFolder()
                        } label: {
                            Label("New Folder …", systemImage: "folder.badge.plus")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
    }

    private var selection: Binding<SidebarDestination?> {
        Binding(
            get: { library.destination },
            set: { if let new = $0 { library.destination = new } }
        )
    }

    /// The folder tree flattened to the rows that are currently visible. Flat, plain rows keep
    /// selection reliable, and expansion is ours to control (e.g. to reveal a new subfolder).
    private var folderRows: [(folder: RecordingFolder, depth: Int, hasChildren: Bool)] {
        var rows: [(folder: RecordingFolder, depth: Int, hasChildren: Bool)] = []
        func walk(parent: String?, depth: Int) {
            let kids = library.folders
                .filter { $0.parentId == parent }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            for kid in kids {
                let has = library.folders.contains { $0.parentId == kid.id }
                rows.append((kid, depth, has))
                if has, library.expandedFolders.contains(kid.id) { walk(parent: kid.id, depth: depth + 1) }
            }
        }
        walk(parent: nil, depth: 0)
        return rows
    }
}

// MARK: - Folder rows

/// Drag payloads are plain strings: a recording is its id, a folder is `folder:<id>`.
/// `folderId` is the drop target (nil = top level / no folder).
@MainActor
private func handleDrop(_ items: [String], into folderId: String?, library: LibraryViewModel) -> Bool {
    guard let item = items.first else { return false }
    if item.hasPrefix("folder:") {
        library.moveFolder(String(item.dropFirst("folder:".count)), toParent: folderId)
        return true
    }
    guard library.recordings.contains(where: { $0.id == item }) else { return false }
    library.moveRecording(item, toFolder: folderId)
    return true
}

private struct UnfiledRow: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 12, height: 16)
            Image(systemName: "tray")
            Text("No Folder").lineLimit(1)
            Spacer()
            Text("\(library.recordingCount(in: .unfiled))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            handleDrop(ids, into: nil, library: library)
        } isTargeted: { isDropTarget = $0 }
        .listRowBackground(isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button {
                library.requestNewFolder()
            } label: {
                Label("New Folder …", systemImage: "folder.badge.plus")
            }
        }
    }
}

private struct FolderRow: View {
    let folder: RecordingFolder
    let depth: Int
    let hasChildren: Bool
    @EnvironmentObject var library: LibraryViewModel
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var isDropTarget = false
    @State private var confirmDelete = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            disclosure
            Image(systemName: "folder")
            if isRenaming {
                TextField("", text: $renameDraft)
                    .focused($renameFocused)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .onDisappear { cancelRename() }
            } else {
                Text(folder.name).lineLimit(1)
                Spacer()
                Text("\(library.recordingCount(in: .folder(folder.id)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .contentShape(Rectangle())
        // Double-click renames. Observed, not a gesture, so a single click still selects the folder.
        .background(DoubleClickMonitor { if !isRenaming { beginRename() } })
        .draggable("folder:" + folder.id)
        .confirmationDialog(
            "Delete folder \"\(folder.name)\"?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) { library.deleteFolder(folder.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Subfolders are deleted too. Recordings inside move to No Folder; none are deleted.")
        }
        .dropDestination(for: String.self) { ids, _ in
            handleDrop(ids, into: folder.id, library: library)
        } isTargeted: { isDropTarget = $0 }
        .listRowBackground(isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button("Rename Folder") { beginRename() }
            Button("New Subfolder …") {
                library.requestNewFolder(parentId: folder.id)
            }
            Divider()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Folder …", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        if hasChildren {
            let open = library.expandedFolders.contains(folder.id)
            Button {
                if open { library.expandedFolders.remove(folder.id) }
                else { library.expandedFolders.insert(folder.id) }
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Collapse" : "Expand")
        } else {
            Color.clear.frame(width: 12, height: 16)
        }
    }

    private func beginRename() {
        renameDraft = folder.name
        isRenaming = true
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

// MARK: - New folder sheet

struct NewFolderSheet: View {
    let request: NewFolderRequest
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private var parentName: String? { library.folderPath(request.parentId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(parentName == nil ? "New Folder" : "New Subfolder in \(parentName!)")
                .font(.headline)
            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        library.createFolder(name: trimmed, parentId: request.parentId)
        dismiss()
    }
}

// MARK: - Move to folder menu (used by recording context menu)

/// Recursive submenu for "Move to Folder" so nested folders keep their hierarchy.
/// Each level offers "Move here" plus a submenu per child.
struct MoveToFolderMenu: View {
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
