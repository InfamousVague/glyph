# Canvases, cards and lines

_A canvas is cards on an endless page with lines between them. Its note keeps it as JSON Canvas 1.0, the file Obsidian's canvas uses._

## A canvas is a note

The + offers a Canvas beside a Note and a Notebook, and makes an empty one called "Untitled canvas". Its note is a name in front matter, then the canvas as JSON:

```markdown
---
title: "Cabin weekend, laid out"
---
{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 110, "text": "# Book the cabin", "color": "4" },
    { "id": "board", "type": "file", "x": 0, "y": 300, "width": 260, "height": 130, "file": "Launch week.md" }
  ],
  "edges": [
    { "id": "e1", "fromNode": "book", "toNode": "board", "label": "then" }
  ]
}
```

Everything after the front matter is a `.canvas` file: saved as one, it opens in Obsidian, and an Obsidian canvas's JSON is drawn the same here. A card Ghost.md cannot read is left out, not the whole canvas.

Name a canvas from the More sheet's Name field or its tab's menu, since it has no heading. The switch in the header goes between the Canvas and its JSON, which you can read and change by hand. Every change on the canvas is written into the JSON, the front matter kept, and saved the way typing is.

## The cards

| Card | What it is |
| --- | --- |
| Words | A card to write on, drawn as a note's words are. |
| A note | One of your notes by its title, drawn small. A tap opens it, except on its title, which zooms to the card; a title with no note says "Not in Ghost.md yet". |
| A link | A web address, opened in the browser with a tap anywhere but its title. A bare address is given `https://`. |
| A picture | From your phone or computer, kept with your notes' pictures and drawn to fill its card. |
| A chart | A card of words that starts as a small Mermaid diagram, and is drawn as one. |
| A table | A card of words that starts as a table, drawn edge to edge. |

**To add one**, double-tap empty space: a card of words appears under your finger, open, with the keyboard up. Or use the + at the bottom left (Add a card), which offers all six and a group; a note is found by part of its title. A new card never lands exactly on the last one. On a wide screen, a note dragged from the sidebar lands as a card where you drop it, and so does a picture file from the computer.

## Picking, moving, resizing

- **Tap a card** to pick it. It wears a ring, a handle at each corner, and a small bar. Tap the page to let it go.
- **Tap the picked card again** to open it: a card of words to write in, with the note's own editor; a note or a link where it goes. A double-tap does both at once.
- **Drag a handle** to resize the card, any kind of card and a group too. The handles stay finger-sized however far you zoom. With a mouse there is a handle on each side as well.
- **The bar** over the picked card: write in it or open it, draw a line from it, colour it, copy it, take it off with its lines.
- **Drag the picked card** and it moves. With a mouse, drag any card. A finger dragging a card that is not picked pans the page, so a card never moves by mistake; press and hold one for a moment and it lifts, as before.
- **A group** is taken by its name or its border, and the cards wholly inside it move with it. Its ground is the page's: drag there to pan, double-tap there to make a card in it. Resize it over a card to take the card in.
- **Snapping.** Cards land on the grid's dots as you move, resize or make them, and the phone ticks as they do. The magnet at the bottom left turns it off and on; it starts on.
- **The keys:** Delete takes the picked card off, the arrows nudge it one dot (Alt for a pixel), Ctrl or Cmd+D copies it, Space held pans, and Escape lets go of the writing, then of the card.

## Lines

The Line tool, second at the bottom left (Draw a line), turns your next two taps into a line: the card it starts from, then the card it goes to. It has an arrow at its end and picks its sides from where the cards are. A card is not joined to itself, two cards are not joined twice, either way round, and a group cannot be one end.

A new line is picked at once, with a field for its words: type them and press Enter. Tap any line to pick it again, and its cross takes it off.

## Groups and colours

**A group** is a labelled box behind the cards, made from the + (about the picked card, when there is one). Dragged by its name or its border, or lifted by a held press, it moves with every card wholly inside it; a card moved on its own leaves its group. Tap a picked group's name to rename it, or use the pencil on its bar; the bin there takes the group off and leaves its cards.

**Colour** follows the page's own hues, the ones a workspace wears. The format's six colours, `"1"` to `"6"`, are drawn as rose, ember, amber, moss, sea and violet, and a hex colour such as `"#4a7a9c"` is kept as it is. Pick a card and choose Colour on its bar for one of the six, or none; a hex colour comes with the file, or is typed into the JSON.

## Getting around

A canvas opens with all of it fitted to the screen.

| To | Do this |
| --- | --- |
| Pan | Drag with one finger, or use a wheel. With a mouse, drag the open ground between cards, or anywhere with Space held or the middle button. |
| Zoom | Pinch, or use the wheel with Ctrl or Cmd held, as a trackpad pinch does. On a wide window, Zoom out and Zoom in sit beside Fit. |
| Go to a card | Tap the title of a note card or a link card, once it is picked. |
| See it all | Fit in the toolbar, or Shift+1. |
| Go back to a card | To card in the toolbar, once a card has been tapped, or Shift+2. |

Once there are two cards, a minimap sits at the bottom right. It is the canvas drawn small: a card of words shows the shape of its words, a note its title, a picture is the picture, and the lines are their own curves. The part of the canvas on the screen is lit inside a soft rounded box, and the rest is shaded. A press grows it by half. A drag on it moves the screen, a tap on the grown map goes there, and a press on the canvas shrinks it again.

## In a note, and the examples

A line that is only `![[Cabin weekend, laid out]]` draws that canvas in a frame inside the note: you can pan, zoom and use its map, but not change it. Its name and an Open sit over it, and a press on the name shows the link to edit. A notebook can hold a canvas as a page ([[Notebooks, and reading one through]]).

Settings › About › Examples adds two example canvases to your library:

- **Add the example canvas** adds [[Cabin weekend, laid out]], one of everything: a group, cards of words and to-dos, a table of who brings what, note cards for [[Launch week]] and [[How to format a note]], a link, a chart of the days, a picture where one can be kept, and lines with words on.
- **Add the “How Ghost.md works” canvas** adds [[How Ghost.md works]]: eight plain cards, the order on the lines.

## In an organization

A canvas filed in an organization's workspace is the team's, like any note there ([[Accounts, sync and the key you hold]], Organizations). Everyone in the organization has it, and two of you can work on it at once: cards moved, written in, made and taken off by both merge, and typing in the same card lands letter by letter. Each member on the canvas is a small arrow in their colour with their handle on it, and a card someone is writing in wears a ring in their colour. On the organization's page their row says they are editing the canvas, and **Jump to cursor** opens it where their pointer is.

**Comments** go on cards. Pick a card and choose Comment on its bar to start a thread; a card with threads has a round on its corner in the colour of whoever started the first open one, with how many are open, and a tap opens the thread - reply, resolve, reopen or delete it, as in a note. The threads are kept in the canvas's own JSON, after the lines, so they travel with the file.

## Not built yet

These were chosen for canvases and are still to come:

- Making a group round cards. Groups come with a file, such as the example canvas.
- Item cards: a list item as a card to tick on the canvas. For now, a note card whose JSON has `"subpath": "#^an-anchor"` opens its note at that item.
- Adding a card by voice.
- A canvas written straight into a note as a ```` ```canvas ```` fence. The frame above is built.
- Export as a `.canvas` file, a picture or a PDF.
- The model's three moves: a gist under a note card's title, laying a note out as a canvas, and offering lines it thinks are missing.

## Read next

- [[Notebooks, and reading one through]]
- [[Pictures and voice memos]]
- [[Links between notes]]
