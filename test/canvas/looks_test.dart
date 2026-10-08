import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/card_looks.dart';
import 'package:ghost_md/canvas/edits.dart';
import 'package:ghost_md/canvas/how_canvas.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/canvas/map_detail.dart';
import 'package:ghost_md/canvas/sample_canvas.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

/// What the screen makes of a card, what it looks like small, and the two example canvases:
/// `src/app/canvas/cardLooks.test.ts`, `mapDetail.test.ts`, `sampleCanvas.test.ts` and `howCanvas.test.ts`, case
/// for case. One case of the last is not here: "names marks the recorder reads as cues" renders each cue through
/// `capture/markdown.ts`, which is stage 8's.
void main() {
  group('colour and names', () {
    test('paints the six presets as the page’s hues and keeps a chosen hex as it is', () {
      expect(['1', '2', '3', '4', '5', '6'].map((c) => paintOf(c)?.hue?.name), ['rose', 'ember', 'amber', 'moss', 'sea', 'violet']);
      expect(paintOf('#ff8800'), const CardPaint.hex('#ff8800'));
      expect(paintOf(null), isNull);
    });

    test('names a file node by its file, without the folder or the .md', () {
      expect(fileTitle('Plans/Cabin trip.md'), 'Cabin trip');
      expect(fileTitle('Cabin trip'), 'Cabin trip');
      expect(fileTitle('photos/tent.JPG'), 'tent.JPG');
    });

    test('wears a preset as the page’s hue and a hex as the card’s own colour, and nothing for no colour', () {
      // `paintProps`, which here is `paintOf` again: what a widget wears is read from it (paint.dart).
      expect(paintOf('4'), const CardPaint.hue(CanvasHue.moss));
      expect(paintOf('#ff8800')?.hex, '#ff8800');
      expect(paintOf(null), isNull);
      expect(paintOf('9'), isNull);
    });

    test('knows one of Ghost.md’s own pictures by a picture name with no folder, and nothing else as one', () {
      CanvasNode file(String name) => CanvasNode.file(id: 'f', file: name, x: 0, y: 0, width: 10, height: 10);
      expect(ownPicture(file('abc.jpg')), 'abc.jpg');
      expect(ownPicture(file('Pictures/abc.jpg')), isNull);
      expect(ownPicture(file('Cabin trip.md')), isNull);
      expect(ownPicture(CanvasNode.text(id: 't', text: 'abc.jpg', x: 0, y: 0, width: 10, height: 10)), isNull);
    });
  });

  group('a card that is only a table', () {
    test('knows a table from words with a table in them', () {
      expect(isOnlyTable(tableCard), isTrue);
      expect(isOnlyTable('| a | b |\n| - | - |\n| 1 | 2 |'), isTrue);
      expect(isOnlyTable('# Prices\n\n| a | b |\n| - | - |'), isFalse);
      expect(isOnlyTable('| just one line |'), isFalse);
      expect(isOnlyTable(''), isFalse);
    });
  });

  group('a card’s words on the map', () {
    test('draws a heading heavier, a list’s line as a dot and a bar, and a paragraph as the lines it wraps to', () {
      final bars = wordBars('# Plan\n\n- [ ] One thing\n\nA paragraph long enough that it runs on to a second line of the card.', 260, 220);
      expect([bars[0].x, bars[0].y, bars[0].strong], [14, 14, true]);
      // The list's line: a square dot, then its words set in from it.
      expect([bars[1].x, bars[1].width, bars[1].height], [14, 8, 8]);
      expect(bars[2].x, 30);
      expect(bars[2].y, bars[1].y);
      // The paragraph: full lines, then what is left over, shorter.
      expect([bars[3].width, bars[4].width], [232, 232]);
      expect(bars[5].width, lessThan(232));
      expect(bars[4].y - bars[3].y, 20);
      expect(bars, hasLength(6));
    });

    test('draws a table as its rows, the card’s width, and nothing for the rule under its head or a fence’s own lines', () {
      expect(wordBars('| a | b |\n| --- | --- |\n| 1 | 2 |', 200, 120).map((b) => b.width), [172, 172]);
      expect(wordBars('```mermaid\nflowchart LR\n```', 200, 120), hasLength(1));
    });

    test('stops at the card’s foot, and draws nothing in a card too small to hold a line', () {
      final many = [for (var n = 0; n < 40; n += 1) 'line $n'].join('\n');
      final bars = wordBars(many, 200, 100);
      expect(bars.length, 4);
      expect(bars.map((b) => b.y + b.height).reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(93));
      expect(wordBars('words', 40, 100), isEmpty);
      // And never more than a page's worth, however tall the card.
      expect(wordBars(many, 200, 4000).length, lessThanOrEqualTo(28));
    });

    test('draws a note as its title and what fits of a few lines under it', () {
      final bars = noteBars('Launch week', 200, 80);
      expect(bars.map((b) => b.strong), [true, false, false]);
      expect(noteBars('Launch week', 200, 30), isEmpty);
    });
  });

  group('the screen’s box on the map', () {
    test('is a closed path with round corners, no rounder than the box allows', () {
      expect(roundedBox(10, 20, 100, 50, 5), 'M15 20h90a5 5 0 0 1 5 5v40a5 5 0 0 1 -5 5h-90a5 5 0 0 1 -5 -5v-40a5 5 0 0 1 5 -5Z');
      // A box smaller than twice the round is a pill, not a knot.
      expect(roundedBox(0, 0, 6, 20, 5), contains('a3 3'));
    });
  });

  group('the example canvas', () {
    test('holds one of everything: a group, words, notes, a link, a chart, a table, a picture, and lines with words', () {
      final canvas = sampleCanvas('view.jpg');
      final kinds = canvas.nodes.map((n) => n.type).toList();
      expect(kinds.where((k) => k == NodeType.group).length, 1);
      expect(kinds.where((k) => k == NodeType.file).length, 3);
      expect(kinds.where((k) => k == NodeType.link).length, 1);
      final words = canvas.nodes.where((n) => n.type == NodeType.text).toList();
      expect(words.any((n) => n.text.startsWith('```mermaid')), isTrue);
      expect(words.any((n) => isOnlyTable(n.text)), isTrue);
      expect(canvas.nodeOf('view')?.type, NodeType.file);
      expect(canvas.nodeOf('view')?.file, 'view.jpg');
      expect(canvas.edges.length, 8);
      expect(canvas.edges.where((e) => e.label != null).length, greaterThanOrEqualTo(4));
      // Every line joins two cards that are there.
      final ids = {for (final n in canvas.nodes) n.id};
      for (final e in canvas.edges) {
        expect(ids.contains(e.fromNode) && ids.contains(e.toNode), isTrue);
      }
    });

    test('is made without the picture where none could be drawn, and reads back through the spec unchanged', () {
      final plain = sampleCanvas();
      expect(plain.nodeOf('view'), isNull);
      expect(plain.edges.length, 7);
      expect(parseCanvas(serializeCanvas(plain)), plain);
      final body = sampleCanvasBody('view.jpg');
      expect(noteTitle(body), canvasTitle);
      expect(canvasOf(body), sampleCanvas('view.jpg'));
    });
  });

  group('the canvas that says how Ghost.md works', () {
    test('is eight plain cards in a group, opening the example board and the sample note, with the order on the lines', () {
      final canvas = howCanvas();
      final cards = canvas.nodes.where((n) => !n.isGroup).toList();
      expect(canvas.nodes.where((n) => n.isGroup), hasLength(1));
      expect(cards, hasLength(8));
      expect([for (final n in cards) if (n.type == NodeType.file) n.file], ['$boardTitle.md', '$sampleTitle.md']);
      // Every line joins two cards that are there, and the first three tell the order of saying.
      final ids = {for (final n in canvas.nodes) n.id};
      for (final edge in canvas.edges) {
        expect(ids.contains(edge.fromNode), isTrue);
        expect(ids.contains(edge.toNode), isTrue);
      }
      expect([for (final e in canvas.edges.take(2)) [e.fromNode, e.toNode]], [
        ['speak', 'marks'],
        ['marks', 'note'],
      ]);
      // Said simply: no card runs past a few lines, and none of them is a chart or a table.
      for (final card in cards) {
        if (card.type != NodeType.text) continue;
        expect(card.text.length, lessThan(160));
        expect(card.text, isNot(matches(RegExp(r'```|\|'))));
      }
    });

    test('is a canvas note under its own title, and comes back the same from the file', () {
      final body = howCanvasBody();
      expect(noteTitle(body), howTitle);
      expect(canvasOf(body), howCanvas());
      expect(parseCanvas(serializeCanvas(howCanvas())), howCanvas());
    });

    test('names the button the home page draws, the microphone', () {
      expect(howCanvas().nodeOf('speak')!.text, contains('**microphone**'));
      expect(serializeCanvas(howCanvas()), isNot(matches(RegExp(r'Speak\*\*'))));
    });
  });
}
