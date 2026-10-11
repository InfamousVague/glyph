/// The filters the editor's arriving words are drawn through: the recorder's words arriving from smoke
/// (`wisp_arrivals.dart`) and the voice's ripples (`wisp_ripples.dart`). Ports, of `src/app/editor/svgFilters.ts`,
/// what those two use: the hidden `<defs>` the filters are kept in, the parts of a smoke filter a frame changes
/// ([Smoke]), and `smokeFilter`.
///
/// A note's lines are the view's, so neither module moves a letter's run: each marks its letters with
/// `filter: url(#id)`, and the filter, kept here beside the editor, is what changes. What each filter does over time
/// - the arc, the sway, the breathing - stays with its module.
///
/// What differs:
/// - The page's filters are elements of a hidden `<svg>` in each editor's own DOM, which the browser draws a marked
///   `<span>` through. Here a filter is a [Smoke] of numbers in one table for every editor ([smokeFilter],
///   [filterNamed]), under the same ids, and a marked letter's painter ([WispLetter]) reads its filter as it paints
///   and draws the letter through the wisp's fragment shader (`shaders/wisp_bend.frag`, `lib/art/wisp_kit.dart`):
///   `feTurbulence` into `feDisplacementMap`, then the blur, the lift and the fade as a layer.
/// - A filter on the page is one field over a whole `<span>`. A painter is told a run's rectangles and nothing else,
///   and a run is cut wherever another mark begins, so here it is one field over the page, read by each letter where
///   it stands: the letters of a word bend together, as under one filter, but the cloud is anchored to the canvas
///   and not to the word's corner.
/// - The filter region (`x`, `y`, `width`, `height`) is the wisp's own for a letter, three widths either side and
///   one and a half heights above and below (`lib/art/wisp_text.dart` `paintWispLetter`), whatever the page fitted
///   to the word.
/// - The shader's noise has two octaves, as every filter of `lib/art` has; the page's arrivals asked for one.
/// - Two filters on one letter (an arriving word that ripples) nest on the page, the inner drawn and the outer
///   bending the result. Here a letter has one pass through the shader. While its own arrival still bends it, that
///   is the pass: the ripple adds its softness and carries the letter whole to where its wave throws the letter's
///   middle, so the wave still runs along the words but does not shear a letter that is smoke anyway. Once the
///   arrival's bend is over (the last three tenths of the arc) the ripple bends the letter itself, under what is
///   left of the arrival's blur. Drawing the arrival to a picture for the ripple to bend, as the page does, was a
///   picture made for each letter each frame.
/// - A ripple is drawn only on letters an arrival marks ([rippleWorn]): a run's painter is its innermost mark's, so
///   two marks on one letter cannot each bring a filter, and nothing ripples but arriving letters anyway.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;

import '../../art/turbulence.dart';
import '../../art/wisp_kit.dart';
import '../../art/wisp_settings.dart';
import '../../art/wisp_text.dart' show paintWispLetter;
import '../editor.dart';
import '../looks/look.dart';
import '../marks/run_paint.dart';
import '../view/editor_view.dart';

/// The parts of a smoke filter a frame changes.
class Smoke {
  Smoke({required this.id, required this.seed, required this.frequency, this.scale = 0, this.stdDeviation = 0, this.slope = 1});

  final String id;

  /// `feTurbulence seed`.
  final int seed;

  /// The noise that bends the letters: its `baseFrequency`, across and down.
  Offset frequency;

  /// How far the noise is swayed: the `dx` and `dy` of an `feOffset` on it (the ripples').
  Offset sway = Offset.zero;

  /// How far they are bent: the displacement's `scale`.
  double scale;

  /// How soft they are: the blur's `stdDeviation`.
  double stdDeviation;

  /// How far they are lifted: the offset's `dy`.
  double dy = 0;

  /// How much of them shows: the alpha's `slope`.
  double slope;

  /// Whether the filter leaves a letter exactly as it is.
  bool get plain => scale < 0.05 && stdDeviation < 0.05 && dy == 0 && slope >= 1;
}

/// The `<defs>` the filters go in, by id.
final Map<String, Smoke> _defs = <String, Smoke>{};

