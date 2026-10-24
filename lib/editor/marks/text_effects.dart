/// Effects on words: moving looks a mark can give the text between its delimiters (`plugins/marks.dart`
/// [EffectLook]), written as an emoji twice either side. `🔥🔥too hot to touch🔥🔥` is heat, `❄️❄️frozen❄️❄️` frost,
/// `🌊🌊out to sea🌊🌊` a wave, `✨✨silver✨✨` a shimmer and `👻👻nobody there👻👻` a haunting. Ports
/// `src/app/editor/textEffects.ts`.
///
/// The words stay words, in their places, kerned and wrapped exactly as they would be without the effect, so the
/// line never moves when an effect comes or goes. The delimiters stay the dimmed marks every delimiter is.
///
/// Three kinds, by what the effect is:
/// - **Heat rising off the words** ([RisingEffect]: heat). The words themselves are bold, in their own colour, and
///   it is the text above them that wavers, seen through the hot air they give off; the words shimmer too, but only
///   slightly. Where the text above is is a question about the layout, so it is measured after each draw
///   ([textAbove]), and the haze follows on the next frame.
/// - **A filter over the whole stretch** ([FilterEffect]: frost): the letters cooled towards ice, and a grainy
///   rime grown out of their edges that creeps, holds and draws back.
/// - **A movement passed along the letters** ([LetterEffect]: wave, shimmer, haunt), each letter on its own clock
///   a step behind the one before, so the movement travels along the words. The delays are negative - the same
///   phases, started long ago - so a line drawn fresh is already moving.
///
/// While the caret is in the words the effect lifts, so they can be edited as plain text; a view that cannot be
/// edited never lifts it. With reduced motion an effect is drawn and does not move: a filter at rest, a haunting
/// half-there, a wave and a shimmer plain. Effects nest, so a haze can shimmer.
///
/// What differs, effect by effect (the pictures are compared in test/editor/marks/effects_test.dart):
/// - The page's marks are kept as it makes them (`cm-textEffect cm-effect-heat` over heated words,
///   `cm-textEffect` over frosted ones, `cm-textEffectAbove` over the text above), and one more is laid on every
///   letter an effect touches: `cm-effectLetter`, which says the letter (`data-text`) and what moves it
///   (`data-fx`). A painter is told a run's rectangles and nothing else, and a run is cut wherever another mark
///   begins, so a letter is the one piece every effect can be drawn on. A letter effect's mark is that letter mark,
///   with the page's classes and its `animation-delay`.
/// - **Wave, shimmer, haunt** are the page's keyframes worked out in Dart at the clock's time ([waveLift],
///   [shimmerGlint], [hauntFade]) and painted: the same curve (`ease-in-out` between keyframes), the same delays,
///   held to the page's computed `top`, `opacity`, `filter`, `color` and `text-shadow` at fixed times. The
///   shimmer's glow on a dark page is two blurred copies of the letter where the page has `text-shadow`.
/// - **Heat** is the wisp's shader (`feTurbulence` into `feDisplacementMap`, then the blur) with the page's
///   numbers: the frequencies breathing every 2.4 s, the seed re-rolled six times in 0.9 s, the bend and the blur by
///   the strength. The page bends a whole `<span>` through one field; here each letter is bent by itself through
///   that same field, read where the letter stands in it, which comes to the same picture (a bend and a blur of
///   several letters is the sum of each one's). The field starts at the corner of the span's paragraph, the
///   `.cm-line`, not of the span, and is drawn by Chromium's own blur ([_inLine], [chromiumBlur]). A ligature
///   across heated letters is set as its letters.
/// - **Frost** is the page's filter primitive by primitive: the cooling is its colour matrix; the rime is the
///   letter's shape grown by the creeping radius (`ImageFilter.dilate`), kept where the noise of the same seed and
///   frequency is bright enough ([_grain]: the specification's noise worked out in Dart for every pixel of the
///   screen from the paragraph's corner, as the page's is), flooded with the page's ice and softened as Chromium
///   softens it, which on most screens is not at all.
/// - Both are held to the page's own pictures, stretch by stretch (test/editor/marks/effects_parity_test.dart).
/// - `prefers-reduced-motion` is the tokens' `reducedMotion`.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart' hide Decoration;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../../art/turbulence.dart';
import '../../art/wisp_kept.dart';
import '../../art/wisp_kit.dart';
import '../../perf/frame_log.dart' show Perf, ghostPerf;
import '../../plugins/marks.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../view/editor_view.dart';
import '../view/line_facts.dart';
import '../view/syntax_tree.dart';
import 'run_paint.dart';
import 'wisp_tables.dart';

/// An effect the editor can draw.
sealed class TextEffect {
  const TextEffect();
}

/// Heat rising off the words: the room round the words its haze may draw into, how strongly each line above is
/// drawn through the haze, nearest first, and how strongly the words themselves waver.
class RisingEffect extends TextEffect {
  const RisingEffect({required this.region, required this.strengths, required this.own});
  final Rect region;
  final List<double> strengths;
  final double own;
}

/// A filter over the whole stretch.
class FilterEffect extends TextEffect {
  const FilterEffect({required this.region});
  final Rect region;
}

/// A movement passed along the letters: one turn of a letter's animation, and how far behind the letter before
/// it each letter runs, in ms.
class LetterEffect extends TextEffect {
  const LetterEffect({required this.cycleMs, required this.stepMs});
  final int cycleMs;
  final int stepMs;
}

/// The type the filters are tuned on: a note's body text.
const double tunedPx = 16;

/// How much bigger than body text `fontPx` is, held above half so small print keeps a visible effect.
double scaleFor(double fontPx) => math.max(0.5, fontPx / tunedPx);

/// Heat's noise at [tunedPx]: the frequencies it breathes between (across, then down) and the bend in pixels.
const ({List<double> low, List<double> high, double bend}) heatNoise = (low: <double>[0.02, 0.085], high: <double>[0.028, 0.12], bend: 5.5);

/// The effects the editor can draw, by the name a mark's look gives.
const Map<String, TextEffect> textEffectsByName = <String, TextEffect>{
  'heat': RisingEffect(region: Rect.fromLTWH(-0.08, -0.45, 1.16, 1.9), strengths: <double>[1, 0.55], own: 0.3),
  'frost': FilterEffect(region: Rect.fromLTWH(-0.1, -0.5, 1.2, 2)),
  // Wave: the words bob along the line, a ripple passing through them from the first letter to the last.
  'wave': LetterEffect(cycleMs: 1600, stepMs: 70),
  // Shimmer: a glint slides across the words every few seconds.
  'shimmer': LetterEffect(cycleMs: 3200, stepMs: 55),
  // Haunt: the words fade almost away and back, slowly, the fading drifting along them.
  'haunt': LetterEffect(cycleMs: 4400, stepMs: 110),
};

