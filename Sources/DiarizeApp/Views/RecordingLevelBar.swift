import SwiftUI
import DiarizeCore

/// Bridges the live `AudioRecorder` to the recording UI without going through
/// `@Published` per-frame. The view polls `devices()` and the meter from a
/// TimelineView; nothing here republishes through the shared view model, so the
/// ticking VU display can't trigger a window-wide re-render (the same isolation
/// the elapsed-time display uses).
final class RecordingMeterHandle: Equatable {
    private let recorder: AudioRecorder
    private let requestedSources: Set<AudioRecorder.Source>

    init(recorder: AudioRecorder, requestedSources: Set<AudioRecorder.Source>) {
        self.recorder = recorder
        self.requestedSources = requestedSources
    }

    struct DeviceLevel: Identifiable {
        let source: AudioRecorder.Source
        let name: String
        /// 0...1 smoothed level for the dot bar.
        let level: Double
        /// Whether the source is currently delivering audio.
        let active: Bool
        var id: String { source.rawValue }
    }

    /// One entry per source that is actually capturing, with its current level.
    /// A requested source whose device name hasn't resolved yet (capture still
    /// spinning up, or it silently failed) is shown with its requested label so
    /// the user always sees what was asked for.
    func devices() -> [DeviceLevel] {
        let names = recorder.deviceNames
        return requestedSources
            .sorted { $0.rawValue < $1.rawValue }
            .map { source in
                let meterChannel: AudioLevelMeter.Channel = source == .mic ? .mic : .system
                let name = names[source] ?? fallbackName(for: source)
                return DeviceLevel(
                    source: source,
                    name: name,
                    level: recorder.meter.level(meterChannel),
                    active: recorder.meter.isActive(meterChannel)
                )
            }
    }

    private func fallbackName(for source: AudioRecorder.Source) -> String {
        switch source {
        case .mic: return "Microphone"
        case .system: return "System Audio"
        }
    }

    static func == (lhs: RecordingMeterHandle, rhs: RecordingMeterHandle) -> Bool {
        lhs === rhs
    }
}

/// A horizontal row of dots that lights up proportionally to a 0...1 level.
/// Pure leaf view — it draws from a value passed in, so a parent TimelineView can
/// re-render just this on each tick.
struct DotLevelBar: View {
    /// 0...1 level.
    let level: Double
    /// Whether the source is delivering audio at all (dimmed when not).
    let active: Bool
    var dotCount: Int = 14

    var body: some View {
        let lit = active ? Int((level * Double(dotCount)).rounded()) : 0
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .fill(color(for: i, lit: lit))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func color(for index: Int, lit: Int) -> Color {
        guard index < lit else { return Color.secondary.opacity(0.18) }
        // Green for the bulk of the range, amber, then red near the top so
        // clipping is obvious.
        let frac = Double(index) / Double(dotCount)
        if frac > 0.85 { return .red }
        if frac > 0.65 { return .orange }
        return .green
    }
}

/// The per-device level rows shown while recording. Driven by a single
/// TimelineView ~20 Hz so only this subtree updates — no window re-render.
struct RecordingLevels: View {
    let meter: RecordingMeterHandle

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { _ in
            let devices = meter.devices()
            VStack(alignment: .leading, spacing: 4) {
                ForEach(devices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.source == .mic ? "mic.fill" : "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundStyle(device.active ? .primary : .secondary)
                            .frame(width: 14)
                        Text(device.name)
                            .font(.caption)
                            .foregroundStyle(device.active ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(width: 180, alignment: .leading)
                        DotLevelBar(level: device.level, active: device.active)
                        if !device.active {
                            Text("waiting…")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
