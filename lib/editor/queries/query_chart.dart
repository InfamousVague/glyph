/// A query drawn as a chart (`show: chart`, lib/core/query/chart.dart; Matt, 2026-10-30, "add all 12"): bars, a line or
/// a pie of its records counted or added up by one field, drawn here in the app's own type and colours, beside the
/// ```mermaid charts, which stay Mermaid's.
///
/// - **Colours** are the activity work's (docs/ACTIVITY.md, the `--activity-*` tokens): each series one, in their
///   order, tuned for light and dark by the tokens themselves. Calm turns those to ink, so a series is then the ink
///   at a lighter strength each, and the chart stays readable without a hue.
/// - **A bar is a button.** A tap picks it, and its records are listed under the chart as a board's lane lists its
///   cards, each opening as a row of a list does; a second tap on it lets it go, and a bar of one record opens it.
///   Over it, a pointer shows what it measures.
/// - **Room.** A bar is never narrower than a finger: more of them than the card is wide scroll sideways. The values
///   are ticked up the side at round numbers, four of them, and each bar says its own on top where it has room.
///
/// Everything is drawn by one painter over the plan [ChartGeometry] works out, so a chart of a thousand records is
/// as cheap a frame as one of ten: the buckets are what is drawn, never the records.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, Tokens, fireMotor;

import '../../activity/job_mark.dart' show activityCalm;
import '../../core/query/query.dart';
import 'query_layout.dart';
import 'query_look.dart';
import 'query_parts.dart';
import 'query_view.dart' show QueryRowLine;

/// The activity tokens a chart's series wear, in order.
const List<String> chartTokens = <String>['activity-sync', 'activity-ai', 'activity-meetings', 'activity-audio', 'activity-images', 'activity-downloads', 'activity-images-2'];

/// The colours a chart's series wear on this page: the activity work's, or in Calm the ink at a strength each.
List<Color> chartColours(Tokens t) {
  if (activityCalm(t)) {
    final ink = t.color('app-ink');
    return <Color>[for (final part in const <double>[0.92, 0.62, 0.42, 0.28, 0.18, 0.12]) QueryLook.mix(ink, part)];
  }
  return <Color>[for (final token in chartTokens) t.color(token)];
}

/// A round number at or above [most], and the step between four ticks up to it.
({double top, double step}) niceScale(double most, {bool percent = false}) {
  if (percent) return (top: 100, step: 25);
  if (most <= 0) return (top: 4, step: 1);
  final raw = most / 4;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  var step = magnitude;
  for (final times in const <double>[1, 2, 2.5, 5, 10]) {
    step = times * magnitude;
    if (step >= raw - 1e-9) break;
  }
  return (top: step * (most / step).ceil(), step: step);
}

/// Where everything of a chart is in a box [size]: each bar's whole and its pieces, each point, each slice.
class ChartGeometry {
  ChartGeometry(this.data, this.size, {required this.axis, required this.foot, required this.head});

  final ChartData data;
  final Size size;

  /// The room at the left for the values, under the bars for their names, and over them for their values.
  final double axis;
  final double foot;
  final double head;

  late final ({double top, double step}) scale = niceScale(data.most, percent: data.measure.fn == Aggregate.percent);

  /// The box the bars stand in.
  Rect get plot => Rect.fromLTRB(axis, head, size.width, size.height - foot);

  double get slot => data.buckets.isEmpty ? 0 : plot.width / data.buckets.length;

  /// How high [value] stands.
  double yOf(double value) => plot.bottom - (scale.top == 0 ? 0 : (value / scale.top).clamp(0, 1.2) * plot.height);

  /// Bar [bar]'s whole, as drawn.
  Rect barRect(int bar) {
    final width = math.min(slot * 0.62, 56.0);
    final x = plot.left + slot * bar + (slot - width) / 2;
    return Rect.fromLTRB(x, yOf(data.whole(bar)), x + width, plot.bottom);
  }

