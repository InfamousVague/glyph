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
