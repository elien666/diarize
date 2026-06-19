# Getting Started

This page takes you from a fresh checkout to your first transcript. For background on what diarize is, see the [documentation home](README.md).

## 1. Install

diarize ships as a CLI (`diarize`) and a native SwiftUI app (`diarize-app`), both built from the same source.

```sh
git clone https://github.com/elien666/diarize.git
cd diarize
swift build -c release
```

To build and open the Mac app:

```sh
./Scripts/build-app.sh
open build/Diarize.app
```

Optionally, put the CLI on your `PATH`:

```sh
cp .build/release/diarize /usr/local/bin/
```

> **Requirements:** macOS 14 (Sonoma) or newer, Apple Silicon (M1+) recommended. See the [project README](../README.md#requirements) for the full list.

## 2. Grant permissions

diarize needs two macOS privacy permissions:

| Permission | Why | Needed for |
| --- | --- | --- |
| **Microphone** | Capture your own voice | Any recording with a mic source |
| **Screen & System Audio Recording** | Capture audio from other apps (meetings, calls, videos) | Recording system audio |

The app shows a **red banner in the footer** when a permission is missing, with a **Grant** button that takes you straight to the right request or System Settings pane. You can record as soon as the permissions you need are granted. More detail in [Recording → Permissions](recording.md#permissions).

## 3. Make your first recording

In the app:

1. Click the red **Start Recording** button in the toolbar to immediately capture **microphone + system audio**, or click the **▾ caret** next to it to choose a title, language, microphone, and which sources to record.
2. A live timer and per-device level meters appear so you can confirm audio is coming in.
3. Click **Stop & Analyze**. diarize diarizes and transcribes the recording, then shows the transcript.

Prefer the terminal? Record from the CLI instead:

```sh
diarize record --title "1:1 with Sam"     # Ctrl-C to stop and auto-transcribe
```

Or transcribe a file you already have:

```sh
diarize transcribe meeting.m4a --lang en --title "Q2 planning"
```

## 4. Name your speakers

The first time diarize hears a voice it assigns a generic label (e.g. `Unknown-a1b2c3`). Rename it once and that person is recognized in **every future recording** thanks to [cross-recording speaker matching](transcripts-and-speakers.md#how-speakers-are-recognized).

## Next steps

- Capture meetings cleanly with [stereo channel separation](recording.md#mic--system-audio-together-stereo-separation).
- Let diarize record calls for you in [Auto Recording Mode](auto-recording.md).
- Fix any speaker mistakes in [Transcripts & Speakers](transcripts-and-speakers.md).
- Keep your archive tidy and private with [Privacy & Data](privacy.md).
