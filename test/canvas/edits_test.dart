import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/edits.dart';
import 'package:ghost_md/canvas/json_canvas.dart';

import 'samples.dart';

/// Making and changing a canvas: cards and lines added, moved, resized, named and taken off, each a new canvas.
/// `src/app/canvas/edits.test.ts`, case for case.
void main() {
  List<double> box(CanvasNode n) => [n.x, n.y, n.width, n.height];
  List<Object> placed(Canvas canvas) => [
    for (final n in canvas.nodes) [n.id, n.x, n.y],
  ];

  group('changing a canvas', () {
    final canvas = parseCanvas(specSample)!;

    test('adds a card, moves it to the pixel, replaces it, and takes it out with its lines', () {
      final card = newTextNode(10.4, 20.6, 'abc');
      expect(card, holds({'id': 'abc', 'type': 'text', 'x': 10, 'y': 21, 'text': ''}));
      final added = withNode(canvas, card);
      expect(added.nodes.last, same(card));
      final moved = withNode(added, movedNode(card, 99.7, -3.2));
      expect(moved.nodes.length, added.nodes.length);
      expect(moved.nodes.last, holds({'id': 'abc', 'x': 100, 'y': -3}));
      // t1 has two edges; both go with it, and nothing else does.
      final gone = withoutNode(canvas, 't1');
      expect(gone.nodes.map((n) => n.id), ['g1', 'f1', 'l1']);
      expect(gone.edges, isEmpty);
    });

    test('names a new node the way Obsidian does: sixteen hex characters, never the same twice', () {
      final ids = {for (var n = 0; n < 50; n += 1) newCanvasId()};
      expect(ids.length, 50);
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
      }
    });
  });

  group('lines between cards', () {
    final canvas = parseCanvas(specSample)!;

    test('makes a new line from one card to another, adds it last, and takes it off again', () {
      final line = newEdge('f1', 'l1', 'ln');
      expect(line, isRecord({'id': 'ln', 'fromNode': 'f1', 'toNode': 'l1'}));
      final added = withEdge(canvas, line);
      expect(added.edges.last, same(line));
      expect(withoutEdge(added, 'ln').edges, canvas.edges);
      // Read back through the spec, it is the same line.
      expect(parseCanvas(serializeCanvas(added))?.edges.last, line);
    });

    test('labels a line, replaces the label, and takes it off with blank', () {
      final line = newEdge('f1', 'l1', 'ln');
      expect(labelledEdge(line, '  then  ').label, 'then');
      expect(labelledEdge(labelledEdge(line, 'then'), 'after'), holds({'label': 'after'}));
      expect(labelledEdge(labelledEdge(line, 'then'), '   ').fields.containsKey('label'), isFalse);
      expect(withEdge(canvas, labelledEdge(canvas.edges[0], 'later')).edges[0], holds({'id': 'e1', 'label': 'later'}));
    });

    test('knows when two cards are already joined, either way round', () {
      expect(joined(canvas, 't1', 'f1'), isTrue);
      expect(joined(canvas, 'f1', 't1'), isTrue);
      expect(joined(canvas, 'f1', 'l1'), isFalse);
    });
  });

  group('sizes and groups', () {
    final canvas = parseCanvas(specSample)!;

    test('resizes a card to the pixel and never smaller than a word and a cross', () {
      final t1 = canvas.nodeOf('t1')!;
      expect(resizedNode(t1, 300.4, 80.6), holds({'x': 0, 'y': 0, 'width': 300, 'height': 81}));
      expect(resizedNode(t1, 10, 10), holds({'width': 120, 'height': 60}));
    });

    test('moves a group with everything wholly inside it, and a card on its own', () {
      final g1 = canvas.nodeOf('g1')!;
      // g1 is -40,-40 600x300: t1 (0,0 250x60) and f1 (300,0 250x120) are inside; l1 (0,150 250x80) is inside too.
      expect(heldBy(canvas, g1).map((n) => n.id), ['t1', 'f1', 'l1']);
      final moved = movedWithHeld(canvas, g1, 60, -40);
      expect(placed(moved), [
        ['g1', 60, -40],
        ['t1', 100, 0],
        ['f1', 400, 0],
        ['l1', 100, 150],
      ]);
      final alone = movedWithHeld(canvas, canvas.nodeOf('t1')!, 20, 20);
      expect(placed(alone), [
        ['g1', -40, -40],
        ['t1', 20, 20],
        ['f1', 300, 0],
        ['l1', 0, 150],
      ]);
    });

    test('names a group, and takes the name off with blank; a card that is not a group has no name to take', () {
      final g1 = canvas.nodeOf('g1')!;
      expect(labelledGroup(g1, '  ').fields.containsKey('label'), isFalse);
      expect(labelledGroup(g1, ' Plans '), holds({'id': 'g1', 'label': 'Plans'}));
      final t1 = canvas.nodeOf('t1')!;
      expect(labelledGroup(t1, 'Plans'), same(t1));
    });
  });

  group('note and link cards made', () {
    test('names a note card by its title as a file, and gives a bare address https', () {
      expect(newFileNode('Cabin trip', 10.4, 20, 'f'), holds({'id': 'f', 'type': 'file', 'file': 'Cabin trip.md', 'x': 10, 'y': 20}));
      expect(newFileNode('  ', 0, 0, 'f'), holds({'file': 'Untitled.md'}));
      expect(newFileNode('Plans/Cabin', 0, 0, 'f'), holds({'file': 'Plans-Cabin.md'}));
      expect(newLinkNode('attack.fm/glyph', 0, 0, 'l'), holds({'type': 'link', 'url': 'https://attack.fm/glyph'}));
      expect(newLinkNode('https://x.y', 0, 0, 'l'), holds({'url': 'https://x.y'}));
      expect(newLinkNode('mailto:a@b.c', 0, 0, 'l'), holds({'url': 'mailto:a@b.c'}));
      expect(newLinkNode('   ', 0, 0), isNull);
    });
  });

  group('pictures, charts and tables', () {
    test('makes a picture card by the store name, and starts a chart and a table as what they are', () {
      expect(newPictureNode('abc.jpg', 5.5, 6, 'p'), holds({'id': 'p', 'type': 'file', 'file': 'abc.jpg', 'x': 6, 'y': 6, 'height': 200}));
      expect(chartCard.startsWith('```mermaid\n'), isTrue);
      expect(tableCard.split('\n')[1], '| --- | --- |');
    });
  });

  group('the picked card’s edits', () {
    final card = CanvasNode.text(id: 'c', x: 100, y: 100, width: 200, height: 100, text: 'x');

    test('resizes by a corner or a side, the far sides staying where they are', () {
      expect(box(resizedBy(card, Handle.se, 40, 20)), [100, 100, 240, 120]);
      expect(box(resizedBy(card, Handle.nw, -40, -20)), [60, 80, 240, 120]);
      expect(box(resizedBy(card, Handle.ne, 40, -20)), [100, 80, 240, 120]);
      expect(box(resizedBy(card, Handle.sw, -40, 20)), [60, 100, 240, 120]);
      // A side moves alone, whatever the pointer does across it.
      expect(box(resizedBy(card, Handle.e, 40, 900)), [100, 100, 240, 100]);
      expect(box(resizedBy(card, Handle.n, 900, -20)), [100, 80, 200, 120]);
      // To the pixel.
      expect(box(resizedBy(card, Handle.se, 10.6, 0.4)), [100, 100, 211, 100]);
    });

    test('stops at the least size, and the card does not slide once it has', () {
      expect(box(resizedBy(card, Handle.se, -900, -900)), [100, 100, leastCard.width, leastCard.height]);
      // From the top left, the bottom-right corner (300, 200) is the one that stays.
      expect(box(resizedBy(card, Handle.nw, 900, 900)), [300 - leastCard.width, 200 - leastCard.height, leastCard.width, leastCard.height]);
    });

    test('copies a card a step aside under a new id, and steps again past a copy already there', () {
      final canvas = Canvas(nodes: [card], edges: const []);
      final copy = duplicated(canvas, card, 'd1');
      expect(copy, card.put({'id': 'd1', 'x': 124, 'y': 124}));
      final again = duplicated(Canvas(nodes: [card, copy], edges: const []), card, 'd2');
      expect([again.x, again.y], [148, 148]);
    });

    test('finds a spot clear of every card’s corner, and leaves a clear one alone', () {
      final canvas = Canvas(nodes: [card], edges: const []);
      expect(clearSpot(canvas, 400, 400), (x: 400.0, y: 400.0));
      expect(clearSpot(canvas, 100, 100), (x: 100 + stepAside, y: 100 + stepAside));
      // A group's corner is not a card's: a card may start in the corner of a group.
      expect(clearSpot(Canvas(nodes: [CanvasNode.group(id: 'g', x: 0, y: 0, width: 500, height: 500)], edges: const []), 0, 0), (x: 0.0, y: 0.0));
    });

    test('colours with a preset and takes the colour off, leaving no empty field', () {
      expect(colouredNode(card, '5'), card.put({'color': '5'}));
      expect(colouredNode(card.put({'color': '5'}), null).fields.containsKey('color'), isFalse);
    });

    test('makes a group about a card with room round it, or a box of its own, and puts it under the cards', () {
      expect(newGroupNode(card, 0, 0, 'g'), isRecord({'id': 'g', 'type': 'group', 'x': 100 - groupRoom, 'y': 100 - groupRoom, 'width': 200 + groupRoom * 2, 'height': 100 + groupRoom * 2}));
      final own = newGroupNode(null, 10.4, 20.6, 'g');
      expect(own, isRecord({'id': 'g', 'type': 'group', 'x': 10, 'y': 21, 'width': 480, 'height': 320}));
      expect(withGroup(Canvas(nodes: [card], edges: const []), own).nodes.map((n) => n.id), ['g', 'c']);
      // The card it was made about is held by it, so it moves with it.
      final about = newGroupNode(card, 0, 0, 'g');
      expect(heldBy(Canvas(nodes: [about, card], edges: const []), about).map((n) => n.id), ['c']);
    });
  });

  group('the grid', () {
    test('is the dots, 24 apart from the canvas’s own corner, and a place goes to the nearest', () {
      expect(grid, 24);
      expect([onGrid(0), onGrid(11), onGrid(12), onGrid(-11), onGrid(-13), onGrid(331)], [0, 0, 24, -0, -24, 336]);
      // A half goes up, as JavaScript rounds one: -12 is half a square back, and lands on 0, not -24.
      expect(onGrid(-12), 0);
      expect(atDot(331, 143), (x: 336.0, y: 144.0));
    });

    test('snaps the sides a handle moves, and brings a card that was off the grid onto it side by side', () {
      final off = CanvasNode.text(id: 'c', x: 100, y: 100, width: 200, height: 100, text: 'x');
      // The right side was at 300: out by 10 it is 310, whose line is 312. The left side, not held, stays at 100.
      expect(box(resizedBy(off, Handle.e, 10, 0, true)), [100, 100, 212, 100]);
      // The top-left corner goes to 96,96; the far corner (300,200) stays.
      expect(box(resizedBy(off, Handle.nw, -3, -3, true)), [96, 96, 204, 104]);
      // Never smaller than the least, snapped or not: the side stops there.
      expect(box(resizedBy(off, Handle.e, -900, 0, true)), [100, 100, 120, 100]);
      // Without snapping, to the pixel as before.
      expect(box(resizedBy(off, Handle.e, 10, 0)), [100, 100, 210, 100]);
    });
  });
}
