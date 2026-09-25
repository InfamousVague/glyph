# Third-party artwork and fonts

Artwork and fonts Ghost.md ships that were made by others, and their licences. Code dependencies are listed in
package.json and Cargo.toml with their own licences.

- **A wisp of smoke** (`src/app/assets/sample-smoke.jpg`), the picture in the sample note
  (`src/app/core/sampleNote.ts`): a photograph by Jocelyn Morales, https://unsplash.com/photos/3LxNwtL1uDs,
  under the Unsplash License (https://unsplash.com/license): free to use, no permission or credit needed,
  credit given anyway. Resized to 1400px on its long side.

(Noto Emoji's ghost and pointing hand were on the guide's "Light or dark?" page for an afternoon on
2026-09-14; the page now has no drawing.)

## Fonts

Every face the app sets is under the SIL Open Font License 1.1 (https://openfontlicense.org): free to use, bundle
and ship in any app, paid or free, as long as the copyright and the licence go with the font files, and no font is
sold on its own. The full text is in each package's `LICENSE`, under `node_modules/`, and the copyright is in each
font file's own metadata. Bundled through Fontsource (https://fontsource.org), which splits each face into subsets by
script; the app loads a face only when something is set in it.

- **Maple Mono** - Copyright (c) 2022, subframe7536 (https://github.com/subframe7536/maple-font), with Reserved Font
  Name Maple Mono. The note font by default.
- **Fira Code** - Copyright 2014-2020 The Fira Code Project Authors (https://github.com/tonsky/FiraCode).
- **Inter** - Copyright 2016 The Inter Project Authors (https://github.com/rsms/inter). The interface font by default.
- **Noto Sans** - Copyright 2022 The Noto Project Authors (https://github.com/notofonts/latin-greek-cyrillic).
- **IBM Plex Sans** and **IBM Plex Mono** - Copyright 2017-2019 IBM Corp.
- **JetBrains Mono** - Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono).
  Code in a note set in a sans.

A Reserved Font Name may not be used by a modified version of the font. Fontsource's subsets are the font cut into
pieces by script, which the OFL counts as modifying it; the app shows the name "Maple Mono" for the face in Settings.
If that is ever a concern, the author's own unmodified WOFF2 files from the maple-font releases can take the
package's place under the same name.


## Models

The app ships no model. It downloads them when asked, each checked against a SHA-256 compiled into the binary, from
the box's own mirror first (`https://attack.fm/glyph/models`) and then from Hugging Face at a pinned revision:

- **Whisper**, for transcription: `ggml-base.en-q5_1.bin` and `ggml-small.en-q5_1.bin`, from ggerganov/whisper.cpp
  on Hugging Face (`src-tauri/src/whisper/model.rs`). The box keeps a copy of both, so it redistributes them.
- **The language models** the AI runs on the phone and the Mac: Qwen3.5 2B, 4B and 9B, and Gemma 4 E4B, as GGUF files
  from unsloth's Hugging Face repositories (`src-tauri/src/llm/model.rs` `CATALOGUE`).

Their licences are not recorded here yet. They should be, before a store listing, since the box's mirror hands the
files out itself.
