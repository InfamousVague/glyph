import 'dart:typed_data';
import 'dart:ui' as ui show ImageByteFormat;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/camera.dart';
import 'package:ghost_md/canvas/paint.dart';
import 'package:ghost_md/canvas/viewport.dart';
import 'package:ghost_md/canvas/world.dart';

import '../support/render.dart';
import 'view_support.dart';

/// What a canvas builds and draws again, and when (lib/canvas/canvas_view.dart `_card`, world.dart, card.dart): a
/// pan or a pinch sets the cards down again and draws none of them; a card carried is the one card built and
/// drawn; a card wholly off the screen is not set down; and a line's path is read from its string once. Counted,
/// not timed, so it says the same on a busy machine.
void main() {
  setUpAll(loadAppFonts);
  const mouse = PointerDeviceKind.mouse;

  Widget cardOf(WidgetTester tester, String id) => tester.widget(find.byKey(ValueKey('card $id')));
  RenderRepaintBoundary layerOf(WidgetTester tester, String id) => tester.renderObject<RenderRepaintBoundary>(find.byKey(ValueKey('card $id')));
  RenderCanvasWorld worldOf(WidgetTester tester) => tester.renderObject<RenderCanvasWorld>(find.byType(CanvasWorld));

  /// How many times each card's own layer has been drawn, and set down without being drawn.
  Map<String, (int drawn, int set)> counts(WidgetTester tester, Iterable<String> ids) => {
    for (final id in ids) id: (layerOf(tester, id).debugSymmetricPaintCount, layerOf(tester, id).debugAsymmetricPaintCount),
  };

  const ids = ['g', 't', 'f', 'n', 'l'];

  testWidgets('a pan and a pinch build no card and draw none: each is set down where the camera has it', (tester) async {
    final shown = Shown(tester);
    await shown.show();
    final before = {for (final id in ids) id: cardOf(tester, id)};
    for (final id in ids) {
      layerOf(tester, id).debugResetMetrics();
    }
    // A finger on the open page pans it; then the view a third closer.
    await shown.drag([const Offset(700, 500), const Offset(690, 480), const Offset(660, 430)]);
    shown.state.camera.zoomBy(1.3);
    await tester.pump();
    expect(shown.view == home, isFalse, reason: 'the view moved');
    for (final id in ids) {
      expect(identical(cardOf(tester, id), before[id]), isTrue, reason: 'card $id was not built again');
    }
    final after = counts(tester, ids);
    for (final id in ids) {
      expect(after[id]!.$1, 0, reason: 'card $id was not drawn again');
      expect(after[id]!.$2, greaterThan(0), reason: 'card $id was set down again');
    }
    await shown.done();
  });

  testWidgets('a card carried is the one card built and drawn, and the note handing the canvas back builds none', (tester) async {
    final shown = Shown(tester);
    await shown.show();
    final before = {for (final id in ids) id: cardOf(tester, id)};
    for (final id in ids) {
      layerOf(tester, id).debugResetMetrics();
    }
    // A mouse drags card n, with no hold.
    final gesture = await tester.startGesture(const Offset(350, 150), kind: mouse);
    await gesture.moveTo(const Offset(380, 190));
    await tester.pump();
    expect(shown.state.lifted, 'n');
    // Lifted, it is built once (its shadow, a little larger); from there each move sets its box down somewhere
    // else, and nothing of the box is built or drawn again.
    final lifted = cardOf(tester, 'n') as Placed;
    final at = shown.node('n');
    layerOf(tester, 'n').debugResetMetrics();
    await gesture.moveTo(const Offset(390, 200));
    await tester.pump();
    await gesture.moveTo(const Offset(420, 260));
    await tester.pump();
    expect(shown.state.lifted, 'n');
    for (final id in ids.where((id) => id != 'n')) {
      expect(identical(cardOf(tester, id), before[id]), isTrue, reason: 'card $id was not built again while n was carried');
      expect(layerOf(tester, id).debugSymmetricPaintCount, 0, reason: 'card $id was not drawn again while n was carried');
    }
    final carried = cardOf(tester, 'n') as Placed;
    expect(shown.node('n').x, isNot(at.x), reason: 'the card went with the pointer');
    expect(carried.at, Offset(shown.node('n').x, shown.node('n').y), reason: 'the carried card is set down where it is');
    expect(identical(carried.child, lifted.child), isTrue, reason: 'the carried card’s box is the box it had');
    expect(layerOf(tester, 'n').debugSymmetricPaintCount, 0, reason: 'the carried card was not drawn again');
    expect(layerOf(tester, 'n').debugAsymmetricPaintCount, greaterThan(0), reason: 'the carried card was set down again');
    await gesture.up();
    await tester.pump();
    // Put down, the canvas is handed to the note, which builds the view again with the body it wrote: the cards
    // that did not move are the ones there were.
    expect(shown.changes, hasLength(1));
    await tester.pump();
    for (final id in ids.where((id) => id != 'n')) {
      expect(identical(cardOf(tester, id), before[id]), isTrue, reason: 'card $id was not built again when n was put down');
    }
    await shown.done();
  });

  testWidgets('a card wholly off the screen is not set down, and is when the view comes back to it', (tester) async {
    final shown = Shown(tester);
    await shown.show();
    final world = worldOf(tester);
    final all = world.debugPainted;
    expect(all, greaterThanOrEqualTo(ids.length));
    // The view moved far to one side: every card and its group are off the screen, and only what has no box of
    // its own to be off the screen with (the lines) is still set down.
    shown.state.camera.moveTo(const CameraView(x: -4000, y: -4000, scale: 1));
    await tester.pump();
    expect(world.debugPainted, lessThanOrEqualTo(all - ids.length));
    shown.state.camera.moveTo(home);
    await tester.pump();
    expect(world.debugPainted, all);
    // A card a little off the edge is still set down: it may draw past its own box (a lifted card's shadow).
    final t = shown.node('t');
    shown.state.camera.moveTo(CameraView(x: -(t.x + t.width) - 20, y: 32, scale: 1));
    await tester.pump();
    expect(world.debugPainted, greaterThan(all - ids.length));
    await shown.done();
  });

  testWidgets('a view zoomed by a hand draws each card as a picture of itself until the hand rests, and one change of scale never does', (tester) async {
    final shown = Shown(tester);
    await shown.show();
    final camera = shown.state.camera;
    // The cards of words and notes and the link; a group's box is drawn as itself throughout.
    Iterable<RenderZoomStill> stills() => tester.allRenderObjects.whereType<RenderZoomStill>();
    final cards = stills().length;
    expect(cards, ids.length - 1);
    Future<Uint8List> picture() async {
      final boundary = tester.allRenderObjects.whereType<RenderRepaintBoundary>().first;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        return data!.buffer.asUint8List();
      }))!;
    }

    // Past the rest of whatever scale the view opened to.
    await tester.pump(CanvasCamera.zoomRest * 2);
    final taken = RenderZoomStill.debugTaken;
    // One change alone (Fit, the zoom buttons, a zoom to a card): no hand at it, no picture, the cards themselves.
    camera.zoomBy(1.1);
    await tester.pump();
    expect(camera.zooming.value, isFalse);
    expect(RenderZoomStill.debugTaken, taken);
    await tester.pump(CanvasCamera.zoomRest * 2);
    // Two fingers moving: a change at every frame. From the second each card is its picture, taken once.
    camera.zoomBy(1.05);
    await tester.pump(const Duration(milliseconds: 16));
    expect(camera.zooming.value, isFalse);
    camera.zoomBy(1.05);
    await tester.pump(const Duration(milliseconds: 16));
    expect(camera.zooming.value, isTrue);
    expect(RenderZoomStill.debugTaken, taken + cards);
    expect(stills().every((still) => still.debugStill), isTrue);
    for (final id in ids) {
      layerOf(tester, id).debugResetMetrics();
    }
    for (var i = 0; i < 4; i += 1) {
      camera.zoomBy(1.03);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(RenderZoomStill.debugTaken, taken + cards, reason: 'the pictures taken as the zoom began are the ones stretched');
    for (final id in ids) {
      expect(layerOf(tester, id).debugSymmetricPaintCount, 0, reason: 'card $id was not drawn again while the hand moved');
    }
    // Far from the size the pictures were taken at, they are taken again: a long zoom in is not a soft one.
    camera.zoomBy(1.6);
    await tester.pump(const Duration(milliseconds: 16));
    expect(RenderZoomStill.debugTaken, taken + cards * 2);
    // The hand rests: every card is drawn as itself, and the screen is the one a view put there at once shows.
    final rested = shown.view;
    await tester.pump(CanvasCamera.zoomRest + const Duration(milliseconds: 20));
    await tester.pump();
    expect(camera.zooming.value, isFalse);
    expect(stills().any((still) => still.debugStill), isFalse);
    final after = await picture();
    camera.moveTo(home);
    await tester.pump(CanvasCamera.zoomRest * 2);
    camera.moveTo(rested);
    await tester.pump();
    expect(camera.zooming.value, isFalse);
    expect(await picture(), after);
    await shown.done();
  });

  test('a line’s path is read from its string once, and is the same path each time it is asked for', () {
    const d = 'M0 0C30 0 70 40 100 40';
    final first = linePath(d);
    expect(identical(linePath(d), first), isTrue);
    expect(identical(linePath('M0 0C30 0 70 40 100 41'), first), isFalse);
    expect(first.getBounds(), const Rect.fromLTRB(0, 0, 100, 40));
  });
}
