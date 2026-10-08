import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/canvas/card_looks.dart';
import 'package:ghost_md/canvas/json_canvas.dart';

import '../support/render.dart';
import 'samples.dart';
import 'view_support.dart';

/// The canvas's controls, and snapping to the grid's dots: `src/app/canvas/CanvasView.controls.test.tsx` and
/// `CanvasView.snap.test.tsx`, case for case. A tap picks and the next opens, a mouse drags a card and a finger
/// drags the picked one, a group is taken by its name, the keys, the picked card's bar, and what the + makes.
void main() {
  setUpAll(loadAppFonts);
  final canvas = parseCanvas(viewSample)!;
  const mouse = PointerDeviceKind.mouse;
  List<double> place(Canvas next, String id) => [next.nodeOf(id)!.x, next.nodeOf(id)!.y];
  List<double> box(Canvas next, String id) => [next.nodeOf(id)!.x, next.nodeOf(id)!.y, next.nodeOf(id)!.width, next.nodeOf(id)!.height];

  Future<void> add(Shown shown, String what) async {
    await shown.press('Add a card');
    await shown.tester.pump(const Duration(milliseconds: 400));
    await shown.tester.ensureVisible(find.text(what));
    await shown.tester.pump(const Duration(milliseconds: 300));
    await shown.tester.tap(find.text(what));
    await shown.tester.pump();
    await shown.tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> withKey(WidgetTester tester, LogicalKeyboardKey held, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(held);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(held);
    await tester.pump();
  }

  group('picking a card', () {
    testWidgets('picks a note card on the first tap and opens it on the next, or from its bar', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('f');
      expect(shown.opened, isEmpty);
      expect(shown.state.chosen, 'f');
      expect(shown.bar('f'), ['Open the note', 'Draw a line from this card', 'Comment on this card', 'Colour', 'Make a copy', 'Take this card off the canvas']);
      await shown.tapCard('f');
      expect(shown.opened, ['Launch week#^photos']);
      await shown.press('Open the note');
      expect(shown.opened, hasLength(2));
      await shown.done();
    });

    testWidgets('picks an address on the first tap, so the page does not leave for it, and opens it on the next', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('l');
      expect(shown.links, isEmpty);
      expect(shown.state.chosen, 'l');
      await shown.tapCard('l');
      expect(shown.links, ['https://attack.fm/glyph']);
      await shown.done();
    });

    testWidgets('opens a card at once on a canvas that cannot change, as it did, and picks nothing', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      await shown.tapCard('f');
      expect(shown.opened, hasLength(1));
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && RegExp(r'^(ring|handle|bar) ').hasMatch((w.key! as ValueKey<String>).value)), findsNothing);
      await shown.done();
    });

    testWidgets('lets the card go on a tap of the page, and Escape lets go of one thing at a time', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('t');
      await shown.tapCard('t');
      expect(shown.state.editing, 't');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      // The writing first; the card is still picked.
      expect(shown.state.editing, isNull);
      expect(shown.state.chosen, 't');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shown.state.chosen, isNull);
      await shown.tapCard('n');
      expect(shown.state.chosen, 'n');
      await shown.tap(const Offset(700, 300));
      expect(shown.state.chosen, isNull);
      await shown.done();
    });

    testWidgets('puts the bar under a card whose top is at the top of the screen', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      // The view opens with the canvas's corner 32px in: t's top is at 32 on the screen, too near for a bar over it.
      await shown.tapCard('t');
      expect(shown.state.debugBarBelow, isTrue);
      expect(tester.getRect(find.byKey(const ValueKey('bar t'))).top, greaterThan(tester.getRect(find.byKey(const ValueKey('card t'))).bottom));
      // n is 100 further down: there is room over it.
      await shown.tapCard('n');
      expect(shown.state.debugBarBelow, isFalse);
      expect(tester.getRect(find.byKey(const ValueKey('bar n'))).bottom, lessThan(tester.getRect(find.byKey(const ValueKey('card n'))).top));
      await shown.done();
    });
  });

  group('moving a card', () {
    testWidgets('moves a card with a mouse that drags it, with no hold, and picks it', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      final gesture = await tester.startGesture(const Offset(350, 150), kind: mouse);
      await gesture.moveTo(const Offset(380, 190));
      await tester.pump();
      expect(shown.state.lifted, 'n');
      await gesture.up();
      await tester.pump();
      expect(place(shown.last, 'n'), [330, 140]);
      expect(shown.state.chosen, 'n');
      await shown.done();
    });

    testWidgets('pans under a finger that drags a card not picked, and moves the picked one', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      final before = shown.view;
      await shown.drag(const [Offset(350, 150), Offset(380, 190)]);
      expect(shown.changes, isEmpty);
      expect(shown.view, isNot(before));
      // Picked - by a tap as a finger makes one - the same drag is the card's.
      await shown.tapCard('n');
      final panned = shown.view;
      final from = shown.card('n');
      await shown.drag([from, from + const Offset(30, 40)]);
      expect(place(shown.last, 'n'), [330, 140]);
      expect(shown.view, panned);
      await shown.done();
    });

    testWidgets('pans with the middle button and with Space held, whatever is under the pointer', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      final before = shown.view;
      await shown.drag(const [Offset(350, 150), Offset(380, 190)], kind: mouse, middle: true);
      expect(shown.changes, isEmpty);
      expect(shown.view, isNot(before));
      final middle = shown.view;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      final from = shown.card('n');
      await shown.drag([from, from + const Offset(30, 40)], kind: mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(shown.changes, isEmpty);
      expect(shown.view, isNot(middle));
      await shown.done();
    });

    testWidgets('takes a group by its name, with everything in it, and pans from its ground', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      final before = shown.view;
      final ground = shown.at(250, 90);
      await shown.drag([ground, ground + const Offset(30, 30)], kind: mouse);
      expect(shown.changes, isEmpty);
      expect(shown.view, isNot(before));
      final name = tester.getCenter(find.byKey(const ValueKey('name g')));
      expect(find.descendant(of: find.byKey(const ValueKey('name g')), matching: find.text('Before')), findsOneWidget);
      await shown.drag([name, name + const Offset(50, 30)]);
      expect(shown.placed(shown.last), [
        ['g', 30, 10],
        ['t', 50, 30],
        ['f', 300, 0],
        ['n', 300, 100],
        ['l', 50, 130],
      ]);
      // And by its border, a finger's width of it.
      final border = shown.at(shown.node('g').x + 4, shown.node('g').y + 100);
      await shown.drag([border, border + const Offset(20, 0)]);
      expect(shown.changes, hasLength(2));
      await shown.done();
    });
  });

  group('the keys', () {
    testWidgets('nudges the picked card with the arrows, ten pixels or one with Alt, and takes it off with Delete', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(shown.changes, isEmpty);
      await shown.tapCard('n');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(place(shown.last, 'n'), [310, 100]);
      await withKey(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowUp);
      expect(place(shown.last, 'n'), [310, 99]);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(shown.last.nodeOf('n'), isNull);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('bar ')), findsNothing);
      await shown.done();
    });

    testWidgets('leaves the keys to a card being written in', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('t');
      await shown.tapCard('t');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      // The card is still there, where it was: the keys were its words'.
      expect(shown.state.live.nodeOf('t'), holds({'x': 0, 'y': 0}));
      expect(shown.changes.where((next) => next.nodeOf('t') == null || next.nodeOf('t')!.x != 0), isEmpty);
      await shown.done();
    });

    testWidgets('copies the picked card with Ctrl or Cmd+D, a step aside, and picks the copy', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('n');
      await withKey(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyD);
      final copy = shown.last.nodes.last;
      expect(copy, holds({'type': 'file', 'file': 'Nowhere.md', 'x': 324, 'y': 124, 'width': 200, 'height': 80}));
      expect(copy.id, isNot('n'));
      expect(shown.state.chosen, copy.id);
      await shown.done();
    });
  });

  group('the picked card’s bar', () {
    testWidgets('colours a card with one of the page’s hues, and takes the colour off', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('n');
      await shown.press('Colour');
      expect(shown.bar('n'), ['No colour', 'Rose', 'Ember', 'Amber', 'Moss', 'Sea', 'Violet', 'Done with the colour']);
      await shown.press('Sea');
      expect(shown.last.nodeOf('n'), holds({'color': '5'}));
      expect(paintOf(shown.node('n').color), const CardPaint.hue(CanvasHue.sea));
      await shown.press('No colour');
      expect(shown.last.nodeOf('n')!.fields.containsKey('color'), isFalse);
      await shown.press('Done with the colour');
      expect(shown.bar('n'), contains('Make a copy'));
      await shown.done();
    });

    testWidgets('starts a line from the card, so the next card tapped ends it', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('n');
      await shown.press('Draw a line from this card');
      expect(shown.state.lining, 'to');
      expect(shown.state.liningFrom, 'n');
      await shown.tapCard('l');
      expect(shown.last.edges.last, holds({'fromNode': 'n', 'toNode': 'l'}));
      expect(shown.links, isEmpty);
      await shown.done();
    });

    testWidgets('writes in a card of words from the bar, and says when it is done', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('t');
      await shown.press('Write in this card');
      expect(shown.state.editing, 't');
      await shown.press('Done writing');
      expect(shown.state.editing, isNull);
      expect(shown.state.chosen, 't');
      await shown.done();
    });
  });

  group('what the + makes', () {
    testWidgets('makes a group about the picked card, under the cards, its name open to be written', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('n');
      await add(shown, 'A group');
      final next = shown.last;
      // First in the file, so it is drawn under every card; with room round the card it was made about.
      expect(next.nodes[0], holds({'type': 'group', 'x': 276, 'y': 76, 'width': 248, 'height': 128}));
      expect(next.nodes.length, canvas.nodes.length + 1);
      expect(find.descendant(of: find.byKey(ValueKey('name ${next.nodes[0].id}')), matching: find.byType(EditableText)), findsOneWidget);
      await shown.done();
    });

    testWidgets('makes a group of its own mid-screen when no card is picked', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await add(shown, 'A group');
      expect(shown.last.nodes[0], holds({'type': 'group', 'width': 480, 'height': 320}));
      await shown.done();
    });

    testWidgets('never sets a new card exactly on the last one', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await add(shown, 'Words');
      final first = shown.last.nodes.last;
      await add(shown, 'A table');
      final second = shown.last.nodes.last;
      expect([second.x - first.x, second.y - first.y], isNot([0, 0]));
      await shown.done();
    });
  });

  group('the zoom buttons', () {
    testWidgets('go closer and further about the middle of the screen, and stop at the ends', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      final before = shown.view.scale;
      await shown.press('Zoom in');
      expect(shown.view.scale, closeTo(before * 1.3, 1e-6));
      await shown.press('Zoom out');
      expect(shown.view.scale, closeTo(before, 1e-6));
      for (var n = 0; n < 20; n += 1) {
        await shown.press('Zoom out');
      }
      expect(shown.view.scale, closeTo(0.1, 1e-6));
      await shown.done();
    });
  });

  // CanvasView.snap.test.tsx
  group('snapping to the grid', () {
    testWidgets('is on until it is turned off, and the magnet says which', (tester) async {
      expect(Preferences.defaults.canvasSnap, isTrue);
      final shown = Shown(tester);
      await shown.show(snap: true);
      bool? pressed() => tester.widget<Semantics>(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Snap to the grid')).properties.toggled;
      expect(pressed(), isTrue);
      await shown.press('Snap to the grid');
      expect(preferences.value.canvasSnap, isFalse);
      expect(pressed(), isFalse);
      await shown.done();
      // A canvas that cannot change has nothing to snap, and no magnet.
      final still = Shown(tester);
      await still.show(editable: false, snap: true);
      expect(find.bySemanticsLabel('Snap to the grid'), findsNothing);
      await still.done();
    });

    testWidgets('lands a dragged card on the nearest dot, and ticks at each new one', (tester) async {
      final shown = Shown(tester);
      await shown.show(snap: true);
      // n is at 300,100. Dragged 31 across and 43 down it would be at 331,143: the nearest dot is 336,144.
      final gesture = await tester.startGesture(const Offset(350, 150), kind: mouse);
      await gesture.moveTo(const Offset(360, 160));
      await tester.pump();
      // 310,110: the nearest dot is 312,120. Drawn there on the way.
      expect(tester.getTopLeft(find.byKey(const ValueKey('card n'))), shown.at(312, 120));
      expect(shown.felt, 0);
      await gesture.moveTo(const Offset(362, 161));
      // The same dot: nothing more is felt.
      expect(shown.felt, 0);
      await gesture.moveTo(const Offset(381, 193));
      expect(shown.felt, 1);
      await gesture.up();
      await tester.pump();
      expect(box(shown.last, 'n'), [336, 144, 200, 80]);
      await shown.done();
    });

    testWidgets('moves a group and its cards by whole squares, so cards on the grid stay on it', (tester) async {
      final shown = Shown(tester);
      await shown.show(snap: true);
      // g is at -20,-20, off the grid: carried 50 across and 30 down it lands on 24,0, a move of 44 and 20 for all it holds.
      final name = tester.getCenter(find.byKey(const ValueKey('name g')));
      await shown.drag([name, name + const Offset(50, 30)]);
      expect(shown.placed(shown.last), [
        ['g', 24, 0],
        ['t', 44, 20],
        ['f', 300, 0],
        ['n', 300, 100],
        ['l', 44, 120],
      ]);
      await shown.done();
    });

    testWidgets('lands a resized card’s moving sides on the grid’s lines, the others staying put, with a tick at each', (tester) async {
      final shown = Shown(tester);
      await shown.show(snap: true);
      await shown.tapCard('n', kind: mouse);
      // n is 300,100 200x80: its right side is at 500, its foot at 180. Out by 30 and 10: the lines are 528 and 192.
      final gesture = await tester.startGesture(shown.handle('n', 'se'), kind: mouse);
      await gesture.moveBy(const Offset(30, 10));
      expect(shown.felt, 1);
      await gesture.moveBy(const Offset(1, 1));
      expect(shown.felt, 1);
      await gesture.up();
      await tester.pump();
      expect(box(shown.last, 'n'), [300, 100, 228, 92]);
      // The top-left corner: its sides go to 288 and 96, and the far corner (528, 192) stays.
      final corner = await tester.startGesture(shown.handle('n', 'nw'), kind: mouse);
      await corner.moveBy(const Offset(-10, -5));
      await corner.up();
      await tester.pump();
      expect(box(shown.last, 'n'), [288, 96, 240, 96]);
      await shown.done();
    });

    testWidgets('nudges by one dot with an arrow, from the nearest dot, and by a pixel with Alt', (tester) async {
      final shown = Shown(tester);
      await shown.show(snap: true);
      await shown.tapCard('n');
      // 300 is half-way to neither: the nearest line is 312 (300/24 is 12.5), and one dot along is 336. Down is untouched.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(place(shown.last, 'n'), [336, 100]);
      await withKey(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowDown);
      expect(place(shown.last, 'n'), [336, 101]);
      await shown.done();
    });

    testWidgets('makes a new card on a dot, and a second a square aside from it', (tester) async {
      final shown = Shown(tester);
      await shown.show(snap: true);
      await add(shown, 'Words');
      final first = shown.last.nodes.last;
      expect([(first.x % 24).abs(), (first.y % 24).abs()], [0, 0]);
      // The first is open to be written in: the + is pressed over it.
      await add(shown, 'Words');
      final second = shown.last.nodes.last;
      expect([second.x - first.x, second.y - first.y], [24, 24]);
      await shown.done();
    });

    testWidgets('leaves everything to the pixel with the magnet off, and nothing is felt', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.drag(const [Offset(350, 150), Offset(381, 193)], kind: mouse);
      expect(box(shown.last, 'n'), [331, 143, 200, 80]);
      expect(shown.felt, 0);
      await shown.done();
    });
  });
}
