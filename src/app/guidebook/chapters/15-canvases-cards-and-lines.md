# Canvases, cards and lines

_A canvas is cards on an endless page with lines between them. Its note keeps it as JSON Canvas 1.0, the file Obsidian's canvas uses._

## A canvas is a note

The + offers a Canvas beside a Note and a Book, and makes an empty one called "Untitled canvas". Its note is a name in front matter, then the canvas as JSON:

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

**To add one**, double-tap empty space: a card of words appears under your finger, open, with the keyboard up. Or use the + at the bottom left (Add a card), which offers all six; a note is found by part of its title. On a wide screen, a note dragged from the sidebar lands as a card where you drop it, and so does a picture file from the computer.

## Moving, writing, taking off

- **Press and hold a card** for a moment and it lifts, and goes where your finger goes. A drag that starts at once pans the page, so a finger on a card never moves it by mistake.
- **Double-tap a card of words** to write in it, with the note's own editor. A picture opens the same way.
- **An open card** has a corner that resizes it and a cross that takes it off, with its lines.
- A note card and a link card open on a tap, so they have no cross yet. To take one off, switch to the JSON and delete it there.
- **Escape** closes an open card, lets go of a line and puts the Line tool down.

## Lines

The Line tool, second at the bottom left (Draw a line), turns your next two taps into a line: the card it starts from, then the card it goes to. It has an arrow at its end and picks its sides from where the cards are. A card is not joined to itself, two cards are not joined twice, either way round, and a group cannot be one end.

A new line is picked at once, with a field for its words: type them and press Enter. Tap any line to pick it again, and its cross takes it off.

## Groups and colours

**A group** is a labelled box behind the cards. A held press lifts it with every card wholly inside it; a card lifted on its own leaves its group. Double-tap a group to name it; its cross takes the group off and leaves its cards.

**Colour** follows the page's own hues, the ones a workspace wears. The format's six colours, `"1"` to `"6"`, are drawn as rose, ember, amber, moss, sea and violet, and a hex colour such as `"#4a7a9c"` is kept as it is. There is no colour picker on the canvas yet: a colour comes with the file, or is typed into the JSON.

## Getting around

A canvas opens with all of it fitted to the screen.

| To | Do this |
| --- | --- |
| Pan | Drag with one finger, or use a wheel. |
| Zoom | Pinch, or use the wheel with Ctrl or Cmd held, as a trackpad pinch does. |
| Go to a card | Tap a note card's or a link card's title. |
| See it all | Fit in the toolbar, or Shift+1. |
| Go back to a card | To card in the toolbar, once a card has been tapped, or Shift+2. |

Once there are two cards, a minimap sits at the bottom right with the screen's box on it: words filled, a note outlined, a picture dark, a link outlined with a dot. A press grows it by half. A drag on it moves the screen, a tap on the grown map goes there, and a press on the canvas shrinks it again.

## In a note, and the examples

A line that is only `![[Cabin weekend, laid out]]` draws that canvas in a frame inside the note: you can pan, zoom and use its map, but not change it. Its name and an Open sit over it, and a press on the name shows the link to edit. A book can hold a canvas as a chapter ([[Books, and reading one through]]).

Settings › About adds two example canvases to your library:

- **Add the example canvas** adds [[Cabin weekend, laid out]], one of everything: a group, cards of words and to-dos, a table of who brings what, note cards for [[Launch week]] and [[How to format a note]], a link, a chart of the days, a picture where one can be kept, and lines with words on.
- **Add the “How Ghost.md works” canvas** adds [[How Ghost.md works]]: eight plain cards, the order on the lines.

## Not built yet

These were chosen for canvases and are still to come:

- Making a group round cards. Groups come with a file, such as the example canvas.
- Item cards: a list item as a card to tick on the canvas. For now, a note card whose JSON has `"subpath": "#^an-anchor"` opens its note at that item.
- Adding a card by voice.
- A canvas written straight into a note as a ```` ```canvas ```` fence. The frame above is built.
- Export as a `.canvas` file, a picture or a PDF.
- The model's three moves: a gist under a note card's title, laying a note out as a canvas, and offering lines it thinks are missing.

## Read next

- [[Books, and reading one through]]
- [[Pictures and voice memos]]
- [[Links between notes]]
