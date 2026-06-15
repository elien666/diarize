import SwiftUI
import DiarizeCore

/// Full-window screen shown while the dedicated auto-recording mode is active.
/// Replaces the normal library UI: a big "Auto Recording Enabled" headline, the
/// live idle/recording status, and the list of recordings captured this session.
struct AutoModeView: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var autoMode: AutoModeController

    @State private var pendingDeleteId: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusBlock
                .padding(.vertical, 28)
            Divider()
            sessionList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()
            Button {
                autoMode.exit()
            } label: {
                Label("Exit Auto Mode", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBlock: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 52))
                .foregroundStyle(library.isRecording ? .red : .secondary)
                .symbolEffect(.pulse, isActive: library.isRecording)

            Text("Auto Recording Enabled")
                .font(.system(size: 30, weight: .semibold))

            if library.isRecording {
                recordingStatus
            } else {
                Text("Waiting for a call …")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button {
                autoMode.manualToggleRecording()
            } label: {
                Label(
                    library.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: library.isRecording ? "stop.circle.fill" : "record.circle"
                )
                .frame(minWidth: 140)
            }
            .controlSize(.large)
            .tint(library.isRecording ? .red : .accentColor)
            .help("Manual override if auto start/stop doesn't trigger")

            if autoMode.autoStopUnavailable {
                Text("Auto-stop needs macOS 14.4 or later — stop recordings manually from the library.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
    }

    private var recordingStatus: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(.red).frame(width: 10, height: 10)
                TimelineView(.periodic(from: library.recordingStartedAt ?? .now, by: 1)) { context in
                    let elapsed = library.recordingStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
                    Text(Self.formatDuration(max(0, elapsed)))
                        .monospacedDigit()
                        .font(.title2.weight(.medium))
                }
                Text(library.recordingSourcesLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let meter = library.recordingMeter {
                RecordingLevels(meter: meter)
                    .frame(maxWidth: 360)
            }
        }
    }

    // MARK: - Session list

    @ViewBuilder
    private var sessionList: some View {
        if autoMode.sessionItems.isEmpty {
            VStack {
                Spacer()
                Text("No recordings yet this session.")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section("This Session") {
                    ForEach(autoMode.sessionItems) { item in
                        SessionRow(
                            item: item,
                            onKeep: { autoMode.keep(item.recordingId) },
                            onDelete: { pendingDeleteId = item.recordingId }
                        )
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct SessionRow: View {
    let item: AutoModeController.SessionItem
    let onKeep: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.body)
                speakersText
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(durationText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
            HStack(spacing: 8) {
                Button("Keep", action: onKeep)
                Button(role: .destructive, action: onDelete) {
                    Text("Delete")
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var speakersText: some View {
        switch item.state {
        case .recording:
            Text("recording …")
        case .analyzing:
            Text("analyzing …")
        case .failed:
            Text("analysis failed")
        case .done, .empty:
            if item.speakers.isEmpty {
                Text("no speakers detected")
            } else {
                Text(item.speakers.joined(separator: ", "))
            }
        }
    }

    private var durationText: String {
        item.durationSec > 0 ? AutoModeView.formatDuration(item.durationSec) : "—"
    }
}
