# Search

Every word of every transcript is indexed for **full-text search**, so you can find a conversation by what was said in it — even across hundreds of recordings.

## Searching in the app

Type into the **search field** in the toolbar and press Return. A results sheet shows matching recordings with **snippets** of the matching text, ranked by relevance. Pick a result to open that recording's transcript.

## Searching from the CLI

```sh
diarize search "roadmap"
```

- **Multiple words** are AND-linked by default: `diarize search budget timeline` finds transcripts containing *both*.
- **Quotes** let you use SQLite FTS5 operators such as `NEAR`, `OR`, and `AND`:
  ```sh
  diarize search "deadline OR milestone"
  diarize search "\"action item\" NEAR/5 owner"
  ```
- `--limit N` caps the number of results (default 30).
- `--json` prints machine-readable output for scripting.

See the [CLI reference](cli.md#search) for full options.

## How it works

Search is powered by SQLite's **FTS5** full-text index, kept in sync as recordings are transcribed. That means search is local, fast, and works offline — like everything else in diarize.

## Related

- [Transcripts & Speakers](transcripts-and-speakers.md) — what you land in when you open a result.
- [Organizing Recordings](organizing.md) — browse by folder when you'd rather not search.
