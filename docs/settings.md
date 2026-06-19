# Settings

The app's **Settings** window groups everything you can tune, plus a few maintenance tools. CLI users can change the same core values with [`diarize config`](cli.md#config).

## Recording

- **Default Language** — Auto-detect, English, or Deutsch. Used for new recordings unless you override it per recording in the [recording options](recording.md#starting-a-recording).

## Privacy

- **Suggest deleting old audio automatically** — when on (the default), diarize periodically offers to delete audio older than your retention window. Transcripts are always kept. See [Privacy & Data](privacy.md#automatic-clean-up-of-old-audio).
- **Keep audio for N day(s)** — the retention window (1–365, default 7).

## Speaker Matching

Controls how aggressively diarize treats two voices as the **same person**. See [Transcripts & Speakers → How speakers are recognized](transcripts-and-speakers.md#how-speakers-are-recognized).

- **Similarity Threshold** — a slider (0.30–0.95). **Lower** = more willing to merge similar voices into one speaker; **higher** = stricter, more likely to create separate speakers.
- **Calibrate from Labeled Speakers** — diarize analyzes the voices you've already named and **recommends a threshold** (with a confidence level), then applies it. Needs at least 2 labeled speakers with embeddings.

## Archive

- **Path** — where recordings, transcripts, and the speaker database are stored. **Change Archive Folder…** picks a new location (takes effect after restarting the app).
- **Remove Duplicates** — finds recordings with identical audio (same content hash) and removes all but the most recent of each.
- **Re-render All Transcripts** — regenerates every Markdown/JSON transcript using current speaker labels, without re-running the models. Use after a round of relabeling.
- **Backfill Audio Hashes** — computes the content hash for older recordings that predate the de-duplication feature.

## Configuration precedence (CLI)

For the CLI, values resolve in this order (highest wins):

**CLI flag → environment variable → `~/.config/diarize/config.json` → built-in default**

| Key | Env var | Default |
| --- | --- | --- |
| `archive.path` | `DIARIZE_ARCHIVE_PATH` | `~/Library/Application Support/diarize/archive` |
| `default.language` | `DIARIZE_LANG_DEFAULT` | `auto` (also `de`, `en`) |
| `similarity.threshold` | `DIARIZE_SIMILARITY_THRESHOLD` | `0.6` |

Set them with [`diarize config set`](cli.md#config), e.g. `diarize config set default.language en`.

## Related

- [Privacy & Data](privacy.md) — the reasoning behind the retention settings.
- [CLI reference](cli.md) — change configuration and run maintenance from the terminal.
