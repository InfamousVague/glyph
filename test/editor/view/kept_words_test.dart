// A line's words are drawn once and kept (lib/editor/view/line.dart, the header's note): a scroll, a caret's blink
// and an effect on another line put every line on screen on the canvas again, and what that cost was the words,
// which had not changed.
//
// Two things are held here.
//
// THE PICTURE IS THE SAME. At every place a page is scrolled to, the page with its words kept is, byte for byte,
// the page with every word drawn afresh (`RenderEditorLine.keepsWords` off, which is the line as it was before it
// kept anything): standing still at offsets between device pixels, in the middle of a drag at each of its steps
// (where the words are carried by whole device pixels and not drawn), and at rest after it. On a screen of two
// device pixels to one, of three, and of the phone's 2.625, where nothing falls on a whole pixel.
//
// THE WORK IS THE WORDS THAT CHANGED. Counted: a drag draws the words of the lines it brings into view and of no
// line already there; a caret's blink and a selection draw none; a letter typed draws its own line's.
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/boards/boards.dart' show drawnBoards;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/items.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/media/media.dart';
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';

import '../../support/render.dart';
import '../input/support.dart';

/// A page of every kind of line the words are drawn in, long enough to scroll some way: paragraphs that wrap to
/// several lines (each visual line is put on a device pixel of its own), list items with their markers at the
/// gutter, headings, a quote, code with its ground, runs with grounds of their own, raised runs and a table.
final String page = <String>[
  '# The cabin, laid out',
  '',
  for (var i = 0; i < 6; i++) ...<String>[
    'Paragraph $i. The road in is unpaved for the last six kilometres and washes out after rain, so the plan is to leave before noon, stop once for water and bread, and be at the gate while there is still light to find the key by. ${'It is further than it looks on the map. ' * (i % 3 + 1)}',
    '',
    '## What to bring, part $i',
    '',
    '- A charger for the drive, and the long cable that reaches the back seat without anyone having to lean forward for an hour',
    '- [ ] Snacks, `in the blue bag`, and ==the good coffee== that Sam keeps asking about',
    '- [x] The map, which is on paper because there is no signal past the second bridge and has not been for years',
    '  - A nested point that wraps as well, so that its marker hangs and its words come back under their own first letter',
    '1. First, the water, x^2^ and H~2~O',
    '2. Second, the wood: a full basket by the door and the rest under the tarpaulin behind the shed where it stays dry',
    '',
    '> A quote that runs on past the edge of the page and comes back under its bar, twice if the page is as narrow as a phone held upright.',
    '',
    '```dart',
    'final cabin = Cabin(beds: 4, stove: true);',
    'print(cabin.describe()); // the stove takes an hour to warm the room',
    '```',
    '',
    '| Day | Who cooks | What |',
    '| --- | --- | --- |',
    '| Friday | Sam | Soup |',
    '| Saturday | Alex | Whatever is left |',
    '',
  ],
].join('\n');

List<Extension> pieces() => <Extension>[
      markExtensions(marks),
      itemExtensions(wiki: WikiOptions(known: (title) => title.length.isEven, open: (title, [anchor]) {}), openHeading: true, doneSyncs: true),
      drawnTables(),
      drawnBoards(),
      mediaExtensions(places: PlaceMode.live),
    ];

Future<({EditorView view, ScrollController scroll})> pumpPage(WidgetTester tester, double ratio) async {
  final view = EditorView(state: EditorState.create(doc: page, extensions: noteExtensions(more: pieces())));
  final scroll = ScrollController();
  addTearDown(view.destroy);
  addTearDown(scroll.dispose);
  // Laid out and snapped at the screen's own pixels, as a phone's page is (`measuredAt`): each visual line is put
  // on a device pixel, and at 2.625 none of them is a whole logical one.
  await pumpApp(tester, prefs: const AppPreferences(theme: 'light'), ratio: ratio, measuredAt: ratio, home: Page(view, scroll));
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump();
  return (view: view, scroll: scroll);
}