  /// Bar [bar]'s piece for [series], stacked from the foot up in the series' order.
  Rect pieceRect(int bar, int series) {
    final whole = barRect(bar);
    var below = 0.0;
    for (var s = 0; s < series; s += 1) {
      below += data.points[bar][s].value ?? 0;
    }
    final mine = data.points[bar][series].value ?? 0;
    return Rect.fromLTRB(whole.left, yOf(below + mine), whole.right, yOf(below));
  }

  /// The point of [series] over bar [bar], on a line.
  Offset point(int bar, int series) => Offset(plot.left + slot * (bar + 0.5), yOf(data.points[bar][series].value ?? 0));

  /// A pie's middle and its radius.
  Offset get middle => Offset(size.height / 2, size.height / 2);
  double get radius => math.max(0, size.height / 2 - 6);

  /// Each slice's start and sweep, from twelve o'clock round.
  List<({double start, double sweep})> get slices {
    final all = <double>[for (var bar = 0; bar < data.buckets.length; bar += 1) math.max(0, data.whole(bar))];
    final sum = all.fold<double>(0, (a, b) => a + b);
    var at = -math.pi / 2;
    return <({double start, double sweep})>[
      for (final each in all)
        () {
          final sweep = sum == 0 ? 0.0 : 2 * math.pi * each / sum;
          final slice = (start: at, sweep: sweep);
          at += sweep;
          return slice;
        }(),
    ];
  }

  /// What is under [at]: a bar, and its series where one piece of it is.
  ({int bar, int? series})? hit(Offset at) {
    if (data.buckets.isEmpty) return null;
    if (data.kind == ChartKind.pie) {
      final from = at - middle;
      if (from.distance > radius || from.distance < radius * 0.55) return null;
      var angle = math.atan2(from.dy, from.dx);
      if (angle < -math.pi / 2) angle += 2 * math.pi;
      for (final (bar, slice) in slices.indexed) {
        if (angle >= slice.start && angle < slice.start + slice.sweep) return (bar: bar, series: null);
      }
      return null;
    }
    if (at.dx < plot.left || at.dx > plot.right || at.dy > size.height) return null;
    final bar = ((at.dx - plot.left) / slot).floor().clamp(0, data.buckets.length - 1);
    if (data.series.length == 1) return (bar: bar, series: null);
    if (data.kind == ChartKind.line) {
      var best = 0;
      var near = double.infinity;
      for (var s = 0; s < data.series.length; s += 1) {
        final off = (point(bar, s).dy - at.dy).abs();
        if (off < near) {
          near = off;
          best = s;
        }
      }
      return (bar: bar, series: best);
    }
    for (var s = 0; s < data.series.length; s += 1) {
      if (pieceRect(bar, s).inflate(1).contains(Offset(barRect(bar).center.dx, at.dy))) return (bar: bar, series: s);
    }
    return (bar: bar, series: null);
  }
}

/// What a bar, or one series of it, says: `In progress · Sam: 3`.
String chartSaid(ChartData data, int bar, int? series) {
  final label = data.buckets[bar].label;
  // A line's points are not parts of a whole: each series says its own (a burndown's remaining and its ideal).
  if (series == null && data.kind == ChartKind.line && data.series.length > 1) {
    return '$label · ${[for (final (s, each) in data.series.indexed) if (data.points[bar][s].value != null) '${each.label}: ${data.points[bar][s].text}'].join(', ')}';
  }
  if (series == null || data.series.length == 1) {
    final text = data.series.length == 1 ? data.points[bar].single.text : plainNumber(data.whole(bar));
    return '$label: $text';
  }
  return '$label · ${data.series[series].label}: ${data.points[bar][series].text}';
}

class QueryChart extends StatefulWidget {
  const QueryChart({super.key, required this.look, required this.result, required this.acts});

  final QueryLook look;
  final QueryResult result;
  final QueryActs acts;

