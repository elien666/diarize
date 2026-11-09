import SwiftUI
import AVFoundation
import DiarizeCore

/// Plays a single transcript segment and stops at its end. One segment plays at a time.
@MainActor
final class SegmentPlayback: ObservableObject {
    @Published private(set) var playingId: Int64?
    private var player: AVPlayer?
    private var endObserver: Any?
    private var finishObserver: NSObjectProtocol?

    func toggle(_ segment: RecordingSegment, url: URL) {
        guard let id = segment.id else { return }
        if playingId == id { stop(); return }
        stop()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        playingId = id
        let end = CMTime(seconds: segment.endSec, preferredTimescale: 600)
        endObserver = p.addBoundaryTimeObserver(forTimes: [NSValue(time: end)], queue: .main) { [weak self] in
            Task { @MainActor in self?.stop() }
        }
        finishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        let start = CMTime(seconds: segment.startSec, preferredTimescale: 600)
        p.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak p] finished in
            guard finished else { return }
            Task { @MainActor in p?.play() }
        }
    }

    func stop() {
        if let token = endObserver { player?.removeTimeObserver(token) }
        if let obs = finishObserver { NotificationCenter.default.removeObserver(obs) }
        endObserver = nil
        finishObserver = nil
        player?.pause()
        player = nil
        playingId = nil
    }
}

extension SpeakerMergeCandidate {
    /// Order-independent key, so a dismissed pair stays dismissed.
    var dismissKey: String { [a.id, b.id].sorted().joined(separator: "|") }
}

enum DismissedMergePairs {
    private static let key = "dismissedMergePairs"
    static var all: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    static func remove(_ pairKey: String) {
        var set = all
        set.remove(pairKey)
        UserDefaults.standard.set(Array(set), forKey: key)
    }
    static func add(_ pairKey: String) {
        var set = all
        set.insert(pairKey)
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}

/// One undoable step: the queue as it was before, plus how to reverse the data change.
private struct UndoEntry {
    let label: String
    let pairsBefore: [SpeakerMergeCandidate]
    let revert: () -> Void
}

/// Review queue for possible duplicate speakers: one pair at a time, side by side, with
/// playable sample segments so a human can decide by ear.
struct ReviewQueueSheet: View {
    @EnvironmentObject var library: LibraryViewModel
    @Binding var pairs: [SpeakerMergeCandidate]
    @Binding var isPresented: Bool

    @StateObject private var playback = SegmentPlayback()
    @State private var undoStack: [UndoEntry] = []
    @State private var newSpeakerSegment: RecordingSegment?
    @State private var newSpeakerName = ""
    @State private var samplePage = 0
    @State private var swapped = false

