# Links, tags and footnotes

Notes get more useful when they point at each other. This chapter covers links between notes, the links back, links to the web, places, tags, footnotes, comments and the bookmark.

## A link to another note

Put a note's name in double square brackets:

```
The photos are still with Sam: see [[Launch week]].
```

Tap the link and that note opens.

- **Case and punctuation don't matter.** `[[launch week]]` finds Launch week, and `[[The Oaks!]]` finds "the oaks".
- **A name with no note yet is drawn dashed.** It's a place to write, not a mistake. Tap it and Ghost.md makes that note, with the name as its heading, and opens it.
- **Other words for the link.** `[[Launch week|the launch]]` shows "the launch" and opens Launch week.
- **A heading in a note.** `[[Weekend trip#Packing]]` points at the Packing heading in Weekend trip.
- **Two notes, one name.** A link opens only one of them, so give each note a name of its own.
- **Not in code.** Brackets inside code are just brackets.

To link to a ticket, use its key: `[[GHO-12]]` shows the ticket's title and a dot for its status. See [[Lists, to-dos and tickets]].

You don't have to type the brackets. **A note**, on the **+** beside an empty line, lets you pick the note to link to.

## Other names for a note

A note can answer to more than one name. List them under `aliases:` in its front matter:

```
---
aliases: [Lisbon, The trip]
---
```

Now `[[Lisbon]]` opens the note too, search finds it by either name, and **A note** on the + offers them. A note's own title wins if another note is called the same.

**Renaming a note.** Only the name is stored in a link, so links that use a note's old name are drawn dashed after you rename it. Add the old name to `aliases:` and they open the note again.

## A link to one line

A list item can have a name: a space, a `^` and the name at the very end of the line. Names are lower-case letters, digits, `_` and `-`.

```
- Ask Sam which photos are cleared ^ask-sam
```

Now you can point at it:

- `[[Launch week#^ask-sam]]` opens Launch week on that line.
- `[[#^ask-sam]]` points at the item of that name in the same note. A tap goes to its line.

The easy way: put the caret on a line and choose **Copy link to this line** in the note's More sheet, under **Links and outline**. A line with no name is given one from its words first. A heading needs no name: its link uses its words. Then paste the link into another note.

Boards use these names too. See [[Boards, tables and live queries]].

## Links back, and the outline

A note's More sheet has a group called **Links and outline**:

- **Links** shows two lists. **Linked from** is every note that links to this one, by its name or an alias, each with the line around the link; tap one to open it there. **Mentioned in** is every note that says this note's name without linking it. **Link** beside one turns those words into a link, with Undo.
- **Outline** lists the note's headings, indented by level, with the one you're reading marked. Tap one to go there. It also counts the note's words, characters and minutes to read, or those of the words you've selected.
- **Local graph** draws this note and the notes one or two links away from it.
- **Copy link to this line**, above.

In Advanced, a **Links** button on the note's bar shows how many notes link here, and opens the same list.

On a Mac or an opened Fold, the side panel has **Links** and **Outline** tabs beside the open note. The outline there follows you as you scroll.

## The graph

**Graph of your notes**, in search and commands or the sidebar, draws every note as a dot and every link as a line. A dot grows with its links and wears its workspace's colour. Notes with no links are dim.

- Pinch or scroll to zoom, and drag to move about. Names appear once you're close enough to read them.
- Tap a dot to open its note.
- Press and hold a dot to light it and the notes it links with.

## A canvas inside a note

A link with `!` in front, alone on its line, draws a canvas inside the note:

```
![[Cabin weekend, laid out]]
```

The canvas appears in a frame you can pan and zoom, with **Open** to go to the canvas itself. Nothing on it can be changed from the frame. Put the caret on the line to see the link as typed. A name that isn't a canvas stays an ordinary link. See [[Canvases, cards and lines]].

## Links to the web

Write one in any of three ways:

- `[our site](https://ghostmarkdown.com)`: the words to read, then the address.
- `https://ghostmarkdown.com` on its own.
- `<https://ghostmarkdown.com>` in angle brackets.

A long address is shown short, so it doesn't push every other word off the line. On the line you're editing, the whole address is shown.

