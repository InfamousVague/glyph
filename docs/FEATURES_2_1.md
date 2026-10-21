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
  `workspaces/Work/Clients/<note>.md`. An organization's workspace is never inside another; since GHST-107
  (2026-10-19) it holds folders, which are the team's (the next section). A parent that is gone, one on an
  organization's own workspace, or a loop reads as none.
- Choosing a workspace (the home filter, All notes' pills) shows the notes of the folders inside it too.
- Renaming or moving a folder moves the files of every folder under it; removing one keeps the folders inside it, a
  level up (their files move with them).
- **Sidebar:** folders inside folders, each folding on its own, its count its notes and those of the folders inside;
  on a wide window (600 wide and up) a note or a folder dragged onto a folder is filed or moved there (a mouse drags
  at once, a finger holds first). An organization's folder takes a note from another folder of the same
  organization and nothing from outside it (GHST-107); a team note leaves the organization through the note's
  Workspace picker, which asks twice.
- **Making and moving:** a folder's More (the sidebar and Settings › Workspaces) has **New folder inside** and
  **Move** (at the top, or into any folder that is not it or inside it). A note's Workspace picker (More sheet) and
  the palette's "File it in …" name nested folders with their path ("Work › Clients"), and are the Move for a note
  everywhere.
- Files: `lib/core/workspaces.dart`, `lib/core/note_folders.dart`, `lib/core/preferences.dart` (`KeptWorkspace.parent`),
  `lib/core/kept_workspaces.dart`, `lib/settings/panes/settings_host.dart`, `lib/notes/tree.dart`,
  `lib/notes/note_tree.dart`, `lib/notes/workspace_sheet.dart` (rows behind `folders: true`, so the sheet the tests
  hold to the web page is unchanged), `lib/note/workspace_picker.dart`, `lib/commands/app_commands.dart`.

### Folders inside an organization's workspace (GHST-107, slice 1)

**Found:** an organization's workspace could neither hold a folder nor be one (`WorkspaceStore` cleared any
`parent` on or under one), and a note's folder already travels: a team note's row carries the note whole, `path`
included, `particulars()` counts the path, and the library writes the file at the row's path when it lands
(`apply_note`). So `orgs/Ghost.md/Clients/Acme/Plan.md` lands at that path on every member's device, and no server
changed.

**What changed:**

- An organization's workspace may be a **parent**, never a child: the folders under it, to any depth, are ordinary
  workspaces with `parent` set, random ids, kept per account in the preferences as any folder's. Their folders on
  disk are under the organization's: `orgs/Ghost.md/Clients/Acme/`.
- **In an organization** is read by walking parents (`orgOfWorkspace(list, id)`, `WorkspaceStore.orgOf(id)`); the
  id's prefix (`isOrgWorkspace`) says only whether a workspace is the organization's own. Everything that asked
  "is this note the team's" walks: the team channel's `isTeamNote`, the account sync's `teamNote`, the version
  history's default, live editing, comment colours, the export, the picker's notice and its asked-twice move (a
  move within the organization is not asked), the pills' and the sidebar's organization mark, the home page's
  "who is here". A folder's pill or row filters; only the organization's own opens the organization.
- **Nothing moves into or out of an organization:** `canMove` keeps a folder in the organization it is in (or out
  of every one), the Move sheet offers no "At the top" for one, and the sidebar's drop rule takes a note from
  another folder of the same organization only. Leaving the organization drops its folders with its workspace.
- **Sync** (`lib/team/folders.dart`): a note from the team is filed by its path: the folders between
  `orgs/<the organization>/` and the file name are found by name under the organization's workspace, then under
  each in turn, or made, and the note is filed in the deepest. A rename or a move of a folder on one device moves
  its files, which puts their rows again, and every other device files them the same way. A folder a pass
  emptied, named by no team note's path, is dropped at the pass's end; a folder empty before the pass (one just
  made, one landed through the preferences, one emptied on purpose) is left alone.
- Files: `lib/core/workspaces.dart`, `lib/core/note_folders.dart` (`folderFor`, `orgFolderNames`),
  `lib/team/folders.dart`, `lib/team/sync.dart`, `lib/sync/engine.dart` (`TeamPass.folders`), the call sites
  above. Tests: `test/organize/org_folders_test.dart`, `test/team_sync/folders_test.dart`.

### Folders above the lists, and the icon view (GHST-107, slices 2 and 3)

Matt, 2026-10-19: "sort notes into folders and display them above the flat lists and support showing a icon file
browser based view in addition to the list views". The folders are the workspaces' own (nested, personal or an
organization's since slice 1); these are the two ways of seeing them.

- **The folder strip** (`lib/notes/folder_strip.dart`, `FolderStrip` and `FolderCrumbs`): with a workspace chosen,
  the folders directly inside it as chips that scroll sideways, under a "Folders" heading with the count: the folder
  glyph, the name, how many notes are in it and under it (`WorkspaceStore.notesUnder`), in its hue where it wears
  one; **New folder** at the end (the workspace sheet with that parent, `folders: true`). Above it, where the
  workspace is: "Work › Clients", each part but the last a way up. Nothing at all for a workspace at the top with no
  folders, so a list that never uses them looks as it did. On home under the filters, on All notes under the order
  words, on an organization's dashboard above its Notes (`onAllNotes` carries the folder's id). A tap chooses the
  folder as its pill would. Not while a search is typed (the cards are what was found), and not in simple mode.
