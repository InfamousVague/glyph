import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/diag/frame_clock.dart';
import 'package:ghost_md/diag/scene_bench.dart';
import 'package:ghost_md/diag/wisp_bench.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// The two benches held to the page: `fixtures/benches-390.json` is what Chromium drew for `diag/WispBench.tsx` and
/// `diag/SceneBench.tsx` mounted alone at 390 x 844 (the script that made it is described in the worker's report;
/// the page's pictures are `fixtures/web/`). Rectangles agree to half a pixel. The page had no status bar
/// (`--app-safe-top` was 0 there), so what is measured here is taken from under the bench's own top inset.
///
/// The frame times are never compared: a page's and Flutter's are different engines' answers.
final Map<String, dynamic> _web = jsonDecode(File('test/diag/fixtures/benches-390.json').readAsStringSync()) as Map<String, dynamic>;

Rect _of(String group, String name, [int index = 0]) {
  final r = ((_web[group] as Map<String, dynamic>)[name] as List)[index] as Map<String, dynamic>;
  return Rect.fromLTWH((r['x'] as num).toDouble(), (r['y'] as num).toDouble(), (r['w'] as num).toDouble(), (r['h'] as num).toDouble());
}

void _near(Rect got, Rect want, String what, {double within = 0.5}) {
  for (final (name, a, b) in [('left', got.left, want.left), ('top', got.top, want.top), ('width', got.width, want.width), ('height', got.height, want.height)]) {
    expect((a - b).abs(), lessThanOrEqualTo(within), reason: '$what $name: here ${a.toStringAsFixed(2)}, the page ${b.toStringAsFixed(2)}');
  }
}

Finder _key(String name) => find.byKey(ValueKey(name));

