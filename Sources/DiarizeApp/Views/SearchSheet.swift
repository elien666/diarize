import SwiftUI
import DiarizeCore

struct SearchSheet: View {
    let query: String
    @Binding var isPresented: Bool
    @EnvironmentObject var library: LibraryViewModel
    @State private var hits: [SearchHit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Search: \(query)", systemImage: "magnifyingglass")
                    .font(.headline)
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            Divider()
            if hits.isEmpty {
                Text("No results for '\(query)'.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(hits, id: \.segmentId) { hit in
                    Button {
                        jump(to: hit)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(hit.speakerLabel ?? "—")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(hit.speakerId.map { SpeakerColors.color(for: $0) } ?? .gray)
                                Text("·")
                                Text(hit.recordingTitle ?? hit.recordingId)
                                Text("·")
                                Text(formatDuration(hit.startSec))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HighlightedSnippet(snippet: hit.snippet)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 720, minHeight: 400, idealHeight: 520)
        .onAppear { runSearch() }
        .onChange(of: query) { _, _ in runSearch() }
    }

    private func runSearch() {
        hits = library.search(query)
    }

    private func jump(to hit: SearchHit) {
        library.sidebarSection = .recordings
        library.selectedRecordingId = hit.recordingId
        isPresented = false
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Renders FTS5 <mark>…</mark> spans as bold yellow inline.
struct HighlightedSnippet: View {
    let snippet: String

    var body: some View {
        Text(makeAttributed())
            .font(.body)
    }

    private func makeAttributed() -> AttributedString {
        var out = AttributedString()
        var s = snippet[...]
        while let openRange = s.range(of: "<mark>") {
            let prefix = AttributedString(s[..<openRange.lowerBound])
            out.append(prefix)
            let afterOpen = s[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "</mark>") {
                var match = AttributedString(afterOpen[..<closeRange.lowerBound])
                match.font = .body.weight(.bold)
                match.backgroundColor = .yellow.opacity(0.4)
                out.append(match)
                s = afterOpen[closeRange.upperBound...]
            } else {
                out.append(AttributedString(afterOpen))
                s = "".prefix(0)
                break
            }
        }
        out.append(AttributedString(s))
        return out
    }
}
