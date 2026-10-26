# Workspaces, folders and search

As your notes grow, you'll want to keep some apart and find others fast. Workspaces and folders sort your notes. Search, smart notebooks and tags find them again, wherever they're filed.

Workspaces and folders are part of Advanced mode. In Simple mode, every note is in one list, there are no workspace pills, and a search can't be kept as a smart notebook. See [[Simple and Advanced]].

## Workspaces

A workspace is a named place for notes, in a colour of its own: Work, Home, a project. On disk it is a folder, and each note in it is a `.md` file inside. Notes in no workspace are in the Inbox.

On home, the button at the end of the search field opens the filters: what to **Show**, and which **Workspace**. In All notes, the workspaces sit as pills along the top. Choose one to see only its notes; tap the chosen pill again to see every note. A note you make while a workspace is chosen goes into it.

### Making and changing one

To make one, do any of these:

- In home's filters, choose **New workspace**.
- In All notes, tap the **+** pill.
- Go to **Settings › Workspaces** and choose **New workspace**.

Give it a **Name**, pick a **Colour**, and tap **Add**. It is chosen as it is made, so the list opens on it, empty.

Long-press a workspace's pill, or choose **Edit** with its name in home's filters, to open its sheet. There you can:

- change its name, then tap **Rename**;
- tap a new colour, which changes at once;
- make a **New folder inside** it;
- **Move** it inside another workspace, or back to the top;
- **Delete workspace**.

**Settings › Workspaces** lists **Your workspaces**, and under them **Organizations' workspaces**, each named and coloured after its organization.

### Deleting one

Deleting a workspace asks first what happens to its notes:

- **Delete, keep the notes**: a workspace at the top leaves its notes in the Inbox. A folder inside another moves its notes up into the one above it.
- **Delete, and move the notes to Trash**: the notes go to the Trash with it, and can be restored from there until it is emptied.

Folders inside a deleted workspace aren't deleted: they move up a level. Notes in the Trash are deleted for good when you empty it, or by themselves thirty days after they went in.

An organization you're in has a workspace too, named and coloured after it. Notes filed there are the team's. It has no name or colour of its own to change here; its sheet takes you to the organization. See [[Organizations and shared notes]].

## Folders inside folders

A workspace can hold folders, and a folder can hold more folders, as deep as you like. A folder is a workspace inside another: it has a name and a colour, and on disk it is a folder inside its parent's.

When a workspace is chosen, its folders stand above the notes under a small **Folders** heading, as a row of chips. Each shows the folder's name and how many notes are in it and in the folders under it. At the end of the row are **New folder** and **New note**, both made right where you are. Tap a folder to go into it. Above the chips, a path like `Work › Clients` shows where you are, and each part takes you back up.

The folders show on home under the filters, in All notes under the order, and on an organization's page above its notes.

With a mouse, right-click a folder for **Open**, **Rename…**, **Move to** and **Delete folder…**. On a phone, use the folder's More in the sidebar. **Delete folder…** asks first whether its notes stay or go to the Trash with it, as deleting a workspace does.

## Cards or icons

Every level can show its notes as **Cards** or as **Icons**. Pick one with the toggle at the end of the folders' heading on home, or in All notes beside the order.

In Icons, the page is a file browser: folders first as large tiles, then the notes, each with an icon for its kind (a note, a notebook, a canvas, a recording). With no workspace chosen, the first tiles are your workspaces. Tap a folder to go in, or a note to open it. **New folder** and **New note** are tiles at the end.

Your choice carries down. Pick Icons for a workspace and every folder inside it shows icons too, until you pick something else lower down.

## Filing a note

To file a note:

1. Open it and tap **More for this note**.
2. Choose **Workspace**. In Simple mode, it is behind **More…** on the sheet.
3. Pick a workspace or a folder. A folder inside another says where, like `Work › Clients`.

To file it somewhere new, type a name under **New workspace** and choose **Add it and file this note there**. **Take this note out of…** puts it back in the Inbox.

You can also drag. Drag a note or a folder onto a folder, or onto a workspace's pill: a mouse drags at once, a finger holds first. A message says where it went, with **Undo**. **Move to…** in a note's menu does the same without dragging, and a screen reader offers it on every note and folder.

### Moves that aren't allowed by drag

- A team's note moves only between the folders of its own organization. It can't be dragged out to a personal folder, to the top, or into another organization.
- A personal note can't be dragged into an organization.
- A folder can't be dragged into itself, into a folder inside it, or into or out of an organization.

