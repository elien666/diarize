# diarize — User Guide

Welcome to the diarize documentation. **diarize** records audio, splits it by speaker, transcribes each segment, and recognizes the same voices across recordings — entirely on your Mac, with no cloud and no API keys.

These pages explain what diarize does from *your* point of view: what each feature is for, when to reach for it, and how to use it. If you're looking for build instructions, the CLI command list, or the project layout, see the [project README](../README.md).

## Getting started

- **[Getting Started](getting-started.md)** — install, grant permissions, and make your first recording.

## Using the app

- **[Recording](recording.md)** — capture microphone, system audio, or both; pick a mic; watch live levels; understand stereo channel separation.
- **[Auto Recording Mode](auto-recording.md)** — let diarize start and stop recording automatically when a call begins and ends.
- **[Transcripts & Speakers](transcripts-and-speakers.md)** — read transcripts, play back audio in sync, and correct who-said-what (rename, reassign, merge, split).
- **[Organizing Recordings](organizing.md)** — folders, drag-and-drop, and renaming in the sidebar.
- **[Search](search.md)** — full-text search across every transcript you've ever made.
- **[Privacy & Data](privacy.md)** — on-device processing, GDPR audio deletion with transcript retention, auto-clean, and stealth mode.
- **[Settings](settings.md)** — language, speaker-matching threshold, calibration, archive location, and maintenance tools.

## Power users

- **[Command-Line Interface](cli.md)** — the scriptable `diarize` CLI: `transcribe`, `record`, `search`, `speakers`, `archive`, `config`.

## How it works

A short tour of the pipeline — capture → diarize → match → transcribe → persist — lives in the [project README](../README.md#how-it-works).
