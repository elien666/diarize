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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(recording.title ?? "Aufnahme")
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
                    Text("\(uniqueSpeakers().count) Sprecher")
                }
                Spacer()
                if recording.processingState == .done {
                    Button("Markdown öffnen") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: recording.transcriptMd))
                    }
                    .controlSize(.small)
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
            // While analyzing, file isn't seekable yet; hide player to avoid empty controls.
            EmptyView()
        } else {
            playerBar
        }
    }

    private var liveRecordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .opacity(0.4)
                .overlay(Circle().stroke(.red))
            Text(formatDuration(library.recordingElapsedSec))
                .monospacedDigit()
                .font(.title3.weight(.medium))
            Text(library.recordingSourcesLabel)
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Button(role: .destructive) {
                library.cancelRecording()
            } label: {
                Label("Verwerfen", systemImage: "trash")
            }
            Button {
                library.stopRecordingAndTranscribe()
            } label: {
                Label("Stop & Analysieren", systemImage: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            .keyboardShortcut("s", modifiers: .command)
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
                Text("Zeit")
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
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56))
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text("Aufnahme läuft")
                .font(.headline)
            Text("Beende die Aufnahme oben mit Stop & Analysieren.\nDanach werden Diarisierung und Transkription ausgeführt.")
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
            Text("Analyse läuft …")
                .font(.headline)
            Text(library.statusMessage.isEmpty ? "Diarisierung und Transkription dauern bei einer Stunde Audio etwa eine Minute." : library.statusMessage)
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
            Text("Kein Transkript")
                .font(.headline)
            Text("In dieser Aufnahme wurde keine Sprache erkannt.\nDu kannst sie oben trotzdem abspielen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    let url = URL(fileURLWithPath: recording.sourcePath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Im Finder zeigen", systemImage: "folder")
                }
                Button(role: .destructive) {
                    library.deleteRecording(recording.id)
                } label: {
                    Label("Aufnahme löschen", systemImage: "trash")
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
            Text("Analyse fehlgeschlagen")
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
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    library.deleteRecording(recording.id)
                } label: {
                    Label("Aufnahme löschen", systemImage: "trash")
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
                            onCancelRename: { renamingSpeakerId = nil }
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
            Label("Aufnahme", systemImage: "record.circle")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.red.opacity(0.2)).foregroundStyle(.red)
                .font(.caption2.weight(.semibold))
                .clipShape(Capsule())
        case .analyzing:
            Label("Analyse", systemImage: "circle.dotted")
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.blue.opacity(0.2)).foregroundStyle(.blue)
                .font(.caption2.weight(.semibold))
                .clipShape(Capsule())
        case .empty:
            Label("Kein Transkript", systemImage: "text.bubble")
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.gray.opacity(0.2)).foregroundStyle(.secondary)
                .font(.caption2.weight(.semibold))
                .clipShape(Capsule())
        case .failed:
            Label("Fehlgeschlagen", systemImage: "exclamationmark.triangle")
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
    let onTapTimestamp: () -> Void
    let onStartRename: () -> Void
    let onSubmitRename: () -> Void
    let onCancelRename: () -> Void

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
                        Button("Abbrechen", action: onCancelRename).controlSize(.small)
                    }
                } else {
                    Button(action: onStartRename) {
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(speakerLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Klicken zum Umbenennen")
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
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
