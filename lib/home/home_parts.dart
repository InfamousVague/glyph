/// The small pieces of layout and motion the home page's cards, rows and lines share, each standing for something
/// the web page wrote in CSS and Flutter has no word for:
///
/// - [Arrive]: `@keyframes arrive` (HomeLayouts.module.css `.rowItem`, NoteCard.module.css `.item`), an entrance from
///   a few pixels below, each item a beat after the one before.
/// - [BottomBaseline]: a flex item with no text in it, whose baseline is its bottom edge (an icon beside a title in
///   `align-items: baseline`).
/// - [ShrinkRow]: a row whose children give way as `flex-shrink` has them, the least precious first (a pinned line's
///   name, notebook and workspace pill), with `margin-inline-start: auto` for the one that keeps to the end.
/// - [CssLines]: lines of text at the height a stylesheet gave them, to the fraction of a pixel. Flutter rounds every
///   line of text to a whole pixel (a line 1.6 of 10.88px is 17, where the page's is 17.408), so a block of six lines
///   stands 2.4px short; this gives the block the height the page gives it.
library;

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../sheet/css.dart' show pageBaseline;

/// `animation: arrive <duration> var(--glacier-ease-out) both; animation-delay: <delay>` from
/// `{ opacity: 0; transform: translateY(<rise>px) }`. Under reduced motion it does not move, as the page's
/// `@media (prefers-reduced-motion: reduce) { animation: none }` has it.
///
/// Ports `@keyframes arrive` of NoteCard.module.css and HomeLayouts.module.css; nothing differs.
class Arrive extends StatefulWidget {
  const Arrive({super.key, required this.duration, this.delay = Duration.zero, this.since = Duration.zero, required this.rise, required this.child});

  final Duration duration;
  final Duration delay;

  /// How long ago the thing came to be on its page ([Arrivals]), where that was before this widget was made: a
  /// list that builds only what is near the screen makes a row again each time it is scrolled to, and a row that
  /// has been on the page all along has long since arrived. The entrance is taken up where it would be by now, and
  /// is over for anything older than its delay and its duration. Nothing ago, for something made as it arrives.
  final Duration since;
  final double rise;
  final Widget child;

  @override
  State<Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<Arrive> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  Timer? _wait;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final wait = widget.delay - widget.since;
    if (context.tokens.reducedMotion) {
      _controller.value = 1;
    } else if (wait > Duration.zero) {
      _wait = Timer(wait, () {
        if (mounted) _controller.forward();
      });
    } else if (wait == Duration.zero) {
      _controller.forward();
    } else if (-wait >= widget.duration) {
      // Arrived before it was drawn.
      _controller.value = 1;
    } else {
      _controller.forward(from: -wait.inMicroseconds / widget.duration.inMicroseconds);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = context.tokens.curve('glacier-ease-out');
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = curve.transform(_controller.value);
        // The same wrappers at every moment, so the child keeps its state from its first frame to its last.
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, widget.rise * (1 - t)), child: child),
        );
      },
    );
  }
}

/// When each thing on a page came to be there, for its entrance ([Arrive]).
///
/// On the web every row of a page is in the document from the page's first render, and its entrance plays once,
/// seen or not. A page here builds only the rows near the screen, so a row scrolled to is made then, and would
/// arrive then, every time. So the page keeps this: it [keep]s the names of everything it lists each time what it
/// lists changes, and a row asks how long [since] its name was first kept. A name that leaves the page and comes
/// back arrives again, as an element made again does.
///
/// Counted on the frames' own clock, which is the clock an entrance runs on.
class Arrivals {
  final Map<Object, Duration> _born = <Object, Duration>{};
  Duration _last = Duration.zero;

  /// The frame being drawn now, or the last one drawn where none is.
  Duration get _now {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.idle) _last = scheduler.currentFrameTimeStamp;
    return _last;
  }

  /// The page lists exactly [names] now: the new ones arrive from this frame, and the ones gone are forgotten.
  void keep(Iterable<Object> names) {
    final now = _now;
    final next = <Object, Duration>{for (final name in names) name: _born[name] ?? now};
    _born
      ..clear()
      ..addAll(next);
  }

  /// How long ago [name] came to be on the page; nothing ago for one the page was never told of.
  Duration since(Object name) {
    final born = _born[name];
    if (born == null) return Duration.zero;
    final since = _now - born;
    return since > Duration.zero ? since : Duration.zero;
  }
}

