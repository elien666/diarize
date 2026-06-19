# Privacy & Data

diarize is built to keep recordings of real conversations private. Two principles drive its design: **everything runs on your device**, and **you stay in control of how long raw audio is kept**.

## On-device by default

All capture, diarization, transcription, speaker matching, and search happen **locally on your Mac** using Core ML models on the Neural Engine. There is **no cloud, no account, and no API key** — your audio and transcripts never leave the machine unless you export them yourself.

Everything is stored under your archive folder (default `~/Library/Application Support/diarize/archive`, configurable in [Settings](settings.md#archive)).

## Deleting audio, keeping the transcript

Raw audio is the most sensitive artifact — and usually the least useful once you have the transcript. diarize lets you **delete the audio file while keeping the transcript and all speaker assignments**.

- **One recording:** in the [recording detail view](transcripts-and-speakers.md#header-actions-when-analysis-is-done), click the **waveform-slash** 🌊 button → **Delete Audio**.
- After deletion the recording stays fully usable for reading and search; the playback bar is replaced with a note like *"Audio deleted on … — transcript kept."*

This is designed with **GDPR data-minimization** in mind: you can retain the business record (the transcript) while disposing of the personal-data-heavy recording.

> To remove a recording **entirely** (audio *and* transcript), use **Delete** instead — diarize asks you to confirm, because it can't be undone.

## Automatic clean-up of old audio

diarize can proactively suggest deleting audio that's older than a retention period you choose:

- On launch (and once a day while the app is open), it looks for recordings whose **audio** is older than the retention window.
- If it finds any, it shows a **single summary prompt** offering to delete those audio files. **Transcripts are always kept.**
- **Nothing is ever deleted automatically** — diarize only *proposes*; you confirm in the sheet.

Configure this in [Settings → Privacy](settings.md#privacy):

- **Suggest deleting old audio automatically** — on by default.
- **Keep audio for N day(s)** — the retention window (default **7 days**, adjustable 1–365).

## Stealth mode (menu bar)

When others can see your screen, you may not want a recording window visible. diarize lives in the **menu bar**: click its status-bar icon to **hide the main window** entirely — the app keeps running and recording, accessible only from the menu bar. Click again to bring the window back.

The icon is deliberately low-key: a **filled circle while recording**, an empty circle otherwise, reading as a generic system utility rather than an obvious recorder.

## Permissions

diarize only requests the macOS permissions it actually needs — **Microphone** and **Screen & System Audio Recording** — and clearly explains why. It surfaces missing permissions in the footer with one-tap **Grant** buttons rather than failing silently. See [Recording → Permissions](recording.md#permissions).

## Related

- [Recording](recording.md) — where recordings come from.
- [Settings](settings.md) — retention, archive location, and maintenance.
