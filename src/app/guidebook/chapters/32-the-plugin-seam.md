# The plugin seam

_How Notion, GitHub, Marks and Claude plug into Ghost.md without the app ever naming them, and how a fifth would._

## Nothing names a plugin

A plugin is a module that ships inside the app and arrives with its updates. There is nothing to install, and nothing from outside yet. The note's More sheet, the list swipe, the recorder, the formatter, the editor and Settings never import one. Each asks the registry, `src/app/plugins/registry.ts`, what the switched-on plugins offer in its place, and draws that.

Four ship, in `BUILT_IN`, all standard:

| id | What it adds | Extension points it uses |
|---|---|---|
| `notion` | List items as tasks on Notion boards | `settings`, `noteLinks`, `noteActions`, `itemAction`, `suggest`, `marks`, `voice`, `itemTargets`, `tips` |
| `github` | Items as issues, and the repo as a briefing for the formatter | `settings`, `noteLinks`, `noteActions`, `itemAction`, `suggest`, `marks`, `formatContext` |
| `marks` | Eleven inline formats: spoiler, highlight, aside, unsure, shout, added, and five effects | `formats` |
| `claude` | A page for the Claude connector | `settings` |

The Claude plugin runs nothing in the app. Claude reaches the account from outside, through the sync service, so the plugin is its page; its switch shows or hides that page and does not connect or disconnect anything.

## The manifest

`PluginManifest` in `src/app/plugins/types.ts` is what a plugin says it is: `id` (lowercase, the key its switch and storage live under), `name`, `description` (one sentence for its card), `version`, `author`, `standard`, `permissions`, `hosts`, `native` and `storage`.

Each permission comes with a `why`, which the person reads.

| kind | Settings calls it | What needs it |
|---|---|---|
| `notes` | Your notes | `noteActions`, `itemAction`, `itemTargets`, `suggest` |
| `network` | The internet | `openUrl`; and Local only holds the plugin off |
| `ai` | The model on your phone | Asserted by code that runs it |
| `voice` | Voice commands | `voice`, `itemTargets` |
| `native` | Built-in app commands | `invoke` |

The words are `PERMISSION_WORDS` in `plugins/reach.ts`, and `reachLine` makes a card's one line: Notion's reads "Your notes · The internet (api.notion.com, attack.fm) · Voice commands · Built-in app commands".

## The host

`createHost(manifest)` in `plugins/host.ts` is a plugin's only way onto the phone, cut to its manifest. Every call checks before it acts, and anything undeclared fails with a `PluginPermissionError` naming the plugin: thrown at once, or for `invoke` a promise that rejects.

- `invoke(command, args)` needs the `native` permission and the command listed under `native.commands`.
- `storage.get`, `set` and `remove` touch only the keys in `storage`. A write or a removal tells every listener (`onPluginStorage`), which is how a note's link marks know to redraw.
- `openUrl(url)` needs `network`.
- `nativeReady()` answers whether this binary's native generation is at least the manifest's. A native command cannot arrive over the air, so a plugin asks before it offers one.
- `require(kind)` is for plugin code that calls core modules directly. `plugins/github/repos.ts` asserts `network` before it reads a repo and `ai` before it runs the model.

Notion and GitHub keep the manifest in `manifest.ts` and export `host` beside it. Marks and Claude declare theirs in `index.tsx` and make no host, since neither reaches the phone. The host is also the seam for plugins from outside, when there are any: they would get the same `PluginHost` over a message bridge instead of a function call.

==A plugin that reaches past its manifest throws the moment the code runs, so it fails its first test instead of quietly doing something Settings never said.==

## The registry

`createRegistry(plugins, store)` is made once, as `plugins`, from `BUILT_IN`. As it is made it:

- refuses two plugins with one id;
- runs `checkExtensions`: voice commands and item targets need `voice`; note actions, the swipe, item targets and suggestions need `notes`; a format needs a capitalised name of letters and digits, and a delimiter of one to three of the same character Markdown does not use, or an emoji twice;
- registers each id as a mark name (`registerMarkName` in `core/itemLinks.ts`), so `[notion](…)` at the end of an item is Notion's;
- hands each plugin's `marks` to `core/markDetails.ts`, behind a check that answers nothing while the plugin is off, so its pills draw plain.

Switches live under `glyph-plugins` in local storage, id to on or off, and a plugin with no switch is on if it is standard. Local only (Settings > Formatting) holds off every plugin whose manifest says `network`, whatever its switch says. A switched-off plugin offers nothing anywhere and keeps its data, so switching it back on brings it back as it was. `storageKeys()` lists every plugin's keys, on or off, with the switches' own key, for `core/reset.ts`.

The app's questions, and who asks them:

| Question | Asked by |
|---|---|
| `noteLinks()`, `noteActions()` | The More sheet, `editor/NoteSettings.tsx` |
| `linksOf(noteId)` | `useNoteLinks`, for the marks at a note's top |
| `itemAction(noteId)`, `suggestions(noteId, body)` | `editor/notePlugins.ts`: the swipe, the press-and-hold send, the quiet word after a line |
| `voiceCommands()`, `itemTargets()`, `tips()` | The recorder, `capture/CaptureScreen.tsx` |
| `contextFor(noteId)` | The formatter, `format/pipeline.ts`, and the review, `ai/useNoteReview.ts` |
| `contextVersion(noteId)` | The formatter, `format/pipeline.ts` |
| `formats()` | The editor, the cheat sheet (`guide/marks.ts`) and the recorder's spoken cues |

