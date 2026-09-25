# The docs

What each page here is for, and when to read it. A topic page says what is true of the code now. `docs/DESIGN.md` says
why and when: it is the dated log of every decision, with Matt's words. When the two disagree, the topic page and the
code win, and the log is history.

Start at the repository's own [README](../README.md): how to run the app, the checks, over-the-air updates, the other
deploys, the signing keys and a move to another domain.

## A note's formats

| Page | What it is for | Read it when |
| --- | --- | --- |
| [MARKDOWN.md](MARKDOWN.md) | Every mark the editor parses and draws, the ones added and the ones left out on purpose, and how each is said while recording. | Adding or changing a mark, or checking that a note still reads as Markdown elsewhere. |
| [BOARDS.md](BOARDS.md) | Kanban boards written in Markdown: the anchor on an item, the `board` fence, the rules a board keeps, and boards on a phone. | Touching `src/app/core/boards/`, `src/app/editor/boards/`, or anything that writes an anchor. |
| [BOOKS.md](BOOKS.md) | A book as a note whose body is its index: the shape, the views, chapter numbers, and where the code is. | Working on books, the aside, or chapter numbers. |
| [CANVAS.md](CANVAS.md) | Canvases in JSON Canvas 1.0: Matt's fifteen choices, the format, the seven slices built, what is not, and where the code is. | Working on `src/app/canvas/`, or checking a canvas still opens in Obsidian. |

## Notes on disk, between devices, and out

| Page | What it is for | Read it when |
| --- | --- | --- |
| [LIBRARY.md](LIBRARY.md) | Notes as a folder of Markdown files: the folder, the front matter each side writes, the index, the sidecars, and the phases built and planned. | Touching `src-tauri/src/library/`, or anything that names a note's file. |
| [SYNC.md](SYNC.md) | Accounts and end-to-end encrypted sync: the keys, the wire, the client's passes, and Claude as one more device. | Changing the account, sync, or anything the server stores. |
| [LIVE.md](LIVE.md) | Live typing between two devices through a relay: the protocol, the seeding trap, and how it lives with the pass sync. | Touching `src/app/core/live/` or `server/src/live.rs`. |
| [SHARING.md](SHARING.md) | Read-only share links: the link and its key, what is shared, the server's routes, the reader page, and saved copies. | Working on `src/app/share/`, the reader page, or `server/src/shares.rs`. |

## Reaching outside the app

| Page | What it is for | Read it when |
| --- | --- | --- |
| [PLUGINS.md](PLUGINS.md) | The plugin API: the four standard plugins, the manifest and how it is enforced, and every extension point. | Adding a plugin, or an extension point for one. |
| [MCP.md](MCP.md) | Claude on the account through the MCP server, hosted or on your own computer: the tools, the set-up, what is kept, and the pieces. | Changing `mcp/` or the hosted server, or helping someone connect Claude. |
| [LANDING.md](LANDING.md) | ghostmarkdown.com: the download page, the privacy and delete-account pages, and the Caddy block they are served by. | Changing `landing/`, or before a store submission. |
| [store/PLAY_STORE.md](store/PLAY_STORE.md) | The plan for Google Play, as of 2026-09-24: what is done, the steps left, the data safety answers, and the decisions for Matt. | Working towards the Play listing. |
| [store/APP_STORE.md](store/APP_STORE.md) | The plan for the App Store, as of 2026-09-24. The iOS app is not ready to submit; this says why and what is left. | Working on the iOS app. |

## Voice

| Page | What it is for | Read it when |
| --- | --- | --- |
| [instruction-voice-commands.md](instruction-voice-commands.md) | What a finished recording may do: the one reader, the safety and mutation boundaries, what happens to the recording, and how it is tested. | Changing what a spoken command can do. |
| [VOICE_TESTS.md](VOICE_TESTS.md) | The voice suite (one recording per feature, checked from the scripts and from the audio) and a six-take walkthrough to play into the phone by hand. | Changing a cue or a command rule, or checking a build against real speech. |

## Art and the rest

| Page | What it is for | Read it when |
| --- | --- | --- |
| [GHOSTS.md](GHOSTS.md) | The dotwork ghost: where each scene is placed, the prompts that made them, and how another is added. | Adding a picture, or placing one of the five not yet placed. |
| [THIRD_PARTY.md](THIRD_PARTY.md) | Artwork, fonts and models made by others, and their licences. | Adding a font, a picture or a model, or before a store listing. |

## DESIGN.md, the history

