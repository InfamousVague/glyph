# Features added for 2.1

Append-only: one section per feature agent, headed with its name.

## publish-email

### Publish a note or a notebook as a site

- **Where:** a note's or a notebook's More sheet (and the bar's Share), under **Site**, below the shared link's rows: Publish as a site, Copy the site's link, Publish again, Unpublish. Settings › Account › **Published sites** lists every site of the account with when it was last published, Copy and Unpublish.
- **What:** the shared link's sealed content (context `glyph/v1/site`), read on the reader page at `https://ghostmarkdown.com/s/<id>#<key>`, a page per address (`/s/<id>/<page-slug>#<key>`), the notebook's pages down the side in order, `[[links]]` and Previous/Next between its pages, pictures, light/dark by the system, Made with Ghost.md. Published by hand, never following saves. Its key is sealed beside it under the account key (`site:<id>`), so every device lists it. Never indexed (meta, header and API), and no option for it, since an indexer cannot read the fragment.
- **Files:** `server/src/sites.rs`, `server/src/store/sites.rs`, `server/src/sites_tests.rs`; `lib/share/sites.dart`, `lib/share/ui/site_rows.dart`, `lib/settings/published_sites.dart`; `tauri/src/read/Site.tsx`, `site.ts`, `Site.module.css`, `drawn.ts`; design in `tauri/docs/SITES.md`; guide chapter 21.
- **Not done:** a page's slug (its title) reaches the web server when someone opens that page's own address (said in SITES.md and the guide, not in the app's row). No site on the iPhone. Settings search does not find the two new cards.

### Email to a note

- **Where:** Settings › Account › **Email to a note**: Turn on an address, the address with Copy, Make a new address, Turn off. Shown only when the service takes mail. Each sync pass files what was mailed, before the notes step.
- **What:** `<16 base32 letters>@in.ghostmarkdown.com`, one an account. Mailgun posts each raw mail to `POST /api/v1/mail/inbound/mime` (HMAC of timestamp and token checked, a token taken once); the service reads it into subject, sender, Markdown body and files, seals it to the account's encryption public key (ECIES as the org-key wrap, context `inbound-mail:<id>`; the mail under that key, `mail:<id>`) and keeps only that. The device opens it with the core's existing `unwrap_with`, `seal_key_import`, `open`, writes the note with `store_apply` (Inbox, `from:` in front matter, pictures kept, other files named), and deletes the sealed copy. 30 mails an hour an address, 10 MB a mail, 200 waiting.
- **Files:** `server/src/mail.rs`, `server/src/mail/{mailgun,message,seal}.rs`, `server/src/store/mail.rs`, `server/src/mail_tests.rs`; `lib/mail/mail_in.dart`, `lib/mail/mail_note.dart`, `lib/mail/ui/mail_card.dart`; design and Matt's setup list in `tauri/docs/MAIL.md`; guide chapter 19.
- **Not done:** files that are not pictures are named, not kept (`MailPassContext.keepOther`, `notKeptLine`, is the seam for feat/files). Not on the iPhone. Nothing goes live until Mailgun, the DNS records and `GLYPH_MAILGUN_SIGNING_KEY` are set (tauri/docs/MAIL.md, "To go live").

Each section is one feature agent's, headed with its name, added to and never rewritten by another.

## clipper: the Ghost.md web clipper

**What it is.** A browser extension in `clipper/` (its own `package.json`, built with esbuild into `clipper/dist/chrome`
and `clipper/dist/firefox`, Manifest V3, one source) that saves what is on a web page into the person's Ghost.md:
Article (Readability), Selection, Full page, Bookmark (link, description, preview picture) and Screenshot (the visible
tab). The popup edits the title, adds tags, files the note in a personal workspace or a notebook, takes a comment, and
saves; a context menu item "Save selection to Ghost.md" and two shortcuts (Alt+Shift+G opens the clipper, Alt+Shift+S
saves the selection or the article straight away). `clipper/README.md` is the whole of it: modes, note format,
permissions and why each, the session ("Stay signed in"), how to build, load unpacked and test, and what each store
would need.

**Sealed in the browser.** It is a device of the account made of the web app's own code (`tauri/src/app/core`:
`derive`/`unwrap`, `call`, `seal`, the sync's `sendFile`), mirroring the connector's `GlyphAccount`. The service sees
the login half of the password and sealed blobs, as from any device; the e2e proof searches every request body for
the page's words and the password and finds neither.

**The note** is plain Markdown: front matter `source:` and `clipped:` (and `tags: [..]`, the one list form the app's
front matter rule and its queries both read), the title as the first heading, the comment, a rule, the page's words,
and pictures as `![alt](image/clip-<id>.jpg)`, stored sealed through the app's file route as the app stores a picture
(1600 px JPEG). A picture that cannot be stored stays a link.

**In the app.** `lib/editor/media/source_line.dart` (new) draws a note's `source:` as one quiet line under its title,
"From field.example/art…tml" (shortened as every address is), whose tap opens the page; the front matter itself stays
folded to "source · clipped · tags". Hooked by one line in `lib/root/note_desk.dart`'s editor extensions. Tests:
`test/clipper/source_line_test.dart`, and `test/clipper/clipped_note_test.dart`, which opens two notes the clipper's
end-to-end run saved (an article with two pictures; a page of tables, code and to-dos) in the app put together and
draws them, phone size and the Fold's inner size.

**Not done.** No store listing or publishing (Chrome Web Store, Edge, AMO, Safari: `clipper/README.md` says what each
needs; Safari needs an Xcode wrapper app). Not offered: an organization's workspace (a team's notes go through the
team's channel, `mcp/team.ts`, which the clipper does not carry) and journals (their pages are named by the minute).
Not verified: Firefox (built, never loaded), a real toolbar click and the real context menu and shortcut keys (the
proof presses the button through Chrome's DevTools command `Extensions.triggerAction`, which grants the same
`activeTab`, and calls the menu's and shortcut's handler directly), real sites (only fixture pages), and the phone
receiving a clip through sync (proven against a local glyph-api and through the connector's and the web app's sync
code, not on the Fold).

**Found beside, not the clipper's:** on a home of two cards across (the Fold opened, 669 and 900 wide), a note card
whose picture is drawn fails its row's layout: `lib/home/note_card.dart` `CardRow` asks for the intrinsic height of a
card holding a `LayoutBuilder` ("LayoutBuilder does not support returning intrinsic dimensions"). Any note with a
picture does it, clipped or not; a phone-width home (one card a row) does not.

# What 2.1 adds

Each section is one agent's, headed with its name, and only ever added to.

## links: links between notes, the graph, embeds, block references, aliases, the outline and a note's length

Branch `feat/links`. Everything is in the Flutter app; the Tauri app and its guide are unchanged.

### What was added, and where a person finds it

- **The link index** (`lib/core/link_index.dart`). One index of which notes link to which, the names each note
  answers to (title, `aliases:`, a ticket's key, its file's path) and every note's words, for the "Mentioned in"
  search. Read whole in a worker isolate once (`Isolate.run`, the index handed back without a copy), then told each
  note that changed as the library's listeners are told (a note that is the same object has not changed), a body at
  a time on the UI isolate: about half a millisecond for one note changed in a library of 2,000 on the Mac
  (`test/core/link_index_test.dart` prints it). A change of more than 64 notes at once is read in the worker again.
  Links are kept by the name written, so which note a name means is asked when wanted, the way the editor asks: a
  rename or a second note of one title is followed at once. Kept in memory, made again at each launch; nothing is
  written anywhere. Made in `lib/root/ghost_root.dart` over the notes every screen shows.
- **Links** on a note: the note's tools have a Links ring (Lucide `link-2`) with the number of notes that link here
  at its corner, after History, coming out of More while there is room, as the other spare tools do. It opens the
  More sheet at its Links page; the sheet has a new group, "Links and outline", with Links, Outline, Local graph and
  Copy link to this line. The Links page (`lib/links/links_panel.dart`): "Linked from N notes", each link's line
  with the link in the full ink, a tap opening that note at that line; "Mentioned in", the notes that say this
  note's title or an alias as words (any case, any punctuation between the words, as a title is matched) and do not
  link it, each with Link, which writes `[[the words as they were]]` into that note through the library (as a
  query's tick writes another note) and says "Linked in Diary." with an Undo that takes the brackets off again
  while they are still there. Words inside code, links, addresses and front matter are not mentions.
- **The side panel** on a window wide enough for two panes (the Fold opened, a Mac): Links and Outline tabs beside
  the book's Index and the desktop's History (`lib/aside/aside_panel.dart`, `AsideTab.links`, `AsideTab.outline`),
  so the side panel's toggle is now in the bar on every note of words there.
- **The graph** (`lib/links/graph_layout.dart`, `lib/links/graph_view.dart`): "Graph of your notes" in the command
  palette and in the sidebar's foot beside Settings (Lucide `network`); a note's local graph from the More sheet's Local
  graph and the palette's "Local graph of this note", one or two links out. A page of its own over the app (pushed
  on the root navigator, as Developer's benches are). Force-directed (Barnes and Hut), laid out in a worker isolate
  past 160 notes (a thousand notes and 3,271 links in about 300 ms on the Mac), the same layout each time; then the
  dots and lines are one recorded picture that a pinch or a drag only draws again (a test holds a pinch to recording
  nothing). Dots coloured by the workspace's hue (`app-space` under `data-hue`, as the canvas and comments wear
  them), sized by links, a note with none dim; names once zoomed in, the busiest first and none over another. Pinch
  or wheel to zoom, drag to move, tap to open (where it was left), hold to light a note and its neighbours.
  Archived notes are left out of the whole graph.
- **Embeds** (`lib/editor/media/note_embeds.dart`): `![[Note]]`, `![[Note#Heading]]`, `![[Note#^name]]` on a line
  of their own draw that note, that heading's section, or that named line (a list item with its own items) in
  place, read only, its name and an Open over it, a tap on the words opening it at the place; at most about half a
  screen tall, faded where there is more. Two levels deep at most; a note never draws itself or a note it is drawn
  inside of (the line stays its link). `![[picture.png]]` and `![[picture.png|300]]` draw a picture the library
  keeps by that name. With the caret on the line it steps aside and the line shows as typed; the file is never
  changed. A canvas named this way is still the canvas's frame (`canvas_frames.dart`).
- **Block references** (`lib/core/block_ids.dart`): a ` ^name` at the end of any line names it (list items had
  them since boards), drawn quiet as an item's is; `[[Note#^name]]` opens the note with the caret before the name
  and the page scrolled to it, `[[#^name]]` goes to it in the same note, and `[[Note#Heading]]` now lands on the
  heading (`lib/note/land_at.dart`). Copy link to this line (More sheet) gives the caret's line a name made from its
  words if it has none (one undoable edit) and copies `[[Title#^name]]`; on a heading it copies
  `[[Title#Heading]]`.
- **Aliases** (`lib/core/aliases.dart`): `aliases:` as Obsidian writes it, a list in brackets, a list with commas,
  a list of lines, or the old `alias:`. A `[[link]]` to an alias opens the note (after any title of the same words:
  `lib/root/library_reads.dart`), the + sheet's A note offers aliases, a search finds a note by its alias as near
  as by its name (`lib/core/search_hits.dart`), and unlinked mentions look for them.
- **The outline** (`lib/links/outline.dart`): the More sheet's Outline page and the side panel's Outline tab, each
  heading indented by its level, the one the page is at ringed (in the side panel it follows the page as it
  scrolls), a tap scrolling the page to it. Read from the editor's own kept lines, so typing reads only the line
  typed.
- **A note's length** (`lib/links/word_count.dart`): words, characters (front matter and line breaks left out) and
  minutes to read at 238 words a minute, on the Outline row's hint and at the top of the Outline page and tab; with
  words selected, the selection's too. Counted only when one of those is drawn, and kept for the body counted.
- `[[Title|words]]` is read with its title before the bar (`lib/editor/items/wiki_links.dart`), so such a link opens
  its note.

### What is not done, or differs

- Markdown links to a note's file (`[words](Some%20note.md)`) are counted as links (backlinks, the graph), as
  Obsidian counts them, but the editor does not open them: the app has never drawn them as links to notes.
- A front matter whose `aliases:` is a list of lines is not front matter to the rest of the app (its rule, the web
  app's and the core's, takes only `key:` lines), so such a note's title is what that rule makes of it; its aliases
  are still read. The two other ways of writing them are front matter as before.
- A block's name is the boards' shape (lower case letters, digits, `-`, `_`); a name Obsidian wrote in capitals is
  not read. Obsidian makes its own in lower case.
- Embeds draw a note's words as a read-only view of them (the app's marks, links, names, pictures); what needs the
  note's own editor (a board, a query, a ticket's panel, comments) is drawn as its lines inside an embed.
