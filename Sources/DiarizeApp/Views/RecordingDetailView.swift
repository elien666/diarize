import AVKit
import SwiftUI
import DiarizeCore

struct RecordingDetailView: View {
    let recording: Recording
    @EnvironmentObject var library: LibraryViewModel
    @StateObject private var player = AudioPlayer()
    @State private var segments: [RecordingSegment] = []
    @State private var renamingSpeakerId: String?
    @State private var renameDraft: String = ""
    @State private var pendingMerge: MergeRequest?
    @State private var pendingDelete = false
    @State private var pendingAudioDelete = false

    struct MergeRequest: Identifiable {
        let id = UUID()
        let fromId: String
        let fromLabel: String
        let intoId: String
        let intoLabel: String
    }

    private var isLiveRecording: Bool {
        recording.processingState == .recording
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controlBar
            Divider()
            content
        }
        .onAppear {
            reload()
            loadAudioIfNeeded()
            consumePendingJump()
        }
        .onChange(of: recording.id) { _, _ in
            reload()
            player.pause()
            player.seek(to: 0)
            loadAudioIfNeeded()
            consumePendingJump()
        }
        .onChange(of: recording.processingState) { _, newState in
            reload()
            // After analysis, the WAV is finalized (header + data flushed). Force a reload
            // even if URL is unchanged — the duration was 0 while still recording.
            if newState == .done || newState == .empty || newState == .failed {
                player.forceReload(url: URL(fileURLWithPath: recording.sourcePath))
            }
        }
        .onChange(of: library.pendingJumpSec) { _, _ in consumePendingJump() }
        .confirmationDialog(
            "Delete \"\(recording.title ?? "Recording")\"?",
            isPresented: $pendingDelete
        ) {
            Button("Delete Recording & Transcript", role: .destructive) {
                library.deleteRecording(recording.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transcript and all speaker assignments for this recording will be permanently deleted. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete audio for \"\(recording.title ?? "Recording")\"?",
            isPresented: $pendingAudioDelete
        ) {
            Button("Delete Audio", role: .destructive) {
                library.deleteAudioOnly(recording.id)
                player.pause()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The audio file will be permanently deleted. The transcript and all speaker assignments will be kept. This cannot be undone.")
        }
        .confirmationDialog(
            "Merge speakers?",
            isPresented: Binding(
                get: { pendingMerge != nil },
                set: { if !$0 { pendingMerge = nil } }
            ),
            presenting: pendingMerge
        ) { request in
            Button("Merge \"\(request.fromLabel)\" into \"\(request.intoLabel)\"", role: .destructive) {
                library.merge(from: request.fromId, into: request.intoId)
                pendingMerge = nil
                reload()
            }
            Button("Cancel", role: .cancel) {
                pendingMerge = nil
            }
        } message: { request in
            Text("All segments and voice data for \"\(request.fromLabel)\" will be permanently merged into \"\(request.intoLabel)\". \"\(request.fromLabel)\" will be removed.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(recording.title ?? "Recording")
                    .font(.title2.weight(.semibold))
                StateBadge(state: recording.processingState)
            }
            HStack(spacing: 12) {
                Text(recording.createdAt, format: .dateTime.year().month().day().hour().minute())
                Text("·")
                Text(formatDuration(recording.durationSec))
                if recording.processingState == .done {
                    Text("·")
                    Text(recording.language.uppercased())
                    Text("·")
                    Text("\(uniqueSpeakers().count) speakers")
                }
                Spacer()
                if recording.processingState == .done {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: recording.transcriptMd))
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .controlSize(.small)
                    .help("Open")
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: recording.transcriptMd)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .controlSize(.small)
                    .help("Reveal in Finder")
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(recording.transcriptMd, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .controlSize(.small)
                    .help("Copy Path")
                    Button {
                        library.retryAnalysis(recordingId: recording.id)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("Re-analyze")
                    if recording.hasAudio {
                        Button {
                            pendingAudioDelete = true
                        } label: {
                            Image(systemName: "waveform.slash")
                        }
                        .controlSize(.small)
                        .help("Delete Audio (keep transcript)")
                    }
                    Button(role: .destructive) {
                        pendingDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                    .help("Delete")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Control bar (player OR live recording controls)

    @ViewBuilder
    private var controlBar: some View {
        if isLiveRecording {
            liveRecordingBar
        } else if recording.processingState == .analyzing {
            analyzingBar
        } else if !recording.hasAudio {
            audioDeletedBar
        } else {
            playerBar
        }
    }

    private var audioDeletedBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            if let deletedAt = recording.audioDeletedAt {
                Text("Audio deleted on \(deletedAt, format: .dateTime.year().month().day()) — transcript kept")
            } else {
                Text("Audio deleted — transcript kept")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var analyzingBar: some View {
        let progress = library.activeAnalysisId == recording.id ? library.analysisProgress : nil
        return HStack(spacing: 12) {
            if let fraction = progress?.fraction {
                ProgressView(value: fraction, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 160)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(progress?.phase ?? "Analyzing …")
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var liveRecordingBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RecordingPulse()
                // Drive the elapsed display with a TimelineView so only this text ticks —
                // not the whole window. (Publishing the elapsed seconds through the shared
                // view model re-rendered the entire NavigationSplitView every second.)
                TimelineView(.periodic(from: library.recordingStartedAt ?? .now, by: 1)) { context in
                    let elapsed = (library.recordingStartedAt).map { context.date.timeIntervalSince($0) } ?? 0
                    Text(formatDuration(max(0, elapsed)))
                        .monospacedDigit()
                        .font(.title3.weight(.medium))
                }
                Text(library.recordingSourcesLabel)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button(role: .destructive) {
                    library.cancelRecording()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                Button {
                    library.stopRecordingAndTranscribe()
                } label: {
                    Label("Stop & Analyze", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            // Per-device live level meters. Isolated TimelineView — see RecordingLevels.
            if let meter = library.recordingMeter {
                RecordingLevels(meter: meter)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(player.duration <= 0)

            Slider(value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ), in: 0...max(player.duration, 1)) {
                Text("Time")
            }
            .disabled(player.duration <= 0)
            Text("\(formatDuration(player.currentTime)) / \(formatDuration(player.duration))")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch recording.processingState {
        case .recording:
            recordingState
        case .analyzing:
            analyzingState
        case .empty:
            emptyTranscriptState
        case .failed:
            failedState
        case .done:
            if segments.isEmpty {
                emptyTranscriptState
            } else {
                transcript
            }
        }
    }

    private var recordingState: some View {
        VStack(spacing: 16) {
            BreathingSymbol(systemName: "waveform.badge.mic", pointSize: 56, color: .systemRed)
                .frame(width: 72, height: 72)
            Text("Recording in progress")
                .font(.headline)
            Text("Stop the recording above with Stop & Analyze.\nDiarization and transcription will run afterwards.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var analyzingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Analysis in progress …")
                .font(.headline)
            Text(library.statusMessage.isEmpty ? "Diarization and transcription take about one minute per hour of audio." : library.statusMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyTranscriptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Transcript")
                .font(.headline)
            Text("No speech was detected in this recording.\nYou can still play it back above.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    let url = URL(fileURLWithPath: recording.sourcePath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                Button(role: .destructive) {
                    library.deleteRecording(recording.id)
                } label: {
                    Label("Delete Recording", systemImage: "trash")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var failedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Analysis Failed")
                .font(.headline)
            if let msg = recording.errorMessage, !msg.isEmpty {
                Text(msg)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 600)
            }
            HStack(spacing: 8) {
                Button {
                    library.retryAnalysis(recordingId: recording.id)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    library.deleteRecording(recording.id)
                } label: {
                    Label("Delete Recording", systemImage: "trash")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(segments, id: \.id) { seg in
                        SegmentRow(
                            segment: seg,
                            speakerLabel: library.speakerLabel(for: seg.speakerId),
                            color: seg.speakerId.map { SpeakerColors.color(for: $0) } ?? .gray,
                            isCurrent: isCurrent(seg),
                            isRenaming: renamingSpeakerId == seg.speakerId,
                            renameDraft: $renameDraft,
                            allSpeakers: library.speakers,
                            onTapTimestamp: { player.seek(to: seg.startSec); player.play() },
                            onStartRename: {
                                guard let sid = seg.speakerId else { return }
                                renamingSpeakerId = sid
                                renameDraft = library.speakerLabel(for: sid)
                            },
                            onSubmitRename: {
                                if let sid = renamingSpeakerId {
                                    library.updateLabel(speakerId: sid, name: renameDraft)
                                }
                                renamingSpeakerId = nil
                                reload()
                            },
                            onCancelRename: { renamingSpeakerId = nil },
                            onAssignSpeaker: { newSpeakerId in
                                if let segId = seg.id {
                                    if let targetId = newSpeakerId,
                                       let fromId = seg.speakerId,
                                       fromId != targetId {
                                        // Assigning to an existing speaker = merge
                                        let fromLabel = library.speakerLabel(for: fromId)
                                        let toLabel = library.speakerLabel(for: targetId)
                                        pendingMerge = MergeRequest(
                                            fromId: fromId,
                                            fromLabel: fromLabel,
                                            intoId: targetId,
                                            intoLabel: toLabel
                                        )
                                    } else {
                                        // nil = new speaker, or same speaker tapped
                                        library.setSegmentSpeaker(segmentId: segId, to: newSpeakerId)
                                        reload()
                                    }
                                }
                            },
                            onSplitHere: {
                                if let segId = seg.id {
                                    let t = player.currentTime > seg.startSec && player.currentTime < seg.endSec
                                        ? player.currentTime
                                        : (seg.startSec + seg.endSec) / 2
                                    library.splitSegment(segmentId: segId, atSec: t)
                                    reload()
                                }
                            }
                        )
                        .id(seg.id ?? 0)
                    }
                }
                .padding()
            }
            .onChange(of: player.currentTime) { _, _ in
                if let current = currentSegment(), let id = current.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func consumePendingJump() {
        guard let target = library.pendingJumpSec else { return }
        loadAudioIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            player.seek(to: target)
            player.play()
            library.pendingJumpSec = nil
        }
    }

    private func reload() {
        segments = library.segments(for: recording.id)
    }

    private func loadAudioIfNeeded() {
        guard recording.hasAudio else { return }
        let url = URL(fileURLWithPath: recording.sourcePath)
        if FileManager.default.fileExists(atPath: url.path) {
            player.load(url: url)
        }
    }

    private func uniqueSpeakers() -> [String] {
        Array(Set(segments.compactMap { $0.speakerId }))
    }

    private func currentSegment() -> RecordingSegment? {
        let t = player.currentTime
        return segments.first { $0.startSec <= t && t < $0.endSec }
    }

    private func isCurrent(_ seg: RecordingSegment) -> Bool {
        let t = player.currentTime
        return seg.startSec <= t && t < seg.endSec
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct StateBadge: View {
    let state: RecordingProcessingState
    var body: some View {
        switch state {
        case .recording:
            Label("Recording", systemImage: "record.circle")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.red.opacity(0.2)).foregroundStyle(.red)
                .font(.caption2.weight(.semibold))
                .clipShape(Capsule())
        case .analyzing:
            Label("Analyzing", systemImage: "circle.dotted")
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.blue.opacity(0.2)).foregroundStyle(.blue)
                .font(.caption2.weight(.semibold))
                .clipShape(Capsule())
        case .empty:
            Label("No Transcript", systemImage: "text.bubble")
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.gray.opacity(0.2)).foregroundStyle(.secondary)
                .font(.caption2.weight(.semibold))
                .clipShape(Capsule())
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle")
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.orange.opacity(0.2)).foregroundStyle(.orange)
                .font(.caption2.weight(.semibold))
                .clipShape(Capsule())
        case .done:
            EmptyView()
        }
    }
}

struct SegmentRow: View {
    let segment: RecordingSegment
    let speakerLabel: String
    let color: Color
    let isCurrent: Bool
    let isRenaming: Bool
    @Binding var renameDraft: String
    let allSpeakers: [Speaker]
    let onTapTimestamp: () -> Void
    let onStartRename: () -> Void
    let onSubmitRename: () -> Void
    let onCancelRename: () -> Void
    let onAssignSpeaker: (String?) -> Void   // nil = create new speaker
    let onSplitHere: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onTapTimestamp) {
                Text(formatTimestamp(segment.startSec))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    HStack {
                        TextField("Name", text: $renameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                            .onSubmit(onSubmitRename)
                        Button("OK", action: onSubmitRename).controlSize(.small)
                        Button("Cancel", action: onCancelRename).controlSize(.small)
                    }
                } else {
                    HStack(spacing: 6) {
                        speakerMenu
                        if hovering {
                            Button(action: onSplitHere) {
                                Image(systemName: "scissors")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Split segment here (at player position)")
                        }
                    }
                }
                Text(segment.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(6)
                    .background(isCurrent ? Color.yellow.opacity(0.18) : Color.clear)
                    .cornerRadius(4)
            }
            Spacer()
        }
        .onHover { hovering = $0 }
    }

    private var speakerMenu: some View {
        Menu {
            Section("Assign to another speaker") {
                ForEach(allSpeakers, id: \.id) { sp in
                    Button {
                        onAssignSpeaker(sp.id)
                    } label: {
                        Label(sp.label ?? "Unknown-\(String(sp.id.suffix(6)))",
                              systemImage: sp.id == segment.speakerId ? "checkmark" : "circle.fill")
                    }
                }
                Button {
                    onAssignSpeaker(nil)
                } label: {
                    Label("New Speaker …", systemImage: "person.badge.plus")
                }
            }
            Divider()
            Button {
                onStartRename()
            } label: {
                Label("Rename current speaker …", systemImage: "pencil")
            }
            .disabled(segment.speakerId == nil)
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(speakerLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Blinking red recording dot.
///
/// Driven by a `TimelineView` 1 Hz tick rather than a SwiftUI `.repeatForever`
/// animation. A repeating SwiftUI animation re-evaluates the view graph and
/// runs an AppKit constraint-layout pass through the surrounding
/// NavigationSplitView every frame (~33% CPU while recording). The timeline
/// here fires once per second and updates only this leaf — same cost as the
/// elapsed-time display, i.e. negligible. The opacity change is implicitly
/// animated so the blink fades smoothly between ticks (the eased interpolation
/// is composited by Core Animation, not re-evaluated by SwiftUI per frame).
private struct RecordingPulse: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.7)) { context in
            // Discrete blink: opacity flips once per tick. No implicit/repeating
            // SwiftUI animation, so there is no per-frame view-graph work — only
            // one update per 0.7s, like the elapsed-time display.
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.7) % 2 == 0
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(on ? 1.0 : 0.25)
        }
        .frame(width: 10, height: 10)
    }
}

/// An SF Symbol that "breathes" (opacity pulse) to signal an active recording.
///
/// Replaces `.symbolEffect(.variableColor.iterative)`, which — like any
/// continuous SwiftUI animation inside the NavigationSplitView — drove a
/// per-frame view-graph + AppKit constraint-layout pass costing ~38% CPU.
/// Here the pulse is a `CABasicAnimation` on the hosting layer's opacity: it is
/// handed to the Core Animation render server once and then composites on the
/// GPU with zero per-frame work in the app. The animation is installed in
/// `viewDidMoveToWindow` so it isn't dropped before the layer joins the render
/// tree (adding it earlier silently does nothing).
private struct BreathingSymbol: NSViewRepresentable {
    let systemName: String
    let pointSize: CGFloat
    let color: NSColor

    func makeNSView(context: Context) -> BreathingSymbolView {
        let v = BreathingSymbolView()
        v.configure(systemName: systemName, pointSize: pointSize, color: color)
        return v
    }

    func updateNSView(_ nsView: BreathingSymbolView, context: Context) {}
}

private final class BreathingSymbolView: NSView {
    private let imageView = NSImageView()

    func configure(systemName: String, pointSize: CGFloat, color: NSColor) {
        wantsLayer = true
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.image = image
        imageView.contentTintColor = color
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: widthAnchor),
            imageView.heightAnchor.constraint(equalTo: heightAnchor),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let layer = imageView.layer else { return }
        layer.removeAnimation(forKey: "breathe")
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1.0
        breathe.toValue = 0.35
        breathe.duration = 0.9
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathe.isRemovedOnCompletion = false
        layer.add(breathe, forKey: "breathe")
    }
}
