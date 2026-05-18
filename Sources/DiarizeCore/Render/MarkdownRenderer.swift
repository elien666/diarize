import Foundation

public enum MarkdownRenderer {
    public static func render(
        title: String?,
        date: Date,
        durationSec: Double,
        language: String,
        segments: [RecordingSegment],
        speakerLabel: (String) -> String
    ) -> String {
        var out = "# \(title ?? "Recording") — \(formatDate(date))\n"
        let speakerNames = orderedSpeakers(in: segments).map { speakerLabel($0) }
        out += "**Duration:** \(formatDuration(durationSec)) · **Language:** \(language)"
        if !speakerNames.isEmpty {
            out += " · **Speakers:** \(speakerNames.joined(separator: ", "))"
        }
        out += "\n\n## Transcript\n\n"

        for seg in segments {
            let ts = formatTimestamp(seg.startSec)
            let speaker = seg.speakerId.map { speakerLabel($0) } ?? "—"
            out += "[\(ts)] **\(speaker):** \(seg.text)\n\n"
        }
        return out
    }

    private static func orderedSpeakers(in segments: [RecordingSegment]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for s in segments {
            guard let id = s.speakerId, !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    static func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func formatDuration(_ seconds: Double) -> String {
        formatTimestamp(seconds)
    }

    static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
