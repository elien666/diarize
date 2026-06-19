# Auto Recording Mode

Auto Recording Mode turns diarize into a hands-free call recorder: while it's active, diarize watches for another app starting to use your microphone — the tell-tale sign that a **call has started** — and automatically begins recording. When the call ends, it stops and transcribes on its own.

This is ideal for "I never remember to hit record" situations: video calls, voice calls, and any app that grabs the mic.

## Entering the mode

Click **Auto Recording Mode** (the ✨ wand icon) in the toolbar. The normal library is replaced by a full-window screen showing:

- a large **Auto Recording Enabled** headline,
- a live status — **"Waiting for a call …"** when idle, or an elapsed timer and level meters while recording,
- a **manual Start/Stop button** as an override, and
- the **list of recordings captured this session**.

The button is disabled until both Microphone and Screen Recording permissions are granted (see [Recording → Permissions](recording.md#permissions)).

## How detection works

diarize polls the system every couple of seconds:

- **To start:** when it sees another process begin capturing the microphone (and you're not already recording), it waits for the signal to persist across a couple of samples — a debounce so a brief blip can't trigger a false start — then begins a **microphone + system audio** recording using your selected mic.
- **To stop:** when that other app stops using the mic, diarize waits for the same debounce and then **stops and transcribes** automatically.

Each captured recording uses the same [stereo channel separation](recording.md#mic--system-audio-together-stereo-separation) as a normal mic + system recording.

## Manual override

Detection can occasionally miss or misfire. The big **Start Recording / Stop Recording** button lets you take over at any time — start a recording the detector didn't catch, or stop one it didn't end.

## Reviewing the session

Every recording made during the session appears in the **This Session** list with its start time, duration, and — once analysis finishes — the speakers that were detected. For each one you can:

- **Keep** — remove it from the session list; the recording stays in your normal [library](organizing.md).
- **Delete** — permanently remove the recording (audio **and** transcript). You'll be asked to confirm.

## Auto-stop and macOS version

Reliable **auto-stop** depends on the OS being able to report *per-process* microphone usage, which requires **macOS 14.4 or later**. On older systems diarize can still auto-*start*, but it shows a hint that you'll need to **stop recordings manually** from the library, because it can't tell when the other app has released the mic.

## Leaving the mode

Click **Exit Auto Mode** (top right) to return to the library. If a recording is in progress when you leave, it keeps running — exiting the mode is treated as an explicit "I've got this from here."

## Related

- [Recording](recording.md) — manual recording, sources, and mic selection.
- [Transcripts & Speakers](transcripts-and-speakers.md) — review and correct what was captured.
- [Privacy & Data](privacy.md) — including stealth mode, useful when others can see your screen.