/// An effect look as the editor reads it: the delimiter's length in code units (`🔥🔥` is four) and the effect.
typedef EffectLookSpec = ({int length, String effect});

/// A stretch to draw an effect on.
typedef EffectRange = ({int from, int to, String effect});

/// The stretches to draw an effect on in `from`-`to`: the words of every node in `looks`, delimiters aside, except
/// a node the selection touches while `atCaret`, which is an editable view with the focus. Nested effects are each
/// a stretch, outer first.
List<EffectRange> effectRanges(EditorState state, Map<String, EffectLookSpec> looks, int from, int to, bool atCaret, [LineFact<bool>? marked]) {
  final found = <EffectRange>[];
  // With `marked` (the lines that have one of the effects' delimiters), only what touches such a line is gone into.
  final holds = marked == null ? null : touching(marked.between(state.doc, state.doc.lineAt(from).number, state.doc.lineAt(to).number));
  syntaxTree(state).iterate(
    from: from,
    to: to,
    enter: (node) {
      final look = looks[node.name];
      if (look == null) return holds == null || node.from < from || holds(node.from, node.to) ? null : false;
      final a = node.from + look.length, b = node.to - look.length;
      if (b <= a) return false;
      if (atCaret && state.selection.ranges.any((r) => r.to >= node.from && r.from <= node.to)) return false;
      found.add((from: a, to: b, effect: look.effect));
      return null;
    },
  );
  return found;
}

/// A letter of a letter effect: its animation's delay is negative, and a step later for each letter, so the
/// movement travels and is already under way.
typedef EffectLetter = ({int from, int to, int delayMs});

final RegExp _space = RegExp(r'\s');

/// The letters of a stretch for a letter effect, spaces aside, each a character whole however many code units it
/// is.
List<EffectLetter> effectLetters(EditorState state, int from, int to, LetterEffect effect) {
  final letters = <EffectLetter>[];
  var pos = from, place = 0;
  for (final rune in state.doc.sliceString(from, to).runes) {
    final ch = String.fromCharCode(rune);
    if (!_space.hasMatch(ch)) {
      letters.add((from: pos, to: pos + ch.length, delayMs: ((place * effect.stepMs) % effect.cycleMs) - effect.cycleMs));
      place += 1;
    }
    pos += ch.length;
  }
  return letters;
}

/// A stretch of words as laid out: one per visual line it runs over, in the view's own coordinates.
class EffectSegment {
  EffectSegment(this.left, this.right, this.top);
  double left;
  double right;
  double top;
}

/// What the view says about a point on the page, for [textAbove]: the text line there, or nothing.
typedef ProbeLine = ({int from, int to, double top, bool empty})? Function(double x, double y);

/// How many visual lines up the text above may be found: the line just above, past one blank line between
/// paragraphs.
const int _search = 3;

/// How far either side of the words the heat reaches, in line heights.
const double _spread = 0.35;

/// The text above one laid-out stretch of heated words: for each strength, nearest first, the document range
/// under the words' width (and a little either side) on a line of text above them. The first is the nearest line
/// with any text, looked for up to three lines up, so a blank line between paragraphs does not end the heat; each
/// further one is the line straight above the last, where the heat has thinned, and stops at a blank line.
List<({int from, int to, double strength})> textAbove(EffectSegment segment, double lineHeight, List<double> strengths, ProbeLine probe) {
  final found = <({int from, int to, double strength})>[];
  final spread = lineHeight * _spread;
  var top = segment.top;
  var searched = 0;
  for (final strength in strengths) {
    ({int from, int to, double top})? hit;
    while (searched < _search) {
      searched += 1;
      final y = top - lineHeight / 2;
      final start = probe(segment.left - spread, y);
      final end = probe(segment.right + spread, y);
      if (start == null || end == null) return found;
      top = math.min(start.top, end.top);
      if (start.empty && end.empty) {
        // A blank line: the heat carries over it to the first text above, but no further past the first it reached.
        if (found.isNotEmpty) return found;
        continue;
      }
      hit = (from: math.min(start.from, end.from), to: math.max(start.to, end.to), top: top);
      break;
    }
    if (hit == null || hit.to <= hit.from) return found;
    found.add((from: hit.from, to: hit.to, strength: strength));
    // The next line up is only ever the one straight above this one.
    searched = _search - 1;
  }
  return found;
}

/// The stretch from `from` to `to` as laid out: one segment per visual line, read from the view's character boxes.
List<EffectSegment> _segmentsOf(EditorViewLike view, int from, int to) {
  final segments = <EffectSegment>[];
  EffectSegment? current;
  // A long heated paragraph is measured by its first stretch only; heat off a whole page of words would be noise.
  final end = math.min(to, from + 400);
  final doc = view.state.doc;
  for (var pos = from; pos < end;) {
    final text = doc.sliceString(pos, math.min(pos + 2, end));
    final next = pos + (text.length > 1 && (text.codeUnitAt(0) & 0xfc00) == 0xd800 ? 2 : 1);
    final a = view.coordsAtPos(pos, 1), b = view.coordsAtPos(next, -1);
    if (a != null && b != null) {
      if (current != null && (a.top - current.top).abs() < 2) {
        current.right = math.max(current.right, b.right);
      } else {
        current = EffectSegment(a.left, b.right, a.top);
        segments.add(current);
      }
    }
    pos = next;
  }
  return segments;
}

final RegExp _blank = RegExp(r'^\s*$');

/// The layout, as [textAbove] asks for it: the line under a point, as a range across the words' width.
ProbeLine _probeOf(EditorViewLike view) {
  // The content's box: its lines' own, read from the first and last laid out.
  double top = double.negativeInfinity, left = 0, right = double.infinity;
  if (view is EditorView) {
    final lines = view.lines;
    if (lines.isNotEmpty && lines.first.hasSize) {
      final at = lines.first.localToGlobal(Offset.zero);
      left = at.dx;
      right = at.dx + lines.first.size.width;
      if (lines.first.from == 0) top = at.dy;
    }
  }
  return (x, y) {
    if (y < top) return null;
    final pos = view.posAtCoords(Offset(math.min(math.max(x, left + 1), right - 1), y), precise: false);
    if (pos == null) return null;
    final at = view.coordsAtPos(pos, 1) ?? view.coordsAtPos(pos, -1);
    if (at == null) return null;
    final line = view.state.doc.lineAt(pos);
    return (from: pos, to: pos, top: at.top, empty: line.length == 0 || _blank.hasMatch(line.text));
  };
}

/// Said to the plugin when the text above its heated words has been measured afresh and differs from what it
/// drew.
final StateEffectType<Object?> _heatMeasured = StateEffect.define<Object?>();

// ---- the keyframes -----------------------------------------------------------------------------------------------

/// How far through its turn a letter is at `seconds`, 0 to 1: `animation-delay` is negative, so the turn began
/// that long before the clock did.
double _turn(double seconds, int delayMs, int cycleMs) {
  final at = (seconds * 1000 - delayMs) % cycleMs;
  return (at < 0 ? at + cycleMs : at) / cycleMs;
}