/// The page as it stands, pixel for pixel: at the screen's own device pixels, which is where a line of words is
/// put on a whole one (a picture test's own picture is at one pixel to a logical one, whatever the screen's).
Future<Uint8List> picture(WidgetTester tester) async {
  RenderObject boundary = find.byType(Page).evaluate().single.renderObject!;
  while (!boundary.isRepaintBoundary) {
    boundary = boundary.parent!;
  }
  final layer = boundary.debugLayer! as OffsetLayer;
  return (await tester.runAsync(() async {
    final image = await layer.toImage(boundary.paintBounds, pixelRatio: tester.view.devicePixelRatio);
    final bytes = await image.toByteData();
    image.dispose();
    return bytes!.buffer.asUint8List();
  }))!;
}

/// The page drawn with every word afresh, where it stands: the scroll view is painted again with the keeping off,
/// and the keeping put back on. What the lines kept is untouched by it.
Future<Uint8List> afresh(WidgetTester tester) async {
  RenderEditorLine.keepsWords = false;
  tester.allRenderObjects.whereType<RenderViewport>().first.markNeedsPaint();
  await tester.pump();
  final drawn = await picture(tester);
  RenderEditorLine.keepsWords = true;
  return drawn;
}

/// How many bytes of two pictures differ, and the first and last rows of pixels they differ in.
({int bytes, int firstRow, int lastRow}) apart(Uint8List a, Uint8List b, int width) {
  var bytes = 0, first = -1, last = -1;
  if (a.length != b.length) return (bytes: (a.length - b.length).abs() + 1, firstRow: 0, lastRow: 0);
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i]) continue;
    bytes += 1;
    final row = i ~/ (width * 4);
    if (first < 0) first = row;
    last = row;
  }
  return (bytes: bytes, firstRow: first, lastRow: last);
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => RenderEditorLine.keepsWords = true);

  for (final ratio in const <double>[2, 2.625, 3]) {
    testWidgets('at $ratio device pixels to one, a page with its words kept is the page drawn afresh: at rest between pixels, through a drag, and after it', (tester) async {
      final rig = await pumpPage(tester, ratio);
      final width = (390 * ratio).round();
      final faults = <String>[];
      var compared = 0;
      Future<void> same(String where) async {
        final kept = await picture(tester);
        final fresh = await afresh(tester);
        final diff = apart(kept, fresh, width);
        if (diff.bytes != 0) faults.add('$where: ${diff.bytes} bytes differ, rows ${diff.firstRow} to ${diff.lastRow}');
        compared += 1;
      }

      await same('as opened');
      final opened = await picture(tester);
      // At rest, where a jump leaves the page: on whole pixels, between them, and far enough for other lines.
      for (final to in const <double>[0.3, 1, 7.77, 13.5, 100.123, 250.9, 251.0, 251.19, 640.4, 3.14159]) {
        rig.scroll.jumpTo(to);
        await tester.pump();
        await same('at rest at $to');
      }

      // A drag, a step at a time, by amounts that fall between device pixels: the words are carried.
      final position = rig.scroll.position;
      final gesture = await tester.startGesture(const Offset(195, 600));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(position.isScrollingNotifier.value, isTrue);
      var carriedSteps = 0;
      final carriedBefore = RenderEditorLine.wordsCarried;
      const steps = <double>[-3.37, -0.11, -12.9, -1 / 3, -27.2, 5.55, -0.5, -41.01, -2.625, -8.08, 19.7, -63.3, -0.01, -15.15, -7.5, -33.33, -1.9, -22.22, 4.04, -55.5, -0.7, -9.99, -17.4, -3.03];
      for (final step in steps) {
        final drawnBefore = RenderEditorLine.wordsDrawn, keptBefore = RenderEditorLine.wordsKept;
        await gesture.moveBy(Offset(0, step));
        await tester.pump();
        // Most of what is on screen was there the frame before, and is put back, not drawn.
        final drawn = RenderEditorLine.wordsDrawn - drawnBefore, kept = RenderEditorLine.wordsKept - keptBefore;
        expect(kept, greaterThan(drawn * 3), reason: 'a step of $step to ${position.pixels} drew $drawn visual lines afresh and kept $kept');
        if (drawn == 0) carriedSteps += 1;
        await same('in a drag at ${position.pixels}');
      }
      expect(carriedSteps, greaterThan(steps.length ~/ 2), reason: 'most steps of a drag bring no new line into view, and draw no words at all');
      final carried = RenderEditorLine.wordsCarried - carriedBefore;
      expect(carried, greaterThan(steps.length * 10), reason: 'the words on screen were carried at each step');
      // The comparison can fail: the page a pixel and a bit further on is another picture.
      final here = await picture(tester);
      expect(apart(here, opened, width).bytes, greaterThan(1000));
      await gesture.moveBy(Offset(0, -1.4 / ratio));
      await tester.pump();
      expect(apart(await picture(tester), here, width).bytes, greaterThan(1000), reason: 'a device pixel and a half further is another picture');

      // The finger lifted with no speed: the page is at rest where it is, and is drawn there afresh.
      final before = RenderEditorLine.wordsDrawn;
      await gesture.up();
      await tester.pump();
      expect(position.isScrollingNotifier.value, isFalse);
      expect(RenderEditorLine.wordsDrawn - before, greaterThan(10), reason: 'at rest, the lines a drag carried are drawn where they stand');
      await same('at rest after the drag, at ${position.pixels}');
      // And standing still, nothing more is drawn.
      final still = RenderEditorLine.wordsDrawn;
      tester.allRenderObjects.whereType<RenderViewport>().first.markNeedsPaint();
      await tester.pump();
      expect(RenderEditorLine.wordsDrawn, still);

      // A fling, caught at frames along it, and where it ends.
      await tester.fling(find.byType(CustomScrollView), const Offset(0, -300), 1800);
      for (var i = 0; i < 12 && position.isScrollingNotifier.value; i++) {
        await tester.pump(const Duration(milliseconds: 37));
        await same('in a fling at ${position.pixels}');
      }
      await tester.pumpAndSettle();
      await same('at rest after the fling, at ${position.pixels}');

      // ignore: avoid_print
      print('at $ratio: $compared pictures of ${opened.length ~/ 4} pixels compared, $carried visual lines carried in the drag; ${faults.isEmpty ? 'every picture the same' : faults.join('\n  ')}');
      expect(faults, isEmpty);
      await finish(tester);
    });
  }

  testWidgets('a blink of the caret and a selection draw no words; a letter typed draws its own line\'s', (tester) async {
    final rig = await pumpEditor(tester, page, more: pieces(), caret: page.indexOf('The road in'));
    final view = rig.view;
    // The caret blinks: its line is painted, and with it every line of the page, none of them afresh.
    var before = RenderEditorLine.wordsDrawn;
    final keptBefore = RenderEditorLine.wordsKept;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(RenderEditorLine.wordsDrawn, before, reason: 'a caret turning draws no words');
    expect(RenderEditorLine.wordsKept, greaterThan(keptBefore), reason: 'the page was painted, from what was kept');

    // A selection over three lines: its ground and the words in its paper are drawn, the words themselves kept.
    before = RenderEditorLine.wordsDrawn;
    view.dispatch(TransactionSpec(selection: EditorSelection.single(page.indexOf('The road in'), page.indexOf('Snacks'))));
    await tester.pump();
    expect(RenderEditorLine.wordsDrawn, before, reason: 'a selection draws no line\'s words again');

    // A letter typed into a paragraph: that line is laid out and its visual lines drawn, and no other line's.
    view.dispatch(TransactionSpec(selection: EditorSelection.single(page.indexOf('The road in'))));
    await tester.pump();
    final line = drawn(tester).firstWhere((line) => line.from <= view.state.selection.main.head && line.to >= view.state.selection.main.head);
    before = RenderEditorLine.wordsDrawn;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.selection.main.head, insert: 'x'), userEvent: 'input.type'));
    await tester.pump();
    final typed = RenderEditorLine.wordsDrawn - before;
    expect(typed, greaterThan(0));
    expect(typed, lessThanOrEqualTo(line.visualLines.length), reason: 'a letter draws the visual lines of its own line (${line.visualLines.length}), not $typed');
    await finish(tester);
  });
}
