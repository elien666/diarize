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
    @State private var jumpToSegmentId: Int64?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            playerBar
            Divider()
            transcript
        }
        .onAppear { reload() }
        .onChange(of: recording.id) { _, _ in reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title ?? "Aufnahme")
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Text(recording.createdAt, format: .dateTime.year().month().day().hour().minute())
                Text("·")
                Text(formatDuration(recording.durationSec))
                Text("·")
                Text(recording.language.uppercased())
                Text("·")
                Text("\(uniqueSpeakers().count) Sprecher")
                Spacer()
                Button("Markdown öffnen") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: recording.transcriptMd))
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var playerBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)

                Slider(value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ), in: 0...max(player.duration, 1)) {
                    Text("Zeit")
                }
                Text("\(formatDuration(player.currentTime)) / \(formatDuration(player.duration))")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .onAppear { loadAudioIfNeeded() }
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

    // MARK: helpers

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
