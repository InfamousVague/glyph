/// The filters the editor's arriving words are drawn through: the recorder's words arriving out of a blur
/// (`wisp_arrivals.dart`) and the voice's ripples (`wisp_ripples.dart`). Ports, of `src/app/editor/svgFilters.ts`,
/// what those two use: the hidden `<defs>` the filters are kept in, the parts of a filter a frame changes
/// ([Smoke]), and `smokeFilter`.
///
/// A note's lines are the view's, so neither module moves a letter's run: each marks its letters with
/// `filter: url(#id)`, and the filter, kept here beside the editor, is what changes. What each filter does over time
/// - the arc, the sway, the breathing - stays with its module.
///
/// What differs:
/// - The page's filters are elements of a hidden `<svg>` in each editor's own DOM, which the browser draws a marked
///   `<span>` through. Here a filter is a [Smoke] of numbers in one table for every editor ([smokeFilter],
///   [filterNamed]), under the same ids, and a marked letter's painter ([WispLetter]) reads its filter as it paints.
/// - The page bends the letters through noise (`feTurbulence` into `feDisplacementMap`) and blurs them. Here they are
///   only blurred, the bend taken into how soft they are (lib/art/blur_letter.dart `letterBlur`), then lifted and
///   faded as a layer (Matt, 2026-10-24: "replace the smoke effect with a gradient blur on all places that use the
///   wisp smoke", and on the Mac too).
/// - The layer's region is the one every letter has, three widths either side and one and a half heights above and
///   below (lib/art/blur_letter.dart `letterRegion`), whatever the page fitted to the word.
/// - Two filters on one letter (an arriving word that ripples) nest on the page, the inner drawn and the outer
///   bending the result. Here the ripple adds its softness to the arrival's and carries the letter whole to where
///   its wave throws the letter's middle (the noise worked out in Dart for that one point, two octaves), so the
///   wave still runs along the words.
/// - A ripple is drawn only on letters an arrival marks ([rippleWorn]): a run's painter is its innermost mark's, so
///   two marks on one letter cannot each bring a filter, and nothing ripples but arriving letters anyway.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' hide Decoration;

import '../../art/blur_letter.dart';
import '../../art/turbulence.dart';
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

/// A letter of an arriving word, drawn in place of the paragraph's through the filter its mark names
/// (`filter: url(#id)`) and, where the voice ripples through it, through the ripple's over that.
///
/// A filter is drawn as a blur (lib/art/blur_letter.dart), where it was the wisp's shader bending the letter
/// through noise (Matt, 2026-10-24: "replace the smoke effect with a gradient blur on all places that use the wisp
/// smoke", on every platform): the filter's bend and its blur together are how soft the letter is, then it is
/// lifted and faded as before. A ripple carries the letter whole to where its wave throws the letter's middle, and
/// adds its own softness, so the wave still runs along the words as the voice moves them.
class WispLetter extends LetterLayer {
  const WispLetter(super.text, this.filter, [this.ripple]);

  /// The ids of the arrival's filter and the ripple's.
  final String? filter;
  final String? ripple;

  /// One filter over the glyph: blurred by its bend and its blur (and [soften] more), then lifted and faded.
  void _smoke(Canvas canvas, LetterGlyph glyph, Size box, Smoke smoke, {double soften = 0}) {
    if (smoke.slope <= 0) return;
    canvas.save();
    canvas.translate(0, smoke.dy);
    paintBlurLetter(canvas, box: box, sigma: letterBlur(smoke.scale, _both(smoke.stdDeviation, soften)), opacity: smoke.slope, draw: (canvas) => glyph.painter.paint(canvas, Offset.zero));
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
        _smoke(canvas, glyph, box, smoke);
      }
      return;
    }
    // The letter carried whole to where the wave throws its middle, with the ripple's softness added to whatever
    // is left of its own arrival.
    final middle = at + box.center(Offset.zero) - wave.sway + const Offset(0.5, 0.5);
    final noise = _noiseOf(wave.seed);
    double thrown(int channel) => wave.scale * (noise.sample(channel, middle.dx, middle.dy, baseFrequencyX: wave.frequency.dx, baseFrequencyY: wave.frequency.dy, octaves: 2) - 0.5);
    canvas.save();
    canvas.translate(-thrown(0), -thrown(1));
    _smoke(canvas, glyph, box, smoke ?? Smoke(id: '', seed: wave.seed, frequency: wave.frequency, slope: 1), soften: wave.stdDeviation);
    canvas.restore();
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
