import SwiftUI
import DiarizeCore

struct SidebarView: View {
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        List(selection: bindingForSelection()) {
            Section {
                ForEach(library.recordings, id: \.id) { rec in
                    NavigationLink(value: SidebarItem.recording(rec.id)) {
                        RecordingRow(recording: rec)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            library.deleteRecording(rec.id)
                        } label: {
                            Label("Delete Recording", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Label("Recordings", systemImage: "waveform")
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

enum SidebarItem: Hashable {
    case recording(String)
    case speaker(String)
}

struct RecordingRow: View {
    let recording: Recording
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                stateIndicator
                Text(recording.title ?? "Recording")
                    .font(.body)
                    .lineLimit(1)
            }
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

    @ViewBuilder
    private var stateIndicator: some View {
        switch recording.processingState {
        case .recording:
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: true)
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

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

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
