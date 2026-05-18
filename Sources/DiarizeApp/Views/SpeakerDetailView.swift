import SwiftUI
import DiarizeCore

struct SpeakerDetailView: View {
    let speaker: Speaker
    @EnvironmentObject var library: LibraryViewModel
    @State private var newLabel: String = ""
    @State private var mergeTargetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            actionsBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataList
                    appearancesList
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .onAppear { newLabel = speaker.label ?? "" }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(SpeakerColors.color(for: speaker.id))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.label ?? "Unnamed-\(String(speaker.id.suffix(6)))")
                    .font(.title2.weight(.semibold))
                Text(speaker.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private var actionsBar: some View {
        let segCount = library.segmentCount(speakerId: speaker.id)
        return HStack(spacing: 8) {
            TextField("Speaker name", text: $newLabel)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Button("Save") {
                library.updateLabel(speakerId: speaker.id, name: newLabel)
            }
            .keyboardShortcut(.defaultAction)
            Spacer()
            Menu("Merge into …") {
                ForEach(library.speakers.filter { $0.id != speaker.id }, id: \.id) { other in
                    Button(other.label ?? other.id) {
                        library.merge(from: speaker.id, into: other.id)
                    }
                }
            }
            .frame(maxWidth: 220)
            Button(role: .destructive) {
                library.deleteSpeakerIfEmpty(speaker.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(segCount > 0)
            .help(segCount > 0
                  ? "Can only be deleted when no segments reference this speaker (\(segCount) present — merge first)"
                  : "Remove speaker and embeddings")
        }
        .padding(.vertical, 8)
    }

    private var metadataList: some View {
        Form {
            LabeledContent("Segmente") { Text("\(library.segmentCount(speakerId: speaker.id))") }
            LabeledContent("Sprechzeit") { Text(formatDuration(library.speechTime(speakerId: speaker.id))) }
            LabeledContent("Created") { Text(speaker.createdAt, format: .dateTime) }
        }
        .formStyle(.grouped)
    }

    private var appearancesList: some View {
        let appearances = library.recordings(for: speaker.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recordings")
                    .font(.headline)
                Text("(\(appearances.count))")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if appearances.isEmpty {
                Text("This speaker has no segments yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appearances.enumerated()), id: \.element.recording.id) { idx, item in
                        Button {
                            library.openRecording(item.recording.id, jumpToSec: item.firstAppearance)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.recording.title ?? "Recording")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text(item.recording.createdAt, style: .date)
                                        Text("·")
                                        Text(item.recording.language.uppercased())
                                        Text("·")
                                        Text("from \(formatDuration(item.firstAppearance))")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(item.segmentCount) segments")
                                        .font(.caption.monospacedDigit())
                                    Text(formatDuration(item.speechTime))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(idx.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.05))
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal)
            }
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
