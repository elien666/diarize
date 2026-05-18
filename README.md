# diarize

**On-device speaker diarization and transcription for macOS — CLI, SwiftUI app, and Swift library.**

`diarize` records audio (microphone, system audio, or both), splits it by speaker, transcribes each segment, and matches voices across recordings so the same person keeps the same identity over time. Everything runs locally on Apple Silicon — no cloud, no API keys.

Built on [FluidAudio](https://github.com/FluidInference/FluidAudio) (diarization + ASR via Core ML), [GRDB](https://github.com/groue/GRDB.swift) (SQLite with FTS5 full-text search), and Swift 6.

---

## Features

- **Record & transcribe in one step** — capture mic + system audio simultaneously (great for meetings), auto-transcribe on stop.
- **Cross-recording speaker matching** — voice embeddings are stored once; the same person is recognized in every future recording.
- **Manual speaker correction** — relabel speakers globally or fix a single segment when the diarizer guesses wrong.
- **Full-text search** — SQLite FTS5 across every transcript, with snippets and ranking.
- **Markdown + JSON output** — transcripts are written as readable Markdown and queryable JSON.
- **Local archive** — recordings, transcripts, and the speaker database live under `~/Library/Application Support/diarize/` (configurable).
- **Two front-ends** — a scriptable CLI (`diarize`) and a native SwiftUI app (`diarize-app`) backed by the same `DiarizeCore` library.

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

All commands accept `--help` for full options.

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
  DiarizeApp/     `diarize-app` SwiftUI app (sidebar, recording detail, search)
Resources/icon/   App icon (SVG + .icns)
Scripts/          Build helpers (app bundle, icon, code signing)
Tests/            DiarizeCore unit tests
```

## How it works

1. **Capture** — `AudioRecorder` taps the microphone via `AVAudioEngine` and system audio via `ScreenCaptureKit`; `AudioMixer` merges them into a single WAV.
2. **Diarize** — FluidAudio segments the waveform by speaker and emits a 256-dim embedding per segment.
3. **Match** — `SpeakerMatcher` compares each new embedding against the SQLite speaker library (cosine similarity ≥ threshold) and either reuses an existing speaker ID or mints a new one.
4. **Transcribe** — each segment is fed to FluidAudio's ASR model in the chosen language.
5. **Persist** — `SpeakerStore` writes recording, segments, and transcript text into SQLite (with FTS5); Markdown + JSON renderers produce human-readable artifacts under the archive.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Core ML diarization and ASR
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite toolkit
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI
