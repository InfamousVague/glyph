/// The example canvas, added from Settings the way the example board is: a note that is a working canvas, with one
/// of each thing a canvas holds (Matt: "make an example canvas with images, charts, tables, notes and lines
/// linking") - a group, cards of words, cards that are other notes, a link, a chart drawn from Mermaid, a table, a
/// picture, and lines between them with words on. A port of `src/app/canvas/sampleCanvas.ts`, written in JSON
/// Canvas exactly as Obsidian would write it, so it is also the file to hand to Obsidian to see the same thing.
///
/// The note cards point at the example board and the sample note by their titles: added together, tapping a card
/// opens the note. The picture is the sample note's own drawing, kept by the picture store when the canvas is made;
/// with no picture store to hand the canvas is made without it.
///
/// What differs: the two titles are written here ([boardTitle], [sampleTitle]) where the web read
/// `core/boardNote.ts` and `core/sampleNote.ts`, which have no ports that name them.
library;

import 'json_canvas.dart';

/// `CANVAS_TITLE`.
const String canvasTitle = 'Cabin weekend, laid out';

/// `BOARD_TITLE` (core/boardNote.ts) and `SAMPLE_TITLE` (core/sampleNote.ts).
const String boardTitle = 'Launch week';
const String sampleTitle = 'How to format a note';

Canvas sampleCanvas([String? picture]) {
  return Canvas(
    nodes: [
      // The plan, in a group on the left.
      CanvasNode.group(id: 'before', x: -40, y: -60, width: 640, height: 500, label: 'Before we go', color: '5'),
      CanvasNode.text(id: 'book', x: 0, y: 0, width: 260, height: 110, color: '4', text: '# Book the cabin\n\nBy Friday. The deposit is **200**.'),
      CanvasNode.text(id: 'pack', x: 320, y: 0, width: 260, height: 110, text: '- [ ] Snacks\n- [ ] A charger for the drive\n- [x] The good coffee'),
      CanvasNode.text(id: 'sam', x: 0, y: 160, width: 260, height: 90, color: '2', text: 'Ask Sam about the dog'),
      CanvasNode.text(id: 'kit', x: 320, y: 160, width: 260, height: 150, text: '| Who | Brings |\n| --- | --- |\n| Sam | The tent |\n| Ali | Food for Saturday |\n| Me | The car, and the coffee |'),
      CanvasNode.file(id: 'board', x: 0, y: 300, width: 260, height: 130, file: '$boardTitle.md'),
      CanvasNode.link(id: 'site', x: 320, y: 340, width: 260, height: 90, color: '5', url: 'https://attack.fm/glyph'),
      // The weekend itself, on the right: the days as a chart, and what it looks like.
      CanvasNode.text(
        id: 'days',
        x: 720,
        y: -40,
        width: 380,
        height: 220,
        color: '6',
        text: '```mermaid\nflowchart LR\n  F[Friday: drive up] --> S[Saturday: the lake]\n  S --> U[Sunday: the long walk]\n  U --> H[Home by dark]\n```\n',
      ),
      CanvasNode.text(id: 'there', x: 720, y: 220, width: 380, height: 110, color: '6', text: '# The weekend\n\nSaturday the lake, Sunday the long walk if it is dry. Nothing planned for the evenings.'),
      CanvasNode.file(id: 'marks', x: 720, y: 370, width: 380, height: 120, file: '$sampleTitle.md'),
      if (picture != null && picture.isNotEmpty) CanvasNode.file(id: 'view', x: 1160, y: 40, width: 320, height: 240, file: picture),
    ],
    edges: [
      CanvasEdge.of(id: 'e1', fromNode: 'book', toNode: 'pack', fromSide: Side.right, toSide: Side.left, label: 'then'),
      CanvasEdge.of(id: 'e2', fromNode: 'book', toNode: 'sam', fromSide: Side.bottom, toSide: Side.top),
      CanvasEdge.of(id: 'e3', fromNode: 'pack', toNode: 'kit', fromSide: Side.bottom, toSide: Side.top, color: '2', label: 'who brings what'),
      CanvasEdge.of(id: 'e4', fromNode: 'before', toNode: 'days', fromSide: Side.right, toSide: Side.left, label: 'and then'),
      CanvasEdge.of(id: 'e5', fromNode: 'sam', toNode: 'board', fromSide: Side.bottom, toSide: Side.top, toEnd: End.none),
      CanvasEdge.of(id: 'e6', fromNode: 'days', toNode: 'there', fromSide: Side.bottom, toSide: Side.top, color: '6'),
      CanvasEdge.of(id: 'e7', fromNode: 'there', toNode: 'marks', fromSide: Side.bottom, toSide: Side.top, toEnd: End.none, label: 'every mark, if you need one'),
      if (picture != null && picture.isNotEmpty) CanvasEdge.of(id: 'e8', fromNode: 'days', toNode: 'view', fromSide: Side.right, toSide: Side.left, label: 'the view'),
    ],
  );
}

String sampleCanvasBody([String? picture]) => canvasNoteBody(canvasTitle, sampleCanvas(picture));
