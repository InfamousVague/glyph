# Links between notes

_Every kind of link a note can hold, and what a tap on each one does: another note, a line inside one, a canvas drawn in place, a page on the web, and a shared note arriving in the app._

## A link to another note

Put a note's title in double brackets:

```
The photos are still with Sam: see [[Launch week]].
```

A tap opens that note. This is what turns a pile of notes into something you can walk through, and it is written the way Obsidian and most notes apps write it.

- **It matches the way a person says a title**, with case and punctuation set aside, so `[[launch week]]` finds Launch week. Only the plain letters a to z and the digits are compared, and anything else, an accented letter included, counts as a break between words, so `[[Cafe]]` does not find a note called Café. A title written wholly in another alphabet cannot be linked to yet.
- **A title with no note is drawn dashed.** It is a place to write, not a mistake: tap it and Ghost.md makes that note, with the title as its heading, and opens it.
- **A link to a book** opens the book where you last left it.
- **Nothing is stored but the words.** The link is the title. Rename a note and the links that used its old title wait, dashed, until you change them too.

## A link to a line

A list item can have a name: a `^` and the name at the end of its line, `- Ask Sam which photos are cleared ^ask-sam`. [[Boards made of list items]] says how those names work. A link can point at one:

- `[[Launch week#^ask-sam]]` opens Launch week on that item. The caret lands at the end of its words and the page scrolls to it, rather than opening where you last left the note.
- `[[#^ask-sam]]`, with nothing before the `#`, points at the item of that name in this same note. A tap goes to the line.

## A canvas in a frame

A link with `!` in front, on a line of its own, draws the canvas it names inside the note: write `![[Cabin weekend, laid out]]` alone on a line, and that canvas appears there in a frame.

The frame is the note's width and about two fifths of the screen's height, never more than 360 pixels, and it is the canvas itself, fitted to the frame to begin with. Pan it with a finger or a mouse wheel, and zoom with a pinch, or the wheel with the modifier key held. A minimap sits in the corner. Over the frame are the canvas's name and **Open**, which opens the canvas note. Nothing on it can be changed from here.

With the caret on the line, the frame steps aside and the line shows as typed. A title that names a note of words, or no note at all, stays a plain link, and in any other app the line reads as a link to the canvas. Canvases are [[Canvases, cards and lines]].

## Links to the web

There are three ways to write one:

- `[our site](https://attack.fm/glyph)`: the words you want read, then the address.
- `https://attack.fm/glyph` on its own.
- `<https://attack.fm/glyph>`, in angle brackets.

An address is shown short, so it does not push every other word off the line: its site, the first three characters after it, an ellipsis, and the last three. A Notion task's hundred-character address shows as something like `notion.so/att…b3c`. A short address stays whole. On the line the caret is on, the whole address is written out, exactly as it is kept.

A link in the middle of words is there to read and to edit: a tap puts the caret in it. To open one, give it a line of its own, and its card opens it. That needs Link previews on: with them off there are no cards.

## Link cards

A line that is only a link, bare, in angle brackets, or written with words, in a list or not, gets a card under it: the page's title, its site, and a line about it. A tap on the card opens the page.

The title is read by the app from the linked site, only for a card on screen, and kept for a week, so a page is asked for at most once a week. Until then, or without it, the card shows the site and the path.

- **Settings › Type › Link previews** off: no cards at all.
- **Settings › Formatting › Local only** on: cards show the site and the path, and nothing is fetched.
- **In a browser tab**: the site and the path, and nothing is fetched.

A list item linked to a Notion task or a GitHub issue ends with a small mark naming the plugin, `[notion](…)`. Ghost.md draws it as a pill with that name, or, where the plugin can read what it points at, as a row under the item saying what it is linked to and how it stands. That is [[Notion and GitHub]].

## Links that open the app

A shared note, read in a browser, has **Open in the Ghost.md app**. That opens a `ghostmd://` link on the phone or the Mac, and Ghost.md saves a copy of the shared note or book into your library and opens it. The copy is yours to change; the shared one stays as it is. Sharing is [[Sharing a note or a book]].

## Saying a link

While recording, each link has its words and an ending, "end link":

- "note link launch week end link" writes `[[Launch week]]`, spelled the way your note spells its title. A title misheard, "week and trip" for a note called Weekend trip, finds the closest of your notes when one is close enough.
- "item link ask Sam end link" writes `[[#^ask-sam]]`.
- "link attack dot fm end link" writes `<https://attack.fm>`.
- "link our site to attack dot fm end link" writes `[our site](https://attack.fm)`: the words, then "to", then the address.

An address is said the way you would read it out: "dot", "slash", "dash", "underscore" and "colon".

## Read next

- [[Boards made of list items]]
- [[Canvases, cards and lines]]
- [[Sharing a note or a book]]
