import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/geometry.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/canvas/viewport.dart';

import 'samples.dart';

/// Where a canvas's cards are, and the view maths the canvas moves by: `src/app/canvas/geometry.test.ts` and
/// `viewport.test.ts`, case for case.
void main() {
  group('where things are', () {
    final canvas = parseCanvas(specSample)!;

    test('bounds every node, and an empty canvas has none', () {
      expect(bounds(canvas), const BoxOf(-40, -40, 600, 300));
      expect(bounds(Canvas(nodes: const [], edges: const [])), isNull);
    });

    test('anchors an edge on the middle of a side', () {
      const box = BoxOf(10, 20, 100, 50);
      expect(anchorOf(box, Side.top), (x: 60.0, y: 20.0));
      expect(anchorOf(box, Side.right), (x: 110.0, y: 45.0));
      expect(anchorOf(box, Side.bottom), (x: 60.0, y: 70.0));
      expect(anchorOf(box, Side.left), (x: 10.0, y: 45.0));
    });

    test('picks the sides that face each other when the edge does not say, and keeps the ones it does', () {
      const left = BoxOf(0, 0, 100, 100);
      const right = BoxOf(400, 20, 100, 100);
      const below = BoxOf(20, 400, 100, 100);
      expect(sidesOf(left, right), (from: Side.right, to: Side.left));
      expect(sidesOf(right, left), (from: Side.left, to: Side.right));
      expect(sidesOf(left, below), (from: Side.bottom, to: Side.top));
      expect(sidesOf(left, below, fromSide: Side.right), (from: Side.right, to: Side.top));
    });

    test('faces across rather than down when two cards are as far apart each way', () {
      const a = BoxOf(0, 0, 100, 100);
      const b = BoxOf(200, 200, 100, 100);
      expect(sidesOf(a, b), (from: Side.right, to: Side.left));
      expect(sidesOf(b, a), (from: Side.left, to: Side.right));
    });
  });

  final canvas = parseCanvas(viewSample)!;

  group('fitting the canvas to the screen', () {
    test('scales the whole canvas into the screen with room around it, no larger than life, centred', () {
      final view = fitted(canvas, 1000, 600);
      // The cards run from -20 to 500 across and -20 to 180 down: 520 by 200, which fits a 1000 by 600 screen at life size.
      expect(view.scale, 1);
      expect(view.x, (1000 - 520) / 2 + 20);
      expect(view.y, (600 - 200) / 2 + 20);
      // Too wide for 300 by 300: the cards' 520 fill the 236 between the room, and sit centred down the screen.
      final small = fitted(canvas, 300, 300);
      expect(small.scale, closeTo((300 - 64) / 520, 1e-5));
      expect(small.x - 20 * small.scale, closeTo(32, 1e-5));
      expect(small.y - 20 * small.scale, closeTo((300 - 200 * small.scale) / 2, 1e-5));
      expect(fitted(Canvas(nodes: const [], edges: const []), 300, 300), const CameraView(x: 32, y: 32, scale: 1));
    });

    test('has room and life size for a screen with no size yet, and for a card with none', () {
      expect(fitted(canvas, 0, 600), const CameraView(x: 32, y: 32, scale: 1));
      expect(fittedTo(const BoxOf(5, 5, 10, 10), 400, -1), const CameraView(x: 32, y: 32, scale: 1));
      // A card of no size is a point: centred, at life size, not scaled up without end.
      final point = Canvas(nodes: [CanvasNode.text(id: 'p', text: '', x: 10, y: 20, width: 0, height: 0)], edges: const []);
      expect(fitted(point, 400, 300), const CameraView(x: 190, y: 130, scale: 1));
    });

    test('never goes smaller than a tenth or larger than three times life', () {
      expect(fittedTo(const BoxOf(0, 0, 1000000, 10), 400, 300).scale, 0.1);
      expect(clampScale(99), 3);
      expect(clampScale(0.001), 0.1);
      expect(clampScale(1.5), 1.5);
    });
  });

  group('zooming and what the screen shows', () {
    test('zooms about a point of the screen, keeping what was under it under it', () {
      const view = CameraView(x: 100, y: 50, scale: 1);
      // The canvas point under (300, 250) is (200, 200); at double size it must still be at (300, 250).
      final doubled = zoomedAt(view, 300, 250, 2);
      expect(doubled, const CameraView(x: 300 - 200 * 2, y: 250 - 200 * 2, scale: 2));
      expect(zoomedAt(view, 0, 0, 99).scale, 3);
      expect(zoomedAt(view, 0, 0, 0.001).scale, 0.1);
    });

    test('fits a card to the screen no larger than life, and reports the box the screen shows', () {
      final view = fittedTo(const BoxOf(100, 50, 200, 80), 400, 300);
      expect(view.scale, 1);
      expect(view, const CameraView(x: 0, y: 60, scale: 1));
      final small = fittedTo(const BoxOf(0, 0, 2000, 1000), 400, 300);
      expect(small.scale, closeTo(0.168, 1e-3));
      expect(shown(const CameraView(x: -100, y: -50, scale: 0.5), 400, 300), const BoxOf(200, 100, 800, 600));
    });
  });
}
