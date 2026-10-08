import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/edits.dart';
import 'package:ghost_md/canvas/js.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/canvas/lines.dart';

import 'samples.dart';

/// A canvas's lines as they are drawn: the curves, their heads, ends kept apart, and labels placed off the cards.
/// `src/app/canvas/lines.test.ts`, case for case.
void main() {
  group('a line drawn', () {
    final canvas = parseCanvas(specSample)!;

    test('draws an edge as a curve with an arrow at its end unless told otherwise, stopping short of the head', () {
      final e1 = edgePaths(canvas)['e1']!;
      expect(e1.d.startsWith('M250 30C'), isTrue);
      expect(e1.d.endsWith('${jsNumber(300 - head)} 60'), isTrue);
      expect(e1.toHead!.startsWith('M300 60'), isTrue);
      expect(e1.fromHead, isNull);
      expect(e1.mid.x, greaterThan(250));
      expect(e1.mid.x, lessThan(300));
      final e2 = edgePaths(canvas)['e2']!;
      expect(e2.toHead, isNull);
      expect(e2.d.endsWith('125 150'), isTrue);
      // A line to a card that is not there is not drawn.
      expect(edgePaths(Canvas(nodes: canvas.nodes, edges: [CanvasEdge.of(id: 'x', fromNode: 't1', toNode: 'nope')]))['x'], isNull);
    });

    test('draws a new line with an arrow at its end', () {
      final line = newEdge('f1', 'l1', 'ln');
      expect(edgePaths(withEdge(canvas, line))['ln']?.toHead, isNotNull);
    });
  });

  group('lines kept apart', () {
    CanvasNode card(String id, double x, double y, {double width = 300, double height = 200}) => CanvasNode.text(id: id, text: id, x: x, y: y, width: width, height: height);

    /// The tip of a head: the first point of its path.
    ({double x, double y}) tip(String? d) {
      final m = RegExp(r'^M([\d.-]+) ([\d.-]+)').firstMatch(d ?? '');
      if (m == null) throw StateError('no head in $d');
      return (x: double.parse(m.group(1)!), y: double.parse(m.group(2)!));
    }

    CanvasEdge edge(String id, String from, String to, {Side? fromSide, Side? toSide, End? toEnd, String? label}) =>
        CanvasEdge.of(id: id, fromNode: from, toNode: to, fromSide: fromSide, toSide: toSide, toEnd: toEnd, label: label);

    test('sets two lines into one side of a card apart along it, in the order their far ends come', () {
      final canvas = Canvas(nodes: [card('a', 0, 0), card('b', 0, 400), card('c', 500, 200)], edges: [edge('e1', 'a', 'c'), edge('e2', 'b', 'c')]);
      final paths = edgePaths(canvas);
      final one = tip(paths['e1']?.toHead);
      final two = tip(paths['e2']?.toHead);
      // Both on c's left side (x 500, middle y 300): the line from above lands above, the one from below below.
      expect(one.x, 500);
      expect(two.x, 500);
      expect(one.y, 300 - endSpread / 2);
      expect(two.y, 300 + endSpread / 2);
      // Alone, a line lands on the middle as before.
      expect(tip(edgePaths(Canvas(nodes: canvas.nodes, edges: [canvas.edges[0]]))['e1']?.toHead), (x: 500.0, y: 300.0));
    });

    test('moves two heads apart that would meet across the gap between neighbouring cards', () {
      final canvas = Canvas(
        nodes: [card('left', 0, 0), card('right', 340, 0), card('up', 0, -600), card('over', 340, -600)],
        edges: [edge('e1', 'up', 'left', fromSide: Side.bottom, toSide: Side.right), edge('e2', 'over', 'right', fromSide: Side.bottom, toSide: Side.left)],
      );
      final paths = edgePaths(canvas);
      final one = tip(paths['e1']?.toHead);
      final two = tip(paths['e2']?.toHead);
      expect(one.x, 300);
      expect(two.x, 340);
      // Neither is at the middle any more, and they are a clear width apart.
      expect(one.y, isNot(100));
      expect(two.y, isNot(100));
      expect(jsHypot(one.x - two.x, one.y - two.y), greaterThanOrEqualTo(headClear - 0.01));
      // Each still on its own side.
      expect(one.y, greaterThan(0));
      expect(one.y, lessThan(200));
      expect(two.y, greaterThan(0));
      expect(two.y, lessThan(200));
    });

    test('sits a label over open canvas rather than over a card, and in the middle when there is nowhere else', () {
      // A straight line from a to c at y 100, with b sitting on it where the middle would be.
      final a = card('a', 0, 0);
      final c = card('c', 800, 0);
      const label = 'over';
      final clear = edgePaths(Canvas(nodes: [a, c, card('b', 450, 0, width: 200)], edges: [edge('e', 'a', 'c', label: label)]))['e']!;
      // Off b (450-650) and off a (to 300): the first try along the curve that is.
      expect(clear.mid.y, closeTo(100, 1e-5));
      expect(clear.mid.x + 20, lessThan(450));
      expect(clear.mid.x - 20, greaterThan(300));
      // A group is open canvas: a label may sit over one, at the curve's middle (the curve runs from a's side at 300
      // to the base of the head at 790, so its middle is 545).
      final group = CanvasNode.group(id: 'g', x: 300, y: -100, width: 500, height: 400);
      expect(edgePaths(Canvas(nodes: [a, c, group], edges: [edge('e', 'a', 'c', label: label)]))['e']!.mid.x, closeTo(545, 1e-5));
      // A card under the whole line: the middle, as it was, on one line.
      final wall = card('b', 320, 0, width: 460);
      final nowhere = edgePaths(Canvas(nodes: [a, c, wall], edges: [edge('e', 'a', 'c', label: label)]))['e']!;
      expect(nowhere.mid.x, closeTo(545, 1e-5));
      expect(nowhere.lines, [label]);
      // No label: no lines.
      expect(edgePaths(Canvas(nodes: [a, c], edges: [edge('e', 'a', 'c')]))['e']!.lines, isEmpty);
    });

    test('breaks a label onto two lines where one line would not fit down the gap between two cards', () {
      final a = card('a', 0, 0);
      final c = card('c', 420, 0);
      const label = 'every mark a note can hold';
      final placed = edgePaths(Canvas(nodes: [a, c], edges: [edge('e', 'a', 'c', label: label, toEnd: End.none)]))['e']!;
      expect(placed.lines, ['every mark a', 'note can hold']);
      // Down the gap: the box of the widest line clear of both cards.
      const half = (13 * 6.8 + 8) / 2;
      expect(placed.mid.x - half, greaterThan(300));
      expect(placed.mid.x + half, lessThan(420));
    });

    test('breaks words into lines of about equal length, never inside a word', () {
      expect(brokenInto('every mark a note can hold', 1), ['every mark a note can hold']);
      expect(brokenInto('every mark a note can hold', 2), ['every mark a', 'note can hold']);
      expect(brokenInto('every mark a note can hold', 3), ['every mark', 'a note', 'can hold']);
      expect(brokenInto('one', 3), ['one']);
      expect(brokenInto('  ', 2), isEmpty);
    });

    test('packs the ends on a side too short for the spread, and keeps them off its corners', () {
      // c's left side is 60px long: three ends cannot be endSpread apart on it, and none may come within 16px of a corner.
      final canvas = Canvas(
        nodes: [card('a', 0, 0), card('b', 0, 300), card('d', 0, 600), card('c', 500, 270, height: 60)],
        edges: [for (final from in ['a', 'b', 'd']) edge(from, from, 'c')],
      );
      final paths = edgePaths(canvas);
      final ys = [for (final id in ['a', 'b', 'd']) tip(paths[id]!.toHead).y];
      // In the order their far ends come, top to bottom, evenly about the middle and no nearer a corner than 16px.
      expect(ys, [286, 300, 314]);
      for (final y in ys) {
        expect(y, greaterThanOrEqualTo(270 + 16));
        expect(y, lessThanOrEqualTo(330 - 16));
      }
    });

    test('breaks a label onto three lines where two will not fit down the gap', () {
      const label = 'the long way round the lake';
      final placed = edgePaths(Canvas(nodes: [card('a', 0, 0), card('c', 390, 0)], edges: [edge('e', 'a', 'c', label: label, toEnd: End.none)]))['e']!;
      expect(placed.lines, hasLength(3));
      expect(placed.lines.join(' '), label);
    });
  });
}
