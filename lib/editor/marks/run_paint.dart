/// What the marks and the inline items paint with: the one [RunPainter] a run carries, built up of layers; the
/// clock the moving ones read; and the little of CSS a style look is written in.
///
/// On the page a mark is a `<span>` and its look is CSS on it: a background with a radius and a spread shadow, an
/// underline, a filter, an animation. The view (`lib/editor/view/line.dart`) draws a run's words and gives whoever
/// styled it one hook, `Props.painter`, called with the run's rectangles on each visual line. Everything here goes
/// through that hook:
///
/// - [MarkPaint] is the painter: a list of [PaintLayer]s, so a highlight's wash, a tag's chip and an effect's
///   letter can lie on one run. `MarkPaint.add` is how a rule puts its layer on.
/// - [BoxLayer] is `background` + `border-radius` + `box-shadow: 0 0 0 <spread>` (+ a border, + a fill to a
///   share of the width, for a counter), sliced at a line wrap as `box-decoration-break: slice` slices it.
/// - [UnderlineLayer] is `text-decoration: underline` with an offset, a thickness and a dotted or dashed style,
///   which a Flutter text style cannot say.
/// - [LetterLayer] draws the run's own letter in place of the paragraph's (a moved, faded, bent or small-capital
///   letter): the base of the effects and the smoke.
/// - [MarkClock] is the time the moving layers read, and [markMotion] the plugin that keeps the lines that hold
///   one painted while any is on screen.
/// - [StyleCss] reads a look's declarations.
///
/// What differs from the page: a filter there is one field over a whole `<span>`; here a run is painted in the
/// pieces the view cuts it into, so anything that is one drawing over several letters is made per letter with a
/// shared field (see `text_effects.dart`).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../looks/look.dart';
import '../view/editor_view.dart';

// ---- the clock ---------------------------------------------------------------------------------------------------

/// The time the moving marks read, in seconds: the animation clock's, as `requestAnimationFrame`'s on the page.
abstract final class MarkClock {
  static double _now = 0;

  /// Set by a test (or a picture) to stop the clock at a moment; null lets it run.
  static double? hold;

  static double get now => hold ?? _now;
}

/// A layer of a run's painting.
abstract class PaintLayer {
  const PaintLayer();

  void behind(Canvas canvas, List<Rect> boxes, RunLook look) {}
  void over(Canvas canvas, List<Rect> boxes, RunLook look) {}

  /// Whether the layer draws the words itself, so the paragraph's are not drawn.
  bool get replacesWords => false;

  /// Whether the layer changes with [MarkClock].
  bool get moves => false;
}

/// The painter of a run with marks on it: its layers, outermost first.
class MarkPaint extends RunPainter {
  const MarkPaint(this.layers);

  final List<PaintLayer> layers;

  /// `current` with `layer` on it.
  static MarkPaint add(RunPainter? current, PaintLayer layer) => MarkPaint(<PaintLayer>[if (current is MarkPaint) ...current.layers, layer]);

  bool get moves => layers.any((layer) => layer.moves);

  @override
  bool get drawsWords => !layers.any((layer) => layer.replacesWords);

  @override
  void paintBehind(Canvas canvas, List<Rect> boxes, RunLook look) {
    if (boxes.isEmpty) return;
    for (final layer in layers) {
      layer.behind(canvas, boxes, look);
    }
  }

  @override
  void paintOver(Canvas canvas, List<Rect> boxes, RunLook look) {
    if (boxes.isEmpty) return;
    for (final layer in layers) {
      layer.over(canvas, boxes, look);
    }
  }
}

class _Motion extends PluginValue {
  _Motion(this.view) {
    _check();
  }

  final EditorViewLike view;
  Ticker? _ticker;
  bool _asked = false;
  bool _gone = false;
  double _last = -1;

  /// The screen's rate, as the page's CSS animations run; the smoke steps itself down to thirty a second
  /// (`STEP_MS`) by the time it reads.
  static const double _step = 1 / 60;

  List<RenderObject> _moving() {
    final own = view;
    if (own is! EditorView) return const <RenderObject>[];
    return <RenderObject>[
      for (final line in own.lines)
        if (line.spec.runs.any((run) => run.painter is MarkPaint && (run.painter! as MarkPaint).moves)) line,
    ];
  }

