# Notebooks and journals

A **notebook** is a set of notes in an order, with an index, like a book you can read straight through. A **journal** is a notebook of dated entries. Both are ordinary notes underneath, so they read fine in any Markdown app.

This book is a notebook.

## Making a notebook

1. Tap **+** and choose **Notebook**.
2. Give it a **Name**.
3. Under **What it is**, leave **Notebook** chosen.
4. Optionally, **Find a note** you already have and tap it to add it as a page. Tap again to take it out. Reorder the pages as you go.
5. Tap **Make the notebook**.

The command palette has **New notebook** too.

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

- **A page is any note,** found by its name. A link to a name with no note yet is a page still to be written. The index says "Not written yet", and opening it makes the note.
- **The order is the list's order.**
- **Parts come from indenting.** A page indented under another is numbered under it: 2.1, 2.2. One level deep.
- **A numbered index** is written `1.`, `2.`, `3.`. A bullet list beside it at the top level, such as further reading, is about the notebook rather than in it, and shows above the index.
- **The notebook's own words stay.** A paragraph before the list is shown over the index.

A note can be a page in more than one notebook.

## The index

Opening a notebook shows its index. The switch at the top flips between **Index** and **Markdown**, if you'd rather edit the list itself.

- Each page is a row. Tap it to open the page.
- Move a page with its grip, or with **up** and **down**. Or take it out of the notebook: the note itself is never touched.
- **Add a page** names a new page. Choose what it starts with, then **Add and open**, or **Add as a canvas** to make the page a canvas.
- **Add a note you have** adds any of your notes, in the order you tick them.
- **Read straight through** shows the pages one after another, like a book. **Index** goes back.

## Reading a page

A page in a notebook wears it. The bar at the top shows the notebook's name and where you are: `2 of 5`. At the foot of the page, **Previous** and **Next** take you to the pages either side, so you can read on without scrolling back up.

On a wide screen, the side panel on the right shows the notebook's index with the open page marked.

A notebook opens where you left it: at its index, on a page, or reading straight through.

## Chapters without a notebook

A note can carry a chapter number in its title, such as `The risks · Ch. 8` or `08 · The risks`. Numbered chapters that belong together, in the same folder or pointing at the same note, are listed in order in the side panel, even without a notebook.

## Tickets in a notebook

Set a **Ticket key** in a notebook's More sheet, such as `GHO`, and its index offers **New ticket**, numbered GHO-1, GHO-2 and on. See [[Lists, to-dos and tickets]].

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

To turn a notebook you already have into a journal, use **Make it a journal** in its More sheet. **Make it a notebook again** turns it back.

### Writing an entry

- In the journal, tap **New entry**. Choose what it starts with: the journal's usual template first, then the others, or **An empty page**.
- From anywhere, the **+** sheet offers **Entry in** and the journal you wrote in last.
- The command palette has **New entry in** for your journals.

Each entry is a note named by the minute it was made, such as `2026-10-26 14.05`. Its line goes at the end of the journal's index.

### Reading a journal

The journal shows its entries by month, newest first. The three newest months are open, and older ones fold to a row each. **Previous** and **Next** on an entry walk the entries in the order you wrote them.

### Your own template

A template is the Markdown each entry starts as. These fill in when the entry is made:

| Write | Becomes |
|---|---|
| `{{date}}` | The day in words |
| `{{time}}` | The time, on a 24-hour clock |
| `{{weekday}}` | The day of the week |
| `{{title}}` | The entry's name |
| `{{journal}}` | The journal's name |

You can give a format after a colon, with words in square brackets: `{{date:D MMMM [at] HH:mm}}`.

## Today's note

**Today**, on the **+** sheet, opens the note named by today's date, and makes it the first time. On a Mac, ⇧⌘D does the same. In Settings › Daily notes you can choose a template for it and where it goes, including into a notebook, so your daily notes collect in one place.

See also: [[Your first notes]], [[Lists, to-dos and tickets]], [[Canvases, cards and lines]], [[Sharing and published sites]]
