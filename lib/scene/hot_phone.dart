/// The phone at work: one drawing in the app's two inks, drawn over the pane of scrolling words (scene/at_work.dart).
/// Matt: "high contrast SVG iconography with cool effects like a piping hot phone CPU". A port of
/// `src/app/scene/HotPhone.tsx` and HotPhone.module.css.
///
/// The case is the dotwork's faint line (the third ink), so the words read through it and the contrast sits on the
/// CPU: a die in full ink at the phone's heart, its core a hatch that warms as a model works (state), rings of dots
/// in the case's faint ink blooming out of it and its pins lighting from the phone's real busy figure and
/// temperature (measured, scene/steps.dart `glowOf`), and above the phone a column of stipple thinning upward, the
/// heat off it in the rings' own language. On the phone's screen, above the die, the working step's icon drawn
/// large: the same lucide family as the strip's (ai/icons.dart), so the mark on the phone and the mark in the step
/// list are one thing.
///
/// Nothing here loops. The rings, the hatch and the column change by a transition when their inputs change, and the
/// mark fades in when the step does; under reduced motion they step. The one looped motion on the scene is the haze
/// on the words, which the overlay owns. Nothing is drawn again unless a ring, a pin, the warmth or the step has
/// changed, or a transition is running: the painter compares its quantised inputs.
///
/// What differs:
/// - The page's `<svg>` is a painter ([HotPhonePainter]) on the same 240 by 544 box (`viewBox="0 -64 240 544"`),
///   scaled to fit the box it is given and centred in it, which is what `block-size: 100%; max-inline-size: 100%`
///   and the svg's own aspect ratio came to. Every number is the page's.
/// - The geometry the page wrote into elements is a set of functions here ([ringDots], [columnDots], [phonePins]),
///   which the painter draws and the tests read where the page's tests read attributes.
/// - The hatch was a `<pattern>` and the rings' edge a `<clipPath>`, each with an id of its own so two phones on one
///   page shared neither. A painter has no ids: the hatch is drawn as its stripes (a 1.5 line down the left edge of
///   a 4 by 4 tile, of which the tile keeps the 0.75 inside it, turned 45 degrees) and the clip is a clip.
/// - `--glow-step` and `--ring` were custom properties and the ring's opacity a `calc()` of them; here each ring's
///   opacity is that sum worked out ([ringOpacity]) and eased by the widget, 600 ms on `--glacier-ease-out`, as the
///   stylesheet's transition did. The mark's `fadeIn` is 200 ms on the CSS `ease-out`.
/// - Not memoised by hand: Flutter draws a widget again only when it is built with something new, and the painter
///   says when that is.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import 'icons.dart';
import 'steps.dart';

/// The drawing's box: `viewBox="0 -64 240 544"`.
const Rect phoneViewBox = Rect.fromLTWH(0, -64, 240, 544);

/// The die's centre.
const double _cx = 120;
const double _cy = 250;

/// The rings: their radii, how many dots each has, and how big a dot is, innermost first (`RINGS`).
const List<({double r, int dots, double dot})> phoneRings = [
  (r: 48, dots: 16, dot: 1.8),
  (r: 62, dots: 20, dot: 1.6),
  (r: 78, dots: 26, dot: 1.4),
  (r: 96, dots: 32, dot: 1.2),
  (r: 116, dots: 40, dot: 1.0),
];

/// The column above the phone: each row's height, its dots and their size, densest at the phone's edge (`COLUMN`).
const List<({double y, int dots, double dot})> _column = [
  (y: -8, dots: 7, dot: 1.6),
  (y: -17, dots: 5, dot: 1.45),
  (y: -27, dots: 4, dot: 1.3),
  (y: -37, dots: 3, dot: 1.15),
  (y: -47, dots: 2, dot: 1.0),
  (y: -56, dots: 1, dot: 0.9),
];
const double _columnFrom = 96;
const double _columnTo = 144;

/// A number as the page wrote it into an attribute: `toFixed(2)`.
double _fixed2(double value) => double.parse(value.toStringAsFixed(2));

