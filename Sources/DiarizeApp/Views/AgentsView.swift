import AppKit
import SwiftUI

/// Explains the MCP server: what agents are, how to connect one and what they may do.
struct AgentsView: View {
    @State private var copied: String?

    /// The CLI embedded in the app bundle. Falls back to the bare command name when the
    /// app runs outside a bundle (e.g. `swift run`).
    private var cliPath: String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/diarize-cli").path
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : "diarize"
    }

    private var claudeCommand: String { "claude mcp add diarize -- \"\(cliPath)\" mcp" }

    private var jsonConfig: String {
        """
        {
          "mcpServers": {
            "diarize": {
              "command": "\(cliPath)",
              "args": ["mcp"]
            }
          }
        }
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                connect
                capabilities
                safety
                examples
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents").font(.largeTitle.weight(.semibold))
            Text("Let an AI assistant on this Mac read your recordings, sort them, name speakers and fix diarization mistakes. It connects through the Model Context Protocol (MCP). Everything stays local: nothing is uploaded.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect an agent").font(.title3.weight(.semibold))
            Text("The assistant starts diarize's built-in MCP server on demand. You only register the command once.")
                .foregroundStyle(.secondary)
            commandBox(title: "Claude Code", text: claudeCommand, key: "claude")
            commandBox(title: "Other MCP clients (JSON config)", text: jsonConfig, key: "json")
            Link("Read the full guide", destination: URL(string: "https://github.com/elien666/diarize/blob/main/docs/mcp.md")!)
                .font(.callout)
        }
    }

    private func commandBox(title: String, text: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = key
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copied == key { copied = nil }
                    }
                } label: {
                    Label(copied == key ? "Copied" : "Copy", systemImage: copied == key ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
            }
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What an agent can do").font(.title3.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                card("Read", "magnifyingglass", "Recordings, transcripts, speakers, folders and which speaker appears where.")
                card("Organize", "folder", "Titles, folders, the processed flag. Find failed recordings and retry the analysis.")
                card("Correct", "person.2.badge.gearshape", "Reassign segments, split turns, name and merge speakers, remove unused ones.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card(_ title: String, _ symbol: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(height: 26, alignment: .leading)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var safety: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Agents can also delete").font(.callout.weight(.medium))
                Text("A connected agent may delete audio, recordings, folders and speakers, and merge speakers. Corrections change how future voices are matched. Only connect agents you trust, and ask for a preview (merge dry run) before big clean-ups.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Things to ask").font(.title3.weight(.semibold))
            ForEach([
                "Give every untitled recording from this week a meaningful title and file it into a folder.",
                "Find unnamed speakers, look at what they say, and tell me who they probably are before renaming anyone.",
                "Retry all failed recordings and report what still fails.",
            ], id: \.self) { prompt in
                Label(prompt, systemImage: "text.bubble")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