Use the note's **Workspace** setting for those. Filing a note in an organization's workspace shares it with the team. Filing a team's note in a workspace of your own takes it from the team, so that asks you to press twice. See [[Organizations and shared notes]].

### Filed for you

Meetings can file themselves. With **Sort meetings into workspaces** on, on the **Meetings** card in **Settings › Recording**, the AI reads each meeting once it is written up and files it in the **Meetings** folder of the workspace it is about. A meeting you've filed yourself stays where you put it. See [[Meetings and the Meet bot]].

Claude can file notes and tidy folders for you too: make, rename, move and delete folders, and move notes into them, under the same rules as dragging. See [[Claude in Ghost.md]].

## Search

Tap Search on the dock, or type in the search field at the top of home. Search looks through the title and every word of every note, and a note's other names too. It leaves the archive out.

It forgives a slip. A word of four letters or more can have one letter wrong, missing, added or swapped (two in a word of eight or more), as long as the first letter is right: "cluade" finds Claude. A word still being typed finds longer words that start like it. Notes whose title matches come first, then the newest. Each result shows the line its words were found in, with them marked.

### Operators

Add operators to narrow a search. They combine, and each must hold:

| Type | To find |
| --- | --- |
| `tag:work` or `#work` | Notes tagged `#work`, or a tag under it like `#work/clients` |
| `in:"Field notes"` | Notes in that workspace and its folders, or pages of that notebook |
| `is:pinned`, `is:archived` | Pinned notes, or the archive |
| `is:todo` or `has:todo` | Notes with a to-do still open |
| `is:done` | Notes whose to-dos are all ticked, or a ticket that is done |
| `is:ticket`, `is:notebook`, `is:journal`, `is:canvas` | Notes of that kind |
| `has:image`, `has:link`, `has:recording` | Notes with a picture, a link, or a recording or voice memo |
| `before:2026-10-01`, `after:2026-10-01` | Made before, or on and after, that day |
| `created:<2w`, `updated:<7d` | Made, or changed, in the last two weeks or seven days |
| `updated:>30d` | Not changed for thirty days |
| `updated:2026-10-01` | Changed on that day |
| `"exact phrase"` | Those words together, in that order |
| `-word`, `-tag:x` | Not that word, not that tag |

A date can be a day, a month (`2026-10`), a year (`2026`), `today` or `yesterday`. A span is days (`7d`), weeks (`2w`), months (`3m`) or years (`1y`). `updated:` and `created:` also take `<` or `>` before a date. Upper and lower case are the same.

Chips under the field show what was understood. A word with a colon that isn't an operator, or an operator with a value it doesn't know, stays an ordinary word, so nothing you type is dropped. A search of operators alone lists every note they let through, newest first.

## Smart notebooks

A smart notebook is a search you keep by name. Search for something, then tap **Save as a smart notebook** under the field, and give it a name.

It shows in the sidebar under **Smart notebooks**, with how many notes it finds. Open it and you see the notes the search finds now. Nothing is filed in it: a note that comes to match is in it at once.

From its More you can change its **Name** or its **Search**, **Move up** or **Move down** in the list, or **Delete smart notebook**. Deleting one never deletes a note. Your smart notebooks are in the command palette too.

Smart notebooks follow your account to every device.

## Tags

Write `#word` anywhere in a note to tag it ([[Links, tags and footnotes]]). The **Tags** page, in the sidebar, lists every tag with how many notes carry it, sorted **Most used** or **A to Z**. A tag inside another, like `#work/clients`, folds under its parent.

Tap a tag to see its notes. To rename it:

1. Open the tag and choose its rename, such as **Rename #work**.
2. Type the **New name**. The sheet says how many notes will change, and that the tags inside it change with it.
3. Tap the rename with its count, such as **Rename in 4 notes**.

Renaming a tag to one that already exists joins the two into one.

## The command palette

The command palette is everything Ghost.md can do, in one list you search. Open it with ⌘K on a Mac, or Ctrl+K on Windows. On a phone, tap the **Search and commands** button at the top of the sidebar.

Type a few letters: a note's title opens it, "new" makes things, "fill" fills a note's blanks. Your smart notebooks, the Tags page and **Ask Claude** are in it too. More in [[Keys and the command palette]].

See also: [[Organizations and shared notes]] · [[Links, tags and footnotes]] · [[Keys and the command palette]] · [[Simple and Advanced]] · [[Claude in Ghost.md]]
