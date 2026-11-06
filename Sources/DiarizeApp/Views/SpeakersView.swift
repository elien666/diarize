import SwiftUI
import DiarizeCore

/// Full page for the speaker library: searchable table with usage numbers, filters for
/// unnamed speakers, a clean-up action for unused ones and merge suggestions. Selecting a
/// speaker opens the existing detail on the right.
struct SpeakersView: View {
    @EnvironmentObject var library: LibraryViewModel

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unnamed = "Unnamed", named = "Named"
        var id: String { rawValue }
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let named: Bool
        let recordings: Int
        let speechTime: Double
        let lastSeen: Date
    }

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var sortOrder = [KeyPathComparator(\Row.speechTime, order: .reverse)]
    @State private var mergePairs: [SpeakerMergeCandidate] = []
    @State private var showMergeSheet = false
    @State private var confirmCleanup = false

    private var allRows: [Row] {
        library.speakers.map { sp in
            let stats = library.speakerStats[sp.id]
            return Row(
                id: sp.id, name: sp.displayName, named: sp.label != nil,
                recordings: stats?.recordingCount ?? 0,
                speechTime: stats?.speechTimeSec ?? 0,
                lastSeen: stats?.lastSeen ?? .distantPast
            )
        }
    }

    private var rows: [Row] {
        allRows
            .filter { row in
                switch filter {
                case .all: return true
                case .unnamed: return !row.named
                case .named: return row.named
                }
            }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted(using: sortOrder)
    }

    private var unusedIds: [String] {
        allRows.filter { $0.recordings == 0 }.map(\.id)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                if !mergePairs.isEmpty { mergeBanner }
                table
            }
            .frame(minWidth: 460, idealWidth: 560)

            Group {
                if let id = library.selectedSpeakerId,
                   let speaker = library.speakers.first(where: { $0.id == id }) {
                    SpeakerDetailView(speaker: speaker).id(speaker.id)
                } else {
                    EmptyDetail(text: "Select a speaker to rename, merge or review.")
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        .task(id: library.speakers.map(\.id)) { await loadMergeSuggestions() }
        .sheet(isPresented: $showMergeSheet) {
            MergeSuggestionsSheet(pairs: $mergePairs, isPresented: $showMergeSheet)
        }
        .confirmationDialog(
            "Remove \(unusedIds.count) unused speakers?",
            isPresented: $confirmCleanup,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                for id in unusedIds { _ = library.deleteSpeakerIfEmpty(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These speakers have no segments in any recording. Their voice data is removed as well.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speakers").font(.title3.weight(.semibold))
                Text("\(library.speakers.count)").foregroundStyle(.secondary)
                Spacer()
                if !unusedIds.isEmpty {
                    Button {
                        confirmCleanup = true
                    } label: {
                        Label("Remove \(unusedIds.count) unused", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .help("Speakers that no recording references any more")
                }
            }
            HStack {
                TextField("Search speakers", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f == .unnamed ? "Unnamed \(allRows.filter { !$0.named }.count)" : f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(12)
    }

    private var mergeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
            Text(mergePairs.count == 1
                 ? "1 pair of speakers sounds like the same person"
                 : "\(mergePairs.count) pairs of speakers sound like the same person")
            Spacer()
            Button("Review") { showMergeSheet = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.15))
    }

    // MARK: Table

    private var table: some View {
        Table(rows, selection: Binding(
            get: { library.selectedSpeakerId },
            set: { library.selectedSpeakerId = $0 }
        ), sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    Circle().fill(SpeakerColors.color(for: row.id)).frame(width: 9, height: 9)
                    Text(row.name)
                        .foregroundStyle(row.named ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            TableColumn("Recordings", value: \.recordings) { row in
                Text("\(row.recordings)").monospacedDigit()
            }
            .width(min: 70, ideal: 80, max: 100)
            TableColumn("Speech time", value: \.speechTime) { row in
                Text(SidebarDurationFormat.string(row.speechTime)).monospacedDigit()
            }
            .width(min: 80, ideal: 90, max: 110)
            TableColumn("Last seen", value: \.lastSeen) { row in
                if row.lastSeen == .distantPast {
                    Text("—").foregroundStyle(.tertiary)
                } else {
                    Text(row.lastSeen, format: .dateTime.month().day())
                }
            }
            .width(min: 70, ideal: 80, max: 100)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, library.segmentCount(speakerId: id) == 0 {
                Button(role: .destructive) {
                    _ = library.deleteSpeakerIfEmpty(id)
                } label: {
                    Label("Delete Unused Speaker", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Suggestions

    private func loadMergeSuggestions() async {
        let store = library.store
        let threshold = library.config.similarityThreshold
        let pairs = await Task.detached(priority: .utility) {
            (try? store.mergeCandidates(minSimilarity: threshold, limit: 30)) ?? []
        }.value
        mergePairs = pairs
    }
}

// MARK: - Merge suggestions sheet

private struct MergeSuggestionsSheet: View {
    @EnvironmentObject var library: LibraryViewModel
    @Binding var pairs: [SpeakerMergeCandidate]
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Possible duplicates").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            Text("Similar voices are only a hint. Check the recordings before merging: a wrong merge makes future voice matching worse.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if pairs.isEmpty {
                Text("No suggestions left.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(pairs, id: \.pairId) { pair in
                        row(pair)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 380)
    }

    private func summary(_ speaker: Speaker) -> String {
        let stats = library.speakerStats[speaker.id]
        let recs = stats?.recordingCount ?? 0
        let time = SidebarDurationFormat.string(stats?.speechTimeSec ?? 0)
        return "\(speaker.displayName): \(recs) recording\(recs == 1 ? "" : "s"), \(time) speech"
    }

    @ViewBuilder
    private func row(_ pair: SpeakerMergeCandidate) -> some View {
        // Suggest keeping the named speaker, otherwise the one with more speech.
        let keepA = (pair.a.label != nil && pair.b.label == nil)
            || ((pair.a.label == nil) == (pair.b.label == nil)
                && (library.speakerStats[pair.a.id]?.speechTimeSec ?? 0) >= (library.speakerStats[pair.b.id]?.speechTimeSec ?? 0))
        let keep = keepA ? pair.a : pair.b
        let drop = keepA ? pair.b : pair.a
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pair.a.displayName).font(.body.weight(.medium))
                    Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
                    Text(pair.b.displayName).font(.body.weight(.medium))
                }
                Text(summary(pair.a)).font(.caption).foregroundStyle(.secondary)
                Text(summary(pair.b)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(String(format: "%.0f%% similar", pair.similarity * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Menu {
                Button("Merge \(drop.displayName) into \(keep.displayName)") { merge(drop: drop, keep: keep) }
                Button("Merge \(keep.displayName) into \(drop.displayName)") { merge(drop: keep, keep: drop) }
                Divider()
                Button("Open \(pair.a.displayName)") { library.openSpeaker(pair.a.id); isPresented = false }
                Button("Open \(pair.b.displayName)") { library.openSpeaker(pair.b.id); isPresented = false }
            } label: {
                Text("Merge …")
            }
            .menuStyle(.button)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func merge(drop: Speaker, keep: Speaker) {
        library.merge(from: drop.id, into: keep.id)
        pairs.removeAll { $0.a.id == drop.id || $0.b.id == drop.id }
    }
}

extension SpeakerMergeCandidate {
    /// Stable identity for a pair (a speaker can appear in several pairs).
    var pairId: String { a.id + "|" + b.id }
}