  @override
  State<QueryChart> createState() => QueryChartState();
}

class QueryChartState extends State<QueryChart> {
  /// The bar picked, and its series where one piece of it was; its records are listed under the chart.
  ({int bar, int? series})? picked;

  /// What a pointer is over, and where.
  ({int bar, int? series})? _over;
  Offset? _at;

  ChartData get data => widget.result.chart!;

  @override
  void didUpdateWidget(QueryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.result.chart;
    final now = widget.result.chart;
    // A pick holds while its bar is still there under the same key.
    final pick = picked;
    if (pick != null && (was == null || now == null || pick.bar >= now.buckets.length || pick.bar >= was.buckets.length || was.buckets[pick.bar].key != now.buckets[pick.bar].key)) picked = null;
  }

  /// A tap on a bar: picked, let go, or (a bar of one record picked already) opened.
  void tap(({int bar, int? series})? hit) {
    if (hit == null) return;
    fireMotor(HapticKind.selection);
    final same = picked != null && picked!.bar == hit.bar && picked!.series == hit.series;
    if (same) {
      final keys = data.keysOf(hit.bar, hit.series);
      if (keys.length == 1) {
        final row = _rows().where((row) => row.key == keys.single).firstOrNull;
        if (row != null) widget.acts.onOpen(row);
      }
      setState(() => picked = null);
      return;
    }
    setState(() => picked = hit);
  }

