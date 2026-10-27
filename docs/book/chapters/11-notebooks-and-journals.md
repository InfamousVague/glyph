# Notebooks and journals

A **notebook** is a set of notes in an order, with an index, like a book you can read straight through. A **journal** is a notebook of dated entries. Both are ordinary notes underneath, so they read fine in any Markdown app.

This book is a notebook.

## Making a notebook

1. Tap **+** and choose **Notebook**.
2. Give it a **Name**.
3. Under **What it is**, leave **Notebook** chosen.
4. Optionally, **Find a note** you already have and tap it to add it as a page. Tap again to take it out. The pages so far are listed above, under **Pages in this notebook**, in the order you chose them; move or remove them there.
5. Tap **Make the notebook**.

Nothing is made until you tap it, so closing the sheet leaves no trace. The command palette has **New notebook** too. In Simple, **Notebook** is behind **More…** on the **+** sheet, with **Today** and a journal's entry.

## What a notebook is made of

A notebook is one note. Its front matter says `book: true`, and its words are its index: a list of links to its pages, in order.

```
---
title: "Field guide"
book: true
---
# Field guide
What to know before the walk.

1. [[Introduction]]
2. [[Trees]]
   - [[Oaks]]
   - [[Pines]]
3. [[Birds]]
```

- **A page is any note,** found by its name. A link to a name with no note yet is a page still to be written. The index says "not written yet", and opening it makes the note.
- **The order is the list's order.**
- **Parts come from indenting.** A page indented under another is numbered under it: 2.1, 2.2. One level deep.
- **A numbered index** is written `1.`, `2.`, `3.`. A bullet list beside it at the top level, such as further reading, is about the notebook rather than in it, and shows above the index.
- **The notebook's own words stay.** A paragraph before the list is shown over the index.

A note can be a page in more than one notebook.

## The index

Opening a notebook shows its index. The switch at the top flips between **Index** and **Markdown**, if you'd rather edit the list itself.

- Each page is a row. Tap it to open the page. A page that is a canvas wears the canvas's mark.
- Move a page with its grip, or a place at a time with its up and down arrows. The cross takes it out of the notebook: the note itself is never touched.
- **Add a page** names a new page. Under **Start with**, choose what it starts with, then **Add and open**, or **Add as a canvas** to make the page a canvas.
- **Add a note you have** adds any of your notes, in the order you tick them. **Find a note to add** narrows the list.
- **Read straight through** shows the pages one after another, each drawn as the note itself, like a book. **Index** goes back.

Every change here is a change to the notebook's own Markdown, so the list behind the switch always matches the index you see.

## Reading a page

A page in a notebook wears it. The bar at the top shows the notebook's name and where you are: `2 of 5`. At the foot of the page, **Previous** and **Next** take you to the pages either side, so you can read on without scrolling back up.

On a wide screen, the side panel on the right shows the notebook's index with the open page marked.

A notebook opens where you left it: at its index, on a page, or reading straight through.

## Chapters without a notebook

A note can carry a chapter number in its title, such as `The risks · Ch. 8` or `08 · The risks`. Numbered chapters that belong together, in the same folder or pointing at the same note, are listed in order in the side panel, even without a notebook.

## Tickets in a notebook

Set a **Ticket key** in a notebook's More sheet, such as `GHO`, and its index offers **New ticket** beside **Add a page**. It asks for the title and what the ticket starts with, numbers it GHO-1, GHO-2 and on, and adds it to the index. A page that's a ticket shows its key and status on its row; tap the status to change it. See [[Lists, to-dos and tickets]].

## Journals

A journal is a notebook whose pages are dated entries. Write as many entries a day as you like.

### Making a journal

1. Tap **+** and choose **Notebook**.
2. Under **What it is**, choose **Journal**.
3. Choose what each entry starts with:
   - **The date and the time**
   - **Just the time**
   - **A morning page**, which starts with a question for the morning
   - **A day's to-dos**, which starts with a to-do list
   - **My own**, a template you write
4. Switch on **With where you are** if each entry should keep where it was written.
5. Tap **Make the journal**.

To turn a notebook you already have into a journal, open its More sheet, choose **Keep it as a journal**, pick what entries start with, then **Make it a journal**. Its pages stay where they are.

Once it's a journal, the same row is called **Journal**. Open it to change the template or **With where you are**: entries you've written stay as they are. **Make it a notebook again** turns it back; its entries stay as pages, and new pages start plain.

### Writing an entry

- In the journal, tap **New entry**. Choose what it starts with: the journal's usual template first, then the others, or **An empty page**.
- From anywhere, the **+** sheet offers **Entry in** and the journal you wrote in last.
- The command palette has **New entry in** for your journals.

Each entry is a note named by the minute it was made, such as `2026-10-26 14.05`, so its file name works in any Markdown app. Its line goes at the end of the journal's index. The entry keeps a `date:` too, the time on the clock where it was written.

### Reading a journal

The journal shows its entries by month, newest first, each row with its day, its time, where it was written and how it starts. The three newest months are open, and older ones fold to a row each; tap one to open it. **Previous** and **Next** on an entry walk the entries in the order you wrote them.

Entries are always in the order they were written, whatever order the index lines are in. Pages planned before a notebook became a journal, and not written yet, are listed apart.

### Your own template

A template is the Markdown each entry starts as. These fill in when the entry is made:

| Write | Becomes |
|---|---|
| `{{date}}` | The day in words |
| `{{time}}` | The time, on a 24-hour clock |
| `{{weekday}}` | The day of the week |
| `{{title}}` | The entry's name |
| `{{journal}}` | The journal's name |

You can give a format after a colon, with words in square brackets: `{{date:D MMMM [at] HH:mm}}`. The letters are the ones Obsidian's Templates use. `{{date:GGGG-[W]WW}}` gives the week, such as `2026-W43`. Anything else in double braces is left as you typed it.

## Today's note

**Today**, on the **+** sheet, opens the note named by today's date, and makes it the first time. The command palette has **Today's note**, and on a Mac ⇧⌘D does the same.

Settings › Daily notes (in Advanced) has three choices:

- **Where they go:** a folder of their own (made with the first one), any of your own workspaces or folders, or **No folder**, which files them as any new note is.
- **Starts from:** a template, filled for the day. Your own templates are listed here too, once you keep some.
- **In a notebook:** a notebook each daily note becomes a page of, its line added to the index when the note is made. Or **None**.

A journal and daily notes differ: a journal keeps entries by the minute, as many a day as you write, while a daily note is one page a date, found again by its name.

See also: [[Your first notes]], [[Lists, to-dos and tickets]], [[Canvases, cards and lines]], [[Sharing and published sites]]
