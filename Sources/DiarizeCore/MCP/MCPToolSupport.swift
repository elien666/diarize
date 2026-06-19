import Foundation
import MCP

/// Error thrown by tool argument parsing / validation. Its message is surfaced to the
/// agent as the text of an `isError` tool result.
struct MCPToolError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// Thin typed accessor over a tool call's `[String: Value]` arguments.
struct ToolArgs {
    let raw: [String: Value]
    init(_ arguments: [String: Value]?) { self.raw = arguments ?? [:] }

    func has(_ key: String) -> Bool { raw[key] != nil }

    func isExplicitNull(_ key: String) -> Bool {
        if case .null? = raw[key] { return true }
        return false
    }

    func string(_ key: String) -> String? {
        guard let v = raw[key] else { return nil }
        return String(v, strict: false)
    }

    func requiredString(_ key: String) throws -> String {
        guard let s = string(key), !s.isEmpty else {
            throw MCPToolError("Missing required string argument '\(key)'")
        }
        return s
    }

    func int(_ key: String) -> Int? {
        guard let v = raw[key] else { return nil }
        return Int(v, strict: false)
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let i = int(key) else { throw MCPToolError("Missing required integer argument '\(key)'") }
        return i
    }

    func double(_ key: String) -> Double? {
        guard let v = raw[key] else { return nil }
        return Double(v, strict: false)
    }

    func requiredDouble(_ key: String) throws -> Double {
        guard let d = double(key) else { throw MCPToolError("Missing required number argument '\(key)'") }
        return d
    }

    func bool(_ key: String) -> Bool? {
        guard let v = raw[key] else { return nil }
        return Bool(v, strict: false)
    }

    func requiredBool(_ key: String) throws -> Bool {
        guard let b = bool(key) else { throw MCPToolError("Missing required boolean argument '\(key)'") }
        return b
    }

    func stringArray(_ key: String) -> [String]? {
        guard case let .array(items)? = raw[key] else { return nil }
        return items.compactMap { String($0, strict: false) }
    }

    func requiredStringArray(_ key: String) throws -> [String] {
        guard let arr = stringArray(key), !arr.isEmpty else {
            throw MCPToolError("Missing required non-empty string array argument '\(key)'")
        }
        return arr
    }
}

/// Shared JSON encoding for tool/resource text payloads. ISO8601 dates match the
/// existing CLI JSON conventions.
enum MCPJSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

// MARK: - DTOs (agent-facing shapes)

struct SpeakerDTO: Encodable {
    let id: String
    let label: String?
    let displayName: String
    let createdAt: Date
    let notes: String?

    init(_ s: Speaker) {
        id = s.id; label = s.label; displayName = s.displayName
        createdAt = s.createdAt; notes = s.notes
    }
}

struct FolderDTO: Encodable {
    let id: String
    let name: String
    let parentId: String?
    let createdAt: Date

    init(_ f: RecordingFolder) {
        id = f.id; name = f.name; parentId = f.parentId; createdAt = f.createdAt
    }
}

struct RecordingSummaryDTO: Encodable {
    let id: String
    let title: String?
    let createdAt: Date
    let durationSec: Double
    let language: String
    let processingState: String
    let folderId: String?
    let processed: Bool
    let processedAt: Date?
    let errorMessage: String?
    let hasAudio: Bool

    init(_ r: Recording) {
        id = r.id; title = r.title; createdAt = r.createdAt; durationSec = r.durationSec
        language = r.language; processingState = r.processingState.rawValue
        folderId = r.folderId; processed = r.processed; processedAt = r.processedAt
        errorMessage = r.errorMessage; hasAudio = r.hasAudio
    }
}

struct RecordingDetailDTO: Encodable {
    let id: String
    let title: String?
    let createdAt: Date
    let durationSec: Double
    let language: String
    let processingState: String
    let folderId: String?
    let processed: Bool
    let processedAt: Date?
    let errorMessage: String?
    let hasAudio: Bool
    let sourceHash: String?
    let sourcePath: String
    let transcriptMdPath: String
    let transcriptJsonPath: String
    let segmentCount: Int

    init(_ r: Recording, segmentCount: Int) {
        id = r.id; title = r.title; createdAt = r.createdAt; durationSec = r.durationSec
        language = r.language; processingState = r.processingState.rawValue
        folderId = r.folderId; processed = r.processed; processedAt = r.processedAt
        errorMessage = r.errorMessage; hasAudio = r.hasAudio; sourceHash = r.sourceHash
        sourcePath = r.sourcePath; transcriptMdPath = r.transcriptMd
        transcriptJsonPath = r.transcriptJson; self.segmentCount = segmentCount
    }
}

struct TranscriptSegmentDTO: Encodable {
    let id: Int64
    let startSec: Double
    let endSec: Double
    let speakerId: String?
    let speakerLabel: String?
    let text: String
    let confidence: Double?
}

struct TranscriptDTO: Encodable {
    let recordingId: String
    let title: String?
    let language: String
    let durationSec: Double
    let segments: [TranscriptSegmentDTO]
}

struct StatusDTO: Encodable {
    let isRecording: Bool
    let active: [RecordingSummaryDTO]
}
