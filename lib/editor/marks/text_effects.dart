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
///   the strength. The page bends a whole `<span>` through one field anchored to it; here each letter is bent
///   through a field anchored to the page, so neighbours bend together but the field is not the one Chromium
///   draws: the same weather, another sky. A ligature across heated letters is set as its letters.
/// - **Frost** has no shader of its own yet. The cooling is the page's colour matrix; the rime is the letter's
///   shape grown by the creeping radius (`ImageFilter.dilate`), kept where the SVG noise of the same seed and
///   frequency is bright enough, flooded with the page's ice and softened. The noise is the specification's, worked
///   out in Dart for a tile 96 pixels square and repeated, where the page's field does not repeat.
/// - `prefers-reduced-motion` is the tokens' `reducedMotion`.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' hide Decoration;

import '../../art/turbulence.dart';
import '../../art/wisp_kit.dart';
import '../../plugins/marks.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../view/editor_view.dart';
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
List<EffectRange> effectRanges(EditorState state, Map<String, EffectLookSpec> looks, int from, int to, bool atCaret) {
  final found = <EffectRange>[];
  syntaxTree(state).iterate(
    from: from,
    to: to,
    enter: (node) {
      final look = looks[node.name];
      if (look == null) return null;
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
  const _Fx(this.name, this.value);
  final String name;
  final double value;

  static List<_Fx> parse(String said) => <_Fx>[
    for (final part in said.split('|'))
      if (part.isNotEmpty) _Fx(part.split('@').first, part.contains('@') ? double.parse(part.split('@').last) : 0),
  ];
}

/// The frost's specks for a seed: `feTurbulence` (fractal noise, two octaves) through `0 0 0 5 -1.9` on its alpha,
/// as a tile to lay over the grown letters.
const int _grainTile = 96;
final Map<String, ui.Image> _grains = <String, ui.Image>{};

ui.Image _grain(int seed, double frequency) {
  final key = '$seed|${frequency.toStringAsFixed(3)}';
  final had = _grains[key];
  if (had != null) return had;
  final noise = Turbulence(seed);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  for (var y = 0; y < _grainTile; y++) {
    for (var x = 0; x < _grainTile; x++) {
      final alpha = noise.sample(3, x + 0.5, y + 0.5, baseFrequencyX: frequency, baseFrequencyY: frequency, octaves: 2);
      final kept = (alpha * 5 - 1.9).clamp(0.0, 1.0);
      if (kept <= 0) continue;
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), paint..color = Color.fromRGBO(0, 0, 0, kept));
    }
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(_grainTile, _grainTile);
  picture.dispose();
  return _grains[key] = image;
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

    // A wave: `position: relative; top`, the letter moved and nothing round it.
    final wave = _of('wave');
    if (wave != null && !still) canvas.translate(0, waveLift(now, wave.round()) * em);

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
    final frost = _of('frost') != null;
    if (frost) {
      final filter = frostFilter(now, fontPx, still: still);
      final ice = (dark ? const Color(0xFFCDEAFF) : const Color(0xFF5AA6DA)).withValues(alpha: 0.95);
      final room = region.inflate(filter.radius + filter.blur * 3);
      canvas.saveLayer(room, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: filter.blur, sigmaY: filter.blur, tileMode: TileMode.decal));
      canvas.saveLayer(
        room,
        Paint()
          ..imageFilter = ui.ImageFilter.dilate(radiusX: filter.radius, radiusY: filter.radius)
          ..colorFilter = ColorFilter.mode(ice, BlendMode.srcIn),
      );
      glyph.painter.paint(canvas, Offset.zero);
      canvas.restore();
      // Kept where the grain is bright: the field stays with the page while the letter may move.
      final grain = _grain(filter.seed, filter.frequency);
      canvas.drawRect(
        room,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.ImageShader(grain, TileMode.repeated, TileMode.repeated, Float64List.fromList(<double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -at.dx, -at.dy, 0, 1])),
      );
      canvas.restore();
    }

    // Heat: the letter through the hot air, at the strongest of what reaches it.
    var heat = 0.0;
    for (final one in fx) {
      if ((one.name == 'heat' || one.name == 'haze') && one.value > heat) heat = one.value;
    }
    final kit = WispKit.maybe;
    final filter = heat > 0 ? heatFilter(now, fontPx, heat, still: still) : null;
    final table = filter == null ? null : kit?.tableNow(filter.seed);
    final paint = Paint();
    // A sheen over the frost is the sheen: the letter is one flat colour either way.
    if (frost || sheen != null) paint.colorFilter = sheen ?? _cold;
    if (filter != null && kit != null && table != null) {
      if (filter.blur >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: filter.blur, sigmaY: filter.blur, tileMode: TileMode.decal);
      final image = glyph.image();
      canvas.saveLayer(region.inflate(filter.blur * 3), paint);
      canvas.translate(region.left, region.top);
      // The field is the page's, not the letter's: neighbours bend together.
      final shader = kit.bend(
        source: image,
        sourceRect: glyph.imageRect.shift(at),
        origin: at + region.topLeft,
        smoke: WispSmoke.flat(seed: filter.seed, frequency: filter.frequency, bend: filter.bend, blur: filter.blur),
        table: table,
      );
      canvas.drawRect(Offset.zero & region.size, Paint()..shader = shader);
      canvas.restore();
    } else if (paint.colorFilter != null || filter != null) {
      // No shader yet: the haze is its softness alone.
      if (filter != null && filter.blur >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: filter.blur, sigmaY: filter.blur, tileMode: TileMode.decal);
      canvas.saveLayer(region, paint);
      glyph.painter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      glyph.painter.paint(canvas, Offset.zero);
    }
    if (layered) canvas.restore();
  }
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

