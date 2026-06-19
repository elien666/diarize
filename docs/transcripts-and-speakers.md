# Transcripts & Speakers

After analysis, each recording opens to a **transcript**: a time-stamped, speaker-labeled list of everything that was said. This page covers reading transcripts, playing audio in sync, and — most importantly — **correcting who said what**.

## Reading a transcript

The recording detail view shows:

- a **header** with the title, date, duration, language, and speaker count, plus quick actions (see below),
- a **playback bar** to scrub and play the audio, and
- the **transcript**, one row per segment: timestamp · speaker · text.

As audio plays, the current segment is **highlighted** and the transcript **auto-scrolls** to keep it centered. Click any **timestamp** to jump playback to that moment.

### Header actions (when analysis is done)

| Icon | Action |
| --- | --- |
| 📄 Open | Open the Markdown transcript in your default editor |
| 📁 Reveal in Finder | Show the transcript file in Finder |
| 📋 Copy Path | Copy the transcript's file path to the clipboard |
| 🔄 Re-analyze | Run diarization + transcription again |
| 🌊 Delete Audio | Delete the audio file but **keep the transcript** — see [Privacy & Data](privacy.md) |
| 🗑 Delete | Delete the whole recording (with confirmation) |

## How speakers are recognized

diarize stores a **voice embedding** (a numeric fingerprint) for every speaker it hears. When a new recording is analyzed, each segment's voice is compared against your existing speaker library:

- if it's **similar enough** to a known speaker (cosine similarity ≥ a threshold), it reuses that speaker's identity;
- otherwise it **creates a new speaker**.

The practical payoff: **name a person once, and they're recognized in every future recording.** Unnamed speakers show a generic label like `Unknown-a1b2c3` and a yellow warning dot in the sidebar until you label them.

The matching threshold is adjustable, and diarize can recommend one from your own labeled speakers — see [Settings → Speaker Matching](settings.md#speaker-matching).

## Correcting speakers

Diarization is good but not perfect. Every segment row has a **speaker menu** (click the colored speaker chip) with these corrections:

### Rename a speaker

Pick **Rename current speaker …**, type the real name, and confirm. The new name applies **everywhere** that speaker appears — across this and all other recordings — because you're renaming the underlying identity, not just one segment.

### Reassign a segment to a different speaker

If a segment is attributed to the wrong person, open the menu and choose the correct speaker under **Assign to another speaker**. You can also choose **New Speaker …** to split a misattributed segment off into a brand-new identity.

> Assigning a segment to an *existing* speaker is treated as a **merge** when the segment's whole speaker is being folded in — diarize asks you to confirm, since all of one speaker's segments and voice data move into the other.

### Split a segment

When the diarizer lumps two speakers into one segment (e.g. a quick back-and-forth), hover the row and click the **scissors** ✂️ icon to **split the segment** at the current playback position (or its midpoint). You can then assign each half to the right speaker.

### Merge two speakers

If the same person ended up as two identities (common when a voice changes slightly between recordings), merge them. In the app, reassign one to the other and confirm the merge; from the CLI use [`speakers merge`](cli.md#speakers). Merging moves **all** segments and embeddings from the source into the target and removes the source.

## The Speakers list

The sidebar's **Speakers** section lists every known voice with its color, name, and segment count. Selecting one opens a speaker detail view. Unnamed speakers are flagged so you know what still needs a label.

## Transcript files

Every transcript is written in two formats under your archive:

- **Markdown** — human-readable, with a title/date heading, a duration · language · speakers line, and a `## Transcript` section of timestamped, speaker-labeled lines. Great for pasting into notes.
- **JSON** — machine-readable, for scripting and downstream tools.

Re-render Markdown/JSON for a recording (after relabeling) without re-running the models via [`archive reprocess`](cli.md#archive), or for everything via **Re-render All Transcripts** in [Settings](settings.md#archive).

## Related

- [Search](search.md) — find any phrase across all transcripts.
- [Organizing Recordings](organizing.md) — group transcripts into folders.
- [Settings → Speaker Matching](settings.md#speaker-matching) — tune and calibrate recognition.
