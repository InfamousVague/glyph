// The five effects and the smoke at fixed times, beside Chromium's. tool/editor_reference.mjs held the page's
// clock at 0, 0.7 and 1.9 seconds (the frame loop told that time, CSS and SVG animations set to it) and wrote each
// letter's computed `top`, `opacity`, `filter`, `color` and `text-shadow` with a picture. Here the same note is
// drawn with the marks' clock held at the same moments: the letter effects' numbers are held to the page's, and a
// picture of each moment is written to shots/ to be looked at beside fixtures/marks-at-*.png.
//
// What the pictures show, effect by effect, is said in lib/editor/marks/text_effects.dart and wisp_format.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/state/state.dart' show Extension;

import '../../support/render.dart';
import 'support.dart';

final RegExp _delay = RegExp(r'animation-delay:\s*(-?\d+)ms');
final RegExp _px = RegExp(r'(-?[\d.]+)px');
final RegExp _srgb = RegExp(r'color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)');

void main() {
  setUpAll(loadAppFonts);

  for (final name in const <String>['marks-at-0', 'marks-at-0_7', 'marks-at-1_9', 'marks-dark-at-0']) {
    testWidgets('$name: the letters where the page\'s keyframes have them, and a picture', (tester) async {
      final fixture = Measured.read('marks', name);
      final at = (fixture.json['at'] as num).toDouble();
      MarkClock.hold = at;
      addTearDown(() => MarkClock.hold = null);
      await pumpMeasured(tester, fixture, formats: marks, more: <Extension>[markExtensions(marks)], shaders: true);
      var waves = 0, haunts = 0, shimmers = 0;
      for (final mark in fixture.drawn) {
        final classes = (mark['classes'] as List).cast<String>();
        final delay = int.tryParse(_delay.firstMatch((mark['attrs'] as Map)['style'] as String? ?? '')?.group(1) ?? '');
        if (delay == null) continue;
        final em = (mark['size'] as num).toDouble();
        final label = '${classes.last} "${mark['text']}" at ${mark['pos']}';
        if (classes.contains('cm-effect-wave')) {
          final top = double.parse(_px.firstMatch(mark['top'] as String)!.group(1)!);
          expect(waveLift(at, delay) * em, closeTo(top, 0.02), reason: label);
          waves += 1;
        } else if (classes.contains('cm-effect-haunt')) {
          final gone = hauntFade(at, delay);
          expect(1 - 0.7 * gone, closeTo(double.parse(mark['opacity'] as String), 0.002), reason: label);
          final blur = _px.firstMatch(mark['filter'] as String);
          if (blur != null) expect(0.05 * em * gone, closeTo(double.parse(blur.group(1)!), 0.01), reason: label);
          haunts += 1;
        } else if (classes.contains('cm-effect-shimmer')) {
          // The glint is all there or not at all: a shadow on the dark page, a pale letter on paper.
          final shadow = mark['shadow'] as String, color = _srgb.firstMatch(mark['color'] as String);
          final lit = fixture.theme == 'dark' ? shadow != 'none' : color != null;
          expect(shimmerGlint(at, delay), lit ? 1 : 0, reason: label);
          shimmers += 1;
        }
      }
      expect(waves, 8);
      expect(haunts, 11);
      expect(shimmers, 6);
      await shot(tester, name.replaceFirst('marks-', 'effects-'));
    });
  }

  test('the smoke and the filters at a moment are the numbers the page writes into its filters', () {
    // wispFormat.ts `pose(0)`: slot 0 at rest.
    final rest = smokePose(0, 0);
    expect(rest.bend, 36);
    expect(rest.soft, 3.2);
    expect(rest.lift, 0);
    expect(rest.shown, 0.7);
    expect(rest.frequency.dx, 0.02);
    expect(rest.frequency.dy, 0.07);
    // And slot 3 a second and a half in, each number rounded as `toFixed` rounds it.
    final moved = smokePose(3, 1.5);
    expect(moved.bend, closeTo(36 + 14 * -0.8085, 0.06));
    expect(moved.frequency.dx, closeTo(0.02, 0.0061));
    // textEffects.ts `heat`: body text of 16px at full strength, at rest and a breath in.
    final still = heatFilter(5, 16, 1, still: true);
    expect(still.frequency.dx, 0.02);
    expect(still.frequency.dy, 0.085);
    expect(still.seed, 7);
    expect(still.bend, 5.5);
    expect(still.blur, 0.6);
    final half = heatFilter(1.2, 16, 0.55);
    expect(half.frequency.dx, closeTo(0.028, 1e-9));
    expect(half.frequency.dy, closeTo(0.12, 1e-9));
    // The seed steps every 0.15 s: the third of them a little past 0.3 s into its 0.9.
    expect(heatFilter(1.25, 16, 0.55).seed, 7 + 2);
    expect(half.bend, 3.03);
    expect(half.blur, 0.33);
    // A filter is sized to the type it is on, held above half.
    expect(heatFilter(0, 32, 1, still: true).bend, 11);
    expect(heatFilter(0, 4, 1, still: true).bend, 2.75);
    // textEffects.ts `frost`: the rime half out, growing, held, and drawing back.
    expect(frostFilter(0, 16).radius, closeTo(0.7, 1e-9));
    expect(frostFilter(3.15, 16).radius, closeTo(1.4, 1e-9));
    expect(frostFilter(5, 16).radius, closeTo(1.4, 1e-9));
    expect(frostFilter(6.3, 16).radius, closeTo(1.05, 1e-9));
    expect(frostFilter(2.5, 16).seed, 5);
    expect(frostFilter(0, 16, still: true).radius, closeTo(1.4, 1e-9));
  });
}