/// Takes the screen down. pumpApp turned the shadows on for a picture; the binding wants its own switch back.
Future<void> _away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

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

  group('the smoke bench against the page', () {
    testWidgets('its bar, its words, its controls and its surface stand where the page’s do', (tester) async {
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () {}, kept: MemoryStored()));
      await tester.pump(const Duration(milliseconds: 100));
      final top = tester.element(_key('bench-over')).tokens.len('app-safe-top');
      Rect at(Finder finder) => tester.getRect(finder).translate(0, -top);

      _near(at(_key('bench-bar')), _of('wisp', 'bar'), 'bar');
      _near(at(_key('bench-title')), _of('wisp', 'title'), 'title');
      _near(at(_key('bench-close')), _of('wisp', 'close'), 'close');
      _near(at(find.descendant(of: _key('bench-close'), matching: find.byType(AppIcon))), _of('wisp', 'closeIcon'), 'the X');
      expect((at(_key('bench-body')).top - _of('wisp', 'body').top).abs(), lessThanOrEqualTo(0.5));
      _near(at(_key('bench-lede')), _of('wisp', 'lede', 0), 'lede');
      _near(at(find.byType(GlacierSegmentedControl)), _of('wisp', 'segmented'), 'the choice');
      for (final (index, word) in const ['Side by side', 'Run the bench', 'Run long'].indexed) {
        _near(at(find.widgetWithText(RowAction, word)), _of('wisp', 'button', index), word);
      }
      _near(at(_key('bench-app-wide')), _of('wisp', 'lede', 1), 'the app-wide sentence');
      // The link is a span of the sentence: its box is the paragraph's own for those words.
      final sentence = tester.renderObject<RenderParagraph>(find.descendant(of: _key('bench-app-wide'), matching: find.byType(RichText)));
      final words = sentence.text.toPlainText();
      final from = words.indexOf('Use');
      final boxes = sentence.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: words.length), boxHeightStyle: ui.BoxHeightStyle.max);
      expect(boxes, hasLength(1), reason: 'the link stands on one line');
      // On the sentence's second line (the sentence's own box, held above, is two lines tall), from its start.
      final box = boxes.single.toRect().shift(at(_key('bench-app-wide')).topLeft), webLink = _of('wisp', 'link');
      expect((box.left - webLink.left).abs(), lessThanOrEqualTo(0.5), reason: 'the link’s left: here ${box.left}, the page ${webLink.left}');
      expect((box.width - webLink.width).abs(), lessThanOrEqualTo(0.5), reason: 'the link’s width: here ${box.width}, the page ${webLink.width}');
      expect(box.top, greaterThan(_of('wisp', 'lede', 1).top + 10));
      final surface = at(find.byWidgetPredicate((w) => w.key is GlobalKey && w.runtimeType.toString() == '_Surface'));
      _near(surface, _of('wisp', 'surface'), 'surface');
      _near(at(_key('bench-head')), _of('wisp', 'head'), 'head');
      _near(at(_key('bench-head-label')), _of('wisp', 'headLabel'), 'the head’s label');
      // The counter's words are frame times; only where it ends and how tall it stands are the page's.
      final counter = at(_key('bench-counter')), webCounter = _of('wisp', 'counter');
      expect((counter.right - webCounter.right).abs(), lessThanOrEqualTo(0.5));
      expect((counter.top - webCounter.top).abs(), lessThanOrEqualTo(0.5));
      expect((counter.height - webCounter.height).abs(), lessThanOrEqualTo(0.5));
      Finder lines(String words) => find.ancestor(of: find.text(words, findRichText: true), matching: find.byType(FractionLines));
      _near(at(lines('A page to scroll')), _of('wisp', 'h3'), 'the first heading');
      for (var i = 0; i < benchParagraphs.length; i++) {
        _near(at(lines(benchParagraphs[i]).first), _of('wisp', 'p', i), 'paragraph ${i + 1}');
      }
      // The whole of the prose: eight sections of the same words, and the page's own bottom edge.
      final prose = _of('wisp', 'prose');
      final last = at(lines(benchParagraphs.last).last);
      expect((last.bottom - prose.bottom).abs(), lessThanOrEqualTo(0.5), reason: 'the last paragraph ends where the page’s article does: here ${last.bottom}, the page ${prose.bottom}');
      await _away(tester);
    });

    testWidgets('a run’s table stands as the page’s does: where it ran, the verdict, the columns and the rows', (tester) async {
      await _smoke(tester);
      await pumpApp(tester, home: WispBench(open: true, onClose: () {}, kept: MemoryStored(), quick: const CellLimits(frames: 2, wallMs: 2000), settle: Duration.zero));
      await tester.tap(find.text('Run the bench'));
      await tester.pump();
      for (var frame = 0; _key('bench-status').evaluate().isNotEmpty; frame++) {
        if (frame == 1000) fail('The bench was still running after a thousand frames.');
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 16));
      final origin = tester.getRect(_key('bench-results')).topLeft, webOrigin = _of('wispRun', 'results').topLeft;
      Rect at(Finder finder) => tester.getRect(finder).shift(-origin);
      Rect web(String name, [int index = 0]) => _of('wispRun', name, index).shift(-webOrigin);
      Finder cell(int row, int column) => find.ancestor(of: _key('bench-cell-$row-$column'), matching: find.byType(Padding)).first;

      _near(at(_key('bench-where')), web('meta'), 'where it ran');
      _near(at(_key('bench-verdict')), web('verdict'), 'the verdict');
      for (var column = 0; column < 7; column++) {
        // The first row: No smoke, at rest. Its numbers are four characters here as there. A cell on the page is as
        // tall as its row; here it is as tall as its own words, so a row's height is its tallest cell's.
        for (final (row, name) in const [(0, 'th'), (1, 'td1')]) {
          final here = at(cell(row, column)), there = web(name, column);
          expect((here.left - there.left).abs(), lessThanOrEqualTo(0.5), reason: '$name ${column + 1} left: here ${here.left}, the page ${there.left}');
          expect((here.top - there.top).abs(), lessThanOrEqualTo(0.5), reason: '$name ${column + 1} top: here ${here.top}, the page ${there.top}');
          expect((here.width - there.width).abs(), lessThanOrEqualTo(0.5), reason: '$name ${column + 1} width: here ${here.width}, the page ${there.width}');
        }
      }
      double tall(int row) => [for (var column = 0; column < 7; column++) at(cell(row, column)).height].reduce((a, b) => a > b ? a : b);
      expect((tall(0) - web('th').height).abs(), lessThanOrEqualTo(0.5), reason: 'the headings’ height: here ${tall(0)}, the page ${web('th').height}');
      // The rows wearing nothing and the mask are as tall as the page's; the filter's are not compared, since the
      // page wrote the filter's own text after "filter: top + foot" and so stood nine lines tall.
      for (final row in const [0, 1, 2, 6, 7, 8]) {
        final there = web('row', row);
        expect((tall(row + 1) - there.height).abs(), lessThanOrEqualTo(0.5), reason: 'row ${row + 1} height: here ${tall(row + 1)}, the page ${there.height}');
      }
      final table = at(_key('bench-table'));
      expect((table.left - web('table').left).abs(), lessThanOrEqualTo(0.5));
      expect((table.top - web('table').top).abs(), lessThanOrEqualTo(0.5));
      expect((table.width - web('table').width).abs(), lessThanOrEqualTo(0.5));
      expect((at(find.byType(RowAction).last).height - web('copy').height).abs(), lessThanOrEqualTo(0.5));
      expect((at(find.byType(RowAction).last).width - web('copy').width).abs(), lessThanOrEqualTo(0.5));
      await _away(tester);
    });

    for (final theme in const ['light', 'dark']) {
      testWidgets('a picture, $theme', (tester) async {
        await _smoke(tester);
      await pumpApp(tester, prefs: AppPreferences(theme: theme), home: WispBench(open: true, onClose: () {}, kept: MemoryStored()));
        await shot(tester, 'wisp-bench-$theme');
      });

      testWidgets('a picture of a run, $theme', (tester) async {
        await _smoke(tester);
      await pumpApp(tester, prefs: AppPreferences(theme: theme), home: WispBench(open: true, onClose: () {}, kept: MemoryStored(), quick: const CellLimits(frames: 2, wallMs: 2000), settle: Duration.zero));
        await tester.tap(find.text('Run the bench'));
        await tester.pump();
        for (var frame = 0; _key('bench-status').evaluate().isNotEmpty && frame < 1000; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.ensureVisible(_key('bench-where'));
        await tester.drag(_key('bench-body'), const Offset(0, -300));
        await shot(tester, 'wisp-bench-run-$theme');
      });
    }
  });

  group('the scene bench against the page', () {
    testWidgets('its bar stands where the page’s does, and its body is the rest of the window', (tester) async {
      await _smoke(tester);
      await pumpApp(tester, home: SceneBench(script: 'heat', onClose: () {}));
      final top = tester.element(_key('scene-over')).tokens.len('app-inset-top');
      Rect at(Finder finder) => tester.getRect(finder).translate(0, -top);
      _near(at(_key('scene-bar')), _of('scene', 'bar'), 'bar');
      _near(at(_key('bench-title')), _of('scene', 'title'), 'title');
      _near(at(_key('scene-again')), _of('scene', 'again'), 'Play again');
      _near(at(find.descendant(of: _key('scene-again'), matching: find.byType(AppIcon))), _of('scene', 'againIcon'), 'its icon');
      _near(at(find.text('Play again')), _of('scene', 'againWord'), 'its word');
      _near(at(_key('bench-close')), _of('scene', 'close'), 'close');
      _near(at(find.descendant(of: _key('bench-close'), matching: find.byType(AppIcon))), _of('scene', 'closeIcon'), 'the X');
      expect((at(_key('scene-body')).top - _of('scene', 'body').top).abs(), lessThanOrEqualTo(0.5));
      await _away(tester);
    });

    testWidgets('the words under a scene that has left are in the middle of the body, as the page’s are', (tester) async {
      await pumpApp(
        tester,
        home: SceneBench(
          script: 'heat',
          onClose: () {},
          // A scene that leaves at once: what the body shows after a play.
          scene: (context, play) {
            WidgetsBinding.instance.addPostFrameCallback((_) => play.played());
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      final top = tester.element(_key('scene-over')).tokens.len('app-inset-top');
      final body = tester.getRect(_key('scene-body')), words = tester.getRect(_key('scene-played'));
      // The page's own picture has them centred in the body; the paragraph there is the body's whole box.
      expect((words.center.dx - body.center.dx).abs(), lessThanOrEqualTo(0.5));
      expect((words.center.dy - body.center.dy).abs(), lessThanOrEqualTo(0.5));
      expect((body.top - top - _of('scene', 'played').top).abs(), lessThanOrEqualTo(0.5));
      await shot(tester, 'scene-bench-played-light');
    });

    for (final theme in const ['light', 'dark']) {
      testWidgets('a picture, $theme', (tester) async {
        await _smoke(tester);
      await pumpApp(tester, prefs: AppPreferences(theme: theme), home: SceneBench(script: 'heat', onClose: () {}));
        await shot(tester, 'scene-bench-$theme');
      });
    }
  });
}