/// A child whose baseline is its own bottom edge, as a replaced element's is in a line or a baseline-aligned row.
class BottomBaseline extends SingleChildRenderObjectWidget {
  const BottomBaseline({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBottomBaseline();
}

class _RenderBottomBaseline extends RenderProxyBox {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => size.height;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => getDryLayout(constraints).height;
}

/// One child of a [ShrinkRow]: how readily it gives way ([shrink], CSS `flex-shrink`; 0 never does), the least it
/// may be ([minWidth], CSS `min-inline-size`), and whether it keeps to the row's end ([toEnd],
/// `margin-inline-start: auto`).
class Shrink extends ParentDataWidget<_ShrinkData> {
  const Shrink({super.key, this.shrink = 0, this.minWidth = 0, this.toEnd = false, required super.child});

  final double shrink;
  final double minWidth;
  final bool toEnd;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _ShrinkData;
    if (data.shrink == shrink && data.minWidth == minWidth && data.toEnd == toEnd) return;
    data
      ..shrink = shrink
      ..minWidth = minWidth
      ..toEnd = toEnd;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => ShrinkRow;
}

class _ShrinkData extends ContainerBoxParentData<RenderBox> {
  double shrink = 0;
  double minWidth = 0;
  bool toEnd = false;
}

/// `display: flex; align-items: center; gap: <gap>` over children that never grow and shrink by their own
/// `flex-shrink` (weighted by their width, as CSS weighs it), down to their `minWidth`. A child marked `toEnd` is
/// pushed to the far edge with whatever room is left. The row is as wide as it is allowed and at least [minHeight]
/// tall.
class ShrinkRow extends MultiChildRenderObjectWidget {
  const ShrinkRow({super.key, this.gap = 0, this.minHeight = 0, super.children});

  final double gap;
  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShrinkRow(gap: gap, minHeight: minHeight);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderShrinkRow)
      ..gap = gap
      ..minHeight = minHeight;
  }
}