/// The centres of ring [n]'s dots, [n] from 1 (`ring`).
List<Offset> ringDots(int n) {
  final band = phoneRings[n - 1];
  return [
    for (var i = 0; i < band.dots; i += 1)
      // Each ring turned by half a step against the one inside it, so the dots never line up into spokes.
      () {
        final angle = (i + (n % 2) * 0.5) / band.dots * math.pi * 2;
        return Offset(_fixed2(_cx + band.r * math.cos(angle)), _fixed2(_cy + band.r * math.sin(angle)));
      }(),
  ];
}

/// The column's dots: the heat off the phone's top, stipple thinning upward.
List<({Offset at, double r})> columnDots() => [
      for (var n = 0; n < _column.length; n += 1)
        for (var i = 0; i < _column[n].dots; i += 1)
          (at: Offset(_fixed2(_columnFrom + (_columnTo - _columnFrom) / _column[n].dots * (i + 0.5) + (n % 2) * 2), _column[n].y), r: _column[n].dot),
    ];

/// The die's pins, measured: one a core, lit one a busy core, top and bottom in turn. Each is 3 by 12.
List<({double x, double y, bool lit})> phonePins(int pins, int litPins) {
  final top = (pins / 2).ceil();
  final bottom = pins - top;
  return [
    for (var k = 0; k < pins; k += 1)
      () {
        final onTop = k.isEven;
        final slot = k ~/ 2;
        final across = 64 / (onTop ? top : bottom);
        return (x: _fixed2(88 + across * (slot + 0.5) - 1.5), y: onTop ? 206.0 : 282.0, lit: k < litPins);
      }(),
  ];
}

/// `.ring { opacity: clamp(0, calc(var(--glow-step, 0) - var(--ring, 1) + 1), 1) }`: ring [n] is there once the glow
/// reaches it.
double ringOpacity(int glowStep, int n) => (glowStep - n + 1).clamp(0, 1).toDouble();

/// `.column`: nothing while cold, half while a model loads or listens, whole while it reads and writes.
double columnOpacity(Warmth warmth) => switch (warmth) { Warmth.cold => 0, Warmth.warm => 0.5, Warmth.hot => 1 };

/// `.core`: the hatch. A cold die is a quarter there, a hot one all ink.
double coreOpacity(Warmth warmth) => switch (warmth) { Warmth.cold => 0.25, Warmth.warm => 0.55, Warmth.hot => 1 };

/// The phone (`HotPhone`, `HotPhoneProps`).
class HotPhone extends StatelessWidget {
  const HotPhone({super.key, required this.warmth, required this.glowStep, required this.litPins, required this.pins, required this.step, required this.still});

  final Warmth warmth;

  /// Which ring the glow reaches, 0 to 5 (steps.dart `glowStepOf`).
  final int glowStep;

  /// How many of the die's pins are lit.
  final int litPins;

  /// How many pins the die has: the phone's cores.
  final int pins;

  /// The working step, whose icon is drawn large on the screen; null once nothing is.
  final StepId? step;

  /// Reduced motion: no fade on the mark, no transitions.
  final bool still;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // .phone { display: block; block-size: 100%; max-inline-size: 100%; overflow: visible; color: var(--app-ink); }
    final ink = t.color('app-ink');
    final ink3 = t.color('app-ink-3');
    final paper = t.color('app-paper');
    final mark = step;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // .ring, .column, .core { transition: opacity 600ms var(--glacier-ease-out); }
          // .phone[data-still] .ring, .phone[data-still] .column, .phone[data-still] .core { transition: none; }
          _Drawing(
            duration: still ? Duration.zero : const Duration(milliseconds: 600),
            curve: t.curve('glacier-ease-out'),
            warmth: warmth,
            glowStep: glowStep,
            litPins: litPins,
            pins: pins,
            ink: ink,
            ink3: ink3,
            paper: paper,
          ),
          // The working step, drawn large on the screen; keyed by the step, so a new step is a new node and its fade
          // plays again.
          // .mark { animation: fadeIn 200ms ease-out both; }
          // @keyframes fadeIn { from { opacity: 0; } }
          // .phone[data-still] .mark { animation: none; }
          if (mark != null)
            TweenAnimationBuilder<double>(
              key: ValueKey(mark),
              tween: Tween<double>(begin: still ? 1 : 0, end: 1),
              duration: still ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              builder: (context, opacity, _) => CustomPaint(painter: HotPhoneMarkPainter(step: mark, opacity: opacity, ink: ink, paper: paper)),
            ),
        ],
      ),
    );
  }
}