double _ease(double t) => Curves.easeInOut.transform(t.clamp(0.0, 1.0));

/// `@keyframes glyph-effect-wave`: `0%, 100% { top: 0 } 25% { top: -0.14em } 75% { top: 0.1em }`, in ems.
double waveLift(double seconds, int delayMs) {
  final t = _turn(seconds, delayMs, 1600);
  if (t < 0.25) return -0.14 * _ease(t / 0.25);
  if (t < 0.75) return -0.14 + 0.24 * _ease((t - 0.25) / 0.5);
  return 0.1 * (1 - _ease((t - 0.75) / 0.25));
}

/// `@keyframes glyph-effect-glint` and `-sheen`: nothing until 76%, whole at 85%, nothing again at 100%. How much
/// of the glint a letter wears: none or all of it. The keyframes' values are mixed from `currentColor`, which Blink
/// does not interpolate, so on the page the glint comes at once half way to its keyframe and goes at once half way
/// from it (measured at fixed times, light and dark: test/editor/marks/fixtures/marks-at-*.json).
double shimmerGlint(double seconds, int delayMs) {
  final t = _turn(seconds, delayMs, 3200);
  return t >= 0.805 && t < 0.925 ? 1 : 0;
}

/// `@keyframes glyph-effect-haunt`: `0%, 100% { opacity: 1; filter: none } 50% { opacity: 0.3; filter:
/// blur(0.05em) }`. How far gone a letter is, 0 to 1.
double hauntFade(double seconds, int delayMs) {
  final t = _turn(seconds, delayMs, 4400);
  return t < 0.5 ? _ease(t / 0.5) : 1 - _ease((t - 0.5) / 0.5);
}

/// Heat's filter at `seconds` for type `fontPx` high at `strength`: `baseFrequency` breathing between its two
/// values every 2.4 s, `seed` re-rolled six times in 0.9 s, `scale` and `stdDeviation`. `still` is reduced motion:
/// the filter at rest. The numbers are rounded as the page writes them into its attributes.
({Offset frequency, int seed, double bend, double blur}) heatFilter(double seconds, double fontPx, double strength, {bool still = false}) {
  final k = scaleFor(fontPx);
  double fixed(double value, int digits) => double.parse(value.toStringAsFixed(digits));
  final low = Offset(fixed(heatNoise.low[0] / k, 4), fixed(heatNoise.low[1] / k, 4));
  final high = Offset(fixed(heatNoise.high[0] / k, 4), fixed(heatNoise.high[1] / k, 4));
  var frequency = low;
  var seed = 7;
  if (!still) {
    final breath = (seconds % 2.4) / 2.4;
    frequency = Offset.lerp(low, high, breath < 0.5 ? breath * 2 : 2 - breath * 2)!;
    seed = 7 + ((seconds % 0.9) / 0.15).floor().clamp(0, 5);
  }
  return (frequency: frequency, seed: seed, bend: fixed(heatNoise.bend * k * strength, 2), blur: fixed(0.6 * k * strength, 2));
}

/// Frost's filter at `seconds` for type `fontPx` high: the rime's reach (`feMorphology radius`: half, out over
/// 45% of seven seconds, held to 80%, back), the grain's seed (four in 4.8 s) and frequency, and the softening.
({double radius, int seed, double frequency, double blur}) frostFilter(double seconds, double fontPx, {bool still = false}) {
  final k = scaleFor(fontPx);
  final reach = 1.4 * k;
  var radius = reach;
  var seed = 3;
  if (!still) {
    final t = (seconds % 7) / 7;
    radius = t < 0.45 ? reach * (0.5 + 0.5 * t / 0.45) : (t < 0.8 ? reach : reach * (1 - 0.5 * (t - 0.8) / 0.2));
    seed = 3 + ((seconds % 4.8) / 1.2).floor().clamp(0, 3);
  }
  return (radius: radius, seed: seed, frequency: 0.55 / k, blur: 0.35 * k);
}

// ---- the drawing -------------------------------------------------------------------------------------------------

/// What moves one letter: a letter effect and its delay, the heat on its own words or over the text above at a
/// strength, or the frost.
class _Fx {
  const _Fx(this.name, this.value, [this.span = '', this.index = 0]);
  final String name;
  final double value;

  /// For an effect that is one filter over a stretch of words (heat, its haze, frost): which stretch this letter
  /// is of, and which of its letters, the first being 0. The page's filter is one field over the stretch's box; a
  /// letter drawn by itself has to know where in that box it stands ([_inSpan]).
  final String span;
  final int index;

  /// `name@value`, or `name@value@span@index`, with `|` between.
  static List<_Fx> parse(String said) => <_Fx>[
    for (final part in said.split('|'))
      if (part.isNotEmpty) _of(part.split('@')),
  ];

  static _Fx _of(List<String> said) =>
      _Fx(said.first, said.length > 1 ? double.tryParse(said[1]) ?? 0 : 0, said.length > 2 ? said[2] : '', said.length > 3 ? int.tryParse(said[3]) ?? 0 : 0);
}

/// A stretch as it was last painted and measured: where its first letter's box stood on the canvas in this painting
/// of its line, and where that box stands in the line's own box, as the view last laid the line out.
class _SpanSeen {
  Offset first = Offset.zero;
  Offset? origin;
}

final Map<String, _SpanSeen> _spansSeen = <String, _SpanSeen>{};

String _spanKey(String name, String span) => '${name == 'haze' ? 'a' : name}$span';

/// Where a letter's box stands in its line's box (the paragraph's own, `.cm-line` on the page), which is where the
/// page's filters start their noise from. Found by bending the plain words through the specification's noise from
/// every corner near and scoring each against Chromium's picture: from the paragraph's corner the heat's haze is
/// 0.3 of 255 from the page's, from the span's own corner 10, from its filter's room 12
/// (test/editor/marks/effects_parity_test.dart holds it now). A `<span>` with a filter has its paragraph for its
/// user space, whatever its own box.
///
/// A painter is told one run's rectangles on the canvas and nothing of the line they are in, so the place is put
/// together from two things: the stretch's first letter says where it stands on the canvas as the line is painted
/// (letters are painted in order, `index` 0 first), and the view says where that same letter stands in its line
/// once the line is laid out ([_TextEffects._measure]). A letter is then as far from the line's corner as it is
/// from the first letter, and the first letter from the corner. Nothing in it is where the line stands on the
/// screen: a page that scrolls bends and frosts its letters the same wherever they are, as the page's own does.
/// Until the view has measured (the first frame a stretch is seen), the first letter is taken for the corner.
Offset _inLine(_Fx fx, Offset corner) {
  if (_spansSeen.length > 512) _spansSeen.clear();
  final seen = _spansSeen[_spanKey(fx.name, fx.span)] ??= _SpanSeen();
  if (fx.index == 0) seen.first = corner;
  return corner - seen.first + (seen.origin ?? Offset.zero);
}

