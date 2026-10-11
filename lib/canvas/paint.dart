/// What the canvas paints rather than builds: the colour a card, a line or a map's mark wears; the dots under the
/// cards; and the lines. The twin of the colour rules of CanvasView.module.css (`--app-space` from `data-hue` or
/// from a card's own style), its `.canvas` background, and `LineLayer.tsx`.
///
/// What differs from the web:
/// - A preset's hue is the tokens of a `[data-hue]` scope and a hex is put into the colour's expression in place of
///   `var(--app-space)`, since a widget has no inline style for the cascade to read ([spaceColor]).
/// - The dots are painted one by one where the page tiled a `radial-gradient`: the same dot, a pixel of ink fading
///   out by 1.6, every 24 of the canvas's pixels from its own corner, and none below a third of life size.
/// - The lines are painted from lines.dart's SVG path strings, and a line is picked by how near a press is to its
///   curve (`.lineHit`, a stroke 24 wide), asked of the path rather than of an element.
/// - A label's halo (`paint-order: stroke`, 6px of the page's ground) is the same words stroked under themselves.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Canvas;
import 'package:glacier/glacier.dart';

import '../art/svg_path.dart';
import '../sheet/css.dart';
import 'camera.dart';
import 'card_looks.dart';
import 'edits.dart' show grid;
import 'json_canvas.dart';
import 'lines.dart';

final RegExp _space = RegExp(r'var\(--app-space(?:,\s*var\(--app-ink(?:-3)?\))?\)');

/// The tokens a colour wears: the page's hue for a preset, [t] itself otherwise.
Tokens paintTokens(Tokens t, CardPaint? paint) => paint?.hue == null ? t : t.child(attrs: {'hue': paint!.hue!.name});

/// The colours worked out so far for each set of tokens, by what was asked. A colour is a stylesheet's expression
/// read and reckoned (`color-mix(in oklch, …)`, and for a hue a scope of tokens made to read it in), and the canvas
/// asked for the same few at every build of a card, of the picked card's bar, and at every paint of the map and
/// the lines: a card carried or written in asked a dozen times a frame (tool/perf.sh canvas, on a Mac: a sixth of
/// the frame's work). The tokens do not change, so the answer does not.
final Expando<Map<Object, Color>> _colours = Expando<Map<Object, Color>>('the canvas colours');

Color _kept(Tokens t, Object asked, Color Function() make) {
  final kept = _colours[t] ??= <Object, Color>{};
  final had = kept[asked];
  if (had != null) return had;
  // A hex is anyone's to choose, and a canvas of many: no more are kept than a canvas could wear at once.
  if (kept.length >= 2048) kept.clear();
  return kept[asked] = make();
}

/// A colour of the stylesheet's own, as it is written there (`Tokens.colorOf`), read once.
Color inkOf(Tokens t, String expression) => _kept(t, expression, () => t.colorOf(expression));

/// A colour written as the stylesheet writes it, for something wearing [paint]: `color-mix(in oklch,
/// var(--app-space) 55%, transparent)` with the preset's hue or the chosen hex as `--app-space`.
Color spaceColor(Tokens t, String expression, CardPaint? paint) => _kept(t, (expression, paint), () {
      final hex = paint?.hex;
      return paintTokens(t, paint).colorOf(hex == null ? expression : expression.replaceAll(_space, hex));
    });

/// `color-mix(in oklch, var(--app-space, var(--app-ink)) share, var(--over))` as the page's engine works it out,
/// for the mixes with one of the page's greys: a card's ground, a group's name, a card on the map. A grey written
/// as `oklch(L 0 0)` has a hue of 0 there, not a hue that is missing, so the mix's hue runs the short way round
/// from the colour's to 0: moss (150) at 7% over the ground is a hue of 10.5, a warm wash and not a green one.
/// Measured on the page (tool/canvas_reference.mjs: `oklch(0.96385 0.0098 10.5)`); the kit's `color-mix` takes the
/// colour's hue whole.
Color spaceOver(Tokens t, CardPaint? paint, double share, String over) => _kept(t, (paint, share, over), () {
      final Oklch a;
      final hex = paint?.hex;
      if (hex != null) {
        final c = t.colorOf(hex);
        a = Oklch.fromSrgb(c.r, c.g, c.b, c.a);
      } else {
        final scoped = paintTokens(t, paint);
        a = scoped.oklch(scoped.raw('app-space') == null ? 'app-ink' : 'app-space');
      }
      final b = t.oklch(over);
      final turn = ((b.h - a.h + 540) % 360) - 180;
      return Oklch(a.l * share + b.l * (1 - share), a.c * share + b.c * (1 - share), (a.h + turn * (1 - share)) % 360, a.alpha * share + b.alpha * (1 - share)).toColor();
    });

/// `.canvas`'s dots.
class DotsPainter extends CustomPainter {
  DotsPainter({required this.camera, required this.ink}) : super(repaint: camera);

