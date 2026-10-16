# Features added for 2.1

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
