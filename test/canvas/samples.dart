/// Canvases for the canvas's tests, each written once for the files that share it: `src/test/canvas.ts`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/json_canvas.dart';

/// For the format's tests: one of each node the JSON Canvas spec has, and two lines, as Obsidian writes them - a
/// group round three cards, a card of words with a preset colour, a note by its file with an anchor, a link with a
/// hex colour and a position that is not a whole pixel; a line with its sides and a label, and one with no head and
/// a colour.
const String specSample = '''{
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
}''';

/// For the view's tests: a group round a card of words, with a preset colour and a task, and a link with a hex
/// colour; a note by its file, with an anchor; and a note Ghost.md does not have. One line with words and one with
/// no head. The cards run from -20 to 500 across and -20 to 180 down, 520 by 200.
const String viewSample = r'''{
  "nodes": [
    { "id": "g", "type": "group", "x": -20, "y": -20, "width": 400, "height": 200, "label": "Before" },
    { "id": "t", "type": "text", "x": 0, "y": 0, "width": 200, "height": 80, "text": "# Book it\n\n- [ ] The cabin", "color": "4" },
    { "id": "f", "type": "file", "x": 300, "y": 0, "width": 200, "height": 80, "file": "Launch week.md", "subpath": "#^photos" },
    { "id": "n", "type": "file", "x": 300, "y": 100, "width": 200, "height": 80, "file": "Nowhere.md" },
    { "id": "l", "type": "link", "x": 0, "y": 100, "width": 200, "height": 80, "url": "https://attack.fm/glyph", "color": "#ff8800" }
  ],
  "edges": [
    { "id": "e1", "fromNode": "t", "toNode": "f", "label": "then" },
    { "id": "e2", "fromNode": "t", "toNode": "l", "toEnd": "none" }
  ]
}''';

/// `toMatchObject`: a record that holds at least these fields with these values.
Matcher holds(Map<String, Object?> fields) => predicate<Object?>((value) {
  if (value is! CanvasRecord) return false;
  for (final entry in fields.entries) {
    if (!value.fields.containsKey(entry.key) || value.fields[entry.key] != entry.value) return false;
  }
  return true;
}, 'a record holding $fields');

/// `toEqual({...})` for a node, an edge or a thread: exactly these fields, in any order.
Matcher isRecord(Map<String, Object?> fields) => predicate<Object?>((value) => value is CanvasRecord && sameJson(value.fields, fields), 'a record of exactly $fields');