  List<QueryRow> _rows() => <QueryRow>[for (final group in widget.result.groups) ...group.rows];

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final data = this.data;
    if (data.buckets.isEmpty) return Part('empty', child: PageWords('Nothing to chart yet.', look.sans(look.em, color: look.ink3), line: look.line));
    final colours = chartColours(look.t);
    final pie = data.kind == ChartKind.pie;
    final pick = picked;
    final legend = pie || data.series.length > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        final height = wide ? 220.0 : 180.0;
        final small = look.xs;
        final axis = pie ? 0.0 : _axisWidth(look, data);
        final least = wide ? 44.0 : 36.0;
        final room = constraints.maxWidth;
        final pieWidth = pie ? (wide ? height + 24 : room) : 0.0;
        final width = pie ? (wide ? height : math.min(room, height)) : math.max(room, axis + least * data.buckets.length);
        final geometry = ChartGeometry(data, Size(width, height), axis: axis, foot: pie ? 0 : small * 1.4 + 6, head: pie ? 0 : small * 1.4 + 2);
        final painter = _ChartPainter(geometry: geometry, look: look, colours: colours, picked: pick, said: (bar, series) => chartSaid(data, bar, series), onTap: tap);
        Widget chart = MouseRegion(
          onHover: (event) => setState(() {
            _over = geometry.hit(event.localPosition);
            _at = event.localPosition;
          }),
          onExit: (_) => setState(() => _over = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.trackpad, PointerDeviceKind.unknown},
            onTapUp: (details) => tap(geometry.hit(details.localPosition)),
            child: RepaintBoundary(child: CustomPaint(key: const ValueKey<String>('query-chart'), size: geometry.size, painter: painter)),
          ),
        );
        final over = _over;
        final at = _at;
        if (over != null && at != null) {
          chart = Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              chart,
              Positioned(
                left: math.min(math.max(0, at.dx + 12), math.max(0, width - 160)),
                top: math.max(0, at.dy - 34),
                child: IgnorePointer(child: _Tip(look: look, text: chartSaid(data, over.bar, over.series))),
              ),
            ],
          );
        }
        if (!pie && width > room) chart = SingleChildScrollView(scrollDirection: Axis.horizontal, child: chart);
        final children = <Widget>[
          if (legend && !pie) _legend(look, data.series.map((each) => each.label.isEmpty ? '–' : each.label).toList(), colours),
          if (pie)
            wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[SizedBox(width: pieWidth, child: chart), Expanded(child: _pieLegend(look, data, colours))])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[Center(child: chart), SizedBox(height: look.space(2)), _pieLegend(look, data, colours)])
          else
            chart,
          if (pick != null) _pickedRows(look, data, pick),
        ];
        return Part(
          'chart',
          child: Semantics(
            container: true,
            label: '${switch (data.kind) {
              ChartKind.bar => 'Bar chart',
              ChartKind.line => 'Line chart',
              ChartKind.pie => 'Pie chart',
            }}: ${data.yLabel.toLowerCase()} by ${data.xLabel.toLowerCase()}',
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        );
      },
    );
  }

  double _axisWidth(QueryLook look, ChartData data) {
    final scale = niceScale(data.most, percent: data.measure.fn == Aggregate.percent);
    var widest = 0.0;
    for (var value = 0.0; value <= scale.top + 1e-9; value += scale.step) {
      final painter = TextPainter(text: TextSpan(text: _tickWords(value, data), style: look.sans(look.xs, tabular: true)), textDirection: TextDirection.ltr)..layout();
      widest = math.max(widest, painter.width);
    }
    return widest + 8;
  }

  Widget _legend(QueryLook look, List<String> labels, List<Color> colours) => Padding(
    padding: EdgeInsets.only(bottom: look.space(2)),
    child: Part(
      'legend',
      child: Wrap(
        spacing: look.space(3),
        runSpacing: look.space(1),
        children: <Widget>[
          for (final (index, label) in labels.indexed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colours[index % colours.length], borderRadius: BorderRadius.circular(3))),
                SizedBox(width: look.space(1)),
                PageWords(label, look.sans(look.xs, color: look.ink2), line: look.lineXs, softWrap: false),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _pieLegend(QueryLook look, ChartData data, List<Color> colours) {
    final sum = <double>[for (var bar = 0; bar < data.buckets.length; bar += 1) data.whole(bar)].fold<double>(0, (a, b) => a + b);
    return Part(
      'legend',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (bar, bucket) in data.buckets.indexed)
            Semantics(
              container: true,
              button: true,
              selected: picked?.bar == bar,
              label: chartSaid(data, bar, null),
              onTap: () => tap((bar: bar, series: null)),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tap((bar: bar, series: null)),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: look.space(1)),
                  child: Row(
                    children: <Widget>[
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: colours[bar % colours.length], borderRadius: BorderRadius.circular(3))),
                      SizedBox(width: look.space(2)),
                      Expanded(child: PageWords(bucket.label, look.sans(look.em, weight: picked?.bar == bar ? 'semibold' : 'regular'), line: look.line, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: look.space(2)),
                      PageWords(
                        '${plainNumber(data.whole(bar))}${sum > 0 ? ' · ${(100 * data.whole(bar) / sum).round()}%' : ''}',
                        look.sans(look.xs, color: look.ink3, tabular: true),
                        line: look.lineXs,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pickedRows(QueryLook look, ChartData data, ({int bar, int? series}) pick) {
    final keys = data.keysOf(pick.bar, pick.series).toSet();
    final rows = <QueryRow>[for (final row in _rows()) if (keys.contains(row.key)) row];
    return Padding(
      padding: EdgeInsets.only(top: look.space(2)),
      child: Part(
        'chartRows',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(child: PageWords(chartSaid(data, pick.bar, pick.series), look.sans(look.em, weight: 'semibold', color: look.ink2), line: look.line)),
                Semantics(
                  button: true,
                  label: 'Show every bar',
                  onTap: () => setState(() => picked = null),
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => picked = null),
                    child: Padding(padding: EdgeInsets.all(look.space(1)), child: PageWords('Clear', look.sans(look.xs, weight: 'semibold', color: look.ink3), line: look.lineXs, softWrap: false)),
                  ),
                ),
              ],
            ),
            for (final (index, row) in rows.indexed) QueryRowLine(look: look, row: row, acts: widget.acts, result: widget.result, first: index == 0),
          ],
        ),
      ),
    );
  }
}

