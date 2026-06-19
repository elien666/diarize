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
                description: "List all known speakers.",
                inputSchema: schema(),
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
                description: "Get the diarized transcript of a recording as structured segments with speaker labels.",
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
                name: "retry_analysis",
                description: "Re-run diarization + transcription on a recording (e.g. one that failed). Returns immediately; analysis runs in the background. Poll get_recording until processingState is done/empty/failed. Fails if the audio was deleted.",
                inputSchema: schema(properties: ["id": prop("string", "Recording id.")], required: ["id"]),
                annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
            ),
        ]
    }
}