- **The icon view** (`lib/notes/icon_browser.dart`, `IconBrowser`): a **segmented toggle** (`BrowseViewToggle`, the
  kit's `GlacierSegmentedControl` at its small size; Matt, 2026-10-19: "use a segmented toggle with iconography for
  the different modes") with a list glyph for Cards and a grid glyph for Icons, each named for a screen reader, on
  All notes' line at the counts' end beside Archived and on the dashboard's Notes heading; one choice for the device
  in `Stored` under `glyph-browse-view`. The toggle makes All notes' line of words 18.15px taller than the web page
  measured it (the words on it sit 9.15 lower, centred), and test/allnotes holds the new numbers. A grid of large tiles laid out like the
  cards' grid: the folders first, then the notes in the page's order; a folder's glyph or a note's kind on a faint
  square, the name on two lines, the count or when it was touched; a tap enters a folder or opens a note, a right-
  click is the note's menu, tiles take a focus ring. At **All**, the root: the workspaces at the top as the first
  tiles (an organization's with its mark), then every note, so All still means every note; the crumbs show nothing.
  In the icon view the strip is not drawn: the folders are the first tiles.
- Files: the two above, `lib/home/home_screen.dart`, `lib/notes/all_notes_screen.dart`,
  `lib/orgs/ui/organization_screen.dart`, `lib/root/ghost_root.dart` and `root_parts.dart` (the sheet record carries
  a parent; `_newFolder`). Tests: `test/organize/folders_test.dart`; pictures by `folders_shots_test.dart` into
  `build/feature-shots/organize/folders-*.png` (24: home, All notes cards and icons, icons at All, the dashboard in
  both views; phone and wide, light and dark). The All notes and dashboard goldens were taken again for the words.
- **Not done:** a tile's long press
  on a phone opens no menu; home keeps its four layouts (the icon view is a browsing page's).

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

Each agent's section, appended. What was added, where a person finds it, and what is not done.

## reminders (branch `feat/reminders`, 2026-10-16)

Reminders on due dates, three home-screen widgets, the icon's shortcuts and a Quick Settings tile. All of it is
Android's: an iPhone and a Mac show none of it (the last part says what an iPhone would take).

### Where a person finds it

- **A reminder on a line**: hold a to-do (or any list item) and choose **Remind me** on its menu, after Assign: In an
  hour, This evening (until five), Tomorrow at Settings' time, Pick a time (the phone's calendar, then its clock), and
  Remove where the line has one. The line shows it as a chip, an alarm clock and "Tomorrow 9:00", in the third ink;
  a tap on the chip opens the same page.
- **A due date reminds by itself**: a to-do (`- [ ]`) or a ticket with a due date and no time is reminded at nine on
  the day, or the time Settings says, and the day before where asked. A plain list item with a date and no box is a
  date, not a task, and reminds only with its own `⏰`.
- **The notification** ("Reminders" channel, high importance): the item's words, then the note's title and why ("Work
  · Due today"). A tap opens the note at that line. **Done** ticks it; **Snooze 1 hour** rings it again an hour on. Done
  is offered only for a to-do with a box and for a ticket (whose status goes to its workflow's done).
- **Settings › Notifications › Reminders**, first on the page: Remind me (on by default), Time (9:00, the phone's own
  clock to change it), The day before. Under them, what Android keeps from reminders and the way to allow it: Allow
  notifications, or Allow exact times (Android's Alarms and reminders page). Findable in Settings' search.
- **Home-screen widgets**: replaced on 2026-10-20 by Voice note, To-dos, Calendar and Recent notes in the app's own
  look (docs/WIDGETS_ANDROID.md), the three below kept as those for widgets already placed. Before: **Quick note** (the pen: a new note with the
  keyboard up; the microphone: a new note being recorded, the microphone opened by that tap and never before),
  **Today** (the open to-dos due today and overdue from every note, each with a box to tick and the row a tap away
  from its note at that line; "Overdue" in a muted red), **Pinned notes** (a tap opens the note). The app's dark look on
  every wallpaper; rows as many as the widget's height holds, and "2 more" under them.
- **The icon's shortcuts** (long-press the app icon): New note, Voice note, Today, Search, then the three notes opened
  last. A launcher shows what it has room for: the Pixel launcher shows four, two of the app's own and two recent notes
  (Launcher3 keeps two places for recent ones), so Today and Search are there to pin but not in its popup.
- **Quick Settings tile**: New note (edit the shade's tiles to add it). Over a locked phone it asks to unlock first.

### How it is written (plain Markdown, docs/MARKDOWN.md's rule)

- A reminder is `⏰ 2026-10-03 09:00` in the line, before the run of Obsidian Tasks' fields:
  `- [ ] Call the plumber ⏰ 2026-10-03 09:00 📅 2026-10-03`. The sign and form are the Obsidian Reminder plugin's,
  which reads them beside Tasks; Tasks itself reads the 📅 after it. Read in the one field grammar
  (lib/core/task_fields.dart: a `tasks` field with the key `reminder`), so a board card's words and a title sent to
  Notion or GitHub leave it out, as they leave out a date. The time is the phone's wall clock wherever it is.
- A ticket keeps its own time in its front matter: `remind: 2026-10-03 09:00` (read; there is no row for it in the
  ticket's panel yet).
- Nothing is written for a due date's own reminder: it is worked out.
- The settings are this device's (`glyph-reminders` in its memory, never synced): only a phone reminds.

### How it works

- **The plan** (lib/reminders/reminder_plan.dart) is pure: every note's dated items, read once per note object
  (lib/reminders/dated_items.dart; the library keeps a note the same object while it is the same), less the Trash, the
  archive, templates and canvases, ticked and cancelled items; only what is still to come, the soonest 64. A pass runs
  1.5 s after the notes, the Trash or the settings last changed (lib/root/phone_extras.dart), never per keystroke, and
  hands the phone the plan only when it is another than the last. Notes that arrive by a sync are library changes like
  any other and are planned here too. At each start and each return to the front, everything is handed over again
  (an app stopped by force has lost its alarms).
- **The alarms** (android/…/ghost_md/reminders/Reminders.kt) are kept in SharedPreferences as the day and time written,
  turned into a moment each time they are armed. **Exact where Android allows it**: `setExactAndAllowWhileIdle` before
  Android 12, and from 12 once the person allows Alarms and reminders (SCHEDULE_EXACT_ALARM; a new install on Android
  14+ starts without it). **Inexact otherwise**: `setAndAllowWhileIdle`, which still rings with the phone asleep and may
  be some minutes late. Not USE_EXACT_ALARM, which Google Play keeps for alarm clocks and calendars.
- **Restarts**: ReminderRestart arms everything again on BOOT_COMPLETED, MY_PACKAGE_REPLACED, TIME_SET,
  TIMEZONE_CHANGED and the exact-alarm permission changing, and after a restart rings once what was due in the last
  twelve hours. Alarms only: no service is started from any of them.
- **Done** is written through the app's library, never by Kotlin writing the file (GhostBackground.kt): while the app
  runs, it is handed to it (`tick` on `ghost_md/reminders`) and written into the open note's editor where that note is
  on screen (saved like typing, no conflict with the note's own save), else through `NoteLibrary.update`; with the app
  closed, a WorkManager job starts an engine of its own with no window on `lib/reminders/background_tick.dart`, which
  opens the core (deaf to its events, so a starting app keeps them), ticks the line (lib/reminders/tick_item.dart, the
  same edit as a tap on the box, boards settled) and lets the engine go. The ticked item leaves the Today widget at
  once, and its other reminders are let go before the app has read the tick.
- **The widgets** (android/…/ghost_md/home/): RemoteViews, no Compose, no collection service. They draw what the app
  last handed over on `ghost_md/home_screen` (lib/home_screen/home_screen_data.dart: Today's to-dos due up to a week
  ahead, the pinned notes, the recent notes; each only when changed), so they draw with the app closed; Today turns its
  own day at midnight by an alarm within ten minutes of it, not waking the phone. The box is a real CheckBox from
  Android 12 (RemoteViews' compound buttons), a ring to press before.
- **The ways in** are `ghostmd://` links to the one activity (lib/home_screen/phone_entries.dart): `new`, `voice`,
  `today`, `search`, and `note/<id>?line=12&find=…`. Covering screens (Settings, a sheet) are put away first, and a new
  note's keyboard is asked for again once the app is in front.

### New permissions, receivers and services

- Permissions: `SCHEDULE_EXACT_ALARM` (user-granted, Android 12+), `RECEIVE_BOOT_COMPLETED`. POST_NOTIFICATIONS was there.
- Receivers: `.reminders.ReminderAlarms` (not exported), `.reminders.ReminderRestart` (not exported; BOOT_COMPLETED,
  MY_PACKAGE_REPLACED, TIME_SET, TIMEZONE_CHANGED, SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED), `.home.WidgetTicks`
  (not exported), and the three providers `.home.QuickNoteWidget`, `.home.TodayWidget`, `.home.PinnedWidget`
  (exported, as a widget's provider must be).
- Service: `.home.NewNoteTile` (BIND_QUICK_SETTINGS_TILE). Worker: `BackgroundTick` (WorkManager, no manifest entry).
- The icon's shortcuts: `res/xml/ghost_app_shortcuts.xml` and `ghost_cutover_app_shortcuts.xml` (new, a build without
  the assistant), and the assistant's two files gained the same rows after Record note (no Voice note there: Record
  note is it). android/app/build.gradle.kts picks the file by build; a build made to be measured has none.

### Proven on the emulator (ghostflutter2, Android 16, at the Fold's cover size 1248x1972)

A reminder set two minutes ahead with Pick a time rang on its minute (exact, `exactAllowReason=permission`) with the
app in the background and again with its process killed; Done ticked the line both ways (the second through the
engine of its own: the file read back `- [x] Pay the rent ⏰ 2026-10-16 13:28`); Snooze 1 hour armed it again an hour
on; a reboot armed both alarms again; the clock moved to the next morning rang the due date's nine o'clock reminder
("Work · Due today") and turned the Today widget's day. The three widgets rendered, ticked a to-do into its note, and
opened the app at the line; the icon's popup showed New note, Voice note and two recent notes and each opened; Search
and Today opened the palette and today's entry; the tile opened a new note. Inexact alarms were not timed.

### Not done, and for the coordinator

- **Today's note**: until `feat/organize` is merged, Today makes a new entry in the journal written in last (a new
  note where there is none). Once merged, `_PhoneDoor.today()` in lib/root/ghost_root.dart should be
  `_withShell((_) { raiseKeyboardSoon(); root._organize.today(); });`.
- **Scan document** is not on the icon: `feat/files`'s `scanToNewNote()` (lib/files/plus_files.dart) is not on main.
  Once merged: a fifth row `ghostmd://scan` in the four shortcut files, a `ScanEntry` in phone_entries.dart, and
  `_PhoneDoor.scan()` calling `scanToNewNote()` then `root._library.createNote(words)` and opening it.
- **Voice note** on the icon and on Quick note is offered in every build, where Record note (the assistant's capture)
  stays behind the developer flag (Matt, 2026-10-11). It opens the dock's own Speak, a voice memo, not the assistant;
  Matt may want it behind the flag too.
- A Kotlin side cannot tell a ticked or edited note from another device while the app is closed: an alarm armed before
  rings with the words it had until the app next runs a pass.
- No row for a ticket's `remind:` in its panel; no recurrence (`🔁`) acted on; the 65th reminder onward waits for the
  next pass.
- Not measured on a real Fold (cover-screen launcher, One UI's shortcut popup, Samsung's battery rules on alarms).

### iPhone (hidden; what it would take)

- **Reminders**: UNUserNotificationCenter with `UNCalendarNotificationTrigger` needs no entitlement, only the
  notification prompt, which the store build has never shown. A Swift half of `ghost_md/reminders` (set, state, pick a
  time), a category with Done and Snooze; Done would need a background launch of a Flutter engine like Android's (an
  `UNNotificationAction` without `.foreground`), and iOS gives that a few seconds at most. Hidden until the store
  build's behaviour may change.
- **App Intents / Shortcuts** ("New note", "Append to note"): an `AppIntent` in the app target can open the app at a
  `ghostmd://` link with no new target; "Append to note" without opening the app needs an App Intents extension
  target (a second bundle, its own signing and provisioning profile, an App Group to reach the library) and a store
  review.
- **WidgetKit** (Today, Pinned, Quick note): a Widget Extension target (SwiftUI), an App Group container the app writes
  the same JSON into (`today`, `pinned`), interactive buttons from iOS 17 through App Intents for the tick, and the
  same signing and review. None of it is added.

## files: attachments, the PDF viewer, scanning and the words read in pictures (branch `feat/files`, 2026-10-16)

### Where a person finds it

- **A file** and **Scan a document** on the first page of the + beside an empty line (and the `/` palette), after A video.
  A file opens Android's own document picker (no permission) or the Mac's open panel. Scan a document opens Google's
  ML Kit document scanner (Android with Google Play services only; its own screen, so the app never holds the camera).
- **The card** under the file's line: the file's mark (a PDF's first page, drawn), its name, "PDF · 2.4 MB · 12 pages",
  or "Not on this device yet." / "It stays on the device it was added on." A tap opens a PDF in the viewer and anything
  else in another app ("Open with"); the mark at its end hands any file over.
- **The PDF viewer**: pages swiped across, drawn on asking by Android's own PdfRenderer; pinch zoom to 5x (redrawn
  sharper once the pinch settles), double tap back; Page n of N (tap: Go to page); Find (the device's places on
  Android 15+, else the pages whose words hold the query, from the PDF's own words or the words read in it); Copy the
  words on this page; Share; Open with. The back gesture closes it.
- **Search**: a note is found by the words read in its pictures, scans and PDFs, and its row's line says where:
  "Rent is due monthly on the first in Lease 2026.pdf, page 2", "TOTAL 42.10 in a picture".
- **Copy the words in it**, under a picture whose line holds the caret, where words were read in it.
- **Settings › Library folder › Files and scans**: Read words in pictures (on by default, kept on this device), Read
  what is already in notes (now, with "Reading, 12 of 40" / "Waiting while Battery saver is on."), and Files in notes
  ("3 files, 12 MB"), with the 25 MB sync limit said under it.

### How it is kept

- **The line** (lib/core/attachment_refs.dart): `[Lease 2026.pdf](file/<uuid>.<ext> "2.4 MB")`, alone on its line: the
  file's own name as the words, its kept name under `file/`, its size as the link's title. Plain Markdown; any app shows
  a link.
- **The file** (lib/files/attachment_store.dart): `<data>/images/files/<uuid>.<ext>`, kept by Dart, whole or not at
  all (a `.part` and a rename). Inside the pictures' folder so the core's Export (`images/files/…`), Backup
  (`Attachments/Pictures/files/…`) and Erase everything carry it with NO change to the Rust core; the core's picture
  commands only ever name files directly under `images/`. At most 512 MB a file.
- **The words read** (lib/files/read_text.dart): a sidecar beside the thing, `<name>.ocr.txt` (`images/<picture>.ocr.txt`,
  `images/files/<file>.ocr.txt`), UTF-8, a form feed between a PDF's pages as `pdftotext` writes them; empty means read
  and nothing found. Read in at launch on a worker isolate and held in memory for the search.
- **The one door** for anything that brings a file in: `storeAttachment(AttachmentSource, name:)` in
  lib/files/attachment_store.dart (sources `AttachmentBytes`, `AttachmentPath(path, move:)`, `AttachmentCopy(copyTo)`),
  answering a `KeptAttachment` whose `.ref` is `file/<name>` and `.markdown` the note's line. It reads the words in it
  soon after. The share-import branch's `storeSharedFile` maps onto it one to one.
- **Deleting**: taking the line out keeps the file (Undo, older versions). A note deleted for good removes the files
  only it linked, with their words, after the core's `delete_note` (the pictures' own rule), from
  `CoreLibrary.destroy` and sync's `LibraryNotes.remove` through `tellNoteGone`.

### Sync (what changed)

- `FileKind` gained `attachment` (`a-<ext>-<stem>`) and `text` (`t-i-<ext>-<stem>` for a picture's words,
  `t-a-<ext>-<stem>` for a file's), on the same `recordings` route, sealed with `file:<id>` like every other file.
- A note's payload names its files (`files`) and the things whose words went (`texts`); the other device fetches what it
  lacks. The settling at the end of a pass makes files whole on both sides as it does pictures (with the same
  ask-again wait), and sends words held here that the account lacks.
- A file over 25 MB (the pictures' own limit, the core's `kept/images.rs` `MAX_BYTES`) is never read or sent, is left
  out of the payload, and its line's size keeps the other devices from asking. **The service is unchanged**: one sealed
  file may be 64 MB there (`RECORDING_LIMIT`, server/src/sync.rs) and any base64url id of up to 64 characters.
- Words read after a note went owe the note again (`glyph-words-owed`, `KeptFiles.owed()`), so the others hear of
  them by the note's next revision, as a versions file kept by hand does.
- `LocalFiles` gained `lengthOf` (a file's size without reading it) and `keepsMedia` (an iPhone, which keeps no files
  yet, fetches and sends none).
- Team notes carry `files` and `texts` in their rows the same way.

### The phone's half

- android/…/ghost_md/Documents.kt over `ghost_md/documents`: `pick`, `canScan`, `scan`, `read`, `readerReady`,
  `pdfOpen`/`pdfPage`/`pdfText`/`pdfFind`/`pdfClose`, `openWith`, `share`, `saving`. PdfRenderer is the system's
  (PDFium inside Android, nothing added to the APK); its words and search need Android 15. Reading words runs on a
  background-priority thread. Files are handed over as copies under their own names in `cacheDir/open/` through a
  FileProvider of their own (`AttachmentFiles`, authority `<id>.attachments`, res/xml/ghost_attachment_paths.xml).
- Gradle: `com.google.android.gms:play-services-mlkit-document-scanner:16.0.0` and
  `com.google.android.gms:play-services-mlkit-text-recognition:19.0.1`. The text recognition is the Play-services
  one, not the bundled `com.google.mlkit:text-recognition`: measured in this app's build, the bundled one is 11.1 MB of
  native library and 1.3 MB of models on arm64 alone (and 18.4 MB more for armeabi-v7a and x86_64, which ship unless
  the ABIs are filtered). The model is fetched once by Play services (asked for with ModuleInstallClient the first
  time, and with the manifest's `com.google.mlkit.vision.DEPENDENCIES = ocr` on a Play install), then reads offline.
- **What it adds to the APK**: about 0.9 MB for the Android pieces, measured on two arm64 debug builds of this branch
  with and without them (dex +0.78 MB in the APK, 2.3 MB unpacked; resources +0.13 MB; no native library), plus this
  branch's Dart. The PDF renderer is Android's own and adds nothing.
- No new permission. The scanner and the reader need Google Play services.
- The Mac (macos/Runner/GhostChannels.swift, `MacDocuments`): `pick` (open panel), `openWith` (the workspace),
  `share` (the share menu), the PDF calls over PDFKit (the same viewer), `read` over Vision's text recognition (a
  page with no words of its own drawn and read), and `saving` as Low Power Mode. No scanner on a Mac.

### Not done

- iPhone: nothing, hidden (no kit is made there; a file's line is the link it always was, and sync neither fetches
  nor sends files). VisionKit's `VNDocumentCameraViewController` would fit under the camera string the store build
  already has (`NSCameraUsageDescription`, "…when you take a photo to add to a note"), but the iPhone keeps no files
  yet: it needs `FilesKit.start` on iOS, a Swift half of `ghost_md/documents` (the scanner, `openWith` through
  UIDocumentInteractionController, PDFKit for the viewer, Vision for the words), and a store review.
- Words are not read on an iPhone (no files there yet).
- (Wired after the merge with main.) The icon's **Scan document** shortcut (`ghostmd://scan`, in the four shortcut files,
  `ScanEntry` in lib/home_screen/phone_entries.dart, `_PhoneDoor.scan` in lib/root/ghost_root.dart) calls
  `scanToNewNote()` (lib/files/plus_files.dart) and opens the new note. The share sheet's and the importers'
  `storeSharedFile` (lib/core/shared_files.dart, `sharedFileDoor`) and the mail's other files
  (lib/mail/mail_note.dart `keepMailFile`, `mailFileStore`) now keep their files in the attachments' store; files the
  share sheet kept under `<data>/attachments/` before are moved in at the next start (`FilesKit.takeInSharedFiles`).
- A shared page (a share's reader) carries no files: a file's card there says it is not on this device.
- The PDF viewer shows one page at a time (swiped), not a continuous scroll; text selection in a PDF is not offered.

## simple-mode: simple or advanced, for a new person (GHST-103, branch `feat/simple-mode`, 2026-10-18)

Matt, 2026-10-17: "right now the app can be quite intense and cumbersome to new users during onboarding allow
selecting between simple and advanced mode where simple mode has a much more approachable UI with fancy features
hidden behind more and work on making formatting and stuff easier to understand". His decisions (2026-10-18): new
installs choose on a walkthrough page, installs from before see a one-time card on home; Simple gets a small Format
bar in the editor (a deliberate exception to STAGE4's "no toolbar"); a simple install starts with the sample note
alone; the mode syncs across devices.

### The choice

**Where:** `lib/core/preferences.dart` (`experience`: `simple` | `advanced`, `experienceChosen`, `simple`,
`choosing(mode)`; `experienceIds`); `lib/sync/prefs.dart` (both keys travel); `lib/guide/pages/mode.dart` and
`lib/guide/pages.dart` (the walkthrough's "How much of it?" page after the theme, Simple lit before anything is
tapped; `walkthroughPagesFor` drops the model page for Simple as it does for an iPhone); `lib/notes/notices.dart`
`ExperienceCard` and `lib/root/root_parts.dart` `_asksExperience` (home's one-time card: the guide was seen, nothing
chosen, here or on another device); `lib/settings/panes/experience_pane.dart` and `settings_sections.dart`
(Settings › Simple or advanced, its own card above Account, two choice cards and "Nothing is lost: switch back any
time."). Choosing Simple also sets `noteView: 'formatted'`: the marks are what a new person finds hard to read, and
the note's view switch brings them back.

- Unchosen reads as advanced, so every install from before the choice is the whole app, as it was; a stored mode this
  build does not know reads as advanced too.
- Starters (`lib/core/sample_library.dart` `starterNotes(now, examples:)`, `starterExamples`; `ghost_root.dart`
  `_settleStarterExamples`, flag `glyph-starter-examples`): a fresh library gets the sample note; the three tickets,
  their notebook, the board and the journal arrive once when Advanced is chosen, and only into a library that still
  holds nothing but the sample. An install from before had them all and is marked as such at its next start.

### What Simple shows

**Where:** `lib/root/root_parts.dart` is the one place that reads `preferences.value.simple` for the shell and hands
each surface what to show (a null callback leaves a control out, the files' own convention); the parts' seams include
it, so switching rebuilds them on the next frame. Settings reads `SettingsFacts.simple`; the band, the More sheet,
the cheat sheet and the template cards read the store themselves when not told.

- **Docks** (`lib/home/home_screen.dart`, `_notesDock`; docs/DOCK.md "Simple mode"): Search, Write a note, Speak
  (where recording exists), Settings. No Claude, no Talk to Claude.
- **Top bar** (`lib/shell/app_shell.dart` `AppShell.simple`, `lib/notes/note_tabs.dart`): Home, sidebar, Back, the
  screen's tools, Settings. No People, Bell, Forward or side panel. **Tabs** (`tabs/tab_parts.dart`): no group
  actions; a group made in Advanced keeps Rename, Ungroup and Close group.
- **Sidebar** (`lib/notes/note_tree.dart`, `notes_drawer.dart`): New note, Search and commands, Open/Fold every
  folder (with folders), Close; no New workspace, names-only, Browse files, Tags row, Smart notebooks or Graph. Folders
  the person already has, Archive and Trash stay.
- **The + sheet** (`lib/notes/new_sheet.dart`): Note, then "More…" which opens in place to Today, Entry, Canvas,
  Notebook, Meeting, From a shared link.
- **Palette** (`lib/commands/palette.dart` `PaletteWorld.simple`): keeps New note, Speak, Home, All notes, Today's
  note, tabs, Back, Open {note}, Theme, Settings, Cheat sheet, Academy, the walkthrough and the note's own basics;
  drops notebooks/journals/entries, the graph, links, Ask Claude, Tags, smart notebooks, workspaces, tab groups,
  Notifications, Organizations.
- **Home filters and All notes** (`lib/home/home_filters.dart`, `home_screen.dart`, `all_notes_screen.dart`): the
  Show radios only; no workspace radios, operator chips, Save as a smart notebook, organization cards, today's events
  or workspace pills. The home page's Academy card (`AcademyCard`, `lib/academy/banner.dart` `academyBannerDue`,
  stamped under `glyph-academy-banner-since`, seven days) invites the Academy for the first week.
- **Settings** (`settings_sections.dart` `simpleSections`): Simple or advanced, Account, Notifications, Appearance,
  About (with the cheat sheet), plus Developer and Test results when developer mode is on. Organizations,
  Workspaces, Daily notes, Library folder, Backup, Export, Import, Recording, AI, Plugins and every plugin's page,
  Specification and Examples wait behind Advanced (`_advanced` on `where`), and search finds nothing of them.
  Appearance (`appearance_pane.dart`) is Page and Text size with "More looks are in Advanced." linking to the choice.
- **The note's +** (`lib/editor/plus/add_rows.dart`, `add_list.dart`): A picture, A to-do, A heading, A bulleted
  list, A numbered list, A quote, A table, A link (new, `[text](url)` with "text" selected), A divider, each with a
  plain hint under it, then More with everything else in today's order; the slash list is basics first.
- **The More sheet** (`lib/note/note_settings.dart` `NoteSettings.simple`): Speak; Reading it (Look, Find and
  replace); Where it sits (Pin, Archive); "More…" which opens in place to the name, bookmarks, Make a board, links,
  comments, the AI, sharing and filing; Help; Move to Trash.
- **A blank note** (`lib/notes/template_cards.dart`): the placeholder and the name chips; no template cards.

### Formatting, easier to understand

**Where:** `lib/note/format_bar.dart` (`FormatBar`: Bold, Italic, Heading, List, To-do, Link, sharing the Style
page's `toggleMark`/`toggleBlock`/`insertLink` through `formatBarTools()` in `lib/editor/band/style_items.dart`);
`lib/note/note_screen.dart` (mounted: on Android a 44pt strip on the keyboard's top, the page a column above it; on
an iPhone the six at the start of the Done bar, `lib/app/iphone_page.dart` `KeyboardBarOffers`; on a wide window
with the keyboard down a glass pill in the dock's hand, beside the dock, with hover tips); `lib/editor/band/
context_band.dart` (`ContextBand.simple`: Style first in the press-and-hold row, before Cut and Copy);
`style_items.dart` and `menu_band.dart` (a hint under every Style item in Simple, "Strong words", "A slant", "A
title for a section", "Bullets", "Steps in order", "A box to tick"…; in Advanced the same words go to screen readers
and desktop hover tips, since `band_reference_test.dart` holds the page to the web's measured geometry; the
decorative plugin marks sit behind a More item in Simple); `lib/settings/panes/cheat_sheet.dart` ("The basics"
first in both modes, a dozen marks with a plain line each from `basicsPlain`; in Simple the rest behind an
"Everything else" disclosure the search looks past). docs/STAGE4.md "Simple mode's Format bar (2026-10-18)".

### Tests

`test/core/preferences_test.dart`, `test/core/sample_library_test.dart`, `test/guide/pages_test.dart` (and the
guide's goldens taken again for the fifth dot; `measure_test.dart` holds the web's four dots where they still agree),
`test/settings/experience_pane_test.dart`, `test/root/simple_test.dart` (switching live, both ways),
`test/shell/simple_bar_test.dart`, `test/sidebar/simple_tree_test.dart`, `test/allnotes/new_sheet_simple_test.dart`,
`test/home/simple_home_test.dart`, `test/commands/palette_simple_test.dart`, `test/editor/band/format_bar_test.dart`,
`test/note/note_format_bar_test.dart`, `test/editor/band/context_band_test.dart`, `test/editor/plus/*`,
`test/settings/panes/pages_test.dart`, `test/allnotes/template_cards_test.dart`, `test/academy/banner_test.dart`.

### Not done

- The Settings' deep links into a gated section while Simple (home's "Get a model" → `ai`) open nothing; the card
  that offers them is not shown in Simple, so nothing reaches it today.
- Dragging a tab onto an existing group's tabs still joins it in Simple (no new groups can be made).
- The desktop Format pill does not shrink with the dock on scroll.
- The note's, an organization's and Settings' own docks keep Claude in Simple (`_pageDock`); home's and All notes'
  do not.
- The Academy's "I know Markdown already" switch and the mode are not tied together.

## simple-shell: simple mode as a shell of its own (GHST-105, branch `feat/simple-plain`, 2026-10-18)

Matt, 2026-10-18: "The simple mode in the app is not quite right, it still is a bit complex with the tabs and such,
spend a significant amount of time looking into simple apps like todoist and others to build out a clean simple
UI". GHST-103 trimmed the advanced shell; this replaces it in simple mode with a shell of its own, built from what
Apple Notes, Simplenote, Google Keep, Bear, Todoist, Things 3, Microsoft To Do, Apple Reminders and TickTick share
on a phone (the ticket holds the research): one navigation stack with Back and no document tabs; a flat list or a
few views as the first screen; search at the top of the list; one create button at the bottom right; Settings a
quiet gear; rows of title, preview line and date; swipe right to pin, left to delete; a note with Back, ⋯ and Done
and a short bar above the keyboard. His decisions: Notes / To-dos tabs with a big + and one mic above them; plain
rows grouped Pinned then by day; ‹ Notes, ⋯, Done on a note with the title in the page; list left and note right on
a wide window. Advanced is untouched.

### The plain shell

**Where:** `lib/shell/app_shell.dart` (`_plain`, `_frame`; `plain = simple && screen.isPlace`): no control row, no
tab row (the `'tabs'` stamp is null, so `app-safe-top` is the inset alone), the banner under the inset, no drawer,
no aside, no docked sidebar; the subtree is not under `TopBarToolsScope`, so a note draws its own header. Narrow:
the place alone, its `OnBack` the phone's gesture. Wide (`splitFits`): a `Row` under `app-split` with the home
builder in `simpleListColumn` (lib/shell/wide_screen.dart; semantics "Your notes", never torn down) and the place on
the right, or `emptyPaneBuilder` / `SimpleEmptyPane` (lib/simple/simple_pane.dart) on the list screen. Tabs:
`openNote` swaps the shown note's tab (`replaceNext`) and `_sync()` calls `OpenTabsController.trimTo(shown)`
(lib/shell/open_tabs.dart), so `prefs.openNotes` is `[id]` or `[]` in simple. Whole-window screens (capture,
meeting, Academy) are as they were.

### The home page

**Where:** `lib/simple/simple_home.dart` (`SimpleHome`, `SimpleRow`, `SimpleGroup`, `simpleGroups`,
`simpleSwipes`), `lib/simple/simple_bar.dart` (`SimpleTab { notes, todos }`, `SimpleBar`, `SimpleActions`); the root
builds it in `_simpleHome` (lib/root/root_parts.dart) in place of `HomeScreen`, keeping the tab on the device
(`_simpleTab`, not synced).

- Header: "Notes" or "To-dos" large, a gear on the right; a search field under it that filters as you type (no
  operator chips, no Filters); the root's notices (update, the simple-or-advanced card, the Academy card) above the
  rows.
- Rows: title, one preview line, the date on the right, a hairline between; a pin mark on pinned rows; grouped
  Pinned, Today, Yesterday, Earlier this week, This month, Earlier (the timeline's words). Tap opens; swipe right
  pins, swipe left deletes; the row's menu holds the rest. Notebooks, journals and canvases that exist are rows by
  their names.
- Bottom: the bar with Notes and To-dos (icon and word, the current one in `app-ink`), and above its end a filled
  round + (`simple-new`: a note straight away; held, the + sheet) and a plain round mic (`simple-speak`: Talk to
  Claude where Claude can hear, the recorder otherwise; none where neither can). On a wide window the bar becomes a
  two-word switch under the header and the two buttons sit at the column's foot (`pane: true`).
- Empty: the ghost with "Write it, or tap the mic and say it." / "Tap + to write it."

### To-dos

**Where:** `lib/simple/simple_todos.dart` (`SimpleTodos`), `lib/simple/todos_groups.dart` (`todoGroups`, `Todo`,
`TodoGroup`, `dueWords`, `priorityWords`). Every open to-do across the notes out of the trash (`openTasks`,
lib/home/dashboard.dart, which skips fences, the archive and the Guide), its due day and priority read with
`fieldsOf` (lib/core/task_fields.dart), grouped Overdue, Today, Later, Someday (dated groups by day then priority;
Someday most recently touched first), with counts in the eyebrows; a collapsed Done shelf for what was ticked in
this sitting. A row: a 44 px tick target (an empty ring, red when overdue), the words stripped of their fields, the
note's name and day under them. The tick calls the root, which writes `tickedBody` through `_writeNote` as the
query lists do; the words open the note at the line (`openNote(id, at: 'line:N')`). Re-read only when the notes
list, the trash or the day changes. Laid out whole inside the page that scrolls.

### The note

**Where:** `lib/note/note_screen.dart` (`back`, `backLabel`), `lib/note/note_tools.dart` (`NoteSimpleHeader`,
`NoteHeaderWord`, `viewSwitchRow`), `lib/note/format_bar.dart` (the tail), `lib/note/note_settings.dart`
(`NoteViewSwitch`), `lib/root/note_desk.dart` (`onAddImage`), `lib/note/note_builder.dart`. In simple with no bar
the note's header is ‹ Notes (or ‹ To-dos, the list it came from; none beside the list on a wide window), ⋯ for the
sheet, and Done while the keyboard is up (lowers it, saved first); the title stays the page's first heading. The
sheet's "Reading it" gains the view switch (Show the marks / Show the formatted note); Pin and Archive are there
already; the dock draws nothing. The Format bar: Bold, Italic, Heading, List, To-do, Link, a divider, then
picture (the band's Add image), + (the +'s list for the caret's line) and the mic (Talk into this note, or the
root's Talk ring where Claude can hear, one mic), with Done after them on the iPhone's row; the row scrolls
sideways with the six first. "Wide" for the pill is the page's own width, so a Fold opened out beside the list
keeps the strip.

### Tests

`test/simple/simple_home_test.dart`, `simple_todos_test.dart`; `test/shell/simple_shell_test.dart` (replaces
`simple_bar_test.dart`); `test/root/simple_test.dart` (the simple page, opening a note in the one tab, the To-dos
tab and a tick written into its note, the simple-or-advanced card), `simple_wide_test.dart` (folded shut and
opened out), `parts_test.dart`; `test/note/note_simple_header_test.dart`, `note_format_bar_test.dart`,
`note_screen_test.dart` (the rig's `back` follows the mode).

### Not done

- The To-dos tab is not kept across launches (the app opens on Notes).
- The Done shelf is per sitting: no tick writes a ✅ date, so "ticked today" cannot be read back from the notes.
- Simple mode on a Mac has no title-bar drag strip (it lived in the bar); the header clears the window buttons.
- The notifications card can still be opened programmatically in simple; nothing offers it.
- Quick-add of a to-do from the To-dos tab (a line typed straight into the list) is not built; the + makes a note.