class _TextEffects extends PluginValue {
  _TextEffects(this.view, this.looks) {
    _redraw(first: true);
  }

  final EditorViewLike view;
  final Map<String, EffectLookSpec> looks;

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

  /// The text above heated words, as last measured: drawn through the haze on the next draw.
  List<_Above> _above = const <_Above>[];
  bool _destroyed = false;

  static final Map<String, Decoration> _made = <String, Decoration>{};

  static Decoration _mark(String className, Map<String, String> attributes) =>
      _made['$className|${attributes.entries.map((e) => '${e.key}=${e.value}').join(';')}'] ??= Decoration.mark(className: className, attributes: attributes);

  @override
  void update(ViewUpdate update) {
    final measured = update.transactions.any((tr) => tr.effects.any((effect) => _heatMeasured.cast(effect) != null));
    if (update.docChanged) _above = const <_Above>[];
    if (measured ||
        update.docChanged ||
        update.viewportChanged ||
        update.selectionSet ||
        update.focusChanged ||
        update.geometryChanged ||
        !identical(syntaxTree(update.state), syntaxTree(update.startState))) {
      _redraw();
    }
  }

  @override
  void destroy() => _destroyed = true;

  void _redraw({bool first = false}) {
    final state = view.state;
    final ranges = view.visibleRanges;
    final atCaret = state.facet(EditorViewLike.editable) && view.hasFocus;
    final found = ranges.isEmpty ? const <EffectRange>[] : effectRanges(state, looks, ranges.first.from, ranges.last.to, atCaret);
    if (found.isNotEmpty) _wantTables(atOnce: first);
    final marks = <({int from, int to, Decoration mark})>[];
    // What moves each letter, by where it starts.
    final cells = <int, ({int to, List<String> fx, List<String> names, int? delay})>{};
    void touch(int from, int to, String fx, [String? name, int? delay]) {
      final had = cells[from];
      cells[from] = (to: to, fx: <String>[...?had?.fx, fx], names: <String>[...?had?.names, ?name], delay: had == null ? delay : null);
    }

    void everyLetter(int from, int to, String fx) {
      var pos = from;
      for (final rune in state.doc.sliceString(from, to).runes) {
        final ch = String.fromCharCode(rune);
        if (!_space.hasMatch(ch)) touch(pos, pos + ch.length, fx);
        pos += ch.length;
      }
    }

    final rising = <EffectRange>[];
    for (final stretch in found) {
      final effect = textEffectsByName[stretch.effect];
      switch (effect) {
        case RisingEffect():
          marks.add((
            from: stretch.from,
            to: stretch.to,
            mark: _mark('cm-textEffect cm-effect-${stretch.effect}', <String, String>{'data-effect': stretch.effect, 'style': 'filter:url(#glyph-effect-${stretch.effect}-own)'}),
          ));
          everyLetter(stretch.from, stretch.to, '${stretch.effect}@${effect.own}');
          rising.add(stretch);
        case FilterEffect():
          marks.add((from: stretch.from, to: stretch.to, mark: _mark('cm-textEffect', <String, String>{'data-effect': stretch.effect, 'style': 'filter:url(#glyph-effect-${stretch.effect})'})));
          everyLetter(stretch.from, stretch.to, stretch.effect);
        case LetterEffect():
          for (final letter in effectLetters(state, stretch.from, stretch.to, effect)) {
            touch(letter.from, letter.to, '${stretch.effect}@${letter.delayMs}', stretch.effect, letter.delayMs);
          }
        case null:
          break;
      }
    }
    // The haze over the text above heated words, as last measured, where it is still text outside the heat itself.
    for (final above in _above) {
      if (above.to > state.doc.length || rising.any((r) => above.from < r.to && above.to > r.from)) continue;
      marks.add((
        from: above.from,
        to: above.to,
        mark: _mark('cm-textEffectAbove', <String, String>{'data-effect': '${above.effect}-above', 'style': 'filter:url(#glyph-effect-${above.effect}-above-${(above.strength * 100).round()})'}),
      ));
      // A range of one line: its letters, the break aside.
      everyLetter(above.from, above.to, 'haze@${above.strength}');
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
    _measureAbove(rising);
  }

  /// Where the text above the heated words is, read once the view is laid out, and drawn on the next update when
  /// it has moved. A haze changes no layout, so this settles after one round: the second measure finds what the
  /// first did and dispatches nothing.
  void _measureAbove(List<EffectRange> rising) {
    if (rising.isEmpty && _above.isEmpty) return;
    view.requestMeasure<List<_Above>>(
      MeasureRequest<List<_Above>>(
        key: this,
        read: (view) {
          final own = view;
          final lineHeight = own is EditorView ? own.heights.lineHeight : 0.0;
          if (lineHeight <= 0) return _above;
          final probe = _probeOf(view);
          return <_Above>[
            for (final stretch in rising)
              if (textEffectsByName[stretch.effect] case final RisingEffect effect)
                for (final segment in _segmentsOf(view, stretch.from, stretch.to))
                  for (final above in textAbove(segment, lineHeight, effect.strengths, probe)) _Above(above.from, above.to, stretch.effect, above.strength),
          ];
        },
        write: (next, view) {
          var same = next.length == _above.length;
          for (var i = 0; same && i < next.length; i++) {
            same = next[i].from == _above[i].from && next[i].to == _above[i].to && next[i].strength == _above[i].strength;
          }
          if (same) return;
          _above = next;
          // Not from inside the measure: on the next turn.
          Timer.run(() {
            if (!_destroyed) view.dispatch(TransactionSpec(effects: _heatMeasured.of(null)));
          });
        },
      ),
    );
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
  return Extension.list(<Extension>[
    ViewPlugin.define<_TextEffects>(
      (view) => _TextEffects(view, looks),
      decorations: (value) => value.decorations,
      // The letters' marks inside every other, so a letter's painter is the one its run carries.
      provide: (plugin) => Prec.highest(EditorViewLike.decorations.of((EditorViewLike view) => view.plugin(plugin)?.letters ?? Decoration.none)),
    ),
    _themed,
    markMotion,
  ]);
}
