# diarize

**On-device speaker diarization and transcription for macOS — CLI, SwiftUI app, and Swift library.**

`diarize` records audio (microphone, system audio, or both), splits it by speaker, transcribes each segment, and matches voices across recordings so the same person keeps the same identity over time. Everything runs locally on Apple Silicon — no cloud, no API keys.

Built on [FluidAudio](https://github.com/FluidInference/FluidAudio) (diarization + ASR via Core ML), [GRDB](https://github.com/groue/GRDB.swift) (SQLite with FTS5 full-text search), and Swift 6.

---

## Features

- **Record & transcribe in one step** — capture mic + system audio simultaneously (great for meetings), auto-transcribe on stop. → [docs](docs/recording.md)
- **Stereo channel separation** — when recording mic + system audio, each goes on its own channel (mic = left, system = right) and is diarized independently, so speaker echo never collapses everyone into one voice. → [docs](docs/recording.md#mic--system-audio-together-stereo-separation)
- **Auto Recording Mode** — detects when a call starts (another app grabs the mic) and records it hands-free, stopping and transcribing on its own. → [docs](docs/auto-recording.md)
- **Cross-recording speaker matching** — voice embeddings are stored once; the same person is recognized in every future recording. → [docs](docs/transcripts-and-speakers.md#how-speakers-are-recognized)
- **Manual speaker correction** — rename speakers globally, reassign or split segments, and merge duplicate identities when the diarizer guesses wrong. → [docs](docs/transcripts-and-speakers.md#correcting-speakers)
- **Synced playback** — play the audio and watch the transcript highlight and auto-scroll; click any timestamp to jump. → [docs](docs/transcripts-and-speakers.md#reading-a-transcript)
- **Live recording feedback** — per-device level meters, mic selection, and automatic recovery if the input device changes mid-recording. → [docs](docs/recording.md#live-level-meters)
- **Full-text search** — SQLite FTS5 across every transcript, with snippets and ranking. → [docs](docs/search.md)
- **Folders & organization** — group recordings into nested folders with drag-and-drop and inline rename. → [docs](docs/organizing.md)
- **Privacy-first** — fully on-device; delete raw audio while keeping transcripts (GDPR-friendly), with optional auto-clean of old audio and a menu-bar stealth mode. → [docs](docs/privacy.md)
- **Markdown + JSON output** — transcripts are written as readable Markdown and queryable JSON.
- **Local archive** — recordings, transcripts, and the speaker database live under `~/Library/Application Support/diarize/` (configurable).
- **Two front-ends** — a scriptable CLI (`diarize`) and a native SwiftUI app (`diarize-app`) backed by the same `DiarizeCore` library.

📖 **New here?** Start with the [User Guide](docs/README.md).

## Requirements

- macOS 14 (Sonoma) or newer
- Apple Silicon (M1+) recommended — Core ML models run on the Neural Engine
- Swift 6 / Xcode 16
- Microphone permission (for `record`); Screen Recording permission (for system-audio capture)

## Install

```sh
git clone https://github.com/elien666/diarize.git
cd diarize
swift build -c release
cp .build/release/diarize /usr/local/bin/   # or anywhere on $PATH
```

To build the SwiftUI app:

```sh
./Scripts/build-app.sh
open build/Diarize.app
```

## CLI quick start

```sh
# Transcribe an existing audio file (mp3, wav, m4a, …)
diarize transcribe meeting.m4a --lang en --title "Q2 planning"

# Record mic + system audio, auto-transcribe on stop (Ctrl-C)
diarize record --title "1:1 with Sam"

# Search across every transcript
diarize search "roadmap"

# Manage the speaker library
diarize speakers list
diarize speakers label spk_a1b2c3 "Sam"
diarize speakers merge spk_a1b2c3 spk_d4e5f6

# Inspect or reprocess the archive
diarize archive list
diarize archive reprocess <recording-id>

# Show / change config
diarize config show
diarize config set default.language en
```

All commands accept `--help` for full options. Full command reference: [docs/cli.md](docs/cli.md).

## Documentation

User-facing guides live in [`docs/`](docs/README.md):

| Guide | What it covers |
| --- | --- |
| [Getting Started](docs/getting-started.md) | Install, permissions, first recording |
| [Recording](docs/recording.md) | Sources, mic selection, level meters, stereo separation |
| [Auto Recording Mode](docs/auto-recording.md) | Hands-free call capture |
| [Transcripts & Speakers](docs/transcripts-and-speakers.md) | Reading transcripts and correcting speakers |
| [Organizing Recordings](docs/organizing.md) | Folders, drag-and-drop, renaming |
| [Search](docs/search.md) | Full-text search across transcripts |
| [Privacy & Data](docs/privacy.md) | On-device processing, audio deletion, stealth mode |
| [Settings](docs/settings.md) | Language, matching threshold, archive, maintenance |
| [CLI Reference](docs/cli.md) | Every `diarize` command and option |

## Configuration

Resolution order (highest wins): **CLI flag → env var → `~/.config/diarize/config.json` → default**.

| Key                    | Env var                          | Default                                            |
| ---------------------- | -------------------------------- | -------------------------------------------------- |
| `archive.path`         | `DIARIZE_ARCHIVE_PATH`           | `~/Library/Application Support/diarize/archive`    |
| `default.language`     | `DIARIZE_LANG_DEFAULT`           | `auto` (also: `de`, `en`)                          |
| `similarity.threshold` | `DIARIZE_SIMILARITY_THRESHOLD`   | `0.6` (cosine similarity for speaker matching)     |

## Project layout

```
Sources/
  DiarizeCore/    Library: audio I/O, diarization, ASR, storage, search
    Audio/        Recorder, mixer, loader, WAV writer
    Pipeline/     Diarization, transcription, speaker matching, calibration
    Storage/      GRDB models, migrations, speaker store
    Render/       Markdown + JSON renderers
  DiarizeCLI/     `diarize` executable (ArgumentParser)
  DiarizeApp/     `diarize-app` SwiftUI app (sidebar/folders, recording detail,
                  search, auto-recording mode, permissions, privacy cleanup, menu bar)
Resources/icon/   App icon (SVG + .icns)
Scripts/          Build helpers (app bundle, icon, code signing)
Tests/            DiarizeCore unit tests
```

## How it works

1. **Capture** — `AudioRecorder` taps the microphone via `AVAudioEngine` and system audio via a `ScreenCaptureKit` / CoreAudio process tap; `AudioMixer` writes a WAV. With both sources active it writes **stereo** (mic = left, system = right) so the two can be diarized in isolation; a single source is written mono.
2. **Diarize** — FluidAudio segments the waveform by speaker and emits an embedding per segment. For stereo recordings each channel is diarized independently and merged with `local` / `remote` prefixes, avoiding echo-induced speaker confusion.
3. **Match** — `SpeakerMatcher` compares each new embedding against the SQLite speaker library (cosine similarity ≥ threshold) and either reuses an existing speaker ID or mints a new one.
4. **Transcribe** — each segment is fed to FluidAudio's ASR model in the chosen language.
5. **Persist** — `SpeakerStore` writes recording, segments, and transcript text into SQLite (with FTS5); Markdown + JSON renderers produce human-readable artifacts under the archive.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Core ML diarization and ASR
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite toolkit
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI
