# What 2.1 added

Each section is one feature agent's, in its own words, appended as its branch was merged. Append only.

## share-import: share into Ghost.md, and imports from Obsidian and Evernote (2026-10-16)

### Share into Ghost.md (Android)

- **Where:** any app's share sheet › Ghost.md (or Ghost Flutter). Text, links, pictures and any file, one or many
  (`SEND`, `SEND_MULTIPLE`; `text/*`, `image/*`, `*/*`: android/app/src/main/AndroidManifest.xml).
- **What happens:** the phone reads what was shared at once, while the sharing app's grant holds
  (android/…/ghost_md/ShareIn.kt): a picture shrunk and turned the right way up into the cache as the editor's own
  Add a picture does (Pictures.kt `shrink`), any other file copied whole. The share waits in the process, as a link
  that opens the app does (AppLinks.kt), so it works from a cold start and while the app is open. Once the notes are
  read the app opens a small sheet over itself (lib/share/ui/share_in_sheet.dart): a new note, named for the share
  (its subject or page title, else its first line, else its first file's name; editable), filed in a workspace or
  none; or added to the end of a note, above its comments, found by its name with the five notes last added to
  first (kept on the device, `glyph-share-recent`). Save or Cancel, and the app's task goes behind the app the
  person shared from (`moveTaskToBack`).
- **As Markdown** (lib/share/share_in.dart): a link is `[page title](url)`, or `<url>` with no title; nothing is
  fetched. Text is kept as it came. A picture is `![](image/<name>)`, adopted by the core like any picture. Any
  other file is `[Lease.pdf](file/<uuid>.pdf)`, kept under `<data>/attachments/` by `storeSharedFile`
  (lib/core/shared_files.dart), the one function the attachments work can point at its own store.
- **Not done:** sync does not carry `attachments/` files, and deleting a note does not remove its file (both belong
  to the attachments work). A GIF or SVG shared as a picture becomes a still JPEG (the editor's insert does the
  same). No iPhone share extension (see below).

### Settings › Export › Import (Android and the Mac; not the iPhone)

The Export page has an Import row; its page has two rows. An import makes **one workspace**, `Imported from
Obsidian 2026-10-16` (a second the same day is `… (2)`), and files everything in it: the app's folders are its
workspaces, each a folder on disk, so the group shows in the sidebar, sits in one folder in Files and Obsidian, and
goes in one go with the page's **Remove this import** (or Settings › Workspaces › delete with "put the notes in the
trash"), which trashes every note it made and takes the workspace away. Nothing is deleted for good there.
Nothing in the library is written over: a taken name gets ` 2`, ` 3`, and the page says each rename. At the end it
says what came in, what was renamed and what was left out.

- **Obsidian vault** (lib/importer/obsidian.dart): the vault's folder chosen with Android's folder picker
  (files/ImportTree.kt, through FilesBridge.kt) or the Mac's open panel (FilesChannel.swift). Every `.md` is a note
  word for word, front matter, `[[wiki links]]` and `![[note embeds]]` as written, at
  `workspaces/<group>/<its folders>/<its name>.md`, dated by its file. Every `.canvas` is a canvas note (its JSON
  Canvas as written, a picture card pointed at the kept picture). Every attachment a note names (`![[x.png]]`,
  `![[x.png|300]]`, `![](../a/x%20y.png)`, `[[x.pdf]]`, `[t](x.pdf)`, found as Obsidian finds them) is kept once and
  its references rewritten: a JPEG, PNG or WebP to `![](image/<name>)`, anything else to `[name](file/<name>)`.
  Two things are added where the app would read a note otherwise than Obsidian (lib/importer/obsidian_names.dart):
  a note whose first line is not its file's name is given `title: "<file name>"` (Obsidian names a note by its
  file; the app by its first line or `title:`, and finds `[[links]]` by that), and a front matter list written down
  the page (`tags:` then `  - a`) is written across (`tags: [a]`), which the app's front matter reader needs.
  Attachments no note names are kept too and listed in one note, "Files from <vault>". Folders starting with a dot
  (`.obsidian/`, `.trash/`, `.git/`) are left out and said; so is a file over 512 MB.
- **Evernote export (.enex)** (lib/importer/evernote.dart, enex.dart, enml.dart): one or more files; each is a
  notebook named by its file, made a Ghost.md notebook whose index lists its notes, its pages in a folder beside it.
  The export is read as it streams in an isolate of its own (linear in its size: see enex.dart on why the text is
  handed to the `xml` parser in pieces that end before markup), a note at a time. A note is `# title`, its tags as
  `#tag` marks (`Quick meals` is `#Quick-meals`, `2024` is `#tag-2024`), its ENML as Markdown (headings, bold,
  italic, strikes, lists nested, `en-todo` and `--en-todo` lists as `- [ ]`/`- [x]`, tables, links, a link to
  another Evernote note as `[[its title]]`, code and code blocks, quotes, rules, line breaks), its resources matched
  to `<en-media>` by MD5 and kept like pictures and files, one the body never names put at its end, and its source
  address as `[Source](…)`. Created and updated dates are Evernote's. Encrypted passages are left out and counted.
- **New packages:** `xml` (was already in the tree under flutter_svg, now direct) and `crypto` (MD5).

### What is not done, and why

- **Links still resolve by title.** With `title:` added a `[[Name]]` link finds an imported note; a link with a
  folder (`[[Projects/Alpha]]`) or a heading is the links work's to follow. A name with no ASCII letters (all
  Japanese, say) has no key the app matches by (lib/core/title_key.dart), so links to it do not resolve.
- **Folders inside the group** are kept on disk; the app shows the group as one workspace, since its folders are
  workspaces. `NoteFolders` now leaves a note that is already under its workspace's folder, at any depth, where it is
  (lib/core/note_folders.dart); renaming the workspace still flattens them, as it always has.
- **iPhone:** no Import (its section is hidden there) and no share extension. A share extension is a separate target
  (an app extension with its own bundle id, `com.apple.share-services`, an App Group the app and the extension both
  join so the extension can drop what it was given into a shared container, and a way for the app to pick it up as
  it opens: a `ghostmd://share` link or a look at the container on launch). It changes the store build's
  entitlements, provisioning profiles and review, so it waits for a decision.
- **Pre-existing, found on the emulator:** in a debug build, a home page of two or more card columns (the Fold
  opened) with a card whose peek draws a picture throws "LayoutBuilder does not support returning intrinsic
  dimensions" (lib/editor/media/images.dart `KeptPicture` builds the picture in a `LayoutBuilder`;
  lib/home/note_card.dart `CardRow` asks each card its intrinsic height), and the home page stops laying out. A
  release build reads the picture's height as 0 instead. Reproduced on main's code with a widget test (a `Home` at
  704 x 933, four notes, one with a picture, a `MemoryPictureStore`); any note with a picture does it, and shares
  and imports bring pictures.
