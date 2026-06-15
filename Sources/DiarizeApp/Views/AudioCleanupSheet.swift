import SwiftUI
import DiarizeCore

/// Summary prompt shown by the GDPR auto-clean when one or more recordings have
/// audio older than the retention period. Lists the candidates and offers to
/// delete all their audio files at once — transcripts are always kept.
struct AudioCleanupSheet: View {
    @EnvironmentObject var cleanup: AudioCleanupController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Clean up old audio", systemImage: "lock.shield")
                    .font(.title3.weight(.semibold))
                Text("\(cleanup.pendingCleanup.count) recording(s) have audio older than \(AudioCleanupController.retentionDays) days. Their transcripts will be kept; only the audio files are deleted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List(cleanup.pendingCleanup, id: \.id) { rec in
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.title ?? "Recording")
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(rec.createdAt, format: .dateTime.year().month().day())
                            Text("·")
                            Text(formatDuration(rec.durationSec))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .frame(minHeight: 160, maxHeight: 260)
            .listStyle(.bordered)

            HStack {
                Spacer()
                Button("Later") { cleanup.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Delete All Audio", role: .destructive) { cleanup.confirmDeleteAll() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
