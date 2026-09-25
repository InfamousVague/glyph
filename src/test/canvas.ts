/**
 * A canvas for the canvas's tests (src/app/canvas/*.test.ts): one of each node the JSON Canvas spec has, and two
 * lines, as Obsidian writes them - a group round three cards, a card of words with a preset colour, a note by its
 * file with an anchor, a link with a hex colour and a position that is not a whole pixel; a line with its sides and
 * a label, and one with no head and a colour. The format, the edits and the lines are each tested against it, so it
 * is written once.
 */
export const SPEC_SAMPLE = `{
  "nodes": [
    { "id": "g1", "type": "group", "x": -40, "y": -40, "width": 600, "height": 300, "label": "Before" },
    { "id": "t1", "type": "text", "x": 0, "y": 0, "width": 250, "height": 60, "text": "# Book the cabin", "color": "4" },
    { "id": "f1", "type": "file", "x": 300, "y": 0, "width": 250, "height": 120, "file": "Plans/Cabin trip.md", "subpath": "#^friday" },
    { "id": "l1", "type": "link", "x": 0, "y": 150.4, "width": 250, "height": 80, "url": "https://attack.fm/glyph", "color": "#ff8800" }
  ],
  "edges": [
    { "id": "e1", "fromNode": "t1", "toNode": "f1", "fromSide": "right", "toSide": "left", "label": "then" },
    { "id": "e2", "fromNode": "t1", "toNode": "l1", "toEnd": "none", "color": "2" }
  ]
}`;