- The palette's "Links to this note" opens the side panel's Links tab where it is shown, else the More sheet's page.
- The guide's chapter 6 is not changed: its Markdown is the web app's byte for byte (test/guide/guidebook_test.dart),
  and the web app has none of this.
- Not walked on a phone or an emulator: held by widget tests and pictures (dark, 430 x 932 at 3, and the Fold's
  inner 900 x 1000).

Each agent's section, appended. What was added, where a person finds it, and what is not done.

## organize (branch `feat/organize`, 2026-10-16)

Search operators, a Tags page, smart notebooks, folders inside folders, and today's note.

### Search operators

**Where:** the home page's search and All notes' search. The command palette searches note names only (`notesByName`
in `lib/commands/palette.dart`), never bodies, so it takes no operators.

`tag:work` (and `#work`; `tag:work` finds `#work/clients` too), `in:"Workspace, folder or notebook"` (a workspace
takes the folders inside it; a notebook its pages; a name being typed narrows by its start), `is:pinned`,
`is:archived` (the archive is otherwise never searched), `is:todo` and `has:todo` (an open to-do), `is:done` (to-dos,
every one ticked, or a ticket in a done status), `is:ticket` (also `is:notebook`, `is:journal`, `is:canvas`),
`has:image`, `has:link` (a note link or a web address), `has:recording` (its tape or a voice memo),
`before:2026-10-01` and `after:2026-10-01`, `created:` and `updated:` with `<7d`, `>2w`, `3m` (thirty days), `1y`, a
day, a month, a year, `today`, `yesterday`, `<date` and `>date`, `"an exact phrase"`, and `-` before any of them or a
word to leave it out (`-updated:<7d` is "not changed in the last week").