Sections 1 to 12 are the original contract, written on 2026-09-11 before a line of code. From 13 on, each entry is a
decision, dated, usually with Matt's words and what was measured. Cite an entry by its number and its title, "DESIGN
§42 (The library)", because the numbers are not unique: §30, §49, §50 and §119 each name two entries, and 34 entries
have no number at all, such as "Claude on the account: the MCP server". Never renumber. A new entry goes at the end,
after the highest number (§123 today).

A topic page's own history is in these entries:

| Page | Entries |
| --- | --- |
| MARKDOWN.md | §3 (the editor core), §23, §29e (the item mark), "Every mark, side by side", "Mermaid diagrams, drawn", §116 |
| BOARDS.md | "Boards, written in markdown", "The board a list is already on", "A board's cards get a menu", "A tick can put an item on the board", "A board holds its height" |
| BOOKS.md | §70, §72, §74, §77, §78, §80, §87, §120 |
| CANVAS.md | §56, §62, §83 |
| LIBRARY.md | §5 (the store before it), §42, §100 |
| SYNC.md, LIVE.md | no entry of their own: the pages are the record. §86 is the pictures' part |
| SHARING.md | §75, §81, §82, §88, §89, §96 |
| PLUGINS.md | §37, "The marks are one plugin", "One GitHub plugin" |
| MCP.md | "Claude on the account: the MCP server", §73 |
| instruction-voice-commands.md | §114, §122, §123 |
| VOICE_TESTS.md | §13, §30 (Talking to the recorder), §38, §39, "The microphone is only open when something is being recorded" |
| GHOSTS.md | §64, §67, §68, §90, §93 |
| store/*.md | §113 |

## research/, the evidence before the build

Notes gathered on 2026-09-11 and 2026-09-12, before and while the first build was made. They cite sources and
measurements and are kept as they were: a snapshot, not maintained. Where one disagrees with the code, the code is
right.

| Page | What it was for |
| --- | --- |
| [research/codemirror.md](research/codemirror.md) | CodeMirror 6 as an editor that keeps the Markdown tokens on screen, on a phone. |
| [research/editor-logic.md](research/editor-logic.md) | What the app inherits from the Glacier kit's rich-text logic. |
| [research/house-style.md](research/house-style.md) | The code style of Matt's repos, read from GlacierUI and AttackFM. Still the reference for how code here is written. |
| [research/kit-surface.md](research/kit-surface.md) | The Glacier kit's components and props, as the app would use them. |
| [research/tokens.md](research/tokens.md) | The kit's design tokens, for the editor's stylesheet. |
| [research/mobile-shell.md](research/mobile-shell.md) | The Tauri 2 recipe for iOS and Android, in AttackFM's conventions. |
| [research/platform-research.md](research/platform-research.md) | Voice capture from a hardware button on Android and iOS. |
| [research/scaffold.md](research/scaffold.md) | The file plan for the first scaffold. |
| [research/spoken-markdown.md](research/spoken-markdown.md) | Getting Markdown out of speech: why it comes from the words said, not from Whisper. |

## prompts/

| Page | What it was for |
| --- | --- |
| [prompts/anti-ai-svgs.md](prompts/anti-ai-svgs.md) | Image prompts for three drawings on the guide's first page. The page they were for went (DESIGN §102), so nothing uses them. |

## What has no page of its own

Some parts of the app are described only in the header of the code that runs them. Read the header first:

| Part | Where it is described |
| --- | --- |
| Releasing: the version, the test gate, the deploy order and a rollback | `scripts/deploy-ota.mjs`, and the README |
| The test suites and the report the app shows | `scripts/test-report.mjs` and `vitest.config.ts` |
| The Android build's switches (staging, dev, Play, signing) | `src-tauri/gen/android/app/build.gradle.kts` |
| glyph-api's routes and environment | `server/src/main.rs` |
| The native commands, by the generation that brought each | `NATIVE_GENERATION` in `src-tauri/src/ota.rs` |
| The spoken cues, and the commands a recording reads | `src/app/capture/markdown.ts` with `src/app/capture/spoken/`; `src/app/ai/instruction.ts`, which decides what the recorder does with a command, `src/app/capture/finalInstruction.ts` and `src/app/capture/command.ts` |
| The app's shell: its screens, tabs, trail and boot | `src/app/App.tsx` and `src/app/shell/` |
| The settings kit and searching Settings | `src/app/settings/kit/settingsKit.tsx` and `src/app/settings/settingsSearch.ts` |