/// A smoke filter added to the defs: fractal noise bending the letters, a blur, a lift and a fade, in that order.
/// `bend`, `soft` and `shown` are where it starts; the caller moves them.
Smoke smokeFilter({required String id, required Offset frequency, required int seed, double bend = 0, double soft = 0, double shown = 1}) =>
    _defs[id] = Smoke(id: id, seed: seed, frequency: frequency, scale: bend, stdDeviation: soft, slope: shown);

/// Takes a filter out of the defs, if it is still the one there: the caller removes its own when it is done.
void removeFilter(Smoke filter) {
  if (identical(_defs[filter.id], filter)) _defs.remove(filter.id);
}

/// The filter `url(#id)` names, or null when it has gone.
Smoke? filterNamed(String? id) => id == null ? null : _defs[id];

/// The filters whose id begins `prefix`: an editor's own, for a test.
List<Smoke> filtersOf(String prefix) => <Smoke>[
  for (final filter in _defs.values)
    if (filter.id.startsWith(prefix)) filter,
];

final RegExp _url = RegExp(r'url\(#([^)]+)\)');

/// The id in a mark's `style: filter:url(#id)`.
String? filterIdOf(Map<String, String> attrs) => _url.firstMatch(attrs['style'] ?? '')?.group(1);

/// The stretches a ripple's filters are worn on, and which filter each wears: what `wisp_ripples.dart` gives, and
/// the arrivals read to mark a letter with both.
typedef RippleWear = List<({int from, int to, String id})> Function(EditorState state);

final Facet<RippleWear, List<RippleWear>> rippleWorn = Facet.define<RippleWear, List<RippleWear>>();

/// The noise a ripple's filter names, worked out here for the one point a letter is carried by.
final Map<int, Turbulence> _noises = <int, Turbulence>{};
Turbulence _noiseOf(int seed) => _noises[seed] ??= Turbulence(seed);

/// Two blurs, one after the other, as one: their deviations add as squares do.
double _both(double a, double b) => math.sqrt(a * a + b * b);

/// The room a filter may paint in round a letter's box: the wisp's own for a letter.
Rect _regionOf(Size box) => Rect.fromLTWH(-3 * box.width, -1.5 * box.height, 7 * box.width, 4 * box.height);

/// `source`, lying over `sourceRect` of the letter's own space, thrown about by the noise of `smoke` and blurred,
/// drawn with the letter's corner at the canvas's origin. `at` is where that corner is on the page: the field is the
/// page's, not the letter's, so neighbours bend together.
///
/// Where a build says so ([wispArrivalsQuick]) this is the wisp's own letter (lib/art/wisp_text.dart
/// `paintWispLetter`, the same layer and bend when a letter is drawn by itself), which while frames follow one
/// another comes off the one sheet every letter in smoke is drawn on (lib/art/wisp_letters.dart), where each
/// arriving letter is a layer and a blur of its own on every frame of its arrival.
void _through(Canvas canvas, WispKit kit, ui.Image table, ui.Image source, Rect sourceRect, Size box, Offset at, WispSmoke smoke, double opacity) {
  if (wispArrivalsQuick) {
    paintWispLetter(canvas, kit: kit, table: table, glyph: source, glyphRect: sourceRect, box: box, smoke: smoke, opacity: opacity, at: at);
    return;
  }
  final region = _regionOf(box);
  final paint = Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
  if (smoke.blur >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: smoke.blur, sigmaY: smoke.blur, tileMode: TileMode.decal);
  canvas.saveLayer(region.inflate(smoke.blur * 3), paint);
  canvas.translate(region.left, region.top);
  final shader = kit.bend(source: source, sourceRect: sourceRect.shift(at), origin: at + region.topLeft, smoke: smoke, table: table);
  canvas.drawRect(Offset.zero & region.size, Paint()..shader = shader);
  canvas.restore();
}

/// A letter of an arriving word, drawn in place of the paragraph's through the filter its mark names
/// (`filter: url(#id)`) and, where the voice ripples through it, through the ripple's over that.
class WispLetter extends LetterLayer {
  const WispLetter(super.text, this.filter, [this.ripple]);

  /// The ids of the arrival's filter and the ripple's.
  final String? filter;
  final String? ripple;

