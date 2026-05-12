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
            metadataList
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
                Text(speaker.label ?? "Unbenannt-\(String(speaker.id.suffix(6)))")
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
        HStack(spacing: 8) {
            TextField("Sprecher-Name", text: $newLabel)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Button("Speichern") {
                library.updateLabel(speakerId: speaker.id, name: newLabel)
            }
            .keyboardShortcut(.defaultAction)
            Spacer()
            Menu("Mergen in …") {
                ForEach(library.speakers.filter { $0.id != speaker.id }, id: \.id) { other in
                    Button(other.label ?? other.id) {
                        library.merge(from: speaker.id, into: other.id)
                    }
                }
            }
            .frame(maxWidth: 220)
        }
        .padding(.vertical, 8)
    }

    private var metadataList: some View {
        Form {
            LabeledContent("Segmente") { Text("\(library.segmentCount(speakerId: speaker.id))") }
            LabeledContent("Sprechzeit") { Text(formatDuration(library.speechTime(speakerId: speaker.id))) }
            LabeledContent("Erstellt") { Text(speaker.createdAt, format: .dateTime) }
        }
        .formStyle(.grouped)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
