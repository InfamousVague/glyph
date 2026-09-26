# Boards made of list items

_A board is a note. Its cards are list items that carry a name, and a small fence lays them out in columns._

## Two pieces of Markdown

Nothing is kept beside the note. Opened in any other app, a board reads as a plan in words.

**An item carries an anchor.** Any list item can end with a space, a `^` and a name: a to-do, a bullet or a numbered step. The anchor names the item so that something else can point at it. It must be the last thing on the line, which keeps it apart from a superscript: `E = mc^2^` stays a superscript, and `- Book the cabin ^book-cabin` is an anchor. Ghost.md draws it small and faint.

**A fence lays out the columns.** It opens with ```` ```board ```` on a line of its own and closes with ```` ``` ````. Each line between is a column: its name, a colon, then the anchors of its cards in order.

Here are both, working. The board is drawn from the fence, and its cards are the four items under it.

```board
To do: book-cabin, pack-coffee
Waiting on Sam: sam-dog
Done: pick-weekend
```

```markdown
- [ ] Book the cabin ^book-cabin
- [ ] Pack the coffee ^pack-coffee
- Sam and the dog ^sam-dog
- [x] Pick the weekend ^pick-weekend
```

In your own notes the items are an ordinary list, anywhere in the note. Here they sit in a block of code only to keep this book's examples off your home page's To do list; the board reads them just the same. Tap the board between its cards and it steps aside for the fence's own lines, ready to type.

When Ghost.md names an item itself, it takes the first three words that carry meaning: "Add ability to auto-tag notes" becomes `add-ability-auto`, not `add-ability-to`. You can type your own, in lower case letters, numbers and hyphens. A name already in a note is never changed, since something may point at it.

## A card is its item

A card shows its item's words, without their Markdown, in three lines at most. A to-do is a card with a box. A bullet or a numbered step is a card with a dot: something on the board that is not work to finish.

| On a card | What happens |
| --- | --- |
| Tick the box | The item is ticked in the note, and the card moves to Done if there is one. Untick it and it goes back to the first column. |
| Tap the words | The caret goes to the item's line in the note, at the end of its words. |
| Press and hold, then drag | The card lifts, and a gap opens where it will land, in any column. Near an edge, the board or the note scrolls along. |
| The chevrons | The card moves one column left or right. |
| The three dots | Its menu: Move to each other column, Tick or Untick for a to-do, Go to the line, what a plugin offers the item, and Take off the board. |

**A column called Done means done.** A column whose name starts or ends with "done" ("Done", "All done", "Done this week") is the Done column. A ticked item is drawn there, dragging a card in ticks it, and dragging it out unticks it. Tick the item in the list instead and its card moves in the same change, so one Undo takes back both. A to-do with no card, ticked in a list whose other items are on a board, joins that board in Done and is given a name. A board with no Done column leaves the ticks to the items.

**The + by a column's name** opens a field at the top of the column. Type the words and press Enter: Ghost.md writes `- [ ] your words ^your-words` under the last item the board names, with its card at the top of that column. The field stays open for the next card; Escape closes it.

**A card whose item has gone** shows its anchor alone, `^pack-coffee`, in faint italics with a greyed box, so nothing disappears without a sign. Its menu can still take it off the board.

**The line under the board sets its height.** Drag the grip at its middle, or step it with the arrow keys (Home and End go to either end); a double-tap gives the board back its own height. The height is written into the fence when you let go, or at each step of the keys, as ```` ```board height=18 ````, in the columns' own ems, from 5 to 60. With no height the board is as tall as its longest column; with one, a longer column scrolls inside itself.

## Making one

| Where | What it does |
| --- | --- |
| The note's More sheet › Make a board | Every list item in the note is named, and a fence of To do, Doing and Done goes in under the title, ticked items in Done. Offered while the note has a list and no board. |
| Press and hold an item › Board from list | Only that list becomes a board, set in just above it. Select several lines first and those lines are the list. |
| Press and hold an item › Add to board | One item joins the board its list is on, else the nearest board above it, else the first in the note: in the first column, or in Done if it is ticked. |
| Tap the board to show its fence, then press and hold a line of it › Copy board | The fence and the items it names, together, to paste into another note. |
| Settings › About › Add the example board | Adds [[Launch week]], a working board with notes on how to change it. |

Each change is one edit, so one Undo puts the note back, and nothing else in the note moves.

## Pointing at an item

The anchor works in a sentence too. `[[#^sam-dog]]` points at an item in this note, and `[[Launch week#^photos]]` at one in another. It is drawn as a quiet link, and a tap goes to the line: the packing, say, waits on [[#^sam-dog]]. A pointer whose item has gone is drawn dotted.

An item linked to Notion or GitHub carries a mark as well, always between its words and its anchor: `- [ ] Book the cabin [notion](https://…) ^book-cabin`. The card shows a small mark in place of the link, Notion's own for Notion and a link sign for GitHub, and the anchor is never sent to Notion or GitHub as part of a title.

## The rules, briefly

- A board never has to hold every item in the note.
- An anchor names one item, the first that has it, and a card in two columns belongs to the first.
- Column names are free. The same name twice is one column, and an empty one (`Blocked:`) stays.
- A note can hold several boards, and an item can sit on more than one.
- Taking a card off the board, from its menu or the fence, leaves the item where it is.

## By voice

Boards are not changed by voice at present. The recorder reads a command once, when you stop, and the only commands it carries out itself are adding to a note and making a new list, each asked about first. "Hey Ghost, move the coffee to Done" moves no card, and "Hey Ghost, make this a board" makes no board. Said into a note's own Speak, words like these are either refused, with the reason, or passed to the AI as a spoken ask about that note, and anything it writes lands as marked changes you can undo ([[Spoken asks and the review]]). [[Commands after Hey Ghost]] has what the recorder does carry out.

## Read next

- [[Books, and reading one through]]
- [[Lists and to-dos]]
- [[Notion and GitHub]]