**Link cards.** A line that is only a link gets a card under it, with the page's title and its site. Tap the card to open the page. The title is read from that site. Turn cards off with **Link previews** in Settings › Account, under **Privacy**. With **Local only** on, nothing is fetched.

With the **Rich embeds** plugin from the Market, a video, a song or a design file linked alone on its line can play or show in its card. [[Plugins, one by one]] says which sites it knows.

A Markdown link to a note's file, `[the plan](The%20plan.md)`, the way some other apps write links, counts in that note's **Linked from** list too.

## A place

A link to `geo:` and two numbers, alone on its line, is a place, with a map drawn under it:

```
[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
```

You rarely type one. Choose **A place** from the **+** beside an empty line to put in where you are, on Android. At the very top of a note, on its first line or the one under the title, a place becomes the note's header. **Map on a tagged note** in Settings › Account turns the maps off.

## Tags

A `#` straight against a word tags the line:

```
- [ ] Ship the pricing page #web #launch
```

- A tag starts with a letter, then can hold letters, digits, `_`, `-` and `/`. A `-` or `/` at the very end is left out.
- `#work/clients` is a tag inside a tag. The Tags page folds it under `#work`.
- `# ` with a space after it is a heading, not a tag. `#42` isn't a tag either, because it starts with a digit.
- A tag needs a space, a bracket or the start of the line before it, so `page#2` isn't one. Nor is a `#` inside code, a link or front matter.
- Tags for the whole note can go in its front matter, as `tags: [errands, home]`. They count with the tags in its words.

A tag is drawn as a small chip. Tap it to see every note that carries it, newest first, with the tags inside it to go on to.

**The Tags page.** **Tags**, in search and commands or the sidebar, lists every tag with how many notes carry it, the most used first or by name. Open a tag and **Rename** gives it a new name in every note that has it. Ghost.md says how many notes that changes before it does.

## Footnotes

A marker where the small print belongs, and a line anywhere below saying what it is:

```
The deposit is four hundred[^sam], not four fifty.

[^sam]: Sam said so on the phone. The email disagrees.
```

The marker is raised and quiet. Tap it and the footnote shows right there, so you never scroll to the bottom. The line that says what it is stays in the note, set quietly.

A marker with no line to go with it is left plain, as you typed it, so a typo shows as a typo. **A footnote**, under More on the **+**, writes both halves for you.

## Comments

A comment is kept in the note itself, so it travels wherever the note goes.

Select some words, or put the caret on a line, and choose **Comment**. It's on the press-and-hold menu, in the note's More sheet, on the note's bar in Advanced when there's room, and on a Mac's right-click menu for a note as **Add a comment**. Ghost.md writes two things for you: a mark after the words, and a block at the end of the note that holds every thread.

````
The ==venue==[^c1] is booked.

```comments
c1 matt 2026-10-04T19:00:12Z
The hall or the barn?
  sam 2026-10-04T19:05:40Z
  The hall. Confirmed this morning.
```
````

In the note the mark is a small round dot, and the block is drawn as a list of threads. Tap the dot or a thread to **Reply**, **Resolve** it, **Reopen** it or **Delete thread**. Deleting asks you to press again. In another app the mark reads as a footnote and the block as plain lines. Comments matter most with a team: see [[Organizations and shared notes]].

## The bookmark

Two section signs at the end of a line, `§§`, mark where a note opens. A note has only one. You rarely type it: **Bookmark this line**, on the note's bar or in its More sheet, puts it on the line you're on. Once there's one, the row says **Move or remove the bookmark**.

## Saying links

While you speak a note, links have spoken forms too:

- "note link launch week end link" writes `[[Launch week]]`, in the note's own spelling.
- "item link ask Sam end link" writes `[[#^ask-sam]]`, a link to a line of this note.
- "anchor ship page end anchor" names the line you're on, ` ^ship-page`.
- "link our site to ghostmarkdown dot com end link" writes a web link with words. "link ghostmarkdown dot com end link" writes the bare address.
- "hashtag web" writes `#web`.
- "footnote Sam said so end footnote" writes a footnote.
- "bookmark this" at the end of a line puts the bookmark there.

See [[Speaking your notes]].

See also: [[Markdown and the Ghost.md marks]], [[Lists, to-dos and tickets]], [[Canvases, cards and lines]], [[Workspaces, folders and search]]
