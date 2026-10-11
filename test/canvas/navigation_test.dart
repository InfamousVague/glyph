import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/card.dart';
import 'package:ghost_md/canvas/card_looks.dart';
import 'package:ghost_md/canvas/minimap.dart';
import 'package:ghost_md/canvas/viewport.dart';

import '../support/render.dart';
import 'samples.dart';
import 'view_support.dart';

/// Finding your way round a canvas: two fingers that pan and pinch, a wheel that pans and a modified wheel that
/// zooms, the keys that fit the canvas and go to a card, the fit that follows the screen's size until a hand has
/// moved the view, the minimap, and the words that wait until their card is near the screen.
/// `src/app/canvas/CanvasView.navigation.test.tsx`, case for case. What is measured is the camera's view, which
/// is where the web's tests read the world's transform.
void main() {
  setUpAll(loadAppFonts);
  const view32 = CameraView(x: 32, y: 32, scale: 1);

  Future<void> wheel(WidgetTester tester, Offset at, Offset delta, {LogicalKeyboardKey? held}) async {
    if (held != null) await tester.sendKeyDownEvent(held);
    final pointer = TestPointer(9, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(delta));
    if (held != null) await tester.sendKeyUpEvent(held);
    await tester.pump();
  }

  Future<void> shift(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  Future<void> resized(WidgetTester tester, double width, double height) async {
    tester.view.physicalSize = Size(width, height) * tester.view.devicePixelRatio;
    await tester.pump();
    await tester.pump();
  }

  group('two fingers and a wheel', () {
    testWidgets('opens at the fitted view: the whole canvas in the screen, centred, no larger than life', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, fit: true, size: const Size(1000, 600));
      // The cards run from -20 to 500 across and -20 to 180 down, which a 1000 by 600 screen holds at life size.
      expect(shown.view, const CameraView(x: (1000 - 520) / 2 + 20, y: (600 - 200) / 2 + 20, scale: 1));
      await shown.done();
    });

    testWidgets('pinches about the point between two fingers, keeping what was under them under them', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      // 100px apart, then 200px: twice the size. The point between them was (150, 100) on the screen, which with the
      // view at (32, 32) is (118, 68) of the canvas; the fingers' middle moves to (200, 100), and that point goes with it.
      final one = await tester.createGesture(pointer: 1);
      final two = await tester.createGesture(pointer: 2);
      await one.down(const Offset(100, 100));
      await two.down(const Offset(200, 100));
      await two.moveTo(const Offset(300, 100));
      final view = shown.view;
      expect(view.scale, 2);
      expect(view.x + 118 * view.scale, closeTo(200, 1e-5));
      expect(view.y + 68 * view.scale, closeTo(100, 1e-5));
      await two.up();
      await one.up();
      await shown.done();
    });

    testWidgets('pans with one finger once it has moved past a tap, and not before', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      final finger = await tester.startGesture(const Offset(500, 400));
      // Three pixels is still a tap.
      await finger.moveTo(const Offset(503, 400));
      expect(shown.view, view32);
      await finger.moveTo(const Offset(540, 370));
      expect(shown.view, const CameraView(x: 72, y: 2, scale: 1));
      await finger.up();
      await shown.done();
    });

    testWidgets('pans with a wheel, and zooms about the pointer with the modifier held', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      await wheel(tester, const Offset(300, 300), const Offset(10, 20));
      expect(shown.view, const CameraView(x: 22, y: 12, scale: 1));
      // At (122, 62) on the screen is (100, 50) of the canvas; zoomed in, it is still there.
      await wheel(tester, const Offset(122, 62), const Offset(0, -100), held: LogicalKeyboardKey.controlLeft);
      final view = shown.view;
      expect(view.scale, closeTo(math.e, 1e-5));
      expect(view.x + 100 * view.scale, closeTo(122, 1e-5));
      expect(view.y + 50 * view.scale, closeTo(62, 1e-5));
      // Never past three times life size.
      await wheel(tester, const Offset(122, 62), const Offset(0, -1000), held: LogicalKeyboardKey.metaLeft);
      expect(shown.view.scale, 3);
      await shown.done();
    });

    testWidgets('pans and pinches with a trackpad’s two fingers, about where the pointer is', (tester) async {
      // Not the web's: there a trackpad's pinch is a wheel with ctrl held. Here it is a gesture of its own.
      final shown = Shown(tester);
      await shown.show(editable: false);
      final pad = TestPointer(7, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(const Offset(150, 100)));
      await tester.sendEventToBinding(pad.panZoomUpdate(const Offset(150, 100), pan: const Offset(50, 0), scale: 2));
      final view = shown.view;
      expect(view.scale, 2);
      expect(view.x + 118 * view.scale, closeTo(200, 1e-5));
      expect(view.y + 68 * view.scale, closeTo(100, 1e-5));
      await tester.sendEventToBinding(pad.panZoomEnd());
      await shown.done();
    });
  });

  group('the keys, and the fit that follows the screen', () {
    testWidgets('fits the whole canvas on Shift+1, and goes to the card last tapped on Shift+2', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, fit: true, size: const Size(1000, 600));
      await wheel(tester, const Offset(500, 300), const Offset(300, 0));
      expect(shown.view.x, 260 - 300);
      await shift(tester, LogicalKeyboardKey.digit1);
      expect(shown.view, const CameraView(x: 260, y: 220, scale: 1));
      // Nothing chosen yet: Shift+2 has nowhere to go.
      await shift(tester, LogicalKeyboardKey.digit2);
      expect(shown.view, const CameraView(x: 260, y: 220, scale: 1));
      await shown.tapCard('f');
      await shift(tester, LogicalKeyboardKey.digit2);
      // f is 300,0 200x80: centred on the screen, at life size.
      expect(shown.view, const CameraView(x: (1000 - 200) / 2 - 300, y: (600 - 80) / 2, scale: 1));
      await shown.done();
    });

    testWidgets('leaves the keys to a field being typed in', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(shown.line('e2'));
      expect(find.byType(LineWords), findsOneWidget);
      await tester.pump();
      await shift(tester, LogicalKeyboardKey.digit1);
      expect(shown.view, view32);
      await shown.done();
    });

    testWidgets('puts down on Escape whatever was up: the card open, the line picked, the Line tool', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('t');
      await shown.tapCard('t');
      expect(shown.state.editing, 't');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shown.state.editing, isNull);

      await shown.tap(shown.line('e2'));
      expect(shown.state.pickedLine, 'e2');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shown.state.pickedLine, isNull);

      await shown.press('Draw a line: tap one card, then another');
      expect(shown.state.lining, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shown.state.lining, isNull);
      await shown.done();
    });

    testWidgets('fits again when the screen changes size, until a hand has moved the view', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, fit: true, size: const Size(700, 500));
      await resized(tester, 1000, 600);
      expect(shown.view, const CameraView(x: 260, y: 220, scale: 1));
      await wheel(tester, const Offset(500, 300), const Offset(0, 40));
      expect(shown.view, const CameraView(x: 260, y: 180, scale: 1));
      // Moved by hand: a new size leaves the view where the hand put it.
      await resized(tester, 700, 500);
      expect(shown.view, const CameraView(x: 260, y: 180, scale: 1));
      // The fit button fits, and the view follows the screen again from there.
      await shown.press('Fit the whole canvas on the screen (Shift+1)');
      await resized(tester, 1000, 600);
      expect(shown.view, const CameraView(x: 260, y: 220, scale: 1));
      // A zoom to a card is a hand moving the view too: f centred on the screen stays where it was put when the
      // screen changes.
      await shown.tap(tester.getCenter(find.descendant(of: find.byKey(const ValueKey('card f')), matching: find.text('Launch week'))));
      expect(shown.view, const CameraView(x: (1000 - 200) / 2 - 300, y: (600 - 80) / 2, scale: 1));
      await resized(tester, 700, 500);
      expect(shown.view, const CameraView(x: 100, y: 260, scale: 1));
      await shown.done();
    });
  });

  group('a card’s title and the minimap', () {
    testWidgets('zooms to a note card on a tap of its title without opening the note, and opens it from the rest', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, size: const Size(700, 500));
      final title = find.descendant(of: find.byKey(const ValueKey('card f')), matching: find.text('Launch week'));
      await shown.tap(tester.getCenter(title));
      expect(shown.opened, isEmpty);
      expect(shown.view, const CameraView(x: (700 - 200) / 2 - 300, y: (500 - 80) / 2, scale: 1));
      final card = tester.getRect(find.byKey(const ValueKey('card f')));
      await shown.tap(card.bottomCenter - const Offset(0, 12));
      expect(shown.opened, ['Launch week#^photos']);
      await shown.done();
    });

    testWidgets('draws a minimap that tells the cards apart, draws the lines, names the group, and frames the screen', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      expect(find.byKey(const ValueKey('map')), findsOneWidget);
      final drawn = MapPainter.lastDrawn!;
      expect(drawn.cards.map((card) => card.kind), ['text', 'note', 'note', 'link']);
      // The lines are the canvas's own curves, the first with its arrow head and the second, told to have none, without.
      expect(drawn.lines, 2);
      expect(drawn.heads, 1);
      expect(drawn.name, 'Before');
      // The link's ring.
      expect(drawn.cards.where((card) => card.ring), hasLength(1));
      // The card of words shows the shape of its words: a heading's heavier bar, then a list's dot and its line.
      expect(drawn.cards[0].bars, [true, false, false]);
      // A note is its title and what fits of a few lines under it.
      expect([for (final card in drawn.cards) if (card.kind == 'note') card.bars.where((strong) => strong).length], [1, 1]);
      // The screen's box, over a shade on what the screen does not show.
      expect(drawn.seen, isNotNull);
      // A card's colour: a preset as a hue, a hex as the card's own.
      expect(drawn.cards[0].paint, const CardPaint.hue(CanvasHue.moss));
      expect(drawn.cards[3].paint, const CardPaint.hex('#ff8800'));
      await shown.done();
    });

    testWidgets('has no minimap for a canvas of one card', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, canvas: '{ "nodes": [{ "id": "a", "type": "text", "x": 0, "y": 0, "width": 100, "height": 50, "text": "Only" }] }');
      expect(find.byKey(const ValueKey('map')), findsNothing);
      await shown.done();
    });

    testWidgets('grows the minimap on a press that moves nothing, and a press on the canvas puts it back', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      final map = find.byKey(const ValueKey('map'));
      final before = shown.view;
      // The press that grows it only grows it.
      expect(shown.state.mapBig, isFalse);
      final press = await tester.startGesture(tester.getCenter(map));
      await tester.pump();
      expect(shown.state.mapBig, isTrue);
      await press.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(shown.view, before);
      expect(shown.state.mapBig, isTrue);
      expect(tester.getSize(map), const Size(306, 204));
      // A press on the canvas puts it back.
      final page = await tester.startGesture(const Offset(300, 300));
      await tester.pump();
      expect(shown.state.mapBig, isFalse);
      await page.up();
      await shown.done();
    });

    testWidgets('moves the view by what a finger moved on the map, read at the map’s size on the page, and goes where a tap on the grown map lands', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, size: const Size(400, 300));
      // Twice life size about the room's corner: the screen's box, -16,-16 and 200 by 150, is inside the cards, so
      // the map frames the cards alone - their 520 by 200 in the 188 by 120 inside the map's room.
      await wheel(tester, const Offset(32, 32), Offset(0, -100 * math.log(2)), held: LogicalKeyboardKey.controlLeft);
      final zoomed = shown.view;
      expect(zoomed.scale, closeTo(2, 1e-10));
      const unit = 188 / 520;
      final map = find.byKey(const ValueKey('map'));
      // The map's size on the page: smaller on a phone's width (0.72 of 204), and half again when grown.
      double onPage() => tester.getRect(map).width / mapWidth;
      final small = onPage();
      expect(small, closeTo(0.72, 1e-6));
      // 27px on the small map is 27 / 0.72 of its units; the view goes the other way by that, at its scale.
      await shown.drag([tester.getCenter(map), tester.getCenter(map) + const Offset(27, 0)]);
      final dragged = shown.view;
      expect(dragged.x, closeTo(zoomed.x - (27 / small / unit) * 2, 1e-5));
      expect(dragged.y, closeTo(zoomed.y, 1e-5));
      // Grown half again, the same 27px is a third fewer units.
      await tester.pump(const Duration(milliseconds: 300));
      final grown = onPage();
      expect(grown, closeTo(0.72 * 1.5, 1e-6));
      await shown.drag([tester.getCenter(map), tester.getCenter(map) + const Offset(27, 0)]);
      expect(shown.view.x, closeTo(dragged.x - (27 / grown / unit) * 2, 1e-5));

      // The middle of the grown map is the middle of the cards, 240,80, and the 400 by 300 screen is centred on it.
      await shown.tap(tester.getCenter(map));
      final went = shown.view;
      expect(went.x, closeTo(200 - 240 * 2, 0.5));
      expect(went.y, closeTo(150 - 80 * 2, 0.5));
      expect(went.scale, closeTo(2, 1e-10));
      await shown.done();
    });
  });

  group('cards made only when near the screen', () {
    testWidgets('leaves a card’s words unmade until the card comes near, then makes it', (tester) async {
      final shown = Shown(tester);
      await shown.show(
        editable: false,
        canvas: r'''{ "nodes": [
          { "id": "t", "type": "text", "x": 0, "y": 0, "width": 200, "height": 80, "text": "# Book it\n\n- [ ] The cabin" },
          { "id": "edge", "type": "text", "x": 1000, "y": 0, "width": 200, "height": 80, "text": "Just off the screen" },
          { "id": "far", "type": "text", "x": 60000, "y": 0, "width": 200, "height": 80, "text": "A long way off" }
        ] }''',
      );
      // (The canvas is too wide to fit even at a tenth of life size, so the far card was never on the screen.)
      Finder words(String id) => find.descendant(of: find.byKey(ValueKey('card $id')), matching: find.byType(CardWords));
      expect(words('t'), findsOneWidget);
      // Measured against the canvas with room to spare (300px), so the words are ready before their card is on
      // the screen: `edge` starts 232px past the 800px screen's right side.
      expect(words('edge'), findsOneWidget);
      expect(words('far'), findsNothing);
      shown.state.camera.panBy(59500, 0);
      await tester.pump();
      expect(tester.widget<CardWords>(words('far')).markdown, 'A long way off');
      // Once made, they stay made.
      shown.state.camera.panBy(-59500, 0);
      await tester.pump();
      expect(words('far'), findsOneWidget);
      await shown.done();
    });
  });

  group('a picked line’s words', () {
    testWidgets('writes the words when the field is left, and writes nothing when they did not change', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(shown.line('e1'));
      final field = find.descendant(of: find.byType(LineWords), matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(field).controller.text, 'then');
      Future<void> leave() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
      }

      await tester.pump();
      await leave();
      expect(shown.changes, isEmpty);
      await tester.enterText(field, ' then ');
      await leave();
      expect(shown.changes, isEmpty);
      await tester.enterText(field, 'and then');
      await leave();
      expect(shown.changes, hasLength(1));
      expect(shown.changes[0].edges.firstWhere((e) => e.id == 'e1'), holds({'label': 'and then'}));
      await shown.done();
    });
  });
}