/// The drawing under the mark, its three kinds of opacity eased as the stylesheet's transitions eased them.
class _Drawing extends ImplicitlyAnimatedWidget {
  const _Drawing({required super.duration, required super.curve, required this.warmth, required this.glowStep, required this.litPins, required this.pins, required this.ink, required this.ink3, required this.paper});

  final Warmth warmth;
  final int glowStep;
  final int litPins;
  final int pins;
  final Color ink;
  final Color ink3;
  final Color paper;

  @override
  AnimatedWidgetBaseState<_Drawing> createState() => _DrawingState();
}

class _DrawingState extends AnimatedWidgetBaseState<_Drawing> {
  final List<Tween<double>?> _rings = List<Tween<double>?>.filled(phoneRings.length, null);
  Tween<double>? _column;
  Tween<double>? _core;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    for (var n = 0; n < _rings.length; n += 1) {
      _rings[n] = visitor(_rings[n], ringOpacity(widget.glowStep, n + 1), (dynamic value) => Tween<double>(begin: value as double)) as Tween<double>?;
    }
    _column = visitor(_column, columnOpacity(widget.warmth), (dynamic value) => Tween<double>(begin: value as double)) as Tween<double>?;
    _core = visitor(_core, coreOpacity(widget.warmth), (dynamic value) => Tween<double>(begin: value as double)) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: HotPhonePainter(
          rings: [for (final ring in _rings) ring!.evaluate(animation)],
          column: _column!.evaluate(animation),
          core: _core!.evaluate(animation),
          pins: widget.pins,
          litPins: widget.litPins,
          ink: widget.ink,
          ink3: widget.ink3,
          paper: widget.paper,
        ),
      );
}

/// Puts the 240 by 544 drawing in [size]: as tall as the box unless that is too wide for it, and in its middle.
void _fit(Canvas canvas, Size size) {
  final k = math.min(size.width / phoneViewBox.width, size.height / phoneViewBox.height);
  canvas.translate((size.width - phoneViewBox.width * k) / 2, (size.height - phoneViewBox.height * k) / 2);
  canvas.scale(k);
  canvas.translate(-phoneViewBox.left, -phoneViewBox.top);
}

/// The case, the die and its hatch, the rings, the pins and the column above, in the two inks. Public so a test can
/// read what is drawn.
class HotPhonePainter extends CustomPainter {
  const HotPhonePainter({required this.rings, required this.column, required this.core, required this.pins, required this.litPins, required this.ink, required this.ink3, required this.paper});

  /// Each ring's opacity, innermost first.
  final List<double> rings;

  /// The column's opacity.
  final double column;

  /// The hatch's opacity.
  final double core;
  final int pins;
  final int litPins;

  /// `currentColor`: the full ink.
  final Color ink;

