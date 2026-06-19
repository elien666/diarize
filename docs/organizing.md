# Organizing Recordings

As your archive grows, the sidebar keeps it manageable with **folders**, **drag-and-drop**, and **inline renaming**.

## The sidebar

The sidebar has two collapsible sections:

- **Recordings** — your recordings, optionally grouped into folders.
- **Speakers** — every known voice (see [Transcripts & Speakers](transcripts-and-speakers.md#the-speakers-list)).

Click a section header to collapse or expand it. Each recording row shows its title, date, duration, language, and a small **state indicator** (recording, analyzing, no-transcript, or failed).

## Folders

Folders can be **nested to any depth**, so you can organize by client, project, month — whatever fits.

- **Create a folder:** right-click the **Recordings** header → **New Folder**. Create a subfolder by right-clicking an existing folder → **New Subfolder**.
- **Rename a folder:** right-click → **Rename Folder**, type the new name, press Return.
- **Delete a folder:** right-click → **Delete Folder**.

Folders start **collapsed** by default so a large archive stays tidy; expand the ones you're working in.

## Moving recordings

Two ways to file a recording:

- **Drag and drop** it onto a folder in the sidebar (the target folder highlights as you hover).
- **Right-click the recording → Move to Folder**, then pick a destination. The submenu mirrors your nested folder structure, with **No Folder** to move it back to the top level.

## Renaming recordings

Right-click a recording → **Rename** (or rename it from the [detail view](transcripts-and-speakers.md)). Untitled recordings show as "Recording" until you give them a name.

## Adding existing audio

Click the **+ (Add Recording)** button in the toolbar to import an existing audio file (mp3, wav, m4a, …). It's diarized and transcribed just like a live recording. From the CLI, use [`transcribe`](cli.md#transcribe).

## Related

- [Search](search.md) — when you'd rather find by *content* than browse folders.
- [Settings → Archive](settings.md#archive) — change where everything is stored, remove duplicates, or re-render transcripts.
