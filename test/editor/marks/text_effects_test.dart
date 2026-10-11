// Ports src/app/editor/textEffects.test.ts (../glyph), case for case and in its order, onto
// lib/editor/marks/text_effects.dart.
//
// What is read differently, because the Dart file draws differently (its header, "What differs"):
// - The page builds SVG filters (`TEXT_EFFECTS.heat.build`, `.frost.build`) and the tests read their attributes.
//   Here the same numbers are `heatFilter` and `frostFilter` at a time, so the cases read those: the attributes'
//   values at rest, and "an <animate>" as "the number moves with the clock" (none under reduced motion).
// - A letter effect's CSS (`theme`, its `@keyframes` and its reduced-motion rule) is the keyframe functions
//   `waveLift`, `shimmerGlint`, `hauntFade`: "a cycle its CSS runs for" is the function's period. The still rule is
//   in the painter (`still`), which only a drawing shows; it is left to effects_test.dart.
// - In the editor the marks are read off the view's decoration sets rather than the DOM, and the per-letter mark
//   is `cm-effectLetter` (with the page's classes on a letter effect's).
//
// Left out: that the filters' <svg> leaves with the editor (there is no element to leave).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/text_effects.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/marks.dart';

const heat = GlyphFormat(name: 'Heat', delimiter: '🔥🔥', look: EffectLook('heat'));
const wave = GlyphFormat(name: 'Wave', delimiter: '🌊🌊', look: EffectLook('wave'));
const shimmer = GlyphFormat(name: 'Shimmer', delimiter: '✨✨', look: EffectLook('shimmer'));
final Map<String, EffectLookSpec> looks = <String, EffectLookSpec>{
  'Heat': (length: '🔥🔥'.length, effect: 'heat'),
  'Shimmer': (length: '✨✨'.length, effect: 'shimmer'),
};

EditorState state(String doc, [int selection = 0]) => EditorState.create(doc: doc, selection: EditorSelection.single(selection), extensions: noteExtensions(formats: const [heat, wave, shimmer]));

List<String> words(EditorState s, bool atCaret) => [for (final r in effectRanges(s, looks, 0, s.doc.length, atCaret)) s.doc.sliceString(r.from, r.to)];

typedef Marked = ({int from, int to, Map<String, String> attrs});