class _RenderShrinkRow extends RenderBox with ContainerRenderObjectMixin<RenderBox, _ShrinkData>, RenderBoxContainerDefaultsMixin<RenderBox, _ShrinkData> {
  _RenderShrinkRow({required double gap, required double minHeight})
      : _gap = gap,
        _minHeight = minHeight;

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _minHeight;
  double get minHeight => _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ShrinkData) child.parentData = _ShrinkData();
  }

  List<RenderBox> get _children {
    final list = <RenderBox>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      list.add(child);
    }
    return list;
  }

  /// Each child's width in a row [available] wide: its own, or less by its share of what does not fit.
  List<double> _widths(List<RenderBox> children, double available) {
    final base = [for (final child in children) child.getMaxIntrinsicWidth(double.infinity)];
    final widths = [...base];
    final gaps = children.isEmpty ? 0.0 : gap * (children.length - 1);
    final frozen = List.filled(children.length, false);
    // CSS resolves flexible lengths in rounds: what a child cannot give (it is at its minimum) is asked of the rest.
    for (var round = 0; round < children.length + 1; round += 1) {
      final over = widths.fold<double>(gaps, (sum, w) => sum + w) - available;
      if (over <= 0.01) break;
      var weight = 0.0;
      for (var i = 0; i < children.length; i += 1) {
        final data = children[i].parentData! as _ShrinkData;
        if (!frozen[i]) weight += data.shrink * base[i];
      }
      if (weight <= 0) break;
      var clamped = false;
      for (var i = 0; i < children.length; i += 1) {
        final data = children[i].parentData! as _ShrinkData;
        if (frozen[i] || data.shrink == 0) continue;
        final next = widths[i] - over * (data.shrink * base[i]) / weight;
        final least = data.minWidth < base[i] ? data.minWidth : base[i];
        if (next <= least) {
          widths[i] = least;
          frozen[i] = true;
          clamped = true;
        } else {
          widths[i] = next;
        }
      }
      if (!clamped) break;
    }
    return widths;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  double _intrinsicHeight(double width) {
    var height = minHeight;
    for (final child in _children) {
      final h = child.getMaxIntrinsicHeight(double.infinity);
      if (h > height) height = h;
    }
    return height;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    final children = _children;
    return children.fold<double>(children.isEmpty ? 0 : gap * (children.length - 1), (sum, child) => sum + child.getMaxIntrinsicWidth(double.infinity));
  }

  @override
  void performLayout() {
    final children = _children;
    final available = constraints.maxWidth;
    final widths = _widths(children, available);
    var height = minHeight;
    for (var i = 0; i < children.length; i += 1) {
      children[i].layout(BoxConstraints(minWidth: 0, maxWidth: widths[i].isFinite ? widths[i] + 0.01 : double.infinity, maxHeight: constraints.maxHeight), parentUsesSize: true);
      if (children[i].size.height > height) height = children[i].size.height;
    }
    final used = children.fold<double>(children.isEmpty ? 0 : gap * (children.length - 1), (sum, child) => sum + child.size.width);
    final spare = available.isFinite && available > used ? available - used : 0.0;
    var x = 0.0;
    for (final child in children) {
      final data = child.parentData! as _ShrinkData;
      if (data.toEnd) x += spare;
      data.offset = Offset(x, (height - child.size.height) / 2);
      x += child.size.width + gap;
    }
    size = constraints.constrain(Size(available.isFinite ? available : used, height));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

/// Text whose lines are each [lineHeight] tall, as CSS `line-height` makes them, where Flutter rounds a line to a
/// whole pixel. The child is one block of text of one size; this is as tall as its lines at their true height, and
/// draws it from its top, so the first line stands exactly where the page's does and each line after drifts by the
/// rounding (under half a pixel a line).
///
/// [above] is where the first line's baseline falls from the top of its line, for a line whose box a stylesheet's
/// rules make taller than its own text (a heading with a count after it); the child is moved to it.
class CssLines extends SingleChildRenderObjectWidget {
  const CssLines({super.key, required this.lineHeight, this.above, required Widget super.child});

  final double lineHeight;
  final double? above;

  /// [above], or on a phone the page's own baseline for a line of one [Text] (lib/sheet/css.dart `pageBaseline`:
  /// whole device pixels, the leading floored), where the engine's is up to three device pixels under it.
  double? _above(BuildContext context) => above ?? pageBaseline(context, child, lineHeight);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCssLines(lineHeight, _above(context));

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderCssLines)
      ..lineHeight = lineHeight
      ..above = _above(context);
  }
}

class _RenderCssLines extends RenderShiftedBox {
  _RenderCssLines(this._lineHeight, this._above) : super(null);

  double _lineHeight;
  set lineHeight(double value) {
    if (value == _lineHeight) return;
    _lineHeight = value;
    markNeedsLayout();
  }

  double? _above;
  set above(double? value) {
    if (value == _above) return;
    _above = value;
    markNeedsLayout();
  }

  /// How many lines a block [height] tall holds, each drawn at the whole pixel Flutter rounds [_lineHeight] to.
  int _lines(double height) {
    final drawn = _lineHeight.roundToDouble();
    if (drawn <= 0) return 1;
    final lines = (height / drawn).round();
    return lines < 1 ? 1 : lines;
  }

  double _tall(double height) => _lines(height) * _lineHeight;

  @override
  double computeMinIntrinsicHeight(double width) => _tall(child?.getMinIntrinsicHeight(width) ?? 0);

  @override
  double computeMaxIntrinsicHeight(double width) => _tall(child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = child?.getDryLayout(constraints.copyWith(minHeight: 0, maxHeight: double.infinity)) ?? Size.zero;
    return constraints.constrain(Size(inner.width, _tall(inner.height)));
  }

  @override
  void performLayout() {
    final inner = child;
    if (inner == null) {
      size = constraints.smallest;
      return;
    }
    inner.layout(constraints.copyWith(minHeight: 0, maxHeight: double.infinity), parentUsesSize: true);
    size = constraints.constrain(Size(inner.size.width, _tall(inner.size.height)));
    var dy = 0.0;
    final above = _above;
    if (above != null) {
      final baseline = inner.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
      if (baseline != null) dy = above - baseline;
    }
    (inner.parentData! as BoxParentData).offset = Offset(0, dy);
  }
}
