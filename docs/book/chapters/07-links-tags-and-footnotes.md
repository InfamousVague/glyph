# Links, tags and footnotes

Notes get more useful when they point at each other. This chapter covers links between notes, links to the web, places, tags, footnotes, comments and the bookmark.

## A link to another note

Put a note's name in double square brackets:

```
The photos are still with Sam: see [[Launch week]].
```

Tap the link and that note opens.

- **Case and punctuation don't matter.** `[[launch week]]` finds Launch week, and `[[The Oaks!]]` finds "the oaks".
- **A name with no note yet is drawn dashed.** It's a place to write, not a mistake. Tap it and Ghost.md makes that note, with the name as its heading, and opens it.
- **Other words for the link.** `[[Launch week|the launch]]` shows "the launch" and opens Launch week.
- **Only the name is stored.** Rename a note and links that use its old name are drawn dashed until you change them too.

To link to a ticket, use its key: `[[GHO-12]]` shows the ticket's title and a dot for its status. See [[Lists, to-dos and tickets]].

## A link to one line

A list item can have a name: a space, a `^` and the name at the very end of the line.

```
- Ask Sam which photos are cleared ^ask-sam
```

Now you can point at it:

- `[[Launch week#^ask-sam]]` opens Launch week on that line.
- `[[#^ask-sam]]` points at the item of that name in the same note. A tap goes to its line.

Boards use these names too. See [[Boards, tables and live queries]].

## A canvas inside a note

A link with `!` in front, alone on its line, draws a canvas inside the note:

```
![[Cabin weekend, laid out]]
```

The canvas appears in a frame you can pan and zoom, with **Open** to go to the canvas itself. Nothing on it can be changed from the frame. See [[Canvases, cards and lines]].

## Links to the web

Write one in any of three ways:

- `[our site](https://ghostmarkdown.com)`: the words to read, then the address.
- `https://ghostmarkdown.com` on its own.
- `<https://ghostmarkdown.com>` in angle brackets.

A long address is shown short, so it doesn't push every other word off the line. On the line you're editing, the whole address is shown.

**Link cards.** A line that is only a link gets a card under it, with the page's title and its site. Tap the card to open the page. Turn cards off with **Link previews** in Settings › Account, under Privacy. With **Local only** on, nothing is fetched.

A YouTube, Spotify or Figma link alone on a line can play or show in place, with the Rich embeds plugin from the Market.

## A place

A link to `geo:` and two numbers, alone on its line, is a place, with a map drawn under it:

```
[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
```

You rarely type one. Choose **A place** from the **+** beside an empty line to put in where you are.

## Tags

A `#` straight against a word tags the line:

```
- [ ] Ship the pricing page #web #launch
```

- A tag can hold letters, digits, `_`, `-` and `/`. `#work/clients` is a tag inside a tag, the way Obsidian reads it.
- `# ` with a space after it is a heading, not a tag. `#42` isn't a tag either, because it starts with a digit.
- A tag is drawn as a small chip. Tap it to see every note that carries it. **Tags** in the command palette lists them all.

## Footnotes

A marker where the small print belongs, and a line anywhere below saying what it is:

```
The deposit is four hundred[^sam], not four fifty.

[^sam]: Sam said so on the phone. The email disagrees.
```

The marker is raised and quiet. Tap it and the footnote shows right there, so you never scroll to the bottom. A marker with no line to go with it says so when you tap it.

## Comments

A comment is kept in the note itself, so it travels wherever the note goes.

Select some words, or put the caret on a line, and choose **Comment**. It's on the press-and-hold menu, in the note's bar and in the More sheet. Ghost.md writes two things for you: a mark after the words, and a block at the end of the note that holds every thread.

````
The ==venue==[^c1] is booked.

```comments
c1 matt 2026-10-04T19:00:12Z
The hall or the barn?
  sam 2026-10-04T19:05:40Z
  The hall. Confirmed this morning.
```
````

In the note the mark is a small round dot, and the block is drawn as a list of threads. Tap the dot or a thread to reply, resolve it, or reopen it. In another app the mark reads as a footnote and the block as plain lines. Comments matter most with a team: see [[Organizations and shared notes]].

## The bookmark

Two section signs at the end of a line, `§§`, mark where a note opens. A note has only one. You rarely type it: the bookmark button in a note's tools (**Bookmark this line**) puts it on the line you're on, and pressing it again moves or removes it.

## Saying links

While you speak a note, links have spoken forms too:

- "note link launch week end link" writes `[[Launch week]]`.
- "link our site to attack dot fm end link" writes a web link with words.
- "hashtag web" writes `#web`.
- "footnote Sam said so end footnote" writes a footnote.
- "bookmark this" at the end of a line puts the bookmark there.

See [[Speaking your notes]].

See also: [[Markdown and Ghost.md's marks]], [[Lists, to-dos and tickets]], [[Canvases, cards and lines]], [[Workspaces, folders and search]]