    private let pageSize = 3

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let pair = pairs.first {
                content(pair)
            } else {
                finished
            }
        }
        .frame(width: 680, height: 540)
        .onDisappear { playback.stop() }
        .alert("New speaker", isPresented: Binding(
            get: { newSpeakerSegment != nil },
            set: { if !$0 { newSpeakerSegment = nil } }
        )) {
            TextField("Name (optional)", text: $newSpeakerName)
            Button("Create") {
                if let seg = newSpeakerSegment { move(seg, to: nil, newLabel: newSpeakerName) }
                newSpeakerSegment = nil
            }
            Button("Cancel", role: .cancel) { newSpeakerSegment = nil }
        } message: {
            Text("Moves this sample to a new speaker and recalculates similarities.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Review duplicates").font(.title3.weight(.semibold))
            if !pairs.isEmpty {
                Text("\(pairs.count) left").foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(undoStack.isEmpty)
            .help(undoStack.last.map { "Undo: \($0.label)" } ?? "Nothing to undo")
            Button("Done") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    private var finished: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(.green)
            Text("No pairs left to review").font(.headline)
            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pair

    @ViewBuilder
    private func content(_ pair: SpeakerMergeCandidate) -> some View {
        let sides = orderedKeepDrop(pair)
        VStack(spacing: 0) {
            HStack {
                Text(String(format: "%.0f%% similar", pair.similarity * 100))
                    .font(.callout.weight(.medium))
                if pair.similarity < library.config.similarityThreshold + 0.03 {
                    Text("barely above threshold")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("Similar voices are only a hint. Listen before merging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                sideColumn(pair.a, other: pair.b)
                Divider()
                sideColumn(pair.b, other: pair.a)
            }
            .frame(maxHeight: .infinity)
            Divider()
            actionBar(pair, keep: sides.keep, drop: sides.drop)
        }
        .id(pair.pairId)
    }

    private func sideColumn(_ speaker: Speaker, other: Speaker) -> some View {
        let stats = library.speakerStats[speaker.id]
        let samples = pageSamples(speaker)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(SpeakerColors.color(for: speaker.id)).frame(width: 10, height: 10)
                Text(speaker.displayName).font(.headline).lineLimit(1)
                Spacer()
                Button("Open") {
                    library.openSpeaker(speaker.id)
                    isPresented = false
                }
                .controlSize(.small)
                .buttonStyle(.link)
            }
            Text("\(stats?.recordingCount ?? 0) recordings · \(SidebarDurationFormat.string(stats?.speechTimeSec ?? 0)) speech")
                .font(.caption)
                .foregroundStyle(.secondary)
            if samples.isEmpty {
                Text("No segments.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(samples, id: \.id) { seg in
                    ReviewSegmentRow(
                        segment: seg, playback: playback, current: speaker, other: other,
                        onMove: { target in
                            if let target {
                                move(seg, to: target.id, newLabel: nil)
                            } else {
                                newSpeakerName = ""
                                newSpeakerSegment = seg
                            }
                        }
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func actionBar(_ pair: SpeakerMergeCandidate, keep: Speaker, drop: Speaker) -> some View {
        let shownKeep = swapped ? drop : keep
        let shownDrop = swapped ? keep : drop
        return HStack(spacing: 10) {
            Button {
                samplePage += 1
                playback.stop()
            } label: {
                Label("More samples", systemImage: "arrow.triangle.2.circlepath")
            }
            .keyboardShortcut("r", modifiers: [])
            Spacer()
            Button("Skip") { skip() }
                .keyboardShortcut("s", modifiers: [])
            Button("Different people") { dismiss(pair) }
                .keyboardShortcut("n", modifiers: [])
                .help("Never suggest this pair again (N)")
            Menu {
                Button("Merge \(shownKeep.displayName) into \(shownDrop.displayName) instead") {
                    swapped.toggle()
                }
            } label: {
                Text("Keeps \(shownKeep.displayName)")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button {
                merge(drop: shownDrop, keep: shownKeep)
            } label: {
                Text("Same person (merge)")
            }
            .keyboardShortcut("j", modifiers: [])
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    // MARK: Logic

    /// Suggest keeping the named speaker, otherwise the one with more speech.
    private func orderedKeepDrop(_ pair: SpeakerMergeCandidate) -> (keep: Speaker, drop: Speaker) {
        let timeA = library.speakerStats[pair.a.id]?.speechTimeSec ?? 0
        let timeB = library.speakerStats[pair.b.id]?.speechTimeSec ?? 0
        let keepA = (pair.a.label != nil && pair.b.label == nil)
            || ((pair.a.label == nil) == (pair.b.label == nil) && timeA >= timeB)
        return keepA ? (pair.a, pair.b) : (pair.b, pair.a)
    }

    private func allSamples(_ speaker: Speaker) -> [RecordingSegment] {
        library.sampleSegments(for: speaker.id, limit: 60, requireAudio: true)
            .filter { ReviewSegmentRow.audioURL(for: $0, library: library) != nil }
            .prefix(pageSize * 4)
            .map { $0 }
    }

    private func pageSamples(_ speaker: Speaker) -> [RecordingSegment] {
        let all = allSamples(speaker)
        guard !all.isEmpty else { return [] }
        let pages = max(1, Int((Double(all.count) / Double(pageSize)).rounded(.up)))
        let start = (samplePage % pages) * pageSize
        return Array(all[start..<min(all.count, start + pageSize)])
    }

    /// Suggested pairs a human can judge by ear: not dismissed, and both speakers still have
    /// audio. A speaker without audio can't be compared, so it is simply left as it is.
    nonisolated static func reviewablePairs(store: SpeakerStore, threshold: Float) -> [SpeakerMergeCandidate] {
        let candidates = (try? store.mergeCandidates(minSimilarity: threshold, limit: 60)) ?? []
        let withAudio = (try? store.speakerIdsWithAudio()) ?? []
        let dismissed = DismissedMergePairs.all
        return candidates.filter {
            withAudio.contains($0.a.id) && withAudio.contains($0.b.id) && !dismissed.contains($0.dismissKey)
        }
    }

    /// Reassign one sample, then recompute the suggestions: centroids moved, so pairs can
    /// appear, vanish or change similarity. The pair under review stays first while it holds.
    private func move(_ segment: RecordingSegment, to speakerId: String?, newLabel: String?) {
        guard let segId = segment.id else { return }
        playback.stop()
        let currentKey = pairs.first?.dismissKey
        let before = pairs
        let target = speakerId.map { library.speakerLabel(for: $0) } ?? (newLabel?.isEmpty == false ? newLabel! : "new speaker")
        if let snap = library.reassignSegmentLearning(segmentId: segId, to: speakerId, newLabel: newLabel) {
            undoStack.append(UndoEntry(label: "moved sample to \(target)", pairsBefore: before) {
                library.undoReassign(snap)
            })
        }
        let store = library.store
        let threshold = library.config.similarityThreshold
        Task {
            var list = await Task.detached(priority: .userInitiated) {
                Self.reviewablePairs(store: store, threshold: threshold)
            }.value
            if let key = currentKey, let i = list.firstIndex(where: { $0.dismissKey == key }) {
                list.insert(list.remove(at: i), at: 0)
            }
            pairs = list
            samplePage = 0
            swapped = false
        }
    }

    private func resetPairState() {
        playback.stop()
        samplePage = 0
        swapped = false
    }

    private func undo() {
        guard let entry = undoStack.popLast() else { return }
        resetPairState()
        entry.revert()
        pairs = entry.pairsBefore
    }

    private func skip() {
        guard pairs.count > 1 else { return }
        undoStack.append(UndoEntry(label: "skipped pair", pairsBefore: pairs) {})
        resetPairState()
        pairs.append(pairs.removeFirst())
    }

    private func dismiss(_ pair: SpeakerMergeCandidate) {
        DismissedMergePairs.add(pair.dismissKey)
        undoStack.append(UndoEntry(label: "marked as different people", pairsBefore: pairs) {
            DismissedMergePairs.remove(pair.dismissKey)
        })
        resetPairState()
        pairs.removeAll { $0.pairId == pair.pairId }
    }

    private func merge(drop: Speaker, keep: Speaker) {
        let before = pairs
        let label = "merged \(drop.displayName) into \(keep.displayName)"
        resetPairState()
        let snapshot = library.mergeUndoable(from: drop.id, into: keep.id)
        if let snapshot {
            undoStack.append(UndoEntry(label: label, pairsBefore: before) { [library] in
                library.undoMerge(snapshot)
            })
        }
        pairs.removeAll { $0.a.id == drop.id || $0.b.id == drop.id }
    }
}

// MARK: - Segment row

private struct ReviewSegmentRow: View {
    let segment: RecordingSegment
    @ObservedObject var playback: SegmentPlayback
    let current: Speaker
    let other: Speaker
    let onMove: (Speaker?) -> Void
    @EnvironmentObject var library: LibraryViewModel

    static func audioURL(for segment: RecordingSegment, library: LibraryViewModel) -> URL? {
        guard let rec = library.recordings.first(where: { $0.id == segment.recordingId }),
              rec.hasAudio,
              FileManager.default.fileExists(atPath: rec.sourcePath)
        else { return nil }
        return URL(fileURLWithPath: rec.sourcePath)
    }

    private var moveMenu: some View {
        Menu {
            Button("Move to \(other.displayName)") { onMove(other) }
            Menu("Move to another speaker") {
                ForEach(library.speakers
                    .filter { $0.id != current.id && $0.id != other.id }
                    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
                        id: \.id) { sp in
                    Button(sp.displayName) { onMove(sp) }
                }
            }
            Divider()
            Button("New speaker …") { onMove(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("This sample is not \(current.displayName)")
    }

    private var isPlaying: Bool { playback.playingId == segment.id }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        let url = Self.audioURL(for: segment, library: library)
        let title = library.recordings.first { $0.id == segment.recordingId }?.title ?? "Recording"
        HStack(alignment: .top, spacing: 10) {
            Button {
                if let url { playback.toggle(segment, url: url) }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
            }
            .buttonStyle(.borderless)
            .disabled(url == nil)
            .help(url == nil ? "Audio deleted or missing" : "Play this segment")
            VStack(alignment: .leading, spacing: 3) {
                Text("\u{201C}\(segment.text)\u{201D}")
                    .font(.callout)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text("\(title) · \(formatDuration(segment.startSec)) · \(Int((segment.endSec - segment.startSec).rounded())) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            moveMenu
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture { if let url { playback.toggle(segment, url: url) } }
        .background(isPlaying ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
}
