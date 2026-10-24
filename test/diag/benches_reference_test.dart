import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/diag/scene_bench.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// The scene bench held to the page: `fixtures/benches-390.json` is what Chromium drew for `diag/WispBench.tsx` and
/// `diag/SceneBench.tsx` mounted alone at 390 x 844 (the smoke bench went with the smoke, 2026-10-24, and its half of
/// the fixture is no one's now) (the script that made it is described in the worker's report;
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

/// What the scene's haze is drawn with, loaded before a screen is built: the program and the noise table come on the
/// machine's own clock, not the test's, so a picture taken before them would be of the words without their haze on
/// one run and with it on the next.
Future<void> _smoke(WidgetTester tester) async {
  await tester.runAsync(() => WispKit.load(seeds: const [7]));
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(BlurEdgeSettings.instance.reset);

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
