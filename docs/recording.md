# Recording

diarize can record three things: your **microphone**, your Mac's **system audio** (everything other apps play), or **both at once**. This page covers how to start a recording, the options you have, and what happens to the audio.

See also: [Auto Recording Mode](auto-recording.md) for hands-free call capture, and the [CLI `record` command](cli.md#record) for recording from the terminal.

## Starting a recording

The toolbar has a **split record control**:

- **Start Recording** (red button) — starts capturing **microphone + system audio** immediately, with no menu. This is the fast path for "just record this meeting."
- **▾ caret** — opens the **recording options** popover, where you can set:
  - a **Title** (optional)
  - the **Language** — Auto, English, or Deutsch
  - the **Microphone** — System Default or a specific input device
  - the **source**: *Microphone + System Audio*, *Microphone Only*, or *System Audio Only*

While a recording is in progress the record control is disabled, and a **timer** plus **per-device level meters** appear in the recording's detail view.

## Choosing a microphone

By default diarize follows the **system default input**. To pin a specific mic (e.g. an external USB interface), open the options popover and pick it under **Microphone**. Your choice is remembered for next time.

If a previously selected device is unplugged, diarize quietly falls back to the system default rather than showing a blank selection.

### Device-switch recovery

If you change the input device in System Settings, or unplug a USB mic *mid-recording*, macOS silently tears down the audio tap — normally that would kill the recording without warning. diarize detects this and **automatically re-attaches to the new device** so the recording keeps going.

## Live level meters

While recording, diarize shows a **level meter per active channel** (microphone and/or system audio). Use them to confirm that:

- your mic is actually picking up sound, and
- system audio is being captured (the meter moves when the other app plays sound).

The meters are designed to be cheap to draw, so they don't add noticeable CPU load during a recording.

## Recording sources explained

| Source | Captures | Typical use |
| --- | --- | --- |
| **Microphone Only** | Your voice / room | In-person notes, voice memos, dictation |
| **System Audio Only** | What other apps play | An online meeting where you only need the remote side, a video, a podcast |
| **Microphone + System Audio** | Both | A call or meeting where you want **both** your side and the remote side |

> System audio capture works even when the meeting app is running on a non-default audio device — diarize uses a CoreAudio process tap with a private aggregate device to capture it reliably.

## Mic + system audio together: stereo separation

When you record **both** sources at once, diarize doesn't just mix them together. It records a **stereo WAV** with:

- **Left channel → your microphone** (local speaker)
- **Right channel → system audio** (remote speakers)

**Why this matters:** when both sources are mixed to mono, your microphone also picks up the remote voices coming out of your speakers as **room echo**. The diarizer then hears each remote voice *twice* — once cleanly from the system-audio tap and once as echo on the mic — and tends to collapse everyone into a single speaker.

By keeping the two sources on separate channels, diarize can:

1. **Diarize each channel independently**, so echo on the mic channel can't contaminate the clean remote audio, and
2. **Merge the results** with `local` / `remote` prefixes so you can tell your side from the other side at a glance.

You don't have to do anything to enable this — it happens automatically whenever a recording includes both mic and system audio.

## Stopping and analysis

Click **Stop & Analyze** (or press <kbd>⌘S</kbd>) to finish. diarize then:

1. finalizes the WAV file,
2. diarizes it (splitting by speaker), matches voices against your [speaker library](transcripts-and-speakers.md#how-speakers-are-recognized),
3. transcribes each segment, and
4. writes the transcript.

A **progress bar in the footer** and in the recording's detail view shows the current analysis phase in real time. You can keep using the app while analysis runs.

To throw away a recording without analyzing it, click **Discard**.

## Permissions

Recording requires macOS privacy permissions:

- **Microphone** — for any mic source.
- **Screen & System Audio Recording** — for system audio.

When something is missing, the footer shows a **red warning** naming the missing permission(s) and a **Grant** button per permission. Tapping it either shows the system prompt (if never asked) or opens the exact System Settings pane (if previously denied). Auto Recording Mode stays disabled until both permissions are granted.

## Where recordings are stored

Audio, transcripts, and the speaker database live under your archive folder:

```
~/Library/Application Support/diarize/archive
```

This is configurable in [Settings](settings.md#archive) (app) or via [`config`](cli.md#config) (CLI). To delete the audio while keeping the transcript, see [Privacy & Data](privacy.md).
