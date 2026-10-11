import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/diag/frame_clock.dart';
import 'package:ghost_md/diag/wisp_bench.dart';
import 'package:ghost_md/diag/wisp_bench_run.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// `diag/WispBench.test.tsx`, case for case: the smoke bench as a screen. It opens over the developer page, offers
/// the three drawings, wears the one chosen, runs the nine cells one surface at a time and puts them in a table.
/// The frame times themselves are the clock's (frame_clock_test.dart); a test's frames say nothing about any
/// engine's, and nothing here reads them as if they did.
///
/// What differs: the page's surfaces were found by `data-draw`; here by the label each has in its header. What a
/// surface wore is read from the strips its edge is drawn through, so the run's "wearing" column is checked too,
/// which jsdom, with no sizes and so a page that never scrolled, could not show.

Finder _key(String name) => find.byKey(ValueKey(name));

/// The surfaces on the screen, by the drawing each wears.
List<String> _surfaces(WidgetTester tester) => [for (final label in tester.widgetList<Text>(_key('bench-head-label'))) label.data!];

/// One of the kit's segmented options, chosen by its word.
Future<void> _choose(WidgetTester tester, String word) async {
  await tester.tap(find.descendant(of: find.byType(GlacierSegmentedControl), matching: find.text(word)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// A link in the sentence about the whole app, by its words; null when the sentence has none such.
TapGestureRecognizer? _link(WidgetTester tester, String words) {
  final sentence = tester.widget<RichText>(find.descendant(of: _key('bench-app-wide'), matching: find.byType(RichText)));
  TapGestureRecognizer? found;
  sentence.text.visitChildren((span) {
    if (span is TextSpan && span.text?.replaceAll(' ', ' ') == words && span.recognizer is TapGestureRecognizer) found = span.recognizer! as TapGestureRecognizer;
    return found == null;
  });
  return found;
}

Future<void> _away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

const _tiny = CellLimits(frames: 2, wallMs: 2000);

/// What the smoke is drawn with, loaded before a screen is built: the programs and the noise table come on the
/// machine's own clock, not the test's, so a picture taken before them would be of the plain edge on one run and of
/// the smoke on the next.
Future<void> _smoke(WidgetTester tester) async {
  await tester.runAsync(() async {
    await WispKit.load();
    await wispMaskBands();
  });
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(() {
    WispSettings.instance.reset();
    WispDrift.instance.debugReset();
  });

  group('the smoke bench', () {
    testWidgets('opens as a dialog wearing the filter, and closes on Escape', (tester) async {
      var closed = 0;
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () => closed += 1, kept: MemoryStored()));
      expect(find.bySemanticsLabel('Smoke bench'), findsWidgets);
      expect(find.text('Smoke bench'), findsOneWidget);
      expect(_surfaces(tester), ['Filter']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
      await _away(tester);
    });

    testWidgets('closes on the back gesture', (tester) async {
      // Not a case of the page's file, which left the gesture to core/back.ts's own: here it is the same stack.
      var closed = 0;
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () => closed += 1, kept: MemoryStored()));
      expect(backStack.goBack(), isTrue);
      expect(closed, 1);
      await _away(tester);
    });

    testWidgets('is nothing while closed', (tester) async {
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: false, onClose: () {}, kept: MemoryStored()));
      expect(find.text('Smoke bench'), findsNothing);
      expect(_surfaces(tester), isEmpty);
      // And asks for no frames: a closed bench counts nothing.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await _away(tester);
    });

    testWidgets('wears the drawing chosen, one surface at a time, and all three side by side for looking', (tester) async {
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () {}, kept: MemoryStored()));
      await _choose(tester, 'Mask');
      expect(_surfaces(tester), ['Mask']);
      await _choose(tester, 'No smoke');
      expect(_surfaces(tester), ['No smoke']);
      await tester.tap(find.text('Side by side'));
      await tester.pump();
      expect(_surfaces(tester), ['Filter', 'Mask', 'No smoke']);
      await tester.tap(find.text('One at a time'));
      await tester.pump();
      expect(_surfaces(tester), ['No smoke']);
      await _away(tester);
    });

    testWidgets('runs the nine cells one surface at a time and puts them in a table with what each surface wore', (tester) async {
      // Frames on the test's clock, one every 16 ms, so the page without smoke holds its frames and the run goes on
      // to the other six every time. The busy verdict is floorVerdict's, and is tried below on numbers.
      final written = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') written.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () {}, kept: MemoryStored(), quick: _tiny, long: _tiny, settle: Duration.zero, version: '1.5.0'));
      await tester.tap(find.text('Run the bench'));
      await tester.pump();
      expect(find.text('Running'), findsOneWidget);
      // The run mounts one drawing after another; turn the clock until it says it is done. A run is some two hundred
      // frames here; one that has not finished in a thousand never will.
      var most = 0;
      for (var frame = 0; _key('bench-status').evaluate().isNotEmpty; frame++) {
        if (frame == 1000) fail('The bench was still running after a thousand frames.');
        await tester.pump(const Duration(milliseconds: 16));
        // Only one surface is ever on the screen: the run switches them rather than adding them.
        most = _surfaces(tester).length > most ? _surfaces(tester).length : most;
      }
      await tester.pump(const Duration(milliseconds: 16));
      String cell(int row, int column) => tester.widget<Text>(_key('bench-cell-$row-$column')).data!;
      // The page without smoke goes first: its floor decides whether the rest is worth running.
      expect([for (var row = 1; row <= 9; row++) [cell(row, 0), cell(row, 1)]], [
        ['No smoke', 'At rest'],
        ['No smoke', 'One repaint a frame'],
        ['No smoke', 'Scrolling'],
        ['Filter', 'At rest'],
        ['Filter', 'One repaint a frame'],
        ['Filter', 'Scrolling'],
        ['Mask', 'At rest'],
        ['Mask', 'One repaint a frame'],
        ['Mask', 'Scrolling'],
      ]);
      expect(_key('bench-cell-10-0'), findsNothing);
      // What each surface wore, read from the view and not from the choice.
      expect([for (final row in const [1, 4, 7]) cell(row, 2)], ['nothing', 'filter: top + foot', 'mask: top + foot']);
      expect(find.textContaining('The page without smoke held its frames', findRichText: true), findsOneWidget);
      expect(tester.widget<Text>(_key('bench-where')).data, startsWith('Ghost.md 1.5.0 · '));
      expect(most, 1);
      expect(_surfaces(tester), hasLength(1));
      // The run's mark is gone with it.
      expect(_key('bench-mark'), findsNothing);
      // The table goes on the clipboard as text, and the button says so for a moment.
      await tester.ensureVisible(find.textContaining('Copy as text', findRichText: true));
      await tester.pump();
      await tester.tap(find.textContaining('Copy as text', findRichText: true));
      await tester.pump();
      expect(written, hasLength(1));
      expect(written.single, contains('draw\tcondition\twearing\tn\tmedian\tp90\tworst'));
      expect(written.single.split('\n').where((line) => RegExp(r'^(none|filter|mask)\t').hasMatch(line)), hasLength(9));
      expect(find.textContaining('Copied', findRichText: true), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(find.textContaining('Copy as text', findRichText: true), findsOneWidget);
      await _away(tester);
    });

    testWidgets('tells the whole app which to draw, from the edge’s own key, and takes it back', (tester) async {
      final kept = MemoryStored();
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () {}, kept: kept));
      await _choose(tester, 'Mask');
      _link(tester, 'Use the mask app-wide')!.onTap!();
      await tester.pump();
      expect(kept.getItem('glyph-wisp-draw'), 'mask');
      expect(find.textContaining('The whole app draws the mask from its next start.', findRichText: true), findsOneWidget);
      // What the app reads as it starts.
      expect(wispDrawAsked(kept), WispDraw.mask);
      _link(tester, 'Back to the default')!.onTap!();
      await tester.pump();
      expect(kept.getItem('glyph-wisp-draw'), isNull);
      // No smoke is not a thing the app can be told to draw.
      await _choose(tester, 'No smoke');
      expect(_link(tester, 'Use the none app-wide'), isNull);
      await _away(tester);
    });

    testWidgets('says so when the smoke is switched off, since every surface then wears nothing', (tester) async {
      // Not a case of the page's file; the page drew the same banner from the preference.
      WispSettings.instance.wanted = false;
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () {}, kept: MemoryStored()));
      expect(find.textContaining('The smoke is switched off under Appearance › Motion'), findsOneWidget);
      WispSettings.instance.wanted = true;
      await tester.pump();
      expect(find.textContaining('The smoke is switched off'), findsNothing);
      await _away(tester);
    });
  });

  group('floorVerdict', () {
    BenchRow row(BenchDraw draw, BenchCondition condition, double median) =>
        BenchRow(draw: draw, condition: condition, wearing: '', reading: Reading(n: 10, median: median, p90: median, worst: median));

    test('says nothing until the page without smoke has been measured', () {
      expect(floorVerdict([]), isNull);
      expect(floorVerdict([row(BenchDraw.filter, BenchCondition.scroll, 3157)]), isNull);
    });

    test('throws the table away when the bare page cannot hold a frame, and licenses it when it can', () {
      // The lane session's own table: a 17ms floor is what made the 585 beside it worth reading.
      expect(floorVerdict([row(BenchDraw.none, BenchCondition.idle, 16.7), row(BenchDraw.none, BenchCondition.scroll, 17.2)])?.ok, isTrue);
      // The browser pane's throttle, or a machine at load 120: every number on the page is the machine's.
      final busy = floorVerdict([row(BenchDraw.none, BenchCondition.idle, 1016.7), row(BenchDraw.none, BenchCondition.scroll, 83.3)]);
      expect(busy?.ok, isFalse);
      expect(busy?.words, contains('this machine was busy'));
      // The repaint cell is the page's own doing and is not the floor.
      expect(floorVerdict([row(BenchDraw.none, BenchCondition.idle, 16.7), row(BenchDraw.none, BenchCondition.repaint, 40)])?.ok, isTrue);
    });
  });

  group('wearingOf', () {
    test('reads what the view wears rather than what was asked for', () {
      expect(wearingOf(const []), 'nothing');
      const size = Size(512, 256);
      expect(
        wearingOf(const [
          WispMaskStrip(rect: Rect.fromLTRB(0, 0, 352, 136), whole: Rect.zero, band: null, bandSize: size, bandAt: Offset.zero),
          WispMaskStrip(rect: Rect.fromLTRB(0, 278, 352, 382), whole: Rect.zero, band: null, bandSize: size, bandAt: Offset.zero),
        ]),
        'mask: top + foot',
      );
      // The filter with its foot alone, and what reduced motion leaves of it.
      const foot = WispSmoke(seed: 3, frequency: Offset(0.018, 0.06), lipB: 300, bend: 23, blur: 3.4);
      expect(wearingOf(const [WispSmokeStrip(rect: Rect.fromLTRB(0, 200, 352, 382), smoke: foot, within: Rect.zero)]), 'filter: foot');
      expect(wearingOf(const [WispFadeStrip(rect: Rect.fromLTRB(0, 350, 352, 382), fade: WispFade.none)]), 'fade: foot');
    });
  });

  group('reportText', () {
    test('is one line a cell, tab-separated, under where it ran', () {
      final text = reportText('Ghost.md 1.5.0 · browser · Chromium · 1024x768 @2', const [
        BenchRow(draw: BenchDraw.filter, condition: BenchCondition.scroll, wearing: 'filter: top + foot', reading: Reading(n: 3, median: 3157, p90: 6507, worst: 6507.4)),
      ]);
      expect(text.split('\n'), [
        'Ghost.md 1.5.0 · browser · Chromium · 1024x768 @2',
        'draw\tcondition\twearing\tn\tmedian\tp90\tworst',
        'filter\tscroll\tfilter: top + foot\t3\t3157.0\t6507.0\t6507.4',
      ]);
    });

    test('carries the floor’s verdict under where it ran, so a pasted table cannot lose it', () {
      final text = reportText('where', const [BenchRow(draw: BenchDraw.none, condition: BenchCondition.idle, wearing: 'nothing', reading: Reading(n: 7, median: 1016.7, p90: 1016.7, worst: 1016.7))]);
      expect(text.split('\n')[1], contains('this machine was busy'));
    });

    test('says where it runs in the page’s shape, from what the app can see', () {
      expect(whereItRuns(version: '0.1.0', platform: 'android', engine: 'Impeller', width: 390, height: 844, ratio: 2), 'Ghost.md 0.1.0 · android · Impeller · 390x844 @2');
      expect(whereItRuns(version: '0.1.0', platform: 'android', engine: 'Impeller', width: 411.4, height: 891.4, ratio: 2.625), 'Ghost.md 0.1.0 · android · Impeller · 411.4x891.4 @2.625');
    });
  });
}
