# Ghost.md plugins

Ghost.md's integrations are plugins: modules that ship inside the app, arrive with its updates, and can each be
switched off in **Settings › Plugins**. Four ship as standard, all listed in `BUILT_IN` in
`src/app/plugins/registry.ts`:

| Plugin | What it adds | Folder |
| --- | --- | --- |
| **Notion** | A note's list items become tasks on a Notion board: swipe an item, tap the quiet "Notion" after it, or send the whole list from the note's More sheet. A task's status reads back onto its item, and ticking the item moves the task. | `src/app/plugins/notion/` |
| **GitHub** | A note linked to a repo sends its list items as issues, which tick both ways like Notion's tasks, and the repo is read on the phone into a short briefing the model gets with the note. Sending needs a token; reading does not. | `src/app/plugins/github/` |
| **Marks** | Ghost.md's own formatting on top of Markdown, eleven marks in one switch: a spoiler in smoke, a highlight (which takes a colour name), an aside, a doubt, a shout, an addition, and five effects written as an emoji twice (heat, frost, wave, shimmer, haunt). Typed or said. | `src/app/plugins/marks/` |
| **Claude** | A page in Settings with the address and instructions for Ghost.md's MCP server (docs/MCP.md). It runs nothing in the app: Claude reaches the account from outside, and the switch only shows or hides the page. | `src/app/plugins/claude/` |

A switched-off plugin offers nothing anywhere, at once. Its data stays where it was, so switching it back on
restores it as it was. A reset clears every plugin's storage, switched on or not.

## How a plugin is put together

```
plugins/
  types.ts         the manifest, the host, and every extension point
  host.ts          createHost(manifest): the plugin's only way onto the phone, cut to its manifest
  registry.ts      the plugins in this build, their switches, and what the app asks them for
  hooks.ts         the registry as React reads it: usePlugins(), useNoteLinks(noteId)
  reach.ts         each permission in Settings' words, and whether a plugin reaches past the phone
  kit.tsx          sheet pieces for a plugin's page on the More sheet (SheetTitle, SheetRow, SheetField, …)
  LinkMarks.tsx    the marks at a note's top saying what it is linked to, and its workspace
  detailsCache.ts  a linked thing read back (a task, an issue): paced, kept fresh, kept offline
  sendItems.ts     sending list items somewhere, once each, with the link written back
  PluginsPane.tsx  Settings › Plugins
  <id>/
    manifest.ts    the manifest, and `export const host = createHost(manifest)`
    index.tsx      the GlyphPlugin: manifest, icon, and the extension points it uses
    …              the plugin's own modules, which reach the phone only through `host`
```

Notion and GitHub keep their manifest in `manifest.ts`, beside the `host` their modules import. Marks and Claude
reach nothing through a host, so each declares its manifest inline in `index.tsx`. `manifest.ts` is the convention
for a plugin with a host, not a rule.

`kit.tsx` is not only the plugins'. The book, canvas, workspace and new-note sheets are drawn from it too, and it
draws with `editor/NoteSettings.module.css`, so a change to a class there restyles every one of those sheets. The
sheet's shell (scrim, grip, drag and the back gesture) is `editor/Sheet.tsx`.

To add one: make the folder, write the manifest and `index.tsx`, and add the plugin to `BUILT_IN` in
`registry.ts`. Nothing else in the app changes. The note's More sheet, the list swipe, the recorder, the AI and
Settings already ask the registry for whatever switched-on plugins offer.

## The manifest

This is `plugins/notion/manifest.ts`, with its reasons shortened:

```ts
export const manifest: PluginManifest = {
  id: 'notion',                    // its switch and its storage live under this
  name: 'Notion',
  description: 'Turns list items into tasks on your Notion boards: swipe an item, say it, or send a whole list.',
  version: '1.0.0',
  author: 'Ghost.md',
  standard: true,                  // on until switched off
  permissions: [                   // each with the reason the person reads
    { kind: 'notes', why: '…' },   // notes · network · ai · voice · native
    { kind: 'network', why: '…' },
    { kind: 'voice', why: '…' },
    { kind: 'native', why: '…' },
  ],
  hosts: ['api.notion.com', 'attack.fm'],  // shown with the network permission
  native: { generation: 12, commands: ['notion_save_account', 'notion_account', 'notion_disconnect', 'notion_request'] },
  storage: ['glyph-notion-links', 'glyph-notion-signin', 'glyph-notion-tasks'],  // localStorage keys it owns
};
```

The manifest is enforced, not decorative:

- **The host** refuses what the manifest doesn't list: a native command, a storage key, or `host.require(kind)`
  for an undeclared permission. `host.openUrl` needs `network`. Plugin code that calls a core module directly
  asserts the permission with `host.require` first: the GitHub plugin before its `fetch` (`src/app/plugins/github/repos.ts`,
  `src/app/plugins/github/issues.ts`) and before the model writes its briefing, and Notion's client before each request.
- **The registry** refuses to load a plugin whose extension points outrun its permissions. Voice commands and item
  targets need `voice`. Note actions, the item swipe, item targets and suggestions need `notes`. It also refuses a
  formatting whose name is not a capitalised word of letters and digits, or whose delimiter is not one to three of
  one character Markdown doesn't use, or an emoji twice.