/// The frost's specks for a seed, as the page's filter works them out: `feTurbulence` (fractal noise, two octaves,
/// its alpha) through `0 0 0 5 -1.9`, for every pixel of the screen from the corner of the stretch's box. A picture
/// [ratio] pixels to the logical one, as big as the stretch's room asks ([atLeast], grown to a step so a longer word
/// does not make it again), and repeated past that. Kept by its seed, its frequency and the screen's ratio.
///
/// The first drawing read the noise once for each logical pixel of a tile. The noise turns over in under two of
/// them, so that was a different speck at every reading, and blurred it came out an even haze round the letters
/// where the page has crystals: the page reads it for every pixel of the screen, two or three to each turn.
final Map<(int, double, double), ({ui.Image image, Size size})> _grains = <(int, double, double), ({ui.Image image, Size size})>{};

({ui.Image image, Size size}) _grain(int seed, double frequency, double ratio, Size atLeast) {
  final key = (seed, frequency, ratio);
  final had = _grains[key];
  if (had != null && had.size.width >= atLeast.width && had.size.height >= atLeast.height) return had;
  double grown(double length) => (length / 48).ceil() * 48.0;
  final size = Size(math.max(had?.size.width ?? 96, grown(atLeast.width)), math.max(had?.size.height ?? 48, grown(atLeast.height)));
  final wide = (size.width * ratio).ceil(), tall = (size.height * ratio).ceil();
  final noise = Turbulence(seed);
  // One square a pixel, in the one draw: its alpha is the speck's.
  final positions = Float32List(wide * tall * 12), colors = Int32List(wide * tall * 6);
  var n = 0;
  for (var y = 0; y < tall; y++) {
    for (var x = 0; x < wide; x++) {
      // Chromium works the noise out half a pixel on from the pixel's own middle (shaders/wisp_bend.frag).
      final alpha = noise.sample(3, (x + 0.5) / ratio + 0.5, (y + 0.5) / ratio + 0.5, baseFrequencyX: frequency, baseFrequencyY: frequency, octaves: 2);
      final kept = (alpha * 5 - 1.9).clamp(0.0, 1.0);
      if (kept <= 0) continue;
      final color = (kept * 255).round() << 24;
      final p = n * 12, c = n * 6;
      final l = x.toDouble(), t = y.toDouble(), r = l + 1, bottom = t + 1;
      positions
        ..[p] = l
        ..[p + 1] = t
        ..[p + 2] = r
        ..[p + 3] = t
        ..[p + 4] = l
        ..[p + 5] = bottom
        ..[p + 6] = r
        ..[p + 7] = t
        ..[p + 8] = r
        ..[p + 9] = bottom
        ..[p + 10] = l
        ..[p + 11] = bottom;
      for (var i = 0; i < 6; i++) {
        colors[c + i] = color;
      }
      n += 1;
    }
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (n > 0) {
    final squares = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.sublistView(positions, 0, n * 12), colors: Int32List.sublistView(colors, 0, n * 6));
    canvas.drawVertices(squares, BlendMode.dst, Paint()..isAntiAlias = false);
    squares.dispose();
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(wide, tall);
  picture.dispose();
  had?.image.dispose();
  return _grains[key] = (image: image, size: Size(wide / ratio, tall / ratio));
}

/// For a test: 2 lays every filter's noise from where the letter stands on the canvas, which is not the page's field
/// (the drawing a right one must beat).
@visibleForTesting
int debugEffectAnchor = 0;

/// A blur of [sigma] logical pixels as Chromium draws `feGaussianBlur` at [ratio] pixels to one: three box blurs,
/// each as wide as the deviation says in whole pixels of the screen (`floor(s * 3 * sqrt(2 pi) / 4 + 0.5)`; an
/// even width is two boxes of it and one a pixel wider), and nothing at all where that width is one. So a filter
/// that says 0.35 softens nothing on a screen of two pixels to one, and the frost's crystals and the haze over the
/// second line up are crisp on the page, where a true Gaussian of that size softened them here. The answer is the
/// deviation of the Gaussian nearest those three boxes, in logical pixels: 0 where the page blurs nothing.
double chromiumBlur(double sigma, double ratio) {
  final wide = (sigma * ratio * 3 * math.sqrt(2 * math.pi) / 4 + 0.5).floor();
  if (wide <= 1) return 0;
  final spread = wide.isOdd ? 3 * (wide * wide - 1) / 12 : 2 * (wide * wide - 1) / 12 + ((wide + 1) * (wide + 1) - 1) / 12;
  return math.sqrt(spread) / ratio;
}

/// `feColorMatrix`: `0.82 0 0 0 0.02  0 0.92 0 0 0.04  0 0 1 0 0.1  0 0 0 1 0`, the offsets as Flutter counts
/// them.
const ColorFilter _cold = ColorFilter.matrix(<double>[0.82, 0, 0, 0, 0.02 * 255, 0, 0.92, 0, 0, 0.04 * 255, 0, 0, 1, 0, 0.1 * 255, 0, 0, 0, 1, 0]);

class _EffectLetter extends LetterLayer {
  const _EffectLetter(super.text, this.fx, {required this.still, required this.dark, required this.fontPx, required this.paper});

  final List<_Fx> fx;
  final bool still;
  final bool dark;

  /// The note's body size, which the filters are sized to.
  final double fontPx;

  /// The page's ground, which a sheen pales a letter towards.
  final Color paper;

  @override
  bool get moves => !still;

  double? _of(String name) {
    for (final one in fx) {
      if (one.name == name) return one.value;
    }
    return null;
  }

  @override
  void drawLetter(Canvas canvas, LetterGlyph glyph, Offset at, Size box, RunLook look) {
    final now = MarkClock.now;
    final em = look.fontSize;
    final region = Rect.fromLTWH(-3 * box.width, -1.5 * box.height, 7 * box.width, 4 * box.height);

    // Where the letter stands in its line, for the filters that lie over a stretch: the heat's (the strongest of
    // what reaches it) and the frost's. Every such stretch is told of the letter, drawn through it or not
    // ([_inLine]). `hotAt` and `coldAt` are the letter's own corner from the line's.
    final lift = look.ascent - glyph.baseline;
    final corner = Offset(at.dx, at.dy - lift);
    _Fx? hot, cold;
    for (final one in fx) {
      if ((one.name == 'heat' || one.name == 'haze') && one.value > (hot?.value ?? 0)) hot = one;
      if (one.name == 'frost') cold = one;
    }
    var hotAt = at, coldAt = at;
    for (final one in fx) {
      if (one.span.isEmpty) continue;
      final inLine = _inLine(one, corner) + Offset(0, lift);
      if (debugEffectAnchor == 2) continue;
      if (identical(one, hot)) hotAt = inLine;
      if (identical(one, cold)) coldAt = inLine;
    }
    final ratio = _screenRatio();

    // A wave: `position: relative; top`, the letter moved and nothing round it.
    final wave = _of('wave');
    if (wave != null && !still) canvas.translate(0, waveLift(now, wave.round()) * em);

    // While frames follow one another, a letter with one effect on it is laid down from what is kept of it.
    if (wispQuick && WispFlow.now && _fromKept(canvas, glyph, look, now, region, cold == null ? null : coldAt, ratio)) return;

    // A haunting: the whole letter, glint and rime and all, faded and softened.
    final haunt = _of('haunt');
    var layered = false;
    if (haunt != null) {
      final gone = still ? null : hauntFade(now, haunt.round());
      final opacity = gone == null ? 0.55 : 1 - 0.7 * gone;
      final blur = gone == null ? 0.0 : 0.05 * em * gone;
      final paint = Paint()..color = Color.fromRGBO(0, 0, 0, opacity);
      if (blur > 0.01) paint.imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal);
      canvas.saveLayer(region, paint);
      layered = true;
    }

    // A shimmer: on the dark page a glow round the letter, on paper the letter gone pale for a moment.
    final shimmer = _of('shimmer');
    final glint = shimmer == null || still ? 0.0 : shimmerGlint(now, shimmer.round());
    ColorFilter? sheen;
    if (glint > 0) {
      if (dark) {
        // `text-shadow: 0 0 0.28em currentColor, 0 0 0.6em color-mix(in srgb, currentColor 55%, transparent)`:
        // a shadow's blur radius is twice its deviation.
        for (final (radius, share) in const <(double, double)>[(0.6, 0.55), (0.28, 1.0)]) {
          canvas.saveLayer(
            region.inflate(radius * em * 2),
            Paint()
              ..color = Color.fromRGBO(0, 0, 0, glint * share)
              ..imageFilter = ui.ImageFilter.blur(sigmaX: radius * em / 2, sigmaY: radius * em / 2, tileMode: TileMode.decal),
          );
          glyph.painter.paint(canvas, Offset.zero);
          canvas.restore();
        }
      } else {
        // `color-mix(in srgb, currentColor 32%, var(--glacier-bg))`, as far as the glint has come.
        final pale = Color.lerp(paper, look.color, 0.32)!;
        sheen = ColorFilter.mode(Color.lerp(look.color, pale, glint)!, BlendMode.srcIn);
      }
    }

    // Frost: the rime under the cooled letter.
    final frost = cold != null;
    if (frost) _rime(canvas, glyph, region, coldAt, now, ratio);

    // Heat: the letter through the hot air, at the strongest of what reaches it.
    final heat = hot?.value ?? 0.0;
    final kit = WispKit.maybe;
    final filter = heat > 0 ? heatFilter(now, fontPx, heat, still: still) : null;
    final table = filter == null ? null : kit?.tableNow(filter.seed);
    // The softening as the page's engine draws it at this screen's pixels: often none at all.
    final soft = filter == null ? 0.0 : chromiumBlur(filter.blur, ratio);
    final paint = Paint();
    // A sheen over the frost is the sheen: the letter is one flat colour either way.
    if (frost || sheen != null) paint.colorFilter = sheen ?? _cold;
    if (filter != null && kit != null && table != null) {
      if (soft >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal);
      final image = glyph.image();
      canvas.saveLayer(region.inflate(soft * 3), paint);
      canvas.translate(region.left, region.top);
      // One field over the stretch: neighbours bend together.
      final shader = kit.bend(
        source: image,
        sourceRect: glyph.imageRect.shift(hotAt),
        origin: hotAt + region.topLeft,
        smoke: WispSmoke.flat(seed: filter.seed, frequency: filter.frequency, bend: filter.bend, blur: soft),
        table: table,
      );
      canvas.drawRect(Offset.zero & region.size, Paint()..shader = shader);
      canvas.restore();
    } else if (paint.colorFilter != null || filter != null) {
      // No shader yet: the haze is its softness alone.
      if (filter != null && soft >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal);
      canvas.saveLayer(region, paint);
      glyph.painter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      glyph.painter.paint(canvas, Offset.zero);
    }
    if (layered) canvas.restore();
  }

  /// The frost's rime round a letter: the letter's shape grown by the creeping radius (`feMorphology`), kept where
  /// the grain is bright enough (`feTurbulence` through `0 0 0 5 -1.9`, `feComposite in`), flooded with the page's
  /// ice and softened (`feGaussianBlur`). The grain is the line's, laid from the line's corner: [coldAt] is
  /// the letter's corner from there.
  void _rime(Canvas canvas, LetterGlyph glyph, Rect region, Offset coldAt, double now, double ratio) {
    final filter = frostFilter(now, fontPx, still: still);
    final ice = (dark ? const Color(0xFFCDEAFF) : const Color(0xFF5AA6DA)).withValues(alpha: 0.95);
    final room = region.inflate(filter.radius + filter.blur * 3);
    // The softening as the page's engine draws it: none on most screens, and the crystals are crisp.
    final soft = chromiumBlur(filter.blur, ratio);
    canvas.saveLayer(room, soft >= 0.05 ? (Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal)) : Paint());
    canvas.saveLayer(
      room,
      Paint()
        ..imageFilter = ui.ImageFilter.dilate(radiusX: filter.radius, radiusY: filter.radius)
        ..colorFilter = ColorFilter.mode(ice, BlendMode.srcIn),
    );
    glyph.painter.paint(canvas, Offset.zero);
    canvas.restore();
    // Kept where the grain is bright: the grain's own pixels are the screen's, from the stretch's corner.
    final grain = _grain(filter.seed, filter.frequency, ratio, Size(coldAt.dx + room.right, coldAt.dy + room.bottom));
    final matrix = Float64List.fromList(<double>[1 / ratio, 0, 0, 0, 0, 1 / ratio, 0, 0, 0, 0, 1, 0, -coldAt.dx, -coldAt.dy, 0, 1]);
    canvas.drawRect(
      room,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.ImageShader(grain.image, TileMode.repeated, TileMode.repeated, matrix),
    );
    canvas.restore();
  }
}