/// A tick's value as the side says it: a percent with its sign.
String _tickWords(double value, ChartData data) => data.measure.fn == Aggregate.percent ? '${value.round()}%' : plainNumber(value);

class _Tip extends StatelessWidget {
  const _Tip({required this.look, required this.text});

  final QueryLook look;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: look.space(2), vertical: look.space(1)),
    decoration: BoxDecoration(color: look.ink, borderRadius: BorderRadius.circular(look.t.radius('sm'))),
    child: Text(text, softWrap: false, textScaler: TextScaler.noScaling, style: look.sans(look.xs, color: look.paper, tabular: true)),
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.geometry, required this.look, required this.colours, required this.picked, required this.said, required this.onTap});

  final ChartGeometry geometry;
  final QueryLook look;
  final List<Color> colours;
  final ({int bar, int? series})? picked;
  final String Function(int bar, int? series) said;
  final void Function(({int bar, int? series}) hit) onTap;

  ChartData get data => geometry.data;

  Color _colour(int index) => colours[index % colours.length];

  /// Whether a bar, or a piece of it, is drawn quiet: something else is picked.
  bool _quiet(int bar, [int? series]) {
    final pick = picked;
    if (pick == null) return false;
    if (pick.bar != bar) return true;
    return pick.series != null && series != null && pick.series != series;
  }

  void _words(Canvas canvas, String text, Offset at, {required double width, Color? color, bool centre = true, bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: look.sans(look.xs, color: color ?? look.ink3, tabular: true, weight: bold ? 'semibold' : 'regular')),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, width));
    painter.paint(canvas, Offset(centre ? at.dx - painter.width / 2 : at.dx - painter.width, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.kind == ChartKind.pie) {
      _pie(canvas);
      return;
    }
    final plot = geometry.plot;
    final scale = geometry.scale;
    final rule = Paint()
      ..color = look.rule
      ..strokeWidth = look.hair;
    // The values up the side, and a rule across at each.
    for (var value = 0.0; value <= scale.top + 1e-9; value += scale.step) {
      final y = geometry.yOf(value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), rule);
      _words(canvas, _tickWords(value, data), Offset(plot.left - 6, y - look.xs * 0.7), width: geometry.axis - 6, centre: false);
    }
    final slot = geometry.slot;
    for (var bar = 0; bar < data.buckets.length; bar += 1) {
      final centre = plot.left + slot * (bar + 0.5);
      _words(canvas, data.buckets[bar].label, Offset(centre, plot.bottom + 4), width: slot - 4, color: picked?.bar == bar ? look.ink : look.ink3, bold: picked?.bar == bar);
    }
    if (data.kind == ChartKind.bar) {
      for (var bar = 0; bar < data.buckets.length; bar += 1) {
        for (var s = 0; s < data.series.length; s += 1) {
          final piece = geometry.pieceRect(bar, s);
          if (piece.height <= 0) continue;
          final top = s == data.series.length - 1 || (data.points[bar].skip(s + 1).every((point) => (point.value ?? 0) == 0));
          final radius = Radius.circular(math.min(4, piece.width / 4));
          final shape = top ? RRect.fromRectAndCorners(piece, topLeft: radius, topRight: radius) : RRect.fromRectAndRadius(piece, Radius.zero);
          canvas.drawRRect(shape, Paint()..color = _quiet(bar, s) ? QueryLook.mix(_colour(s), 0.32) : _colour(s));
        }
        final whole = geometry.barRect(bar);
        if (slot >= 26) {
          final text = data.series.length == 1 ? data.points[bar].single.text : plainNumber(data.whole(bar));
          _words(canvas, text, Offset(whole.center.dx, whole.top - look.xs * 1.4), width: slot, color: _quiet(bar) ? look.ink4 : look.ink2, bold: picked?.bar == bar);
        }
      }
      return;
    }
    // A line: one for each series, a dot at each bar's place. A point with nothing to measure is left out, and the
    // line breaks there: a burndown's days still to come (lib/core/query/planning.dart).
    for (var s = 0; s < data.series.length; s += 1) {
      final path = Path();
      var drawing = false;
      for (var bar = 0; bar < data.buckets.length; bar += 1) {
        if (data.points[bar][s].value == null) {
          drawing = false;
          continue;
        }
        final at = geometry.point(bar, s);
        drawing ? path.lineTo(at.dx, at.dy) : path.moveTo(at.dx, at.dy);
        drawing = true;
      }
      final colour = picked != null && picked!.series != null && picked!.series != s ? QueryLook.mix(_colour(s), 0.32) : _colour(s);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = colour,
      );
      for (var bar = 0; bar < data.buckets.length; bar += 1) {
        if (data.points[bar][s].value == null) continue;
        final at = geometry.point(bar, s);
        final big = picked?.bar == bar && (picked?.series == null || picked?.series == s);
        canvas.drawCircle(at, big ? 5 : 3, Paint()..color = colour);
        if (big) canvas.drawCircle(at, 2, Paint()..color = look.paper2);
        if (data.series.length == 1 && slot >= 26) _words(canvas, data.points[bar][s].text, Offset(at.dx, at.dy - look.xs * 1.6), width: slot, color: look.ink2);
      }
    }
  }

  void _pie(Canvas canvas) {
    final middle = geometry.middle;
    final radius = geometry.radius;
    final rect = Rect.fromCircle(center: middle, radius: radius);
    for (final (bar, slice) in geometry.slices.indexed) {
      if (slice.sweep <= 0) continue;
      canvas.drawArc(rect, slice.start, slice.sweep, true, Paint()..color = _quiet(bar) ? QueryLook.mix(_colour(bar), 0.32) : _colour(bar));
      // A hairline of the card's own ground between two slices.
      canvas.drawArc(
        rect,
        slice.start,
        slice.sweep,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = look.paper2,
      );
    }
    canvas.drawCircle(middle, radius * 0.56, Paint()..color = look.paper2);
    final pick = picked;
    final text = pick == null ? plainNumber(<double>[for (var bar = 0; bar < data.buckets.length; bar += 1) data.whole(bar)].fold<double>(0, (a, b) => a + b)) : plainNumber(data.whole(pick.bar));
    final painter = TextPainter(text: TextSpan(text: text, style: look.sans(look.t.fontSize('lg'), weight: 'semibold', tabular: true)), textDirection: TextDirection.ltr)..layout();
    painter.paint(canvas, middle - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final nodes = <CustomPainterSemantics>[];
    for (var bar = 0; bar < data.buckets.length; bar += 1) {
      final Rect rect;
      if (data.kind == ChartKind.pie) {
        rect = Rect.fromCircle(center: geometry.middle, radius: geometry.radius);
      } else if (data.kind == ChartKind.line) {
        rect = Rect.fromCenter(center: geometry.point(bar, 0), width: math.max(8, geometry.slot), height: 24);
      } else {
        rect = geometry.barRect(bar).inflate(2);
      }
      nodes.add(
        CustomPainterSemantics(
          rect: rect,
          properties: SemanticsProperties(label: said(bar, null), button: true, selected: picked?.bar == bar, onTap: () => onTap((bar: bar, series: null)), textDirection: TextDirection.ltr),
        ),
      );
    }
    return nodes;
  };

  @override
  bool shouldRepaint(_ChartPainter old) => old.geometry.data != geometry.data || old.geometry.size != geometry.size || old.picked != picked || old.colours.toString() != colours.toString() || old.look.ink != look.ink;

  @override
  bool shouldRebuildSemantics(_ChartPainter old) => shouldRepaint(old);
}