  void _check() {
    if (_asked || _gone) return;
    _asked = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _asked = false;
      if (_gone) return;
      final any = _moving().isNotEmpty;
      if (any && _ticker == null) {
        _ticker = Ticker(_tick)..start();
      } else if (!any && _ticker != null) {
        _ticker!.dispose();
        _ticker = null;
      }
    });
  }

  void _tick(Duration elapsed) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds / 1e6;
    if (now - _last < _step - 0.002) return;
    _last = now;
    MarkClock._now = now;
    final moving = _moving();
    if (moving.isEmpty) {
      _ticker?.dispose();
      _ticker = null;
      return;
    }
    for (final line in moving) {
      line.markNeedsPaint();
    }
  }

  @override
  void docViewUpdate(EditorViewLike view) => _check();

  @override
  void destroy() {
    _gone = true;
    _ticker?.dispose();
    _ticker = null;
  }
}

/// Keeps the lines that hold a moving mark painted while any is laid out: the page's animation loop. Every
/// extension that brings a moving layer brings this; it is one plugin however many do.
final Extension markMotion = ViewPlugin.define<PluginValue>(_Motion.new);

// ---- boxes -------------------------------------------------------------------------------------------------------

/// Which ends of its mark a piece of a box is: a mark is drawn in pieces (the view cuts a run where another mark
/// begins inside it), and only the mark's own ends are rounded and spread, as `box-decoration-break: slice` leaves
/// the cut edges of a wrapped `<span>` square.
enum BoxEdge { both, start, end, none }

BoxEdge boxEdgeOf(String? said) => switch (said) {
  'start' => BoxEdge.start,
  'end' => BoxEdge.end,
  'none' => BoxEdge.none,
  _ => BoxEdge.both,
};

double _device() {
  final views = ui.PlatformDispatcher.instance.views;
  return views.isEmpty ? 1.0 : views.first.devicePixelRatio;
}

/// A position on a whole device pixel, so two pieces of one box meet without a seam.
double snapToDevice(double value) {
  final ratio = _device();
  return (value * ratio).roundToDouble() / ratio;
}

/// `background`, `border-radius`, `box-shadow: 0 0 0 <spread> <color>` and `padding`, on an inline box.
class BoxLayer extends PaintLayer {
  const BoxLayer({
    this.color,
    this.radius = 0,
    this.spread = 0,
    this.spreadColor,
    this.edge = BoxEdge.both,
    this.onTop = false,
    this.padStart = 0,
    this.padEnd = 0,
    this.border = 0,
    this.borderColor,
    this.inset = 0,
    this.insetColor,
    this.fill,
    this.fillColor,
    this.fillPart,
    this.fillPad = 0,
    this.top = 0,
    this.bottom = 0,
  });

  final Color? color;

  /// `border-radius`, in pixels.
  final double radius;

  /// The shadow's spread, in pixels, and its colour.
  final double spread;
  final Color? spreadColor;
  final BoxEdge edge;

  /// Painted over the words (a redaction's bar) and not behind them.
  final bool onTop;

  /// Padding (and border) the box has beyond its words, at its start and its end.
  final double padStart, padEnd;

  /// A border all round, in pixels, inside the padding's outer edge.
  final double border;
  final Color? borderColor;

  /// `box-shadow: inset 0 0 0 <n>`: a hairline inside the edge.
  final double inset;
  final Color? insetColor;

  /// A ground from the start to this share of the width (a counter's `--fill`).
  final double? fill;
  final Color? fillColor;

  /// Where this piece stands in the box the fill is a share of, counted in characters of one width: how many
  /// come before it, how many it is, and how many the box holds; with [fillPad], the box's padding either side
  /// of them. Null for a box in one piece.
  final ({int before, int own, int total})? fillPart;
  final double fillPad;

  /// How far the box reaches above and below the words' own box (a border's width).
  final double top, bottom;

