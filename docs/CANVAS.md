# Canvases

A canvas is cards on an infinite page with lines between them: the thing Obsidian calls a canvas, in Glyph. Matt
(2026-09-20): "we're going to build something similar for Glyph". His fifteen choices steer it; this is the standard
they set, and it will grow as the slices land.

## Matt's choices

Fifteen questions, asked on 2026-09-20 before a line was written, and his answers. Build to these; where a thing
was not asked, say so rather than cite him.

1. **What a canvas is:** both a ```canvas fence in a note and a canvas note of its own.
2. **Format:** JSON Canvas 1.0 verbatim, so it opens in Obsidian and back; not a grammar of Glyph's own.
3. **Card kinds, all four in v1:** text; a note (a wiki link, drawn live the way a home card draws one); an item
   (a `^anchor` list item as a card, tickable from the canvas); pictures and web links.
4. **Lines:** arrows with labels - directed, a label if wanted, each end picking its side by itself.
5. **Groups:** yes, in v1: a labelled box whose cards move with it.
6. **Colour:** the page's workspace hues. Not Obsidian's six presets as a palette of the canvas's own, and not
   ink-only. The presets are read as rose, ember, amber, moss, sea, violet; a hex is kept as it is.
7. **Platform:** the phone and the Mac equally - every action by touch and by pointer from the first day.
8. **Adding a card on the phone, all four:** double-tap empty space (a text card under the fingers, keyboard up);
   a + in the dock (text, note, picture or link, landing in the middle of the view); a note dragged from the
   sidebar on a wide screen; by voice ("Glyph, add a card": the words said land near the last card).
9. **The model, all three from the start:** the gist under a note card's title; "Glyph, make a canvas of this
   note" (headings to groups, items to cards, links to arrows - a first draft to push around); lines it thinks
   are missing, offered and accepted with a tap.
10. **Moving about:** pan and pinch; Fit and zoom-to-card (Obsidian's Shift+1 and Shift+2, as buttons and
    shortcuts, and a card's title tapped zooms to it); and a minimap in a corner with the view drawn on it.
11. **Sync:** the same end-to-end encrypted feed as notes; nothing new in the engine.
12. **Boards:** a separate feature. They share anchors and item cards, and nothing else.
13. **Embedding:** a canvas in a note (`![[name.canvas]]`, drawn read-only, tap to open) and as its own note.
    Not chosen: a canvas nested on a canvas, and a home card drawn as a thumbnail.
14. **Export:** the `.canvas` file, and a picture, and a PDF.
15. **The first slice:** read and draw a real Obsidian file faithfully, with pan and pinch; editing second.

**Not asked, so not his:** how a card is moved (a drag, or a press-and-hold first, given one finger pans); how a
card's words are edited (a tap, a double-tap); how a card or a line is deleted; how a line is drawn; resizing,
snapping, duplicating. Obsidian's answers - drag from a card's edge dot for a line, double-click to edit or to
label a line, select and Delete - contradict nothing above.

## The format is JSON Canvas, as it is

A canvas is written in [JSON Canvas 1.0](https://jsoncanvas.org/spec/1.0/), the open format Obsidian's `.canvas`
files use, verbatim (Matt chose interop over a grammar of Glyph's own). A canvas made in Glyph opens in Obsidian; an
Obsidian canvas pasted into Glyph is drawn the same. `canvas/jsonCanvas.ts` reads and writes it.

```json
{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin", "color": "4" },
    { "id": "plan", "type": "file", "x": 320, "y": 0, "width": 260, "height": 160, "file": "Launch week.md", "subpath": "#^photos" },
    { "id": "site", "type": "link", "x": 0, "y": 160, "width": 260, "height": 100, "url": "https://attack.fm/glyph" },
    { "id": "before", "type": "group", "x": -40, "y": -40, "width": 660, "height": 340, "label": "Before we go" }
  ],
  "edges": [
    { "id": "e1", "fromNode": "book", "toNode": "plan", "fromSide": "right", "toSide": "left", "label": "then" }
  ]
}
```

Four kinds of node: `text` (markdown on a card), `file` (another note, named by its title as a file: `Launch
week.md` is the note called "Launch week", and a `subpath` of `#^anchor` opens it on that item), `link` (a web
address) and `group` (a labelled box around other cards). Every node has `x`, `y`, `width`, `height` in the
canvas's own pixels, and nodes are in ascending z-order: the first is drawn under the rest. An edge joins two nodes,
leaves and arrives by a side (`top`, `right`, `bottom`, `left` - worked out from where the nodes are when left out),
and has an arrow at its end unless `toEnd` says `none`. A `label` sits on the line.

**Colour** is the spec's: `"1"` to `"6"` are its six presets, whose looks each app chooses, or a hex colour. Glyph
paints the presets as the page's own hues - rose, ember, amber, moss, sea, violet, the ones a workspace wears
(`ink.css`) - and keeps a hex as it is.

**Read leniently, written exactly.** A node that is not what the spec says is left out, not the whole canvas; an edge
to a node that is not there goes with it. What is kept is written back with only the spec's fields, so a round trip
changes nothing anyone meant.

## Where a canvas lives

**As a note of its own.** A note whose body is the JSON is a canvas note, and is drawn as a canvas where its words
would be (editor/NoteScreen.tsx). Obsidian names a canvas by its file; Glyph has no files, so the name is front
matter, which is how any note from outside is named (docs/MARKDOWN.md):

```markdown
---
title: "Cabin weekend, laid out"
---
{
  "nodes": [ … ],
  "edges": [ … ]
}
```

Everything after the front matter is the `.canvas` file, character for character. Settings > About adds an example
one (`canvas/sampleCanvas.ts`), the way it adds the example board.

**In a note**, as a ```canvas fence, the way a board or a Mermaid diagram sits in a note. Not built yet.

## What is drawn, so far

The first slice reads and draws (`canvas/CanvasView.tsx`): cards where the file puts them, groups behind them,
lines with their arrows and labels, one finger or a wheel to pan, two fingers or a modifier and the wheel to zoom
about the point under them, and Fit. A card of words is the note's own editor, read-only, so it draws exactly as a
note does. A note card draws that note small (notes/NotePeek.tsx) and opens it on a tap - at its anchor when the
card names one; a note not in Glyph is drawn as waiting, the way a `[[link]]` to nothing is. A link card opens its
address.

**The second slice edits.** A double-tap on the page makes a card of words there, open with the keyboard up (choice
8), and the `+ Card` tool makes one mid-screen. A press held on a card lifts it and it goes where the finger goes,
put down to the pixel; a plain drag still pans, so a finger on a card never moves it by mistake. A double-tap on a
card of words opens it to be written in - its editor in the note's own mode, the words going straight into the
canvas - and a card open that way has a cross to take it off, which takes its lines with it. Every change is
written into the note as the spec's JSON with the front matter kept (`jsonCanvas.ts` `withCanvas`), saved the way
typing is, so a canvas edited in Glyph still opens in Obsidian. A canvas shown where it cannot be written - a card
on another canvas, a note not open - stays read-only.

The press-and-hold to move, the double-tap to open and the cross to take off were never put to Matt (the "not
asked" list below); they are the app's own conventions - a board's card and a tab are moved by a held press too -
chosen so one habit serves the whole app, and are his to change.

Not yet: drawing lines and labelling them, resizing a card, moving a group with its cards, the other three ways to
add a card (the dock's +, dragging a note in, by voice), item cards, zoom-to-card and the minimap, a canvas inside a
note, export, and the model's three moves (a gist on note cards, laying a note out as a canvas, suggesting lines).
Each is a slice of its own.
