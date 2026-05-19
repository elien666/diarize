import Foundation
import GRDB

public struct Speaker: Codable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: String
    public var label: String?
    public var createdAt: Date
    public var notes: String?

    public static let databaseTableName = "speakers"

    public init(id: String = "spk_" + UUID().uuidString, label: String? = nil, createdAt: Date = Date(), notes: String? = nil) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
        self.notes = notes
    }

    public var displayName: String {
        label ?? "Unbekannt-\(String(id.suffix(6)))"
    }
}

public struct SpeakerEmbedding: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var id: Int64?
    public var speakerId: String
    public var vector: Data           // Float32 little-endian, dim 256
    public var recordingId: String?
    public var segmentStart: Double?
    public var segmentEnd: Double?
    public var createdAt: Date

    public static let databaseTableName = "speaker_embeddings"

    public init(speakerId: String, vector: [Float], recordingId: String? = nil, segmentStart: Double? = nil, segmentEnd: Double? = nil, createdAt: Date = Date()) {
        self.id = nil
        self.speakerId = speakerId
        self.vector = SpeakerEmbedding.encode(vector)
        self.recordingId = recordingId
        self.segmentStart = segmentStart
        self.segmentEnd = segmentEnd
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var asFloats: [Float] {
        SpeakerEmbedding.decode(vector)
    }

    public static func encode(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: buf.baseAddress, count: count))
        }
    }
}

public enum RecordingProcessingState: String, Codable, Sendable, CaseIterable {
    case recording      // live capture in progress
    case analyzing      // diarization + ASR running
    case done           // transcript exists
    case empty          // pipeline completed but no speech found
    case failed         // pipeline errored
}

public struct Recording: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var id: String
    public var title: String?
    public var sourcePath: String
    public var durationSec: Double
    public var language: String
    public var transcriptMd: String
    public var transcriptJson: String
    public var createdAt: Date
    public var sourceHash: String?
    public var processingState: RecordingProcessingState
    public var errorMessage: String?
    public var folderId: String?

    public static let databaseTableName = "recordings"

    public init(
        id: String = "rec_" + UUID().uuidString,
        title: String?,
        sourcePath: String,
        durationSec: Double,
        language: String,
        transcriptMd: String,
        transcriptJson: String,
        createdAt: Date = Date(),
        sourceHash: String? = nil,
        processingState: RecordingProcessingState = .done,
        errorMessage: String? = nil,
        folderId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourcePath = sourcePath
        self.durationSec = durationSec
        self.language = language
        self.transcriptMd = transcriptMd
        self.transcriptJson = transcriptJson
        self.createdAt = createdAt
        self.sourceHash = sourceHash
        self.processingState = processingState
        self.errorMessage = errorMessage
        self.folderId = folderId
    }
}

public struct RecordingFolder: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var createdAt: Date

    public static let databaseTableName = "recording_folders"

    public init(id: String = "fld_" + UUID().uuidString, name: String, parentId: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = createdAt
    }
}

public struct RecordingSegment: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var id: Int64?
    public var recordingId: String
    public var speakerId: String?
    public var startSec: Double
    public var endSec: Double
    public var text: String
    public var confidence: Double?

    public static let databaseTableName = "recording_segments"

    public init(recordingId: String, speakerId: String?, startSec: Double, endSec: Double, text: String, confidence: Double?) {
        self.id = nil
        self.recordingId = recordingId
        self.speakerId = speakerId
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
        self.confidence = confidence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