/// What an effect's letter is laid down from while frames follow one another (lib/art/wisp_kept.dart), for the
/// effects that were a layer and a blur for every letter on every frame and are the same picture from one frame to
/// the next, or one of a few:
///
/// - **A haunting** alone is the letter under a blur that comes and goes with it, and faded. The blur is kept at
///   steps of an eighth of one of the screen's pixels (a dozen or two pictures a letter, made over its first turn
///   and there for every turn after), and the fade is how much of the kept picture is laid. A letter not yet
///   blurred by a sixteenth of a pixel is all but whole (99 parts in 100), and is drawn as itself.
/// - **A shimmer's glint** on a dark page is two blurred copies of the letter under it, the same two whenever it
///   glints: kept once, with the letter drawn over as text. On paper the glint is the letter gone pale, which is
///   the letter set in the paler colour and no layer at all.
///
/// Answers whether it drew the letter. A letter with more than one effect on it, a frost, a heat (which has the
/// sheet, in [drawLetter]) and reduced motion are drawn as they always were.
extension on _EffectLetter {
  bool _fromKept(Canvas canvas, LetterGlyph glyph, RunLook look, double now, Rect region, Offset? coldAt, double ratio) {
    final haunt = _of('haunt'), shimmer = _of('shimmer');
    final glint = shimmer == null || still ? 0.0 : shimmerGlint(now, shimmer.round());
    for (final one in fx) {
      if (one.name == 'heat' || one.name == 'haze') return false;
    }
    if (coldAt != null) {
      // A frost alone: the rime and the cooled letter over it, one picture for as long as the rime reaches as far
      // (its radius is whole pixels of the screen, as the engine's dilate rounds it), its grain is the same seed's,
      // and the letter stands where it did in its line. The page under it may scroll: the grain is the
      // line's, and goes with it.
      if (haunt != null || glint > 0) return false;
      final filter = frostFilter(now, fontPx, still: still);
      final room = region.inflate(filter.radius + filter.blur * 3);
      WispKept.paint(
        canvas,
        (glyph, 'frost', filter.seed, (filter.radius * ratio).round(), (coldAt.dx * 8).round(), (coldAt.dy * 8).round(), dark, fontPx),
        over: room,
        ratio: ratio,
        sharp: true,
        draw: (into) {
          _rime(into, glyph, region, coldAt, now, ratio);
          into.saveLayer(region, Paint()..colorFilter = _cold);
          glyph.painter.paint(into, Offset.zero);
          into.restore();
        },
      );
      return true;
    }
    if (still) return false;
    if (haunt != null && glint > 0) return false;
    final em = look.fontSize;
    // The letter's ink, with room for what overhangs its box.
    final pad = (glyph.painter.preferredLineHeight * 0.3).ceilToDouble();
    final ink = Rect.fromLTWH(-pad, -pad, glyph.painter.width + 2 * pad, glyph.painter.height + 2 * pad);

    if (haunt != null) {
      final gone = hauntFade(now, haunt.round());
      final blur = 0.05 * em * gone;
      final step = (blur * ratio * 8).round();
      if (step == 0) {
        glyph.painter.paint(canvas, Offset.zero);
        return true;
      }
      final soft = step / (ratio * 8);
      final over = ink.inflate(soft * 3 + 1);
      WispKept.paint(
        canvas,
        (glyph, 'haunt', step),
        over: over,
        ratio: ratio,
        // Hardly blurred at the turn's ends, among letters that are not blurred at all.
        sharp: true,
        opacity: 1 - 0.7 * gone,
        draw: (into) {
          into.saveLayer(over, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal));
          glyph.painter.paint(into, Offset.zero);
          into.restore();
        },
      );
      return true;
    }