- **Made or changed:** `before:`/`after:` are when a note was made (`createdAt`); `updated:` is the last change
  (`updatedAt`). `before:` is before the day starts, `after:` from the day on.
- Operators combine with AND. The plain words left over keep the ranking exactly as it was (`findNotes` on the home
  page, the strict every-word rule in All notes). A query with no operator is read as it always was. An unknown
  `x:y`, or a known key with a value it does not know (`is:blue`), is a plain word.
- Under the field: with it empty and focused, a row of the operators that scrolls across (a tap puts one in); with
  something typed, a chip for each operator understood, in plain words ("Tagged #work", "Changed in the last 7
  days"), whose cross takes it out of the field, and **Save as a smart notebook**.
- **Cost:** the parse is per keystroke and tiny; matching asks only kept readings (`NoteMarks` for tags, to-dos,
  pictures and links, read once per body like `searchText`; `NoteFacts`; the note's own fields). Over 400 invented
  notes in the test VM a letter is 1.5 ms plain and 0.5 to 1.2 ms with operators
  (`test/organize/search_match_test.dart` prints both). The first operator over a library nobody has read for
  marks costs ~28 ms of reading in that VM, so the search field's read-ahead (`lib/core/search_ahead.dart`) now
  reads the marks too, a slice after each frame, as it reads `searchText`.
- Files: `lib/core/search_query.dart` (the parser), `lib/core/search_match.dart` (the filter), `lib/core/note_marks.dart`
  (the per-note cache), `lib/home/search_hints.dart` (the row); changed `lib/core/search_hits.dart`,
  `lib/home/home_layout.dart` (`homeFound`), `lib/notes/all_notes.dart` (`browseNotes`), `lib/home/home_filters.dart`,
  `lib/home/home_screen.dart`, `lib/notes/all_notes_screen.dart`, `lib/core/search_ahead.dart`.

### Tags page

**Where:** the sidebar's **Tags** row (over the folders, with how many tags there are), the palette's **Tags**, and a
tap on any tag's chip in a note, which opens that tag's page.

- Every tag with how many notes carry it (the archive left out), tags inside tags (`#work/clients`) as a tree that
  folds (kept per device, `glyph-tags-closed`), by **Most used** or **A to Z** (`glyph-tags-sort`).
- A tag's page: its notes and those of the tags inside it, in the home page's row style, newest first, and chips for
  the tags inside it.
- **Rename** (the pencil in the bar): a sheet that says how many notes it changes (the archive's included, and the
  Trash's are renamed too), says when the new name is a tag already ("the two become one"), and then writes each
  note over the revision the library has (`NoteLibrary.update`), the note being read through its own screen
  (`NoteScreenState.writeNotebook`). It reaches `#tag` and `#tag/…` in the words outside code, maths, addresses and
  the other quiet places, and the front matter's `tags:`/`tag:` lists; a ticket's `labels:` are left alone.
- Tags are the query reader's (`lib/core/query/records.dart`) rule: the `#tag` grammar of `lib/core/tags.dart` outside
  `quietRanges`, plus the front matter lists.
- Files: `lib/core/tag_index.dart`, `lib/notes/collection_screen.dart`, the tap in `lib/editor/items/tags.dart`
  (`tagOpener` facet), `NoteDeskWorld.openTag` in `lib/root/note_desk.dart`.

### Smart notebooks

**Where:** **Save as a smart notebook** under the home and All notes searches; the sidebar's **Smart notebooks**
heading, each row with how many notes its search finds now and a More (rename, change the search, move up or down,
delete); the palette's **Show <name>**. A tap opens its page: the notes its search finds, in the search's order.

- Kept in the synced preferences under the key **`smartNotebooks`**:
  `[{"id": "s-k3f9x2", "name": "Open at work", "query": "in:work is:todo"}, …]`, in the sidebar's order. Added to
  `syncedPrefs` (`lib/sync/prefs.dart`), so they follow the account as the workspaces do. The typed `Preferences`
  has no field for it: it rides in `Preferences.more`, which keeps keys the class does not model, so the shared class
  is untouched. `lib/core/smart_notebooks.dart`, `lib/notes/smart_notebook_sheet.dart`.
- Counts in the sidebar are kept per list of notes (`NotesMemo`), so they are counted again when a note changes,
  never as the sidebar is only drawn again.

### Folders inside folders

**Found:** folders were workspaces, a flat list, each `workspaces/<name>/` on disk (`lib/core/note_folders.dart`);
the Rust library already reads subfolders and moves files into nested paths (`library_path`, `apply_note`), so
**nothing in `native/` changed**.

**What changed:**

- A personal workspace may have a **`parent`** (kept beside its name in the synced `workspaces` preference:
  `{"id": "w-…", "name": "Clients", "parent": "w-work"}`). Its folder on disk is inside its parent's:
  `workspaces/Work/Clients/<note>.md`. An organization's workspace is never inside another and never holds one. A
  parent that is gone, an organization's, or a loop reads as none.
- Choosing a workspace (the home filter, All notes' pills) shows the notes of the folders inside it too.
- Renaming or moving a folder moves the files of every folder under it; removing one keeps the folders inside it, a
  level up (their files move with them).
- **Sidebar:** folders inside folders, each folding on its own, its count its notes and those of the folders inside;
  on a wide window (600 wide and up) a note or a folder dragged onto a folder is filed or moved there (a mouse drags
  at once, a finger holds first). An organization's folder takes no drop and gives none: a team note is moved through
  the note's Workspace picker, which asks twice.
- **Making and moving:** a folder's More (the sidebar and Settings › Workspaces) has **New folder inside** and
  **Move** (at the top, or into any folder that is not it or inside it). A note's Workspace picker (More sheet) and
  the palette's "File it in …" name nested folders with their path ("Work › Clients"), and are the Move for a note
  everywhere.
- Files: `lib/core/workspaces.dart`, `lib/core/note_folders.dart`, `lib/core/preferences.dart` (`KeptWorkspace.parent`),
  `lib/core/kept_workspaces.dart`, `lib/settings/panes/settings_host.dart`, `lib/notes/tree.dart`,
  `lib/notes/note_tree.dart`, `lib/notes/workspace_sheet.dart` (rows behind `folders: true`, so the sheet the tests
  hold to the web page is unchanged), `lib/note/workspace_picker.dart`, `lib/commands/app_commands.dart`.

### Today's note

**Where:** the **+** sheet's **Today** row (after Note), the palette's **Today's note**, and on a Mac
**Command-Shift-D** (no other shortcut uses it; the editor's Shift chords are Command-Shift-Z and -U) and
File › Today's Note.

- **One note a date**, named `2026-10-16` (the name the built-in "A day" template gives, and Obsidian's Daily notes
  give theirs). Today opens the note of that name (not archived, not in the Trash), or makes it from the template
  Settings names (your own page of that name where you keep Your templates, else the built-in), files it, and opens
  it with the caret where the template leaves it. A template whose heading is no date gets `title: "2026-10-16"`.
- **Not a journal:** a journal keeps entries by the minute, as many a day as are written, each a line of its index; a
  daily note is one page per date, found again by its name, two taps never making two.
- **Settings › Workspaces › Daily notes** (a page behind Workspaces, off the section list so the list stays the web's;
  found by Settings' search for "daily"): where they go (the **Daily notes** folder, made with the first one, the
  default; any workspace; or none), what they start from, and a notebook whose index a new daily note joins. Kept in
  the synced preferences under **`dailyNotes`** (`{"folder": "w-…" | "", "notebook": "<note id>", "template": "A day"}`),
  also in `Preferences.more`. `lib/notes/daily_notes.dart`, `lib/settings/panes/daily_notes_pane.dart`. The row on
  the Workspaces page is drawn only where the app has a library (`dailyNotesLibrary`, set by the root).
- A daily note is the app's making, from a template, and is not location-tagged as a note typed from **+ › Note** is.

### Hubs touched

`lib/root/ghost_root.dart` (an `Organize` field, its dispose, `openTag` in the desk's world, `today` for the desktop
keys, the folders' workspace list), `lib/root/root_parts.dart` (the sheet over the app, `onSaveSearch`, the
collection screen's builder, the sidebar's and the docked tree's new props, the palette's, the + sheet's Today),
`lib/shell/screen.dart` and `lib/shell/app_shell.dart` (a seventh screen kind, `ScreenCollection`, a place drawn
where All notes is), `lib/commands/palette.dart` (three optional doings and a world list),
`lib/settings/settings_sections.dart` (one sub-page entry) and `lib/settings/kit/settings_icons.dart` (one glyph),
`lib/sync/prefs.dart` (two keys), `lib/notes/new_sheet.dart` (one row), `lib/shell/desktop/desktop_commands.dart`,
`lib/root/desktop_wiring.dart`, `macos/Runner/AppDelegate.swift` (one menu item). The root's own work is in
`lib/root/organize.dart`.

### Not done

- The guide is unchanged: its chapters are the Tauri app's, byte for byte (`test/guide/guidebook_test.dart`), and the
  web app has none of this.
- No search operators in the Tauri/web app, the reader page or the Claude connector.
- On a phone held upright the sidebar takes no drags (it is a card over the page); a note moves through its
  Workspace picker there.
- The workspace pills and the home filter list nested folders flat, by name (names are unique, so nothing is
  ambiguous); only the pickers say the path.
- Nothing walked on a device: tests and pictures only (`test/organize/`, pictures under
  `build/feature-shots/organize/`).

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