  final CanvasCamera camera;
  final Color ink;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final view = camera.view;
    // `clamp(0%, (scale - 0.3) * 40%, 18%)` of the ink.
    final share = ((view.scale - 0.3) * 0.4).clamp(0.0, 0.18);
    if (share <= 0) return;
    final step = grid * view.scale;
    final startX = view.x - (view.x / step).floorToDouble() * step - step;
    final startY = view.y - (view.y / step).floorToDouble() * step - step;
    final across = ((size.width - startX) / step).ceil() + 1;
    final down = ((size.height - startY) / step).ceil() + 1;
    if (across <= 0 || down <= 0 || across * down > 60000) return;
    final points = Float32List(across * down * 2);
    var n = 0;
    for (var j = 0; j < down; j += 1) {
      for (var i = 0; i < across; i += 1) {
        points[n++] = startX + i * step;
        points[n++] = startY + j * step;
      }
    }
    // A pixel of ink, gone by 1.6: a round dot 2.6 across, its edge softened.
    final paint = Paint()
      ..color = ink.withValues(alpha: ink.a * share)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRawPoints(ui.PointMode.points, points, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(DotsPainter old) => old.camera != camera || old.ink != ink;
}

/// One line as the view holds it: the edge and its path.
typedef DrawnLine = ({CanvasEdge edge, EdgePath path});

/// The paths read from their strings so far. A line's curve and its heads are read back from the strings lines.dart
/// writes (the web's own, character for character), and were read again at every paint of the canvas, of its map
/// and at every press: the same string is the same path, so each is read once. A card carried makes new strings
/// for the lines that end on it at every move, so the paths kept are let go of once they are many.
final Map<String, ui.Path> _paths = <String, ui.Path>{};

/// [d] as a path, read once. The path is shared: whoever is handed it draws it and changes nothing of it.
ui.Path linePath(String d) {
  final had = _paths[d];
  if (had != null) return had;
  if (_paths.length >= 512) _paths.clear();
  return _paths[d] = svgPath(d);
}

/// The lines of a canvas in its edges' order (CanvasView.tsx `lines`).
List<DrawnLine> drawnLines(Canvas canvas) {
  final paths = edgePaths(canvas);
  return [
    for (final edge in canvas.edges)
      if (paths[edge.id] != null) (edge: edge, path: paths[edge.id]!),
  ];
}

/// The line a press at a point of the canvas is on, by id: the topmost within 12 of its curve (`.lineHit`).
String? lineAt(List<DrawnLine> lines, double x, double y) {
  for (final line in lines.reversed) {
    final path = linePath(line.path.d);
    if (!path.getBounds().inflate(12).contains(Offset(x, y))) continue;
    for (final metric in path.computeMetrics()) {
      final steps = math.max(8, (metric.length / 6).ceil());
      for (var i = 0; i <= steps; i += 1) {
        final at = metric.getTangentForOffset(metric.length * i / steps)?.position;
        if (at != null && (at - Offset(x, y)).distance <= 12) return line.edge.id;
      }
    }
  }
  return null;
}

/// `LineLayer.tsx`: each line's curve, its heads and its label, in the canvas's own pixels.
class LinesPainter extends CustomPainter {
  LinesPainter({required this.lines, required this.picked, required this.t});

  final List<DrawnLine> lines;

  /// The picked line, by id: in the page's own ink, a step heavier, its label left off.
  final String? picked;
  final Tokens t;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final ground = t.color('glacier-bg');
    for (final line in lines) {
      final isPicked = picked == line.edge.id;
      // `.edge { color: var(--app-space, var(--app-ink-3)) }`, `.edge[data-picked] { color: var(--app-ink) }`
      final paint = paintOf(line.edge.color);
      final color = isPicked ? t.color('app-ink') : (paint == null ? t.color('app-ink-3') : spaceColor(t, 'var(--app-space)', paint));
      canvas.drawPath(
        linePath(line.path.d),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPicked ? 3 : 2
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      final fill = Paint()..color = color;
      if (line.path.fromHead != null) canvas.drawPath(linePath(line.path.fromHead!), fill);
      if (line.path.toHead != null) canvas.drawPath(linePath(line.path.toHead!), fill);
      if (line.edge.label == null || isPicked || line.path.lines.isEmpty) continue;
      // `.label`: 13px, medium, the muted text, centred on the point, a 6px stroke of the page behind it.
      final label = _labelOf(t, line.path.lines.join('\n'), ground);
      final at = Offset(line.path.mid.x - label.text.width / 2, line.path.mid.y - label.text.height / 2);
      label.halo.paint(canvas, at);
      label.text.paint(canvas, at);
    }
  }

  /// A label's words set twice, once stroked in the page's ground and once in their ink, for the tokens they are
  /// drawn with: kept from one paint to the next. The lines are painted again at every move of a card carried, and
  /// each paint set every label's words twice over, the same words in the same face; where they are drawn is all
  /// that changes.
  static final Expando<Map<String, ({TextPainter halo, TextPainter text})>> _labels = Expando<Map<String, ({TextPainter halo, TextPainter text})>>('the lines’ labels');

  static ({TextPainter halo, TextPainter text}) _labelOf(Tokens t, String words, Color ground) {
    final kept = _labels[t] ??= <String, ({TextPainter halo, TextPainter text})>{};
    final had = kept[words];
    if (had != null) return had;
    // A label being typed is another at every letter: no more are kept than a canvas has lines for.
    if (kept.length >= 256) {
      for (final each in kept.values) {
        each.halo.dispose();
        each.text.dispose();
      }
      kept.clear();
    }
    final style = pageText(t, 13, weight: 'medium', height: labelLine / 13);
    TextPainter make(TextStyle style) => TextPainter(text: TextSpan(text: words, style: style), textAlign: TextAlign.center, textDirection: TextDirection.ltr)..layout();
    return kept[words] = (
      halo: make(
        style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeJoin = StrokeJoin.round
            ..color = ground,
        ),
      ),
      text: make(style.copyWith(color: t.color('glacier-text-muted'))),
    );
  }

  @override
  bool shouldRepaint(LinesPainter old) => !identical(old.lines, lines) || old.picked != picked || !identical(old.t, t);
}
