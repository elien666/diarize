import SwiftUI
import DiarizeCore

/// Middle column: the recordings of whatever the sidebar points at (all, unfiled, or a
/// folder including its subfolders), narrowed by the filter chips and grouped by date.
/// Grouping is presentation only. It never changes which recordings match.
struct RecordingListView: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var autoMode: AutoModeController

    @State private var searchText = ""
    @State private var pendingDeleteId: String?

    private enum DateGroup: Int, CaseIterable {
        case today, yesterday, thisWeek, earlier

        var title: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "This Week"
            case .earlier: return "Earlier"
            }
        }

        static func of(_ date: Date) -> DateGroup {
            let cal = Calendar.current
            if cal.isDateInToday(date) { return .today }
            if cal.isDateInYesterday(date) { return .yesterday }
            if let week = cal.dateInterval(of: .weekOfYear, for: .now), week.contains(date) { return .thisWeek }
            return .earlier
        }
    }

    private var visible: [Recording] {
        library.recordingsInScope(filter: library.recordingFilter, matching: searchText)
    }

    private var grouped: [(group: DateGroup, items: [Recording])] {
        let buckets = Dictionary(grouping: visible) { DateGroup.of($0.createdAt) }
        return DateGroup.allCases.compactMap { g in
            buckets[g].map { (g, $0) }
        }
    }

    /// Recordings auto-mode captured this session that the user hasn't kept or deleted yet.
    private var pendingReviewIds: Set<String> {
        Set(autoMode.sessionItems.map(\.recordingId))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visible.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .onChange(of: attentionCount) { _, count in
            // The pill disappears at 0, so don't leave the filter stuck on.
            if count == 0, library.recordingFilter == .needsAttention { library.recordingFilter = .all }
        }
        .confirmationDialog(
            "Delete this recording permanently?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId { autoMode.delete(id) }
                pendingDeleteId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
        } message: {
            Text("The audio file and transcript will be removed and cannot be recovered.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(visible.count) \(visible.count == 1 ? "recording" : "recordings")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                // Right-aligned so it doesn't shift when the recording count changes width.
                if attentionCount > 0 {
                    attentionPill
                }
                Menu {
                    Button {
                        library.openImportDialog()
                    } label: {
                        Label("Import Audio File …", systemImage: "square.and.arrow.down")
                    }
                    .disabled(library.importInProgress || library.isRecording)
                    Divider()
                    Button {
                        var parent: String?
                        if case .folder(let id) = library.destination { parent = id }
                        library.requestNewFolder(parentId: parent)
                    } label: {
                        Label("New Folder …", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Import audio, new folder")
            }
            // Fixed height: the pill is taller than the count text, so without this the
            // header (and the list below) jumps when the pill appears or disappears.
            .frame(height: 26)
            TextField("Filter by title", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }
        .padding(12)
    }

    private var attentionCount: Int {
        library.recordingsInScope(filter: .needsAttention).count
    }

    /// One toggle pill in orange: failed analyses and recordings not yet marked processed.
    /// Only shown while there is something to look at.
    private var attentionPill: some View {
        let on = library.recordingFilter == .needsAttention
        return Button {
            library.recordingFilter = on ? .all : .needsAttention
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle")
                Text("Needs attention")
                Text("\(attentionCount)").fontWeight(.semibold)
            }
            .font(.callout)
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(on ? Color.orange.opacity(0.22) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.orange.opacity(on ? 1 : 0.6)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show only recordings that failed or haven't been marked processed")
    }

    // MARK: List

    private var list: some View {
        List(selection: $library.selectedRecordingId) {
            ForEach(grouped, id: \.group) { bucket in
                Section(bucket.group.title) {
                    ForEach(bucket.items, id: \.id) { rec in
                        RecordingRow(
                            recording: rec,
                            showTimeOnly: bucket.group == .today || bucket.group == .yesterday,
                            review: pendingReviewIds.contains(rec.id)
                                ? ReviewActions(
                                    keep: { autoMode.keep(rec.id) },
                                    delete: { pendingDeleteId = rec.id })
                                : nil
                        )
                        .tag(rec.id)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            if library.recordingFilter != .all || !searchText.isEmpty {
                Text("Nothing matches")
                    .font(.headline)
                Text("Try another filter or clear the search.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Text("No recordings here yet")
                    .font(.headline)
                Text("Start a recording, turn on Auto mode, or drop an audio file anywhere in this window.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RecordingRow

/// Keep / delete choices for a recording that auto mode just captured.
struct ReviewActions {
    let keep: () -> Void
    let delete: () -> Void
}

struct RecordingRow: View {
    let recording: Recording
    var showTimeOnly: Bool = false
    var review: ReviewActions?
    @EnvironmentObject var library: LibraryViewModel
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        rowContent
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
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                } else {
                    Text(recording.title ?? "Recording")
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if recording.processed {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .help("Marked processed")
                }
            }
            if !isRenaming {
                HStack(spacing: 6) {
                    if showTimeOnly {
                        Text(recording.createdAt, format: .dateTime.hour().minute())
                    } else {
                        Text(recording.createdAt, format: .dateTime.month().day().hour().minute())
                    }
                    Text("·")
                    Text(formatDuration(recording.durationSec))
                    if let path = folderHint {
                        Text("·")
                        Text(path).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let review {
                    HStack(spacing: 8) {
                        Label("Auto-recorded", systemImage: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(.tint)
                        Spacer()
                        Button("Keep", action: review.keep)
                            .help("Remove this hint. The recording stays in your library.")
                        Button("Delete", role: .destructive, action: review.delete)
                            .help("Delete audio and transcript")
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// Show where the recording lives whenever the list isn't already scoped to exactly that folder.
    private var folderHint: String? {
        guard let folderId = recording.folderId else { return nil }
        if case .folder(let scope) = library.destination, scope == folderId { return nil }
        return library.folderPath(folderId)
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
            Image(systemName: "record.circle").foregroundStyle(.red)
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
        SidebarDurationFormat.string(seconds)
    }
}

enum SidebarDurationFormat {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