  /// One smoke filter over the glyph: bent and blurred, then lifted and faded.
  void _smoke(Canvas canvas, LetterGlyph glyph, Offset at, Size box, Smoke smoke, {double soften = 0}) {
    if (smoke.slope <= 0) return;
    final soft = _both(smoke.stdDeviation, soften);
    canvas.save();
    canvas.translate(0, smoke.dy);
    final kit = WispKit.maybe;
    final table = smoke.scale < 0.05 ? null : kit?.tableNow(smoke.seed);
    if (kit == null || table == null) {
      // Nothing to bend, or no shader yet: the letter with its softness and its fade alone.
      if (soft < 0.05 && smoke.slope >= 1) {
        glyph.painter.paint(canvas, Offset.zero);
      } else {
        final paint = Paint()..color = Color.fromRGBO(0, 0, 0, smoke.slope.clamp(0.0, 1.0));
        if (soft >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal);
        canvas.saveLayer(_regionOf(box).inflate(soft * 3), paint);
        glyph.painter.paint(canvas, Offset.zero);
        canvas.restore();
      }
    } else {
      _through(canvas, kit, table, glyph.image(), glyph.imageRect, box, at, WispSmoke.flat(seed: smoke.seed, frequency: smoke.frequency, bend: smoke.scale, blur: soft), smoke.slope);
    }
    canvas.restore();
  }

  @override
  void drawLetter(Canvas canvas, LetterGlyph glyph, Offset at, Size box, RunLook look) {
    final smoke = filterNamed(filter), wave = filterNamed(ripple);
    if (wave == null || (wave.scale < 0.05 && wave.stdDeviation < 0.05)) {
      // No ripple on it, or a voice lying still: the arrival alone, or the letter as it is.
      if (smoke == null || smoke.plain) {
        glyph.painter.paint(canvas, Offset.zero);
      } else {
        _smoke(canvas, glyph, at, box, smoke);
      }
      return;
    }
    if (smoke != null && smoke.scale >= 0.05) {
      // Still bent by its own arrival: that filter, with the ripple's softness added and the letter carried whole
      // to where the wave throws its middle.
      final middle = at + box.center(Offset.zero) - wave.sway + const Offset(0.5, 0.5);
      final noise = _noiseOf(wave.seed);
      double thrown(int channel) => wave.scale * (noise.sample(channel, middle.dx, middle.dy, baseFrequencyX: wave.frequency.dx, baseFrequencyY: wave.frequency.dy, octaves: 2) - 0.5);
      canvas.translate(-thrown(0), -thrown(1));
      _smoke(canvas, glyph, at, box, smoke, soften: wave.stdDeviation);
      return;
    }
    // Its own bend is over: the ripple bends the letter itself, under what is left of the arrival's blur.
    final slope = smoke?.slope ?? 1;
    if (slope <= 0) return;
    final kit = WispKit.maybe;
    final table = kit?.tableNow(wave.seed);
    final soft = _both(smoke?.stdDeviation ?? 0, wave.stdDeviation);
    canvas.translate(0, smoke?.dy ?? 0);
    if (kit == null || table == null) {
      // No shader yet: the ripple is its softness alone.
      final paint = Paint()..color = Color.fromRGBO(0, 0, 0, slope.clamp(0.0, 1.0));
      if (soft >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal);
      canvas.saveLayer(_regionOf(box).inflate(soft * 3), paint);
      glyph.painter.paint(canvas, Offset.zero);
      canvas.restore();
      return;
    }
    _through(canvas, kit, table, glyph.image(), glyph.imageRect, box, at, WispSmoke.flat(seed: wave.seed, frequency: wave.frequency, bend: wave.scale, blur: soft).copyWith(slide: wave.sway), slope);
  }
}

/// A word whose turn has not come: there, so the line does not move, but unseen (`opacity: 0`).
class WispUnseen extends PaintLayer {
  const WispUnseen();

  @override
  bool get replacesWords => true;
}

/// Has the lines that hold a letter wearing a filter painted again: what the browser does by itself when a
/// filter's attribute is set.
void repaintWearing(EditorViewLike view) {
  if (view is! EditorView) return;
  for (final line in view.lines) {
    if (line.spec.runs.any((run) => run.painter is MarkPaint && (run.painter! as MarkPaint).layers.any((layer) => layer is WispLetter))) line.markNeedsPaint();
  }
}