  /// The third ink: the case and the rings.
  final Color ink3;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    _fit(canvas, size);
    Paint fill(Color color, [double opacity = 1]) => Paint()..color = color.withValues(alpha: color.a * opacity);
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    // The rings, measured: each is there once the glow reaches it. Kept inside the case, and in the faint third ink
    // like the case, so over the words they read as heat off the die and not as speckle on the text (the review saw
    // full-ink dots across the lines at the outer rings, in both themes). The die, its pins and the mark keep the
    // contrast.
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(18, 18, 204, 444), const Radius.circular(26)));
    for (var n = 0; n < phoneRings.length; n += 1) {
      if (rings[n] <= 0) continue;
      final paint = fill(ink3, rings[n]);
      for (final at in ringDots(n + 1)) {
        canvas.drawCircle(at, phoneRings[n].dot, paint);
      }
    }
    canvas.restore();

    // The heat off the phone's top, state: stipple thinning upward.
    if (column > 0) {
      final paint = fill(ink, column);
      for (final dot in columnDots()) {
        canvas.drawCircle(dot.at, dot.r, paint);
      }
    }

    // The case: the dotwork's faint line, so the words read through it.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 6, 228, 468), const Radius.circular(34)), stroke(ink3, 4));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(100, 22, 40, 4), const Radius.circular(2)), fill(ink3));

    // The die: paper and full ink, solid, so a line passing behind it is hidden by it; its core the hatch that warms.
    final die = RRect.fromRectAndRadius(const Rect.fromLTWH(88, 218, 64, 64), const Radius.circular(4));
    canvas.drawRRect(die, fill(paper));
    canvas.drawRRect(die, stroke(ink, 4));
    const coreRect = Rect.fromLTWH(102, 232, 36, 36);
    canvas.drawRect(coreRect, fill(paper));
    if (core > 0) {
      canvas.save();
      canvas.clipRect(coreRect);
      // <pattern patternUnits="userSpaceOnUse" width="4" height="4" patternTransform="rotate(45)">
      //   <line x1="0" y1="0" x2="0" y2="4" stroke="currentColor" strokeWidth="1.5" />
      canvas.rotate(math.pi / 4);
      final paint = fill(ink, core);
      // The core's corners in the pattern's own turned space.
      const r = math.sqrt1_2;
      final from = ((coreRect.left + coreRect.top) * r / 4).floor() * 4.0;
      final to = (coreRect.right + coreRect.bottom) * r;
      final top = (coreRect.top - coreRect.right) * r;
      final bottom = (coreRect.bottom - coreRect.left) * r;
      for (var x = from; x <= to; x += 4) {
        canvas.drawRect(Rect.fromLTRB(x, top, x + 0.75, bottom), paint);
      }
      canvas.restore();
    }

    // The pins, measured: one a core, lit one a busy core, top and bottom in turn.
    for (final pin in phonePins(pins, litPins)) {
      final rect = Rect.fromLTWH(pin.x, pin.y, 3, 12);
      canvas.drawRect(rect, fill(pin.lit ? ink : paper));
      canvas.drawRect(rect, stroke(ink, 1.5));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HotPhonePainter old) {
    if (old.column != column || old.core != core || old.pins != pins || old.litPins != litPins || old.ink != ink || old.ink3 != ink3 || old.paper != paper) return true;
    for (var n = 0; n < rings.length; n += 1) {
      if (old.rings[n] != rings[n]) return true;
    }
    return false;
  }
}

/// The working step's mark: a tile of paper ruled in ink, and the step's icon on it at 48, stroke 1.75. Public so a
/// test can read which step is drawn and how far in its fade is.
class HotPhoneMarkPainter extends CustomPainter {
  const HotPhoneMarkPainter({required this.step, required this.opacity, required this.ink, required this.paper});

  final StepId step;
  final double opacity;
  final Color ink;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    canvas.save();
    _fit(canvas, size);
    const tile = Rect.fromLTWH(84, 104, 72, 72);
    final whole = opacity >= 1;
    if (!whole) canvas.saveLayer(tile.inflate(2), Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    // <rect x="84" y="104" width="72" height="72" rx="12" fill="var(--app-paper)" stroke="currentColor" strokeWidth="3" />
    final rounded = RRect.fromRectAndRadius(tile, const Radius.circular(12));
    canvas.drawRRect(rounded, Paint()..color = paper);
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // <Mark x={96} y={116} size={48} strokeWidth={1.75} />
    final icon = stepIcons[step]!;
    canvas.translate(96, 116);
    DrawnIconPainter(strokes: icon.shapes, washed: [for (final index in icon.wash) icon.shapes[index]], color: ink, strokeWidth: 1.75).paint(canvas, const Size.square(48));
    if (!whole) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(HotPhoneMarkPainter old) => old.step != step || old.opacity != opacity || old.ink != ink || old.paper != paper;
}