`contextFor` joins every plugin's context. `contextVersion` passes one plugin's version through as it is, so notes formatted before plugins existed are not formatted again.

Only the formats wait. The editor reads `formats()` once, when its view is made, so switching Marks off reaches an open note the next time it is opened; the recorder reads its spoken cues once, when its screen opens. The swipe, the quiet words and the More sheet ask the registry when they are used.

## React, rows and pills

- `plugins/hooks.ts`: `usePlugins()`, through `useSyncExternalStore`, and `useNoteLinks(noteId)`, read again on a storage write or a switch. It sits apart so the registry stays plain code the recorder can call.
- `plugins/PluginsPane.tsx` is Settings > Plugins: a card per plugin with its switch, "What it may reach" with a Why that opens each permission's reason, and the way to its own page. That page is a Settings section of its own, `plugin:<id>`, while the plugin is on.
- `plugins/kit.tsx` is the More sheet's parts (`SheetTitle`, `SheetRow`, `SheetField` and the rest), so a plugin's picker draws in the sheet's look. The book, canvas, workspace and new-note sheets are built from them too.
- `plugins/LinkMarks.tsx` draws, at a note's top, its workspace and a mark per link a plugin reports through `NoteLink.linked`. A tap opens the More sheet.
- `core/markDetails.ts` stands behind the pill at the end of a linked item: the mark is read back through the provider registered under its name, `peek` on every draw, `want` to read again, `actions` for the menu.

## Shared machinery

Two jobs had been written twice and had drifted, so both plugins now share them.

- `plugins/sendItems.ts`: `itemSender(mark)` sends items and writes each link back, one undo per item. The same words from the same note to the same place are not made twice within five minutes. A made thing always gets its link, found again by its words or its line. A failure stops the run and is said in the service's words.
- `plugins/detailsCache.ts`: `detailsCache({ host, storageKey, read, … })` reads two at a time, keeps an answer fresh for 45 seconds, tries a failure again once it is as old as a stale answer, and keeps the last 300 answers in the plugin's own storage, so a note opened offline shows what its links last said.

Every change a plugin makes to the open note goes through `NoteEditing` (`editor/notePlugins.ts`), which edits through the editor, so each is one undo and saves like typing.

## Adding a fifth plugin

Say it sends items to an issue tracker, and its id is `tracker`.

1. Make `src/app/plugins/tracker/`. Write `manifest.ts`: the id, one sentence of description, `standard`, each permission with its why (`notes` and `network` at least), its `hosts`, and every local storage key it will use. Export `host = createHost(manifest)` beside it.
2. Write its modules so they reach the phone only through `host`. One that calls core code directly asserts first, `host.require('network')`.
3. Link items the one way: send them through `itemSender('tracker')`, whose `send(items, to, editing, make)` writes each link with `linkedLine(line, url, 'tracker')` from `core/itemLinks.ts`. The id is the mark's name, so `[tracker](…)` is known the moment the registry loads.
4. Read the issues back with `detailsCache`, and export its `MarkDetailsProvider` as `marks`, so the pills show where each stands.
5. Write `index.tsx`: a `GlyphPlugin` with the manifest, an `icon` from `@glacier/icons`, and the points it uses. A `noteLinks` row with its `Picker` and `linked`, an `itemAction` for the swipe, `suggest` for the quiet word, `settings: { Pane, summary, hue }` for its page. Voice commands would need `voice` in the manifest.
6. Add it to `BUILT_IN` in `plugins/registry.ts`, and to the list in `plugins/registry.test.ts` that checks each built-in plugin against its manifest.
7. If it needs a command in the binary, add it to the Rust shell, raise `NATIVE_GENERATION` in `src-tauri/src/ota.rs`, and list the command under `native.commands`, with the manifest's `native.generation` set to the new number. Ask `nativeReady()` before offering it, as Notion's `unavailable()` does through `notionAvailable()`, so an older binary says it needs an update.
8. Run `npx vitest run src/app/plugins`, and lint the files you touched by path.

Nothing else in the app changes. The More sheet, the swipe, the recorder, the formatter and Settings already ask.

## What docs/PLUGINS.md still says

- Two standard plugins, Notion and "Projects" in `src/app/plugins/projects/`. Four ship, and there is no `projects/` folder: the repo briefing is the GitHub plugin's `formatContext` (`plugins/github/repos.ts`).
- "The seven built in" formats, "the Spoiler plugin". The Marks plugin has eleven, the spoiler one of them.
- Its tree has no `hooks.ts`, `reach.ts`, `LinkMarks.tsx`, `sendItems.ts` or `detailsCache.ts`, and gives every plugin a `manifest.ts`.
- `settings` is `{ Pane, summary() }`; the code adds `hue`. A `noteLinks` row also answers `linked(noteId)`, and suggestions need `notes` too.
- Its example manifest's author is "Glyph"; the built-in ones say "Ghost.md".
- It, like much of the code, calls the note's sheet "the cog". The button is three dots now, "More for this note". And in the code, `InlineFormat`'s comment in `plugins/types.ts` says a format is typed, not spoken; every one of the Marks plugin's eleven has a `cue`, and the recorder hears it.

## Read next

- [[Notion and GitHub]]
- [[The Claude connector, inside]]
- [[Tests, and the report that ships]]
