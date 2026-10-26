# Workspaces, folders and search

As your notes grow, you'll want to keep some apart and find others fast. Workspaces and folders sort your notes. Search, smart notebooks and tags find them again, wherever they're filed.

Workspaces and folders are part of Advanced mode. In Simple mode, every note is in one list.

## Workspaces

A workspace is a named place for notes, in a colour of its own: Work, Home, a project. On disk it is a folder, and each note in it is a `.md` file inside. Notes in no workspace are in the Inbox.

On home, the button at the end of the search field opens the filters: what to show, and which workspace. In All notes, the workspaces sit as pills along the top. Choose one to see only its notes. A note you make while a workspace is chosen goes into it.

To make one, choose **New workspace** in home's filters, tap the **+** pill in All notes, or go to **Settings › Workspaces**. Long-press a workspace's pill to open its sheet: change its name and colour, make a **New folder inside**, **Move** it, or delete it.

Deleting a workspace asks first what happens to its notes: **Delete, keep the notes** leaves them in the Inbox, and **Delete, and move the notes to Trash** sends them to the Trash. Nothing is deleted for good until you empty the Trash.

An organization you're in has a workspace too, named and coloured after it. Notes filed there are the team's. See [[Organizations and shared notes]].

## Folders inside folders

A workspace can hold folders, and a folder can hold more folders, as deep as you like.

When a workspace is chosen, its folders stand above the notes as a row of chips. Each shows the folder's name and how many notes are in it and under it. At the end of the row are **New folder** and **New note**, both made right where you are. Tap a folder to go into it. Above the chips, a path like `Work › Clients` shows where you are, and each part takes you back up.

With a mouse, right-click a folder for **Open**, **Rename…**, **Move to** and **Delete folder…**. On a phone, use the folder's More in the sidebar. Deleting a folder asks first whether its notes stay or go to the Trash with it.

## Cards or icons

Every level can show its notes as **Cards** or as **Icons**. Pick one with the toggle at the end of the folders' heading on home, or in All notes beside the order.

In Icons, the page is a file browser: folders first as large tiles, then the notes, each with an icon for its kind (a note, a notebook, a canvas, a recording). Tap a folder to go in, or a note to open it.

Your choice carries down. Pick Icons for a workspace and every folder inside it shows icons too, until you pick something else lower down.

## Filing a note

To file a note, open it, tap **More for this note**, then **Workspace**. Pick a workspace or a folder, or type a new name and choose **Add it and file this note there**. **Take this note out of…** puts it back in the Inbox.

You can also drag. Drag a note or a folder onto a folder: a mouse drags at once, a finger holds first. A message says where it went, with **Undo**. **Move to…** in a note's menu does the same without dragging.

A few moves aren't allowed by drag. A team's note stays inside its organization, and a personal note can't be dragged into one. Use the Workspace setting for those, which asks twice because it shares or unshares the note.

Claude can file notes and tidy folders for you too. See [[Claude in Ghost.md]].

## Search

Tap Search on the dock, or type in the search field at the top of home. Search looks through the title and every word of every note, and leaves the archive out.

Add operators to narrow it. They combine, and each must hold:

| Type | To find |
| --- | --- |
| `tag:work` or `#work` | Notes tagged `#work`, or a tag under it like `#work/clients` |
| `in:"Field notes"` | Notes in that workspace and its folders, or pages of that notebook |
| `is:pinned`, `is:archived` | Pinned notes, or the archive |
| `is:todo`, `is:done` | Notes with open to-dos, or every to-do ticked |
| `is:ticket`, `is:notebook`, `is:journal`, `is:canvas` | Notes of that kind |
| `has:image`, `has:link`, `has:recording` | Notes with a picture, a link or a recording |
| `before:2026-10-01`, `after:2026-10-01` | Made before, or on and after, that day |
| `updated:<7d`, `created:<2w` | Changed, or made, in the last seven days or two weeks |
| `"exact phrase"` | Those words together, in that order |
| `-word`, `-tag:x` | Not that word, not that tag |

A date can be a day, a month (`2026-10`), a year, `today` or `yesterday`. A span is days (`7d`), weeks (`2w`), months (`3m`) or years (`1y`). Chips under the field show what was understood.

## Smart notebooks

A smart notebook is a search you keep by name. Search for something, then tap **Save as a smart notebook** under the field, and give it a name.

It shows in the sidebar under **Smart notebooks**. Open it and you see the notes the search finds now. Nothing is filed in it: a note that comes to match is in it at once. From its More you can rename it, change its search, move it in the list or delete it. Deleting one never deletes a note.

Smart notebooks follow your account to every device.

## Tags

Write `#word` anywhere in a note to tag it ([[Links, tags and footnotes]]). The **Tags** page, in the sidebar, lists every tag with how many notes carry it. A tag inside another, like `#work/clients`, folds under its parent.

Tap a tag to see its notes. **Rename** gives it a new name in every note that has it, after telling you how many notes will change.

## The command palette

The command palette is everything Ghost.md can do, in one list you search. Open it with ⌘K on a Mac, or Ctrl+K on Windows and in a browser. On a phone, it's in the sidebar drawer.

Type a few letters: a note's title opens it, "new" makes things, "fill" fills a note's blanks. Your smart notebooks, the Tags page and **Ask Claude** are in it too. More in [[Keys and the command palette]].

See also: [[Organizations and shared notes]] · [[Links, tags and footnotes]] · [[Keys and the command palette]] · [[Simple and Advanced]] · [[Claude in Ghost.md]]