    if (glint > 0) {
      if (dark) {
        // The glint is there or not: the two glows at their whole strength, as [drawLetter] lays them.
        final over = ink.inflate(0.9 * em + 1);
        WispKept.paint(
          canvas,
          (glyph, 'glow'),
          over: over,
          ratio: ratio,
          draw: (into) {
            for (final (radius, share) in const <(double, double)>[(0.6, 0.55), (0.28, 1.0)]) {
              into.saveLayer(
                over,
                Paint()
                  ..color = Color.fromRGBO(0, 0, 0, share)
                  ..imageFilter = ui.ImageFilter.blur(sigmaX: radius * em / 2, sigmaY: radius * em / 2, tileMode: TileMode.decal),
              );
              glyph.painter.paint(into, Offset.zero);
              into.restore();
            }
          },
        );
        glyph.painter.paint(canvas, Offset.zero);
        return true;
      }
      // On paper: the letter set in the pale colour the sheen mixes it to.
      if (look.style.foreground != null) return false;
      // As the sheen leaves it: the pale colour, through as much of the letter as the letter's own colour shows.
      final pale = Color.lerp(paper, look.color, 0.32)!;
      LetterGlyph.of(text, styleOf(look).copyWith(color: pale.withValues(alpha: pale.a * look.color.a))).painter.paint(canvas, Offset.zero);
      return true;
    }
    return false;
  }
}

/// The screen's pixels to a logical one, as the frame is drawn.
double _screenRatio() {
  final views = SchedulerBinding.instance.platformDispatcher.views;
  return views.isEmpty ? 1.0 : views.first.devicePixelRatio;
}

// ---- the stylesheet ----------------------------------------------------------------------------------------------

/// Plain inline spans for the filters, so the words wrap and kern as they would with no effect on them; heat's own
/// words, bold; and the letter every effect is drawn on.
final LookSheet _theme = LookSheet('editor/textEffects.ts', <LookRule>[
  // '.cm-effect-heat': { fontWeight: '700' }
  LookRule('cm-effect-heat', classes: 2, (p, e) => p.weight = 700),
  LookRule(
    'cm-effectLetter',
    null,
    classes: 2,
    box: (p, e) {
      final attrs = p.element?.attrs ?? const <String, String>{};
      p.painter = MarkPaint.add(
        p.painter,
        _EffectLetter(attrs['data-text'] ?? '', _Fx.parse(attrs['data-fx'] ?? ''), still: e.t.reducedMotion, dark: e.dark, fontPx: e.body, paper: e.t.color('glacier-bg')),
      );
    },
  ),
]);

final Extension _themed = baseTheme(_theme);

class _Above {
  const _Above(this.from, this.to, this.effect, this.strength);
  final int from;
  final int to;
  final String effect;
  final double strength;
}

/// How many times the effects' marks were made, and how many times the ones there were kept: for a test.
@visibleForTesting
int debugEffectsMade = 0, debugEffectsKept = 0;

int _editors = 0;

class _TextEffects extends PluginValue {
  _TextEffects(this.view, this.looks, this.marked) {
    _redraw(first: true);
  }

  final EditorViewLike view;
  final Map<String, EffectLookSpec> looks;

  /// The lines with one of the effects' delimiters: where the tree is walked.
  final LineFact<bool>? marked;

  /// The heat's seeds, off the first frame: asked for when the note first shows an effect (wisp_tables.dart).
  final WispTables _tables = WispTables(const <int>[7, 8, 9, 10, 11, 12]);

  void _wantTables({required bool atOnce}) => _tables.want(
    atOnce: atOnce,
    gone: () => _destroyed,
    ready: () {
      final own = view;
      if (own is! EditorView) return;
      for (final line in own.lines) {
        line.markNeedsPaint();
      }
    },
  );

  /// The page's own marks: heated words, frosted words, the text above.
  DecorationSet decorations = Decoration.none;

  /// A mark on every letter an effect touches, which is where it is drawn.
  DecorationSet letters = Decoration.none;

