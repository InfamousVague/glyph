/// Ripples through the words as the person talks: the recorder's page (`lib/capture/ui/live_page.dart`) shows what
/// it hears, and the voice runs through the words still coming in, bending them in waves that swell with the mic
/// level and lie still in a pause. Ports `src/app/editor/wispRipples.ts`.
///
/// Matt: "the memo page should real time fade words in with the wisp effect and should show the voice recording
/// ripples giving the text weird wisp ripples". The fading-in is `wisp_arrivals.dart`; this is the ripples.
///
/// Only the arriving words ripple, never the text already set around them (Matt: "it makes all of the text around
/// it into the wisp text; it should only make text that's fading in as I'm talking in the wisp look"): the ranges
/// this draws on are the letters the arrivals report in motion, run together into stretches, and a word that has
/// settled drops out of it as it sets. A few filters are shared round the stretches, each a slow, wide noise
/// moving the words (low frequency across, higher down, so the wave runs along them) with a touch of blur, its
/// throw scaled by the level. Each letter is carried whole by the wave and softened, where the page bends it
/// through the noise (lib/editor/ai/wisp_filters.dart; Matt, 2026-10-24: "replace the smoke effect with a gradient
/// blur on all places that use the wisp smoke"). The noise sways a few pixels rather than sliding far, and the filter region is wide
/// around each letter, so a short word bent hard is never clipped. The level is followed with a quick rise and a
/// slow fall, the way a needle moves, on the animation clock at about thirty steps a second, and the loop stops
/// altogether once the voice has died away, so silence costs nothing. Reduced motion: no ripples.
///
/// The level comes from whoever mounts it, as a subscribe function, so this knows nothing of the recorder
/// ([RippleSource]); the pure parts are exported for the tests.
///
/// What differs:
/// - The page's filters are SVG, worn by a `<span>` over each stretch. Here a filter is a [Smoke] of numbers
///   (`wisp_filters.dart`), and what wears it is each arriving letter: the stretch's mark (`cm-wispRipple`) is kept
///   as the page makes it, and the arrivals read which filter a letter's stretch wears ([rippleWorn]) and mark the
///   letter with both, since a run has one painter. So `wispRipples` draws nothing without `wispArrivals` beside
///   it, which is where its words come from on the page too.
/// - `prefersStill()` is the facet `wispStill` (`lib/editor/marks/wisp_motion.dart`), read when the editor is made:
///   an extension has no window to ask as it is written. With it set the level is never listened to.
/// - The filters are named by the call (`wispripple-<n>-<k>`), not by the editor: the arrivals need the names from
///   the state alone. One call's extension is for one editor.
/// - `requestAnimationFrame` is a `Ticker` and its time is `wispNow`, which a test holds.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart' show baseTheme;
import '../marks/wisp_motion.dart';
import 'wisp_filters.dart';

abstract interface class RippleSource {
  /// Hears the level, 0 to 1, as it comes; answers how to stop hearing it.
  void Function() subscribe(void Function(double level) listener);
}

/// The stretches rippling: the arriving letters in motion (`wisp_arrivals.dart`), in document order, run together
/// where only a space or two lies between them, so a phrase is one stretch. Letters leaving (ghosts) take no part.
List<({int from, int to})> rippledRanges(EditorState state) {
  final letters = <({int from, int to})>[
    for (final m in moving(state))
      if (m.to > m.from) (from: m.from, to: m.to),
  ]..sort((a, b) => a.from - b.from);
  final stretches = <({int from, int to})>[];
  for (final letter in letters) {
    final last = stretches.isEmpty ? null : stretches.last;
    if (last != null && letter.from <= last.to + 2 && !state.doc.sliceString(last.to, math.max(last.to, letter.from)).contains('\n')) {
      stretches[stretches.length - 1] = (from: last.from, to: math.max(last.to, letter.to));
    } else {
      stretches.add(letter);
    }
  }
  return stretches;
}

/// The level followed: up quickly with a voice, down slowly after it.
double follow(double shown, double level) {
  final rate = level > shown ? 0.45 : 0.08;
  final next = shown + (level - shown) * rate;
  return next < 0.004 ? 0 : next;
}

/// How far a line bends and blurs at a followed level: nothing in silence, a full wave by ordinary talking.
({double scale, double blur}) shape(double level) {
  final amount = math.min(1.0, level / 0.3);
  return (scale: (amount * amount * 30 * 10).round() / 10, blur: (amount * 1.4 * 100).round() / 100);
}

const int _filters = 4;
const double _stepMs = 33;

int _instances = 0;