  void _paint(Canvas canvas, List<Rect> boxes) {
    for (var i = 0; i < boxes.length; i++) {
      final first = i == 0 && (edge == BoxEdge.both || edge == BoxEdge.start);
      final last = i == boxes.length - 1 && (edge == BoxEdge.both || edge == BoxEdge.end);
      final box = boxes[i];
      // A cut edge is square and meets the next piece exactly: the shape runs on past it and is clipped there, to
      // whole pixels, so two pieces of one wash neither part nor lie over each other.
      final rect = Rect.fromLTRB(first ? box.left - padStart : box.left - 4, box.top - top, last ? box.right + padEnd : box.right + 4, box.bottom + bottom);
      canvas.save();
      if (!first || !last) canvas.clipRect(Rect.fromLTRB(first ? box.left - 4096 : box.left, box.top - 4096, last ? box.right + 4096 : box.right, box.bottom + 4096), doAntiAlias: false);
      RRect shape(Rect of, double r) => RRect.fromRectAndCorners(
        of,
        topLeft: first ? Radius.circular(r) : Radius.zero,
        bottomLeft: first ? Radius.circular(r) : Radius.zero,
        topRight: last ? Radius.circular(r) : Radius.zero,
        bottomRight: last ? Radius.circular(r) : Radius.zero,
      );
      final whole = rect.inflate(spread);
      // A spread follows its box's corners: round where they are round, square where they are square.
      final outline = shape(whole, radius > 0 ? radius + spread : 0);
      final ground = color, shadow = spreadColor ?? color;
      if (ground != null && shadow != null && ground == shadow) {
        // One colour: the box and its spread are one shape, drawn once, so a wash never lies twice over itself.
        canvas.drawRRect(outline, Paint()..color = ground);
      } else {
        if (shadow != null && spread > 0) canvas.drawDRRect(outline, shape(rect, radius), Paint()..color = shadow);
        if (ground != null) canvas.drawRRect(shape(rect, radius), Paint()..color = ground);
      }
      if (fill != null && fillColor != null && fill! > 0) {
        // The gradient runs over the padding box of the whole span, which a piece works out from its own letters.
        final inner = rect.deflate(border);
        var from = inner.left, across = inner.width;
        final part = fillPart;
        if (part != null && part.own > 0) {
          final letter = box.width / part.own;
          from = box.left - part.before * letter - fillPad;
          across = part.total * letter + 2 * fillPad;
        }
        canvas.save();
        canvas.clipRRect(shape(inner, math.max(0, radius - border)));
        canvas.drawRect(Rect.fromLTRB(from, inner.top, from + across * fill!.clamp(0.0, 1.0), inner.bottom), Paint()..color = fillColor!);
        canvas.restore();
      }
      if (border > 0 && borderColor != null) {
        canvas.drawRRect(
          shape(rect.deflate(border / 2), math.max(0, radius - border / 2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = border
            ..color = borderColor!,
        );
      }
      if (inset > 0 && insetColor != null) {
        canvas.drawRRect(
          shape(rect.deflate(inset / 2), math.max(0, radius - inset / 2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = inset
            ..color = insetColor!,
        );
      }
      canvas.restore();
    }
  }

  @override
  void behind(Canvas canvas, List<Rect> boxes, RunLook look) {
    if (!onTop) _paint(canvas, boxes);
  }

  @override
  void over(Canvas canvas, List<Rect> boxes, RunLook look) {
    if (onTop) _paint(canvas, boxes);
  }
}

// ---- underlines --------------------------------------------------------------------------------------------------

enum UnderlineStyle { solid, dotted, dashed }

/// `text-decoration: underline` as the page draws it with `text-underline-offset` and
/// `text-decoration-thickness`: the line's top that far under the baseline.
class UnderlineLayer extends PaintLayer {
  const UnderlineLayer({this.color, required this.offset, required this.thickness, this.style = UnderlineStyle.solid, this.opacity = 1});

  /// Null for the words' own colour.
  final Color? color;

  /// Both in pixels.
  final double offset, thickness;
  final UnderlineStyle style;
  final double opacity;

  @override
  void behind(Canvas canvas, List<Rect> boxes, RunLook look) {
    final ink = color ?? look.color;
    final paint = Paint()..color = ink.withValues(alpha: ink.a * opacity);
    // Blink draws a decoration a whole number of pixels thick, never under one (measured: 0.09em of 17.45px is a
    // line of two).
    final thick = math.max(1.0, thickness.roundToDouble());
    for (final box in boxes) {
      final y = snapToDevice(box.top + look.ascent + offset);
      switch (style) {
        case UnderlineStyle.solid:
          canvas.drawRect(Rect.fromLTRB(box.left, y, box.right, y + thick), paint);
        case UnderlineStyle.dotted:
          // Its dotted line: square dots a thickness wide, a thickness apart, from the run's start.
          for (var x = box.left; x < box.right - 0.01; x += thick * 2) {
            canvas.drawRect(Rect.fromLTRB(x, y, math.min(x + thick, box.right), y + thick), paint);
          }
        case UnderlineStyle.dashed:
          // And its dashed one: dashes three thicknesses long, two apart.
          final dash = thick * 3, period = thick * 5;
          for (var x = box.left; x < box.right - 0.01; x += period) {
            canvas.drawRect(Rect.fromLTRB(x, y, math.min(x + dash, box.right), y + thick), paint);
          }
      }
    }
  }
}

// ---- letters -----------------------------------------------------------------------------------------------------

/// A letter laid out as itself, kept while its look lasts: what a [LetterLayer] draws and bends.
class LetterGlyph {
  LetterGlyph._(this.painter);

  final TextPainter painter;
  ui.Image? _image;
  Rect imageRect = Rect.zero;
  double _ratio = 0;

  static final Map<String, LetterGlyph> _kept = <String, LetterGlyph>{};
  static const int _most = 600;

  /// The glyph of `text` in `style`. Kept by what it says and how, the oldest let go past a screenful.
  static LetterGlyph of(String text, TextStyle style) {
    final key = '$text\u0000${style.hashCode}';
    final had = _kept.remove(key);
    if (had != null) return _kept[key] = had;
    if (_kept.length >= _most) {
      final oldest = _kept.keys.first;
      _kept.remove(oldest)!._dispose();
    }
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    return _kept[key] = LetterGlyph._(painter);
  }

  /// Lets every kept glyph go: a face arrived, or a test ended.
  static void clear() {
    for (final glyph in _kept.values) {
      glyph._dispose();
    }
    _kept.clear();
  }

  void _dispose() {
    _image?.dispose();
    painter.dispose();
  }

  double get baseline => painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);

  /// The letter as a picture, with room round its box for ink that overhangs it, for a shader to read.
  ui.Image image() {
    final ratio = _device();
    if (_image != null && _ratio == ratio) return _image!;
    _image?.dispose();
    final pad = (painter.preferredLineHeight * 0.3).ceilToDouble();
    final rect = Rect.fromLTWH(-pad, -pad, painter.width + 2 * pad, painter.height + 2 * pad);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    painter.paint(canvas, Offset(pad, pad));
    final picture = recorder.endRecording();
    final w = math.max(1, (rect.width * ratio).ceil()), h = math.max(1, (rect.height * ratio).ceil());
    _image = picture.toImageSync(w, h);
    picture.dispose();
    _ratio = ratio;
    imageRect = Rect.fromLTWH(rect.left, rect.top, w / ratio, h / ratio);
    return _image!;
  }
}

/// Draws the run's letter itself, in place of the paragraph's. `text` is the run's own text, which a painter is
/// not told: the decoration says it (`data-text`). A subclass says where and how.
abstract class LetterLayer extends PaintLayer {
  const LetterLayer(this.text);

  final String text;

  @override
  bool get replacesWords => true;

  /// The style the letter is set in: the run's, unless the layer changes it.
  TextStyle styleOf(RunLook look) => look.style;

  /// Draws the glyph with its box's corner at the origin of `canvas`. `at` is where that corner is on the canvas,
  /// for a field that must not move with the letter.
  void drawLetter(Canvas canvas, LetterGlyph glyph, Offset at, Size box, RunLook look);

  @override
  void over(Canvas canvas, List<Rect> boxes, RunLook look) {
    final glyph = LetterGlyph.of(text, styleOf(look));
    final box = boxes.first;
    // The run's box is its content area: the baseline is the face's ascent under its top.
    final at = Offset(box.left, box.top + look.ascent - glyph.baseline);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    drawLetter(canvas, glyph, at, Size(glyph.painter.width, glyph.painter.height), look);
    canvas.restore();
  }
}

// ---- the CSS a look is written in --------------------------------------------------------------------------------

/// A look's declarations (`plugins/types.ts` `FormatLook` 'style', and the `style` attribute a mark carries), read
/// as far as the marks use CSS: `background`, `border-radius`, `box-shadow` (a spread alone), `color`,
/// `-webkit-text-fill-color`, `font-size`, `font-style`, `font-weight`, `font-variant-caps`, `letter-spacing`,
/// `text-decoration` with its colour, offset and thickness, and `filter: var(--app-ink-flat)`.
class StyleCss {
  StyleCss._(this.declarations);

  /// The declarations in order, a later one of the same property written over an earlier (a tint's after a look's).
  final Map<String, String> declarations;

  static final Map<String, StyleCss> _parsed = <String, StyleCss>{};

  factory StyleCss.parse(String css) => _parsed.putIfAbsent(css, () {
    final found = <String, String>{};
    for (final part in css.split(';')) {
      final colon = part.indexOf(':');
      if (colon < 0) continue;
      final name = part.substring(0, colon).trim().toLowerCase(), value = part.substring(colon + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      found.remove(name);
      found[name] = value;
    }
    return StyleCss._(found);
  });

  String? operator [](String property) => declarations[property];

  static final RegExp _em = RegExp(r'^(-?[\d.]+)em$');
  static final RegExp _px = RegExp(r'^(-?[\d.]+)px$');
  static final RegExp _spread = RegExp(r'^0\s+0\s+0\s+(-?[\d.]+)em\s+(.+)$');

  /// A length in pixels: `0.2em` of `em`, or `3px`.
  static double? length(String? value, double em) {
    if (value == null) return null;
    final ems = _em.firstMatch(value);
    if (ems != null) return double.parse(ems.group(1)!) * em;
    final px = _px.firstMatch(value);
    if (px != null) return double.parse(px.group(1)!);
    return value == '0' ? 0 : null;
  }

  /// `font-size: 0.88em` as its share of the parent's size.
  double? get fontSizeEm {
    final found = _em.firstMatch(declarations['font-size'] ?? '');
    return found == null ? null : double.parse(found.group(1)!);
  }

  double? get letterSpacingEm {
    final found = _em.firstMatch(declarations['letter-spacing'] ?? '');
    return found == null ? null : double.parse(found.group(1)!);
  }

  bool get italic => declarations['font-style'] == 'italic';
  bool get smallCaps => declarations['font-variant-caps'] == 'all-small-caps';

  /// `filter: var(--app-ink-flat)`: everything in the box printed flat in the ink.
  bool get flat => (declarations['filter'] ?? '').contains('--app-ink-flat');

  /// `box-shadow: 0 0 0 <n>em <color>`: the spread in ems and the colour as written.
  ({double em, String color})? get shadow {
    final found = _spread.firstMatch(declarations['box-shadow'] ?? '');
    return found == null ? null : (em: double.parse(found.group(1)!), color: found.group(2)!);
  }

  /// `text-decoration: underline dotted 0.11em`, with the longhands after it.
  ({UnderlineStyle style, String? thickness})? get underline {
    final said = declarations['text-decoration'];
    if (said == null || !said.contains('underline')) return null;
    final words = said.split(RegExp(r'\s+'));
    final style = words.contains('dotted') ? UnderlineStyle.dotted : (words.contains('dashed') ? UnderlineStyle.dashed : UnderlineStyle.solid);
    final thick = words.where((word) => _em.hasMatch(word) || _px.hasMatch(word)).firstOrNull;
    return (style: style, thickness: declarations['text-decoration-thickness'] ?? thick);
  }
}

/// `color-mix(in srgb, currentColor <n>%, transparent)`: the words' own ink, that much of it.
Color inkShare(Color ink, double share) => ink.withValues(alpha: ink.a * share);