  /// Which editor's stretches these are, in the names their letters are told ([_Fx.span]): two editors on one
  /// screen each count their stretches from nothing.
  final int _id = _editors++;

  /// The text above heated words, as last measured: drawn through the haze on the next draw.
  List<_Above> _above = const <_Above>[];
  bool _destroyed = false;

  /// The stretches [decorations] and [letters] were made for, and whether they show [_above] as it now is.
  List<EffectRange> _drawn = const <EffectRange>[];
  bool _aboveDrawn = true;

  /// A mark by what it says: its class and the four attributes any of these marks carries (`data-effect`, `style`,
  /// `data-fx`, `data-text`). Looked up by those themselves, not by a string joined from them for each letter.
  static final Map<(String, String?, String?, String?, String?), Decoration> _made = <(String, String?, String?, String?, String?), Decoration>{};

  static Decoration _mark(String className, Map<String, String> attributes) =>
      _made[(className, attributes['data-effect'], attributes['style'], attributes['data-fx'], attributes['data-text'])] ??= Decoration.mark(className: className, attributes: attributes);

  @override
  void update(ViewUpdate update) {
    final measured = update.transactions.any((tr) => tr.effects.any((effect) => _heatMeasured.cast(effect) != null));
    if (!(measured ||
        update.docChanged ||
        update.viewportChanged ||
        update.selectionSet ||
        update.focusChanged ||
        update.geometryChanged ||
        !identical(syntaxTree(update.state), syntaxTree(update.startState)))) {
      return;
    }
    ChangeDesc? changes;
    if (update.docChanged) {
      final changed = changes = update.changes;
      // The text above heated words goes with a change that left it alone; one that touched it has it measured
      // again, and until then there is no haze to draw.
      if (_above.any((above) => changed.touchesRange(above.from, above.to) != Touch.none)) {
        _above = const <_Above>[];
        _aboveDrawn = false;
      } else if (_above.isNotEmpty) {
        _above = <_Above>[for (final above in _above) _Above(changed.mapPos(above.from, 1), changed.mapPos(above.to, -1), above.effect, above.strength)];
      }
    }
    _redraw(changes: changes);
  }

  /// Whether the marks as they are, moved by [changes], are the marks [found] would be given: the same stretches
  /// with the same effects, none of them touched by the change (a letter typed elsewhere in the note, the caret
  /// moved outside them, the page scrolled with the same effects on it), over the same text above.
  bool _stands(List<EffectRange> found, ChangeDesc? changes) {
    if (!_aboveDrawn || found.length != _drawn.length) return false;
    for (var i = 0; i < found.length; i++) {
      final was = _drawn[i], now = found[i];
      if (was.effect != now.effect) return false;
      if (changes == null) {
        if (was.from != now.from || was.to != now.to) return false;
      } else {
        if (changes.touchesRange(was.from, was.to) != Touch.none) return false;
        if (changes.mapPos(was.from, 1) != now.from || changes.mapPos(was.to, -1) != now.to) return false;
      }
    }
    return true;
  }

  @override
  void destroy() => _destroyed = true;

  /// Makes the marks for the view as it now is, or keeps the ones there are: [changes] is what the document
  /// changed by since they were made, if it did.
  ///
  /// The stretches are found each time (a walk of the tree that goes only into lines with one of the effects'
  /// delimiters): a change far off can still close a fence over an effect, and the caret lifts one by entering it.
  /// What is not done each time is what they are then made into, a mark for every letter of every effect on
  /// screen: with the Effects' lines of the sample note on screen that was 220 to 290 microseconds of every letter
  /// typed anywhere in the note, and the haze over the text above was taken off and measured back on each one.
  void _redraw({bool first = false, ChangeDesc? changes}) {
    final state = view.state;
    final ranges = view.visibleRanges;
    final atCaret = state.facet(EditorViewLike.editable) && view.hasFocus;
    final found = ranges.isEmpty ? const <EffectRange>[] : effectRanges(state, looks, ranges.first.from, ranges.last.to, atCaret, marked);
    if (found.isNotEmpty) _wantTables(atOnce: first);
    if (!first && _stands(found, changes)) {
      if (changes != null) {
        decorations = decorations.map(changes);
        letters = letters.map(changes);
      }
      _drawn = found;
      debugEffectsKept += 1;
      if (ghostPerf) Perf.count('effects.kept');
      _measure(<EffectRange>[
        for (final stretch in found)
          if (textEffectsByName[stretch.effect] is RisingEffect) stretch,
      ]);
      return;
    }
    debugEffectsMade += 1;
    if (ghostPerf) Perf.count('effects.made');
    _drawn = found;
    _aboveDrawn = true;
    final marks = <({int from, int to, Decoration mark})>[];
    // What moves each letter, by where it starts.
    final cells = <int, ({int to, List<String> fx, List<String> names, int? delay})>{};
    void touch(int from, int to, String fx, [String? name, int? delay]) {
      final had = cells[from];
      cells[from] = (to: to, fx: <String>[...?had?.fx, fx], names: <String>[...?had?.names, ?name], delay: had == null ? delay : null);
    }

    // Each letter of a stretch one filter lies over: what moves it, which stretch (`span`) and which letter of it.
    void everyLetter(int from, int to, String fx, String span) {
      var pos = from, index = 0;
      for (final rune in state.doc.sliceString(from, to).runes) {
        final ch = String.fromCharCode(rune);
        if (!_space.hasMatch(ch)) touch(pos, pos + ch.length, '$fx@$span@${index++}');
        pos += ch.length;
      }
    }

    final rising = <EffectRange>[];
    // A stretch is named by its place among those on screen: the same after a change elsewhere in the note.
    var nth = 0;
    for (final stretch in found) {
      final span = '$_id.${nth++}';
      final effect = textEffectsByName[stretch.effect];
      switch (effect) {
        case RisingEffect():
          marks.add((
            from: stretch.from,
            to: stretch.to,
            mark: _mark('cm-textEffect cm-effect-${stretch.effect}', <String, String>{'data-effect': stretch.effect, 'style': 'filter:url(#glyph-effect-${stretch.effect}-own)'}),
          ));
          everyLetter(stretch.from, stretch.to, '${stretch.effect}@${effect.own}', span);
          rising.add(stretch);
        case FilterEffect():
          marks.add((from: stretch.from, to: stretch.to, mark: _mark('cm-textEffect', <String, String>{'data-effect': stretch.effect, 'style': 'filter:url(#glyph-effect-${stretch.effect})'})));
          everyLetter(stretch.from, stretch.to, '${stretch.effect}@0', span);
        case LetterEffect():
          for (final letter in effectLetters(state, stretch.from, stretch.to, effect)) {
            touch(letter.from, letter.to, '${stretch.effect}@${letter.delayMs}', stretch.effect, letter.delayMs);
          }
        case null:
          break;
      }
    }
    // The haze over the text above heated words, as last measured, where it is still text outside the heat itself.
    var over = 0;
    for (final above in _above) {
      final span = '$_id.${over++}';
      if (above.to > state.doc.length || rising.any((r) => above.from < r.to && above.to > r.from)) continue;
      marks.add((
        from: above.from,
        to: above.to,
        mark: _mark('cm-textEffectAbove', <String, String>{'data-effect': '${above.effect}-above', 'style': 'filter:url(#glyph-effect-${above.effect}-above-${(above.strength * 100).round()})'}),
      ));
      // A range of one line: its letters, the break aside.
      everyLetter(above.from, above.to, 'haze@${above.strength}', span);
    }
    // Nested effects give marks out of order (the outer stretch, then the inner one); the set wants them sorted.
    final order = <int>[for (var i = 0; i < marks.length; i++) i]
      ..sort((a, b) {
        final x = marks[a], y = marks[b];
        return x.from != y.from ? x.from - y.from : (y.to != x.to ? y.to - x.to : a - b);
      });
    final builder = RangeSetBuilder<Decoration>();
    for (final i in order) {
      builder.add(marks[i].from, marks[i].to, marks[i].mark);
    }
    decorations = builder.finish();

    final perLetter = RangeSetBuilder<Decoration>();
    for (final from in cells.keys.toList()..sort()) {
      final cell = cells[from]!;
      final names = cell.names.toSet();
      perLetter.add(
        from,
        cell.to,
        _mark(<String>[if (names.isNotEmpty) 'cm-textEffect', for (final name in names) 'cm-effect-$name', 'cm-effectLetter'].join(' '), <String, String>{
          if (names.isNotEmpty) 'data-effect': names.join(' '),
          if (cell.delay != null && names.length == 1) 'style': 'animation-delay:${cell.delay}ms',
          'data-fx': cell.fx.join('|'),
          'data-text': state.sliceDoc(from, cell.to),
        }),
      );
    }
    letters = perLetter.finish();
    _measure(rising);
  }