/// One of the shared filters: a slow, wide noise, swayed a few pixels, bending the words, with a touch of blur.
Smoke _slot(String id, int seed) => smokeFilter(id: id, frequency: const Offset(0.007, 0.045), seed: seed, bend: 0, soft: 0);

// Plain inline spans, so the line's kerning and wrapping are exactly what they are without the ripple. Made once: a
// theme made again for every editor is mounted again for every editor (view/text_panel.dart).
// '.cm-wispRipple': {}
final Extension _rippleTheme = baseTheme(const LookSheet('editor/wispRipples.ts', <LookRule>[]));

class _Ripples extends PluginValue {
  _Ripples(this.view, this.source, this.prefix) {
    for (var i = 0; i < _filters; i += 1) {
      final id = '$prefix-$i';
      _marks.add(Decoration.mark(className: 'cm-wispRipple', attributes: <String, String>{'style': 'filter:url(#$id)'}));
    }
    // Reduced motion: no ripples, and nobody listening.
    if (view.state.facet(wispStill)) return;
    for (var i = 0; i < _filters; i += 1) {
      _slots.add(_slot('$prefix-$i', i * 13 + 5));
    }
    _redraw();
    _stop = source.subscribe((level) {
      if (_gone) return;
      _level = level.clamp(0.0, 1.0);
      if (_level > 0) {
        _frame ??= Ticker(_tick);
        if (!_frame!.isActive) _frame!.start();
      }
    });
  }

  final EditorViewLike view;
  final RippleSource source;
  final String prefix;

  DecorationSet decorations = Decoration.none;
  final List<Smoke> _slots = <Smoke>[];
  final List<Decoration> _marks = <Decoration>[];
  int _count = 0;
  void Function()? _stop;
  double _level = 0;
  double _shown = 0;
  Ticker? _frame;
  double _last = double.negativeInfinity;
  bool _gone = false;

  @override
  void update(ViewUpdate update) {
    if (_slots.isEmpty) return;
    if (update.docChanged || update.viewportChanged || !identical(moving(update.state), moving(update.startState))) _redraw();
  }

  @override
  void destroy() {
    _gone = true;
    _stop?.call();
    _frame?.dispose();
    _frame = null;
    for (final slot in _slots) {
      removeFilter(slot);
    }
  }

  /// The words still arriving, each stretch wearing one of the shared filters; settled text wears none.
  void _redraw() {
    final stretches = rippledRanges(view.state);
    decorations = stretches.isEmpty
        ? Decoration.none
        : Decoration.set(<Range<Decoration>>[for (final (i, stretch) in stretches.indexed) _marks[i % _filters].range(stretch.from, stretch.to)]);
    _count = stretches.length;
  }

  void _tick(Duration _) {
    if (_gone) return;
    final now = wispNow();
    if (now - _last < _stepMs) return;
    _last = now;
    _shown = follow(_shown, _level);
    // Nothing arriving, nothing to bend: the filters only move while there are words wearing them.
    if (_count > 0) {
      _pose(now / 1000);
      repaintWearing(view);
    }
    if (_shown == 0 && _level == 0) {
      // The voice has died away and the lines lie still: nothing to draw until it comes back.
      _frame?.stop();
    }
  }

  /// Every filter at time `t` and the followed level, each on its own phase.
  void _pose(double t) {
    final at = shape(_shown);
    double fixed(double value, int digits) => double.parse(value.toStringAsFixed(digits));
    for (final (k, s) in _slots.indexed) {
      final phase = k * 1.7;
      s
        ..sway = Offset(fixed(7 * math.sin(t * 2.3 + phase), 2), fixed(5 * math.sin(t * 1.6 + phase * 1.3), 2))
        ..frequency = Offset(fixed(0.007 + 0.002 * math.sin(t * 0.9 + phase), 4), fixed(0.045 + 0.012 * math.sin(t * 0.7 + phase * 0.8), 4))
        ..scale = at.scale
        ..stdDeviation = at.blur;
    }
  }
}

Extension wispRipples(RippleSource source) {
  _instances += 1;
  final prefix = 'wispripple-$_instances';
  return Extension.list(<Extension>[
    ViewPlugin.define<_Ripples>((view) => _Ripples(view, source, prefix), decorations: (value) => value.decorations),
    // Which filter each stretch wears, for the arrivals to mark its letters with.
    rippleWorn.of(
      (state) => state.facet(wispStill)
          ? const <({int from, int to, String id})>[]
          : <({int from, int to, String id})>[for (final (i, stretch) in rippledRanges(state).indexed) (from: stretch.from, to: stretch.to, id: '$prefix-${i % _filters}')],
    ),
    _rippleTheme,
  ]);
}