- **Settings › Plugins** shows each permission with its reason, and the hosts, straight from the manifest
  (`reach.ts` has the words).

A permission can also be declared only so the card is honest about what the plugin reaches from off the phone.
Claude's `notes` and `network` are such: nothing in the app exercises them.

## Extension points

All optional, all in `types.ts`:

| Field | Where it shows | Shape |
| --- | --- | --- |
| `settings` | Its own row and page in Settings, while it's on, in its own colour | `{ Pane, summary(), hue? }`, the hue one of those settings.css draws |
| `noteLinks` | Rows under **Linked to** on a note's More sheet; each opens the plugin's `Picker` inside the sheet. What a note is linked to is also worn at its top (`LinkMarks.tsx`) | `hint(noteId)`, `unavailable()`, `Picker`, `linked(noteId)` |
| `noteActions` | Rows under the links (Send list to Notion) | `visible`, `hint`, `enabled`, `run(editing)` |
| `itemAction` | Swiping a list item left in a note | `label`, `busyLabel`, `available(noteId)`, `run(text, editing)` |
| `voice` | Commands heard while recording, tried before Ghost.md's own | `parse(text)`, `describe(parsed, ctx)`, `run(parsed, ctx)` |
| `itemTargets` | A word that can end an item command's note name ("new task for AttackFM **in Notion**") | `word`, `afterAdd(noteId, lines, ctx)` |
| `tips` | Suggestions in a pause while recording | `(recentTitle) => Tip[]` |
| `formatContext` | Background the model is handed with a note when the AI runs on it (`format/pipeline.ts`) and in the review after a recording | `for(noteId)`, `version(noteId)` |
| `suggest` | A quiet word at the end of a line the plugin could act on, tapped to do it (the "Notion" after an unsent to-do) | `(noteId, body) => Suggestion[]`, each `line`, `label`, `busyLabel`, `run(editing)` |
| `marks` | Read-back for the links a plugin writes: a pill on the item, a card on tap, and the actions (`done`, `reopen`) that make a tick sync both ways | `peek`, `want`, `open`, `reads?`, `actions?` |
| `formats` | An inline formatting of its own in every note (the eleven built in are all the Marks plugin's, `plugins/marks/index.tsx`): the words between two runs of its delimiter, drawn its way, and a word for it on the Style page of the press-and-hold menu (the spoiler's `\|\|secret\|\|`, in smoke) | `InlineFormat[]`, each `name` (a capitalised node name), `delimiter` (one to three of a character Markdown doesn't use, or an emoji twice for an effect: `🔥🔥`), `look` (`{ kind: 'wisp' }`, `{ kind: 'style', css, clearAtCaret? }`, or `{ kind: 'effect', effect }` naming one of `editor/textEffects.ts`'s effects), and optionally `cue` (the word that says it while recording: "highlight … end highlight"), `about` (its line in the guide), `icon` (its own mark on the Style page) and `tint` (a name in brackets after it made into CSS: `==the key==(green)`) |

`NoteEditing` (for note actions, the swipe and suggestions) changes the note on screen through its editor, so each
change is one undo step and saves like typing.

**Voice commands, today.** Since the recorder reads a command only from the finished recording (DESIGN §114,
`ai/instruction.ts`), `voice` and `itemTargets` are heard only by the phrase-by-phrase reader in
`capture/take.ts`, which the voice test suite drives (docs/VOICE_TESTS.md). A recording made in the app does not run
them: "send that to Notion" said into the recorder stays words. `tips` and a format's `cue` still reach the
recorder.

**Local only.** While the person has Local only on (Settings › Formatting), every plugin whose manifest
declares the `network` permission is off, whatever its switch says, and the registry tells its listeners
when that changes. A plugin that can do part of its work without the network should split that part
into a plugin without the permission, or it goes dark with the rest.

**Linking an item.** There is one form for a list item linked to something outside Ghost.md, and every plugin
writes it through `core/itemLinks.ts` `linkedLine(line, url, name)`: the words stay as they are and the item
ends with a mark, a link whose words are the plugin's lowercase name - `- [ ] Buy milk [notion](https://…)`.
The editor draws the mark as a small solid pill with the name on it, `unsentItems` skips marked items (and
the older whole-words form), and a run of the model keeps the mark's link by construction (`format/links.ts`): a
link whose words survive is made the link again. A plugin should not invent its own way of marking a line: the pill, the suggestion and the model's handling all key
off this one shape. Sending itself follows `sendItems.ts`: the same words are never made twice, a made thing
always gets its link, and a failure stops the run.

`CaptureContext` (for voice commands) can:

- read the take's note and the last thing said
- set the status chip
- link words of the take to a URL
- append a line
- update another note while keeping the take in step

A context's `version` must change whenever `for` would say something new; the note is then formatted again. When
exactly one plugin gives a context, its version is used as it is, so notes formatted before plugins existed stay
formatted.

## Plugins from outside Ghost.md

Not yet. Every plugin ships in the app. The host is the seam for them: an outside plugin would get the same
`PluginHost` over a message bridge from a sandboxed frame instead of as a function call, with the manifest shown
for approval before it loads. That is a plan; none of it is built.
