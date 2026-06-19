# Command-Line Interface

The `diarize` CLI exposes the same engine as the app, scriptably. Every command and subcommand accepts `--help` for full options.

```
diarize <command> [options]
```

Commands: [`transcribe`](#transcribe) · [`record`](#record) · [`search`](#search) · [`speakers`](#speakers) · [`archive`](#archive) · [`config`](#config) · [`mcp`](#mcp)

---

## transcribe

Diarize and transcribe an existing audio file (mp3, wav, m4a, …).

```sh
diarize transcribe meeting.m4a --lang en --title "Q2 planning"
```

| Option | Description |
| --- | --- |
| `<file>` | Path to the audio file (required) |
| `--lang <de\|en\|auto>` | Language (default from config) |
| `--title <text>` | Optional transcript title |
| `--archive <path>` | Override the archive path |
| `--force` | Re-process even if this audio's hash is already archived |

---

## record

Record microphone and/or system audio, transcribing automatically after you stop (Ctrl-C).

```sh
diarize record --title "1:1 with Sam"
```

| Option | Description |
| --- | --- |
| `--mic` | Record microphone only |
| `--system` | Record system audio only (e.g. online meetings) |
| `--output <path>` | WAV path (default `<archive>/recordings/<timestamp>.wav`) |
| `--title <text>` | Optional title for the transcript |
| `--lang <de\|en\|auto>` | Language (default from config) |
| `--no-transcribe` | Keep the WAV only; don't transcribe |

With neither `--mic` nor `--system`, both sources are recorded. See [Recording](recording.md) for what each source captures and how mic + system audio is handled.

---

## search

Full-text search across all transcripts (SQLite FTS5).

```sh
diarize search "roadmap"
diarize search "deadline OR milestone"
```

| Option | Description |
| --- | --- |
| `<terms…>` | Search term(s). Multiple words are AND-linked. Quotes allow FTS5 syntax (`NEAR`, `OR`, `AND`) |
| `--limit <N>` | Maximum results (default 30) |
| `--json` | Machine-readable JSON output |

More in [Search](search.md).

---

## speakers

Manage the speaker library. See [Transcripts & Speakers](transcripts-and-speakers.md) for the concepts.

```sh
diarize speakers list
diarize speakers label spk_a1b2c3 "Sam"
diarize speakers merge spk_a1b2c3 spk_d4e5f6
```

| Subcommand | Description |
| --- | --- |
| `list` | List all known speakers |
| `show <id>` | Show details of a speaker |
| `label <id> <name>` | Set or overwrite a speaker's name |
| `merge <from> <into>` | Merge two speakers — `from` is deleted, `into` takes over its embeddings & segments |
| `delete <id>` | Delete a speaker and all its embeddings |
| `recalibrate [--apply]` | Recommend a similarity threshold from your labeled speakers; `--apply` writes it to config |
| `diagnose <ref>` | Show embedding similarities to all other speakers (helps decide merges); `<ref>` is a speaker ID or label substring |

---

## archive

Manage the recording archive.

```sh
diarize archive list
diarize archive reprocess <recording-id>
```

| Subcommand | Description |
| --- | --- |
| `list` | List all archived recordings |
| `show <id>` | Show paths & key data of a recording |
| `reprocess <id>` | Re-render Markdown + JSON with current speaker labels (no model run) |
| `reprocess-all` | Re-render **all** recordings with current labels |
| `backfill-hashes` | Compute content hashes for recordings missing them |
| `dedupe [--dry-run]` | Find duplicates (same content hash) and keep only the most recent per hash; `--dry-run` shows without deleting |
| `delete <id>` | Delete a recording from the archive (the source file is left untouched) |

---

## config

Show or change configuration. Values resolve as **CLI flag → env var → `~/.config/diarize/config.json` → default** (see [Settings](settings.md#configuration-precedence-cli)).

```sh
diarize config show
diarize config set default.language en
```

| Subcommand | Description |
| --- | --- |
| `show` | Show the current configuration |
| `set <key> <value>` | Set a value. Keys: `archive.path`, `default.language`, `similarity.threshold` |

---

## mcp

Run a [Model Context Protocol](https://modelcontextprotocol.io) server (over stdio) that
exposes your library to local AI agents. You normally register this command with an MCP
client rather than running it by hand.

```sh
diarize mcp
```

| Option | Description |
| --- | --- |
| `--archive <path>` | Override the archive path |

Agents can read recordings, speakers, folders and live recording status; find the latest
or unprocessed recordings; mark them processed (bulk); read failed recordings' errors and
retry analysis; and manage titles, folders and GDPR audio deletion. Full tool reference
and setup: [MCP Server](mcp.md).

---

## Related

- [Documentation home](README.md)
- [Project README](../README.md) — build instructions and project layout.
