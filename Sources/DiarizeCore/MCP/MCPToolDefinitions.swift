import MCP

extension DiarizeMCPServer {
    /// Build a JSON-Schema object `Value` for a tool's input.
    private static func schema(properties: [String: Value] = [:], required: [String] = []) -> Value {
        var object: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            object["required"] = .array(required.map { .string($0) })
        }
        return .object(object)
    }

    private static func prop(_ type: String, _ description: String) -> Value {
        ["type": .string(type), "description": .string(description)]
    }

    private static let readOnly = Tool.Annotations(readOnlyHint: true, idempotentHint: true)
    private static let safeWrite = Tool.Annotations(readOnlyHint: false, idempotentHint: true)
    private static let creating = Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
    private static let destructive = Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: false)

    static var toolDefinitions: [Tool] {
        [
            // MARK: Read
            Tool(
                name: "list_speakers",
                description: "List known speakers with usage stats: segmentCount, speechTimeSec, recordingCount, lastSeen and a 'named' flag. Use unnamed=true to find 'Unbekannt-…' speakers that still need a name. Speakers with recordingCount 0 are orphans and can be removed with delete_speaker.",
                inputSchema: schema(properties: [
                    "unnamed": prop("boolean", "true = only speakers without a name; false = only named; omit = all."),
                ]),
                annotations: readOnly
            ),
            Tool(
                name: "get_speaker",
                description: "Everything needed to identify one speaker: stats, the recordings they appear in (newest first, with per-recording speech time and first appearance) and their longest sample segments with text. Use it to decide who an 'Unbekannt-…' speaker is before calling rename_speaker.",
                inputSchema: schema(properties: [
                    "id": prop("string", "Speaker id."),
                    "sampleLimit": prop("integer", "Max sample segments (default 5)."),
                ], required: ["id"]),
                annotations: readOnly
            ),
            Tool(
                name: "suggest_merges",
                description: "Pairs of speakers whose voices are similar enough to be the same person, most similar first, with stats for both. A suggestion is not proof: check with get_speaker (and merge_speakers dryRun) before merging, a wrong merge degrades future voice matching.",
                inputSchema: schema(properties: [
                    "minSimilarity": prop("number", "Cosine similarity threshold 0-1 (default: the app's configured speaker threshold)."),
                    "limit": prop("integer", "Max pairs (default 20)."),
                ]),
                annotations: readOnly
            ),
            Tool(
                name: "list_folders",
                description: "List all folders. Reconstruct the hierarchy from each folder's parentId (null = root).",
                inputSchema: schema(),
                annotations: readOnly
            ),
            Tool(
                name: "list_recordings",
                description: "List recordings newest-first. Filter by processed flag, processing state (e.g. 'failed' for retry candidates), folder, or full-text search. Includes errorMessage and processingState.",
                inputSchema: schema(properties: [
                    "limit": prop("integer", "Max recordings to return (default 50)."),
                    "processed": prop("boolean", "true = only processed; false = only unprocessed; omit = any."),
                    "state": prop("string", "Filter by processing state: recording, analyzing, done, empty, failed."),
                    "folderId": prop("string", "Filter to this folder. Pass null for root (unfiled); omit for any folder."),
                    "search": prop("string", "Full-text search over transcript segments."),
                ]),
                annotations: readOnly
            ),
            Tool(
                name: "get_recording",
                description: "Get full metadata for one recording, including errorMessage, hasAudio and segment count.",
                inputSchema: schema(properties: ["id": prop("string", "Recording id.")], required: ["id"]),
                annotations: readOnly
            ),
            Tool(
                name: "get_transcript",
                description: "Get the diarized transcript of a recording as structured segments, each with an id, time range, speakerId/label, text and ASR confidence. Use the text + confidence to judge diarization quality, then correct it with reassign_segment / split_segment / rename_speaker / merge_speakers.",
                inputSchema: schema(properties: ["id": prop("string", "Recording id.")], required: ["id"]),
                annotations: readOnly
            ),
            Tool(
                name: "recording_status",
                description: "Whether a recording is currently in progress, and which recording(s).",
                inputSchema: schema(),
                annotations: readOnly
            ),

            // MARK: Write
            Tool(
                name: "set_title",
                description: "Set a recording's title.",
                inputSchema: schema(properties: [
                    "id": prop("string", "Recording id."),
                    "title": prop("string", "New title."),
                ], required: ["id", "title"]),
                annotations: safeWrite
            ),
            Tool(
                name: "move_recording",
                description: "Move a recording into a folder. Omit or pass null folderId to move it to the root (unfiled).",
                inputSchema: schema(properties: [
                    "id": prop("string", "Recording id."),
                    "folderId": prop("string", "Destination folder id, or null for root."),
                ], required: ["id"]),
                annotations: safeWrite
            ),
            Tool(
                name: "create_folder",
                description: "Create a folder, optionally nested under a parent. Returns the new folder.",
                inputSchema: schema(properties: [
                    "name": prop("string", "Folder name."),
                    "parentId": prop("string", "Parent folder id, or omit for a root folder."),
                ], required: ["name"]),
                annotations: creating
            ),
            Tool(
                name: "rename_folder",
                description: "Rename a folder.",
                inputSchema: schema(properties: [
                    "id": prop("string", "Folder id."),
                    "name": prop("string", "New name."),
                ], required: ["id", "name"]),
                annotations: safeWrite
            ),
            Tool(
                name: "move_folder",
                description: "Move a folder (with everything in it) under another folder, or to the top level when parentId is omitted or null. Refuses to move a folder into itself or one of its own subfolders.",
                inputSchema: schema(properties: [
                    "id": prop("string", "Folder id to move."),
                    "parentId": prop("string", "New parent folder id, or null for top level."),
                ], required: ["id"]),
                annotations: safeWrite
            ),
            Tool(
                name: "delete_folder",
                description: "Delete a folder. Child folders are deleted; recordings inside are moved to root (not deleted).",
                inputSchema: schema(properties: ["id": prop("string", "Folder id.")], required: ["id"]),
                annotations: destructive
            ),
            Tool(
                name: "set_processed",
                description: "Bulk set or clear the 'processed' flag on recordings. Returns the number updated.",
                inputSchema: schema(properties: [
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Recording ids."],
                    "processed": prop("boolean", "true to mark processed, false to clear."),
                ], required: ["ids", "processed"]),
                annotations: safeWrite
            ),
            Tool(
                name: "delete_audio",
                description: "GDPR: permanently delete a recording's raw audio file while keeping the transcript and speaker data. Irreversible.",
                inputSchema: schema(properties: ["id": prop("string", "Recording id.")], required: ["id"]),
                annotations: destructive
            ),
            Tool(
                name: "delete_recording",
                description: "Permanently and completely remove one or more recordings: transcript, segments, raw audio (if still present) and folder/speaker links. Unlike delete_audio — which only deletes the WAV and keeps the transcript — this leaves nothing behind: the recording no longer appears in list_recordings or get_recording. Use to discard noise / false-start captures (empty or fragment transcripts). Irreversible. Pass a single id, or ids for a batch. Returns how many were deleted and any ids that didn't exist.",
                inputSchema: schema(properties: [
                    "id": prop("string", "Recording id (single delete)."),
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Recording ids (batch delete). Combine with or use instead of 'id'."],
                ]),
                annotations: destructive
            ),
            Tool(
                name: "retry_analysis",
                description: "Re-run diarization + transcription on a recording (e.g. one that failed). Returns immediately; analysis runs in the background. Poll get_recording until processingState is done/empty/failed. Fails if the audio was deleted.",
                inputSchema: schema(properties: ["id": prop("string", "Recording id.")], required: ["id"]),
                annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
            ),

            // MARK: Diarization correction
            Tool(
                name: "reassign_segment",
                description: "Fix a mis-attributed segment: move it to the correct speaker (use a segment id from get_transcript). Also moves the segment's voice embedding so future recordings match this voice better. The speaker must already exist (see create_speaker / list_speakers).",
                inputSchema: schema(properties: [
                    "segmentId": prop("integer", "Segment id from get_transcript."),
                    "speakerId": prop("string", "Target speaker id (must exist)."),
                ], required: ["segmentId", "speakerId"]),
                annotations: safeWrite
            ),
            Tool(
                name: "reassign_segments",
                description: "Batch version of reassign_segment: move many segments (ids from get_transcript) to one existing speaker in a single call. Each affected recording is re-rendered once. Unknown segment ids are reported in 'missing' and skipped.",
                inputSchema: schema(properties: [
                    "segmentIds": ["type": "array", "items": ["type": "integer"], "description": "Segment ids."],
                    "speakerId": prop("string", "Target speaker id (must exist)."),
                ], required: ["segmentIds", "speakerId"]),
                annotations: safeWrite
            ),
            Tool(
                name: "set_speaker_notes",
                description: "Set or clear free-text notes on a speaker, e.g. 'collective bucket for demo-day video voices, ignore' or 'probably the organizer of the 9:14 audio test'. Notes are shown by list_speakers and get_speaker. They are lost when the speaker is merged away, so copy them first if needed.",
                inputSchema: schema(properties: [
                    "id": prop("string", "Speaker id."),
                    "notes": prop("string", "Notes text, or empty/null to clear."),
                ], required: ["id"]),
                annotations: safeWrite
            ),
            Tool(
                name: "delete_speaker",
                description: "Delete a speaker that has no segments left (an orphan, or an empty bucket after reassigning). Refuses if any segment still references it: merge_speakers or reassign_segments first. Also removes its voice embeddings. Irreversible.",
                inputSchema: schema(properties: ["id": prop("string", "Speaker id.")], required: ["id"]),
                annotations: destructive
            ),
            Tool(
                name: "create_speaker",
                description: "Create a new speaker, e.g. to attribute a voice that isn't a known speaker yet. Returns the new speaker. Reassign segments to it with reassign_segment.",
                inputSchema: schema(properties: [
                    "label": prop("string", "Optional name for the speaker."),
                ]),
                annotations: creating
            ),
            Tool(
                name: "rename_speaker",
                description: "Set or clear a speaker's name (e.g. name an 'Unbekannt-…' speaker you identified from the transcript). Re-renders the transcript files of every recording the speaker appears in.",
                inputSchema: schema(properties: [
                    "id": prop("string", "Speaker id."),
                    "label": prop("string", "New name, or empty/null to clear it."),
                ], required: ["id"]),
                annotations: safeWrite
            ),
            Tool(
                name: "merge_speakers",
                description: "Merge two speaker identities that are the same person: all of 'from''s segments and voice embeddings move to 'into', then 'from' is deleted. Re-renders the affected recordings. Pass dryRun=true to only preview what would change (nothing is written).",
                inputSchema: schema(properties: [
                    "from": prop("string", "Speaker id to merge away (deleted)."),
                    "into": prop("string", "Speaker id to keep."),
                    "dryRun": prop("boolean", "true = preview only: returns segment/recording counts and both names, changes nothing."),
                ], required: ["from", "into"]),
                annotations: destructive
            ),
            Tool(
                name: "split_segment",
                description: "Split one segment at an absolute timestamp (seconds) when it bundled two speakers' speech. The first half keeps the original id; the second half is a new segment with the same speaker — reassign it afterwards. Returns the new segment id.",
                inputSchema: schema(properties: [
                    "segmentId": prop("integer", "Segment id from get_transcript."),
                    "atSec": prop("number", "Absolute split time in seconds, strictly inside the segment."),
                ], required: ["segmentId", "atSec"]),
                annotations: safeWrite
            ),
        ]
    }
}