  /// What is read once the view is laid out. Where the text above the heated words is, drawn on the next update
  /// when it has moved (a haze changes no layout, so this settles after one round: the second measure finds what
  /// the first did and dispatches nothing). And where the first letter of every stretch a filter lies over stands in
  /// its own line, which is where the letters' painters take the filter's noise from ([_inLine]); a line whose
  /// letters were painted before that was known, or with what it was, is painted again.
  void _measure(List<EffectRange> rising) {
    final filtered = <(String, int)>[
      for (var nth = 0; nth < _drawn.length; nth++)
        if (textEffectsByName[_drawn[nth].effect] case RisingEffect() || FilterEffect()) (_spanKey(_drawn[nth].effect, '$_id.$nth'), _firstLetter(_drawn[nth].from, _drawn[nth].to)),
    ];
    if (rising.isEmpty && _above.isEmpty && filtered.isEmpty) return;
    view.requestMeasure<({List<_Above> above, Map<String, Offset> origins})>(
      MeasureRequest<({List<_Above> above, Map<String, Offset> origins})>(
        key: this,
        read: (view) {
          final own = view;
          final lineHeight = own is EditorView ? own.heights.lineHeight : 0.0;
          if (lineHeight <= 0 || own is! EditorView) return (above: _above, origins: const <String, Offset>{});
          final probe = _probeOf(view);
          final above = <_Above>[
            for (final stretch in rising)
              if (textEffectsByName[stretch.effect] case final RisingEffect effect)
                for (final segment in _segmentsOf(view, stretch.from, stretch.to))
                  for (final above in textAbove(segment, lineHeight, effect.strengths, probe)) _Above(above.from, above.to, stretch.effect, above.strength),
          ];
          // Each stretch's first letter in its own line's box: the corner of the text there, as the line's painter
          // hands it to the letter's.
          final origins = <String, Offset>{};
          void place(String key, int pos) {
            final line = own.lineAt(pos);
            final at = line == null || !line.hasSize ? null : line.coordsAtPos(pos - line.from, 1);
            if (at != null) origins[key] = at.topLeft;
          }

          for (final (key, pos) in filtered) {
            place(key, pos);
          }
          for (var nth = 0; nth < above.length; nth++) {
            if (above[nth].to <= own.state.doc.length) place(_spanKey('haze', '$_id.$nth'), _firstLetter(above[nth].from, above[nth].to));
          }
          return (above: above, origins: origins);
        },
        write: (read, view) {
          var moved = false;
          for (final entry in read.origins.entries) {
            final seen = _spansSeen[entry.key] ??= _SpanSeen();
            if (seen.origin == entry.value) continue;
            seen.origin = entry.value;
            moved = true;
          }
          if (moved && view is EditorView) {
            for (final line in view.lines) {
              line.markNeedsPaint();
            }
          }
          final next = read.above;
          var same = next.length == _above.length;
          for (var i = 0; same && i < next.length; i++) {
            same = next[i].from == _above[i].from && next[i].to == _above[i].to && next[i].strength == _above[i].strength;
          }
          if (same) return;
          _above = next;
          _aboveDrawn = false;
          // Not from inside the measure: on the next turn.
          Timer.run(() {
            if (!_destroyed) view.dispatch(TransactionSpec(effects: _heatMeasured.of(null)));
          });
        },
      ),
    );
  }

  /// The first letter of `from`-`to` that is not a space: the one its stretch's letters count from.
  int _firstLetter(int from, int to) {
    var pos = from;
    for (final rune in view.state.doc.sliceString(from, math.min(to, view.state.doc.length)).runes) {
      final ch = String.fromCharCode(rune);
      if (!_space.hasMatch(ch)) return pos;
      pos += ch.length;
    }
    return from;
  }
}

/// The effect looks of `formats`, by node name.
Map<String, EffectLookSpec> effectLooksOf(Iterable<GlyphFormat> formats) => <String, EffectLookSpec>{
  for (final format in formats)
    if (format.look case final EffectLook look when textEffectsByName.containsKey(look.effect)) format.name: (length: format.delimiter.length, effect: look.effect),
};

/// The effect looks of `formats`, drawn.
Extension textEffects(Iterable<GlyphFormat> formats) {
  final looks = effectLooksOf(formats);
  if (looks.isEmpty) return const Extension.list(<Extension>[]);
  final marked = delimitedLines(<GlyphFormat>[
    for (final format in formats)
      if (looks.containsKey(format.name)) format,
  ]);
  return Extension.list(<Extension>[
    ViewPlugin.define<_TextEffects>(
      (view) => _TextEffects(view, looks, marked),
      decorations: (value) => value.decorations,
      // The letters' marks inside every other, so a letter's painter is the one its run carries.
      provide: (plugin) => Prec.highest(EditorViewLike.decorations.of((EditorViewLike view) => view.plugin(plugin)?.letters ?? Decoration.none)),
    ),
    _themed,
    markMotion,
  ]);
}
