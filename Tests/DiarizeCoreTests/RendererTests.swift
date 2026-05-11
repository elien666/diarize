import Testing
import Foundation
@testable import DiarizeCore

@Suite struct RendererTests {

    @Test func markdownContainsHeaderAndSegments() {
        let segs: [RecordingSegment] = [
            RecordingSegment(recordingId: "rec_1", speakerId: "spk_a", startSec: 3.5, endSec: 8.2, text: "Hallo zusammen.", confidence: 0.9),
            RecordingSegment(recordingId: "rec_1", speakerId: "spk_b", startSec: 9.0, endSec: 12.0, text: "Servus.", confidence: 0.8),
        ]
        let labels: [String: String] = ["spk_a": "Björn", "spk_b": "Anna"]
        let md = MarkdownRenderer.render(
            title: "Test-Meeting",
            date: Date(timeIntervalSince1970: 1_750_000_000),
            durationSec: 120,
            language: "de",
            segments: segs,
            speakerLabel: { labels[$0] ?? $0 }
        )

        #expect(md.contains("# Test-Meeting"))
        #expect(md.contains("**Sprache:** de"))
        #expect(md.contains("**Sprecher:** Björn, Anna"))
        #expect(md.contains("**Björn:** Hallo zusammen."))
        #expect(md.contains("[00:00:04]") || md.contains("[00:00:03]"))   // rounding
    }

    @Test func jsonRendererProducesValidStructure() throws {
        let recording = Recording(
            id: "rec_42",
            title: "X",
            sourcePath: "/tmp/a.mp3",
            durationSec: 60,
            language: "de",
            transcriptMd: "/tmp/a.md",
            transcriptJson: "/tmp/a.json"
        )
        let segs: [RecordingSegment] = [
            RecordingSegment(recordingId: "rec_42", speakerId: "spk_x", startSec: 0, endSec: 5, text: "Hallo", confidence: 0.9),
        ]
        let data = try JSONRenderer.render(recording: recording, segments: segs, speakerLabel: { _ in "Björn" })
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["recordingId"] as? String == "rec_42")
        #expect((json?["segments"] as? [[String: Any]])?.count == 1)
        #expect((json?["speakers"] as? [[String: Any]])?.first?["label"] as? String == "Björn")
    }
}
