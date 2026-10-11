import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/card.dart';
import 'package:ghost_md/canvas/card_looks.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/canvas/minimap.dart';
import 'package:ghost_md/canvas/paint.dart';
import 'package:ghost_md/canvas/world.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/home/note_peek.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'samples.dart';
import 'view_support.dart';

/// The canvas drawn and edited: `src/app/canvas/CanvasView.test.tsx`, case for case. Where the web's test pressed
/// an element at a point that is not on it (jsdom lays nothing out, so any point would do), the press here is at a
/// point that is; the moves are the web's.
///
/// Two cases are not the web's own: a note dragged in from the sidebar and a picture file dropped from the
/// computer land through `onDrop`, which has no twin here yet, so they are held as what `onDrop` does with them
/// (`addNoteCard`, `addPictureCard` at the point).

/// The smallest picture there is: one transparent pixel.
final Uint8List pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const pictures = '''{ "nodes": [
  { "id": "mine", "type": "file", "x": 0, "y": 0, "width": 200, "height": 150, "file": "abc.jpg" },
  { "id": "theirs", "type": "file", "x": 300, "y": 0, "width": 200, "height": 150, "file": "Pictures/abc.jpg" }
] }''';

void main() {
  setUpAll(loadAppFonts);
  final canvas = parseCanvas(viewSample)!;
  final hex16 = RegExp(r'^[0-9a-f]{16}$');

  group('a canvas drawn', () {
    testWidgets('places every card where the file puts it, the group behind, and its words in the note’s own editor', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      expect(find.byWidgetPredicate((w) => w is Placed && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('card ')), findsNWidgets(5));
      final text = tester.getRect(find.byKey(const ValueKey('card t')));
      expect(text.left, shown.at(0, 0).dx);
      expect(text.width, 200);
      final words = tester.widget<CardWords>(find.descendant(of: find.byKey(const ValueKey('card t')), matching: find.byType(CardWords)));
      expect(words.markdown, contains('The cabin'));
      // To be read: it takes no taps.
      expect(find.descendant(of: find.byType(CardWords), matching: find.byType(IgnorePointer)), findsWidgets);
      expect(find.text('Before'), findsOneWidget);
      // The group is first in the file, so it is first in the world: under the cards.
      final world = tester.widget<CanvasWorld>(find.byType(CanvasWorld));
      final keys = [for (final child in world.children) (child.key as ValueKey<String>?)?.value];
      expect(keys.indexOf('card g'), lessThan(keys.indexOf('card t')));
      await shown.done();
    });

    testWidgets('draws each line with an arrow at its end unless told not to, and the label on it', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      final lines = shown.state.lines;
      expect(lines, hasLength(2));
      expect(lines[0].path.toHead, isNotNull);
      expect(lines[0].path.lines, ['then']);
      expect(lines[1].path.toHead, isNull);
      expect(lines[1].path.lines, isEmpty);
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LinesPainter), findsOneWidget);
      await shown.done();
    });

    testWidgets('paints a chosen hex as the card’s own colour, and names a link by its address', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false);
      final t = tester.element(find.byType(CanvasView)).tokens;
      final paint = paintOf(shown.node('l').color);
      expect(paint, const CardPaint.hex('#ff8800'));
      expect(spaceColor(t, 'var(--app-space)', paint).toARGB32(), 0xffff8800);
      expect(find.descendant(of: find.byKey(const ValueKey('card l')), matching: find.text('attack.fm/glyph')), findsOneWidget);
      await shown.done();
    });

    testWidgets('opens a note card by its title and anchor on a tap, and says when the note is not there', (tester) async {
      final shown = Shown(tester);
      final opened = <String>[];
      await shown.show(
        editable: false,
        wiki: CanvasWiki(known: (title) => title == 'Launch week', open: (title, [at]) => opened.add('$title $at'), body: (title) => title == 'Launch week' ? '# Launch week\n\n- [ ] Get the photos back ^photos' : null),
      );
      final found = find.byKey(const ValueKey('card f'));
      expect(tester.widget<NotePeek>(find.descendant(of: found, matching: find.byType(NotePeek))).body, contains('photos'));
      await shown.tapCard('f');
      expect(opened, ['Launch week ^photos']);
      expect(find.descendant(of: find.byKey(const ValueKey('card n')), matching: find.text('Not in Ghost.md yet')), findsOneWidget);
      await shown.done();
    });
  });

  group('a canvas edited', () {
    testWidgets('is read-only without onChange, and a double-tap on the page then makes a card of words, open', (tester) async {
      final still = Shown(tester);
      await still.show(editable: false);
      // An image to a reader, by what it holds (`role="img"`, `aria-label`).
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'A canvas of 5 cards' && w.properties.image == true), findsOneWidget);
      expect(find.bySemanticsLabel('Add a card'), findsNothing);
      await still.done();
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(const Offset(600, 400));
      await shown.tap(const Offset(600, 400));
      expect(shown.changes, hasLength(1));
      final next = shown.last;
      expect(next.nodes.length, canvas.nodes.length + 1);
      final made = next.nodes.last;
      expect(made, holds({'type': 'text', 'text': '', 'width': 260, 'height': 120}));
      expect(made.id, matches(hex16));
      // Open to be written in, at once.
      expect(shown.state.editing, made.id);
      await shown.done();
    });

    testWidgets('lifts a card on a held press and puts it down where the finger let go, to the pixel', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      final gesture = await tester.startGesture(const Offset(50, 40));
      await tester.pump(shown.held);
      expect(shown.state.lifted, 't');
      await gesture.moveTo(const Offset(80.4, 25.6));
      await gesture.up();
      await tester.pump();
      expect(shown.changes, hasLength(1));
      expect(shown.last.nodeOf('t'), holds({'x': 30, 'y': -14}));
      expect(shown.state.lifted, isNull);
      await shown.done();
    });

    testWidgets('pans rather than lifting when the finger moves before the hold, so the card stays put', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      final gesture = await tester.startGesture(const Offset(50, 40));
      await gesture.moveTo(const Offset(90, 40));
      await tester.pump(Duration(milliseconds: holdMs + 80));
      await gesture.up();
      await tester.pump();
      expect(shown.changes, isEmpty);
      await shown.done();
    });

    testWidgets('picks a card of words on a tap and opens it on the next, and its bar takes the card off', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tapCard('t');
      // Picked, not open: it wears the ring and its bar.
      expect(shown.state.chosen, 't');
      expect(shown.state.editing, isNull);
      expect(shown.has('ring t'), isTrue);
      await shown.tapCard('t');
      expect(shown.state.editing, 't');
      await shown.press('Take this card off the canvas');
      expect(shown.changes, hasLength(1));
      expect(shown.last.nodeOf('t'), isNull);
      // Its two lines went with it.
      expect(shown.last.edges, isEmpty);
      await shown.done();
    });
  });

  group('lines drawn', () {
    testWidgets('draws a line from the first card tapped to the second with the Line tool, once, and never onto itself', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.press('Draw a line: tap one card, then another');
      expect(shown.state.lining, 'from');
      await shown.tapCard('f');
      expect(shown.state.liningFrom, 'f');
      expect(shown.state.lining, 'to');
      // The same card again is not a line.
      await shown.tapCard('f');
      expect(shown.changes, isEmpty);
      await shown.tapCard('l');
      expect(shown.changes, hasLength(1));
      expect(shown.last.edges.last, holds({'fromNode': 'f', 'toNode': 'l'}));
      expect(shown.last.edges.last.id, matches(hex16));
      // The tool is put down, and the new line is picked, its words ready to be written.
      expect(shown.state.lining, isNull);
      expect(find.byType(LineWords), findsOneWidget);
      // And neither the note nor the address opened under the line's taps.
      expect(shown.opened, isEmpty);
      expect(shown.links, isEmpty);
      await shown.done();
    });

    testWidgets('picks a line on a tap, writes words on it, and takes it off', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(shown.line('e2'));
      expect(shown.state.pickedLine, 'e2');
      await tester.enterText(find.descendant(of: find.byType(LineWords), matching: find.byType(EditableText)), 'after');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(shown.changes, hasLength(1));
      expect(shown.last.edges.firstWhere((e) => e.id == 'e2'), holds({'label': 'after'}));
      await tester.tap(find.descendant(of: find.byType(LineWords), matching: find.text('×')));
      await tester.pump();
      expect(shown.changes[1].edges.where((e) => e.id == 'e2'), isEmpty);
      await shown.done();
    });
  });

  group('sizes and groups', () {
    testWidgets('lifts a group with the cards inside it, and leaves the one outside', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      // g is -20,-20 400x200, so its right edge is 380: t and l are wholly inside; f and n reach 500 and are not.
      final from = shown.at(250, 60);
      await shown.drag([from, from + const Offset(50, 30)], hold: shown.held);
      expect(shown.placed(shown.changes[0]), [
        ['g', 30, 10],
        ['t', 50, 30],
        ['f', 300, 0],
        ['n', 300, 100],
        ['l', 50, 130],
      ]);
      await shown.done();
    });

    testWidgets('picks a group on a tap, names it from its bar, and the bar takes only the group off', (tester) async {
      // A desktop's screen, whose pointer is a mouse: the eight handles and the bar's desktop places.
      debugCanvasCoarse = false;
      addTearDown(() => debugCanvasCoarse = null);
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(shown.at(250, 60), kind: PointerDeviceKind.mouse);
      expect(shown.state.chosen, 'g');
      // A group has handles as a card has: it is resized the same way.
      expect(shown.handles('g'), 8);
      await shown.press('Name this group');
      final field = find.descendant(of: find.byKey(const ValueKey('name g')), matching: find.byType(EditableText));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Trip');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(shown.changes[0].nodes[0], holds({'id': 'g', 'label': 'Trip'}));
      await shown.press('Take this group off the canvas; its cards stay');
      final after = shown.changes[1];
      expect(after.nodeOf('g'), isNull);
      expect(after.nodes.length, canvas.nodes.length - 1);
      await shown.done();
    });

    testWidgets('resizes a picked card by a handle, in the canvas’s pixels, no smaller than the least, the far sides staying put', (tester) async {
      // A desktop's screen, whose pointer is a mouse: the eight handles and the bar's desktop places.
      debugCanvasCoarse = false;
      addTearDown(() => debugCanvasCoarse = null);
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(const Offset(50, 40), kind: PointerDeviceKind.mouse);
      CanvasNode latest() => shown.last.nodeOf('t')!;
      Future<void> pull(String name, Offset by, {bool watch = false}) async {
        final gesture = await tester.startGesture(shown.handle('t', name), kind: PointerDeviceKind.mouse);
        await gesture.moveBy(by);
        await tester.pump();
        if (watch) {
          // Drawn at each size on the way, before anything is handed on.
          expect(tester.getSize(find.byKey(const ValueKey('card t'))).width, 260);
          expect(shown.changes, isEmpty);
        }
        await gesture.up();
        await tester.pump();
      }

      // t is 0,0 200x80. The bottom-right corner grows it down and to the right.
      await pull('se', const Offset(60.4, 40.6), watch: true);
      expect(latest(), holds({'x': 0, 'y': 0, 'width': 260, 'height': 121}));
      // The top-left corner moves the card's corner with it: the bottom-right one stays where it was.
      await pull('nw', const Offset(-40, -20));
      expect(latest(), holds({'x': -40, 'y': -20, 'width': 300, 'height': 141}));
      // The middle of a side moves that side alone.
      await pull('e', const Offset(20, 350));
      expect(latest(), holds({'x': -40, 'y': -20, 'width': 320, 'height': 141}));
      // Dragged past the least, a side stops there and the card does not slide. (Its corner is off the screen's
      // edge by now: the page is moved over first, which the web's test, with nothing laid out, had no need of.)
      shown.state.camera.panBy(-100, -100);
      await tester.pump();
      await pull('nw', const Offset(940, 920));
      expect(latest(), holds({'x': 160, 'y': 61, 'width': 120, 'height': 60}));
      await shown.done();
    });

    testWidgets('resizes a group by its handles and leaves the cards in it where they are', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(shown.at(250, 60), kind: PointerDeviceKind.mouse);
      final gesture = await tester.startGesture(shown.handle('g', 'se'), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(180, 60));
      await gesture.up();
      await tester.pump();
      expect([for (final n in shown.changes[0].nodes) [n.id, n.x, n.y, n.width, n.height]], [
        ['g', -20, -20, 580, 260],
        ['t', 0, 0, 200, 80],
        ['f', 300, 0, 200, 80],
        ['n', 300, 100, 200, 80],
        ['l', 0, 100, 200, 80],
      ]);
      await shown.done();
    });

    testWidgets('makes a card on a double-tap of a group’s ground, which is the page’s', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.tap(shown.at(250, 60));
      await shown.tap(shown.at(250, 60));
      final next = shown.changes[0];
      expect(next.nodes.length, canvas.nodes.length + 1);
      expect(next.nodes.last, holds({'type': 'text', 'text': ''}));
      expect(shown.state.editing, next.nodes.last.id);
      await shown.done();
    });
  });

  group('more ways to add', () {
    testWidgets('adds a note card from the + sheet by its title, and a link card by its address', (tester) async {
      final shown = Shown(tester);
      await shown.show(wiki: CanvasWiki(known: (_) => true, open: (title, [at]) {}, titles: () => ['Launch week', 'Cabin trip']));
      await shown.press('Add a card');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('A note'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, 'cab');
      await tester.pump();
      expect(find.byKey(const ValueKey('add note Cabin trip')), findsOneWidget);
      expect(find.byKey(const ValueKey('add note Launch week')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('add note Cabin trip')));
      await tester.pump();
      expect(shown.changes[0].nodes.last, holds({'type': 'file', 'file': 'Cabin trip.md'}));
      expect(find.text('Which note?'), findsNothing);
      await shown.press('Add a card');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('A link'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, 'attack.fm');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(shown.changes[1].nodes.last, holds({'type': 'link', 'url': 'https://attack.fm'}));
      await shown.done();
    });

    testWidgets('takes a note dropped in from the sidebar as a card where it lands', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      shown.state.addNoteCard('Launch week', shown.state.camera.under(90, 70));
      await tester.pump();
      expect(shown.changes[0].nodes.last, holds({'type': 'file', 'file': 'Launch week.md', 'x': 90 - 32 - 130, 'y': 70 - 32 - 80}));
      await shown.done();
    });

    testWidgets('draws the + sheet over the window, where nothing in the note’s page can keep it under the header', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.press('Add a card');
      await tester.pump(const Duration(milliseconds: 400));
      final sheet = find.text('A picture');
      expect(sheet, findsOneWidget);
      // In the app's overlay, not in the canvas's own box.
      expect(find.descendant(of: find.byType(CanvasWorld), matching: sheet), findsNothing);
      expect(find.ancestor(of: sheet, matching: find.byType(Overlay)), findsWidgets);
      await shown.done();
    });

    testWidgets('closes the + sheet on a back gesture and on a tap beside it, adding nothing', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      await shown.press('Add a card');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('A picture'), findsOneWidget);
      expect(BackScope.of(tester.element(find.byType(CanvasView))).goBack(), isTrue);
      await tester.pump();
      expect(find.text('A picture'), findsNothing);
      await shown.press('Add a card');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(const Offset(400, 20));
      await tester.pump();
      expect(find.text('A picture'), findsNothing);
      expect(shown.changes, isEmpty);
      await shown.done();
    });

    testWidgets('marks a card that is only a table, so the table fills it', (tester) async {
      final shown = Shown(tester);
      await shown.show(
        editable: false,
        canvas: r'''{ "nodes": [
          { "id": "t", "type": "text", "x": 0, "y": 0, "width": 200, "height": 100, "text": "| a | b |\n| - | - |\n| 1 | 2 |" },
          { "id": "w", "type": "text", "x": 300, "y": 0, "width": 200, "height": 100, "text": "# Words\n\n| a |\n| - |" }
        ] }''',
      );
      Rect words(String id) => tester.getRect(find.descendant(of: find.byKey(ValueKey('card $id')), matching: find.byType(CardWords)));
      // No padding: the words start at the card's own line. The other has the card's padding.
      expect(words('t').left - tester.getRect(find.byKey(const ValueKey('card t'))).left, lessThan(2));
      expect(words('w').left - tester.getRect(find.byKey(const ValueKey('card w'))).left, greaterThan(8));
      await shown.done();
    });
  });

  group('pictures, charts and the toolbar', () {
    testWidgets('shows icon tools at the bottom left, named for a reader', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      final tools = find.bySemanticsLabel('Canvas tools');
      final labels = [
        for (final element in find.descendant(of: tools, matching: find.byWidgetPredicate((w) => w is Semantics && (w.properties.button ?? false))).evaluate()) (element.widget as Semantics).properties.label,
      ];
      expect(labels, ['Add a card', 'Draw a line: tap one card, then another', 'Snap to the grid', 'Zoom out', 'Zoom in', 'Fit the whole canvas on the screen (Shift+1)']);
      final box = tester.getRect(tools);
      expect(box.left, lessThan(40));
      expect(box.bottom, greaterThan(560));
      await shown.done();
    });

    testWidgets('draws a picture of Ghost.md’s own on its card, and one from elsewhere as waiting', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, canvas: pictures, pictures: MemoryPictureStore()..lend({'abc.jpg': pixel}));
      expect(find.descendant(of: find.byKey(const ValueKey('card mine')), matching: find.byType(Image)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('card theirs')), matching: find.byType(Image)), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('card theirs')), matching: find.textContaining('vault')), findsOneWidget);
      await shown.done();
    });

    // Differs 35 (docs/PARITY.md): the map drew one of Ghost.md's own pictures as the plain block a picture from
    // elsewhere is, where the page's draws the picture in the card's box (Minimap.tsx `<image href={url} ... />`).
    testWidgets('draws that picture on the minimap too, once it is decoded, and one from elsewhere as the block it was', (tester) async {
      final shown = Shown(tester);
      await shown.show(editable: false, canvas: pictures, pictures: MemoryPictureStore()..lend({'abc.jpg': pixel}));
      expect(find.byKey(const ValueKey('map')), findsOneWidget);
      // Decoded off the frame, and the map drawn again when it has been.
      for (var i = 0; i < 40 && !(MapPainter.lastDrawn?.pictures.contains('mine') ?? false); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      final drawn = MapPainter.lastDrawn!;
      expect(drawn.cards.map((card) => (card.id, card.kind)), [('mine', 'picture'), ('theirs', 'picture')]);
      expect(drawn.pictures, {'mine'});
      await shown.done();
    });

    testWidgets('picks a picture on a tap, to resize or take off, and never opens one', (tester) async {
      // A desktop's screen, whose pointer is a mouse: the eight handles and the bar's desktop places.
      debugCanvasCoarse = false;
      addTearDown(() => debugCanvasCoarse = null);
      final shown = Shown(tester);
      await shown.show(canvas: pictures, pictures: MemoryPictureStore()..lend({'abc.jpg': pixel}));
      await shown.tapCard('mine', kind: PointerDeviceKind.mouse);
      await shown.tapCard('mine', kind: PointerDeviceKind.mouse);
      expect(shown.state.chosen, 'mine');
      expect(shown.state.editing, isNull);
      expect(shown.opened, isEmpty);
      expect(shown.handles('mine'), 8);
      // A picture has nothing to open: its bar has no first button for it.
      expect(shown.bar('mine'), ['Draw a line from this card', 'Comment on this card', 'Colour', 'Make a copy', 'Take this card off the canvas']);
      await shown.press('Take this card off the canvas');
      expect(shown.changes[0].nodes.map((n) => n.id), ['theirs']);
      await shown.done();
    });

    testWidgets('adds a picture from the + sheet, and a chart that starts as a diagram', (tester) async {
      final shown = Shown(tester);
      await shown.show(pick: () async => 'picked.jpg');
      await shown.press('Add a card');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('A picture'));
      await tester.pump();
      await tester.pump();
      expect(shown.changes[0].nodes.last, holds({'type': 'file', 'file': 'picked.jpg'}));
      await shown.press('Add a card');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('A chart'));
      await tester.pump();
      final chart = shown.changes[1].nodes.last;
      expect(chart.type, NodeType.text);
      expect(chart.text.startsWith('```mermaid'), isTrue);
      expect(shown.state.editing, chart.id);
      await shown.done();
    });

    testWidgets('makes a card of a picture kept from a file dropped on the canvas, where it lands', (tester) async {
      final shown = Shown(tester);
      await shown.show();
      shown.state.addPictureCard('dropped.jpg', shown.state.camera.under(40, 40));
      await tester.pump();
      expect(shown.changes[0].nodes.last, holds({'type': 'file', 'file': 'dropped.jpg'}));
      await shown.done();
    });
  });
}
