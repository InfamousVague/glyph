# Canvases

A canvas is cards on an infinite page with lines between them: the thing Obsidian calls a canvas, in Glyph. Matt
(2026-09-20): "we're going to build something similar for Glyph". His fifteen choices steer it; this is the standard
they set, and it will grow as the slices land.

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

Not yet: making and moving cards, drawing lines, editing a card's words, a canvas inside a note, a home card drawn
as a thumbnail, export as a picture or PDF, and the model's three moves (a gist on note cards, laying a note out as
a canvas, suggesting lines). Each is a slice of its own.