/// The marks of class `name` the view draws, in document order.
List<Marked> marksOf(EditorView view, String name) {
  final found = <Marked>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      if (value is MarkDecoration && (value.attrs['class'] ?? '').split(' ').contains(name)) found.add((from: from, to: to, attrs: value.attrs));
      return null;
    });
  }
  return found..sort((a, b) => a.from != b.from ? a.from - b.from : b.to - a.to);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('effects on words', () {
    test('draws the words between the flames, and neither flame', () {
      final s = state('It was 🔥🔥too hot to touch🔥🔥 all day, and 🔥🔥again🔥🔥.');
      expect(words(s, false), ['too hot to touch', 'again']);
      expect(effectRanges(s, looks, 0, s.doc.length, false).every((r) => r.effect == 'heat'), isTrue);
    });

    test('lifts while the caret is in the words, in a view that can be edited, and only then', () {
      const doc = 'a 🔥🔥hot🔥🔥 and 🔥🔥warm🔥🔥';
      final inside = state(doc, doc.indexOf('hot') + 1);
      expect(words(inside, true), ['warm']);
      // A view that cannot be edited never lifts it.
      expect(words(inside, false), ['hot', 'warm']);
      // On a flame counts as in it, so the caret beside a mark shows the plain words to edit.
      expect(words(state(doc, doc.indexOf('🔥🔥hot')), true), ['warm']);
    });

    test('draws nothing where a mark has no words, or no mark names an effect', () {
      expect(words(state('🔥🔥🔥🔥'), false), isEmpty);
      expect(effectRanges(state('🔥🔥hot🔥🔥'), const <String, EffectLookSpec>{}, 0, 11, false), isEmpty);
      // `textEffects([...])` is `[]` on the page: no extension at all, so a state made with it runs no plugin.
      expect(effectLooksOf(const [GlyphFormat(name: 'Shout', delimiter: '^^', look: StyleLook(''))]), isEmpty);
      expect(EditorState.create(extensions: textEffects(const [GlyphFormat(name: 'Shout', delimiter: '^^', look: StyleLook(''))])).facet(viewPlugin), isEmpty);
    });

    test('draws an effect inside another, each its own stretch, the outer first', () {
      final s = state('a 🔥🔥hot ✨✨and bright✨✨ day🔥🔥');
      expect(
        [
          for (final r in effectRanges(s, looks, 0, s.doc.length, false)) [r.effect, s.doc.sliceString(r.from, r.to)],
        ],
        [
          ['heat', 'hot ✨✨and bright✨✨ day'],
          ['shimmer', 'and bright'],
        ],
      );
    });

    test('passes a letter effect along the letters: spaces aside, each a step behind, already under way', () {
      final s = state('go 🌊🌊a b🙂🌊🌊');
      final from = s.doc.toString().indexOf('a b');
      final letters = effectLetters(s, from, from + 'a b🙂'.length, const LetterEffect(cycleMs: 1000, stepMs: 300));
      expect([for (final l in letters) s.doc.sliceString(l.from, l.to)], ['a', 'b', '🙂']);
      // Each a step behind the one before, wrapped round the cycle, and negative, so none waits to start.
      expect([for (final l in letters) l.delayMs], [-1000, -700, -400]);
      final many = effectLetters(state('abcdefgh'), 0, 8, const LetterEffect(cycleMs: 1000, stepMs: 300));
      expect(many.every((l) => l.delayMs < 0 && l.delayMs >= -1000), isTrue);
    });

    test('builds heat for the type it is on, the same haze at any size, and still under reduced motion', () {
      // At rest (the clock at nought) the filter is what the page writes into its attributes.
      final body = heatFilter(0, 16, 1);
      expect(body.frequency, const Offset(0.0200, 0.0850)); // feTurbulence baseFrequency="0.0200 0.0850"
      expect(body.bend, 5.50); // feDisplacementMap scale
      expect(body.blur, 0.60); // feGaussianBlur stdDeviation
      // Two <animate>: the frequency breathes and the seed is re-rolled.
      expect(heatFilter(0.6, 16, 1).frequency, isNot(body.frequency));
      expect({for (var i = 0; i < 6; i++) heatFilter(i * 0.15 + 0.01, 16, 1).seed}.length, 6);
      // Twice the type: twice the bend and blur, and waves half as fine, so it looks the same.
      final heading = heatFilter(0, 32, 1);
      expect(heading.bend, 11.00);
      expect(heading.frequency, const Offset(0.0100, 0.0425));
      // Reduced motion: no <animate>, the filter at rest whatever the clock says.
      for (final t in <double>[0, 0.2, 0.6, 1.3, 2.0]) {
        final still = heatFilter(t, 16, 1, still: true);
        expect((still.frequency, still.seed, still.bend, still.blur), (body.frequency, body.seed, body.bend, body.blur), reason: 'at $t s');
      }
    });

    test('builds frost as a rime grown from the letters and coloured by the page, at rest under reduced motion', () {
      // feMorphology (dilate) is the rime's `radius`; the flood's colour is the painter's (the page's class
      // `cm-effectFrostIce`), which a picture shows (effects_test.dart).
      final moving = [for (final t in <double>[0, 1, 2, 3, 4, 5, 6]) frostFilter(t, 16)];
      // Two <animate>: the reach creeps out and back, and the grain's seed is re-rolled.
      expect({for (final f in moving) f.radius}.length, greaterThan(1));
      expect({for (final f in moving) f.seed}.length, greaterThan(1));
      expect(moving.every((f) => f.radius > 0), isTrue);
      final still = [for (final t in <double>[0, 1, 2, 3, 4, 5, 6]) frostFilter(t, 16, still: true)];
      expect({for (final f in still) (f.radius, f.seed, f.frequency, f.blur)}.length, 1);
    });

    test('gives every letter effect a cycle its CSS runs for, a step, and a still rule for reduced motion', () {
      // The page's keyframes, worked out in Dart: each runs for its effect's cycle.
      final keyframes = <String, double Function(double seconds, int delayMs)>{'wave': waveLift, 'shimmer': shimmerGlint, 'haunt': hauntFade};
      var seen = 0;
      for (final entry in textEffectsByName.entries) {
        final effect = entry.value;
        if (effect is! LetterEffect) continue;
        seen += 1;
        final name = entry.key;
        final at = keyframes[name];
        expect(at, isNotNull, reason: name);
        expect(effect.stepMs, greaterThan(0), reason: name);
        final cycle = effect.cycleMs / 1000;
        final samples = [for (var i = 0; i < 40; i++) i * cycle / 40];
        // It moves, and a cycle later it is where it was.
        expect({for (final t in samples) at!(t, -effect.cycleMs).toStringAsFixed(6)}.length, greaterThan(1), reason: name);
        for (final t in samples) {
          expect(at!(t + cycle, -effect.cycleMs), closeTo(at(t, -effect.cycleMs), 1e-6), reason: '$name at $t s');
        }
        // Not a shorter one: half a cycle on it is somewhere else, for some moment of it.
        expect(samples.any((t) => (at!(t + cycle / 2, -effect.cycleMs) - at(t, -effect.cycleMs)).abs() > 1e-3), isTrue, reason: name);
      }
      expect(seen, 3);
    });
  });

  group('the text above heated words', () {
    /// A page of lines 20 px apart, each with its text as a range and blank or not: a stand-in for the layout.
    ProbeLine page(List<({int from, int to, bool empty})> lines) => (x, y) {
      final index = (y / 20).floor();
      if (y < 0 || index >= lines.length) return null;
      final line = lines[index];
      // Across the line's width in characters of 10 px, from its start; past its end is its end.
      final across = (x / 10).floor();
      final at = line.from + (across < 0 ? 0 : across);
      final pos = at < line.to ? at : line.to;
      return (from: pos, to: pos, top: index * 20.0, empty: line.empty);
    };
    ({int from, int to, bool empty}) line(int from, int to, {bool empty = false}) => (from: from, to: to, empty: empty);
    const strengths = <double>[1, 0.5];

    test('is the line just above, under the words and a little either side, then the one above that, weaker', () {
      final probe = page([line(0, 40), line(41, 81), line(82, 122)]);
      // Words on the third line, from 100 px to 160 px.
      final above = textAbove(EffectSegment(100, 160, 40), 20, strengths, probe);
      expect(above, [(from: 41 + 9, to: 41 + 16, strength: 1.0), (from: 0 + 9, to: 0 + 16, strength: 0.5)]);
    });

    test('carries over one blank line between paragraphs to the text above it, and no further', () {
      final probe = page([line(0, 30), line(31, 31, empty: true), line(32, 60)]);
      expect([for (final a in textAbove(EffectSegment(0, 50, 40), 20, strengths, probe)) a.strength], [1.0]);
      // The weaker line stops at a blank line rather than jumping it.
      final gap = page([line(0, 30), line(31, 31, empty: true), line(32, 60), line(61, 90)]);
      expect(textAbove(EffectSegment(0, 50, 60), 20, strengths, gap), [(from: 32, to: 37, strength: 1.0)]);
    });

    test('is nothing on the first line, or above a line too short to reach the words', () {
      expect(textAbove(EffectSegment(0, 50, 0), 20, strengths, page([line(0, 30)])), isEmpty);
      final short = page([line(0, 3), line(4, 60)]);
      expect(textAbove(EffectSegment(200, 300, 20), 20, strengths, short), isEmpty);
    });
  });

  group('the effects in an editor', () {
    EditorView? view;
    tearDown(() {
      view?.destroy();
      view = null;
    });

    test('marks heated words bold with a slight waver of their own, and hangs the haze for the lines above off the view', () {
      const doc = 'so 🔥🔥hot🔥🔥 today';
      final on = view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(formats: const [heat], more: [textEffects(const [heat])])));
      // The page's own mark over the words: `.cm-textEffect.cm-effect-heat[data-effect=heat]` (bold is that class's rule).
      final marked = [for (final m in marksOf(on, 'cm-textEffect')) if (!(m.attrs['class'] ?? '').contains('cm-effectLetter')) m];
      expect([for (final m in marked) doc.substring(m.from, m.to)], ['hot']);
      expect(marked.single.attrs['data-effect'], 'heat');
      expect(marked.single.attrs['class']!.split(' '), contains('cm-effect-heat'));
      // The words waver too, but at under a third of the line above's bend: each letter says so, and the filter of
      // that strength is the page's `-heat-own`.
      final rising = textEffectsByName['heat']! as RisingEffect;
      final letters = marksOf(on, 'cm-effectLetter');
      expect([for (final l in letters) l.attrs['data-text']], ['h', 'o', 't']);
      expect([for (final l in letters) doc.substring(l.from, l.to)], ['h', 'o', 't']);
      // What moves each: the heat at its own strength, and which letter of which stretch it is.
      // (The stretch is named by its editor and its place among the editor's stretches.)
      final said = [for (final l in letters) RegExp(r'^heat@([\d.]+)@\d+\.(\d+)@(\d+)$').firstMatch(l.attrs['data-fx']!)!];
      expect([for (final m in said) (double.parse(m.group(1)!), m.group(2), m.group(3))], [(rising.own, '0', '0'), (rising.own, '0', '1'), (rising.own, '0', '2')]);
      expect(heatFilter(0, 16, rising.own).bend, 1.65);
      expect(heatFilter(0, 16, rising.own).blur, 0.18);
      // One haze per line above, nearest the strongest (`-heat-above-100`, `-heat-above-55`).
      expect([for (final s in rising.strengths) (s * 100).round()], [100, 55]);
      expect(heatFilter(0, 16, rising.strengths[0]).bend, 5.50);
      expect(heatFilter(0, 16, rising.strengths[1]).bend, 3.03);
    });

    test('marks each letter of a letter effect with its class and its delay', () {
      const doc = 'we 🌊🌊sail on🌊🌊';
      final on = view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(formats: const [wave], more: [textEffects(const [wave])])));
      final letters = marksOf(on, 'cm-effect-wave');
      expect([for (final l in letters) doc.substring(l.from, l.to)], ['s', 'a', 'i', 'l', 'o', 'n']);
      expect(letters.every((l) => RegExp(r'animation-delay:\s*-\d+ms').hasMatch(l.attrs['style'] ?? '')), isTrue);
    });
  });
}
