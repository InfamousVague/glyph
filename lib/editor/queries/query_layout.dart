/// The few things a stylesheet lays out that a query's drawing and a ticket's panel need and Flutter has no widget
/// for: words on lines as tall as the rule says, with the baseline where Blink puts it ([PageWords]); a flex row
/// whose items give way by `flex-shrink` ([CssRow]); a flex row that wraps, its items on their baselines
/// ([CssWrap]); and a box whose baseline is said ([Baselined]). There is no web file behind this one: on the page
/// these are `display: flex`, `flex-wrap: wrap`, `align-items: baseline` and `line-height` in
/// `QueryView.module.css` and `TicketPanel.module.css`.
///
/// [Part] names a drawn piece by the class its element has in those stylesheets, so a test can find "the third
/// `row`" and hold its box against the page's (test/editor/queries/reference_test.dart). It draws nothing.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';


/// A piece of the drawing, named as its stylesheet names it (`row`, `nameWords`, `cm-field`).
class Part extends MetaData {
  const Part(String name, {super.key, required Widget super.child}) : super(metaData: name, behavior: HitTestBehavior.deferToChild);

  String get name => metaData as String;
}

/// The device pixels to a CSS one the page is laid out in: 1 on a desktop, a phone's own on a phone (2.625 on the
/// Fold's cover screen), where a line's leading is a sixty-fourth of a DEVICE pixel and a face's ascent a whole
/// one. One for the whole app, as the screen is; said by whoever makes a look for what is drawn
/// (`QueryLook`, from the tokens' `css.lineDpr`) before anything here is asked.
double pageRatio = 1;

/// A face's ascent and descent at a size, each rounded to a whole pixel, as Blink rounds them before it sets a line.
({double ascent, double descent}) glyphBox(TextStyle style) {
  final key = (style.fontFamily, style.fontSize, style.fontWeight, style.fontVariations?.join(','), pageRatio);
  return _glyphs[key] ??= () {
    // The face alone, with no line height of its own: the ascent and descent are the font's.
    final face = TextStyle(inherit: false, fontFamily: style.fontFamily, fontFamilyFallback: style.fontFamilyFallback, fontSize: style.fontSize, fontWeight: style.fontWeight, fontVariations: style.fontVariations);
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: face),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final line = painter.computeLineMetrics().first;
    final ratio = pageRatio;
    var box = (ascent: line.ascent.roundToDouble(), descent: line.descent.roundToDouble());
    if (ratio != 1) {
      // In the phone's own pixels, and a descent rounded down takes a pixel from the ascent (looks/look.dart
      // `_box`, measured beside a phone's page).
      final exact = line.descent * ratio;
      var up = (line.ascent * ratio).roundToDouble(), down = exact.roundToDouble();
      if (down < exact - 1e-4) {
        down += 1;
        up -= 1;
      }
      box = (ascent: up / ratio, descent: down / ratio);
    }
    painter.dispose();
    return box;
  }();
}

final Map<Object, ({double ascent, double descent})> _glyphs = <Object, ({double ascent, double descent})>{};

/// Where Blink puts the baseline of a line [line] tall set in [style]: the half-leading above the letters, down to
/// the whole pixel below, then the ascent.
double pageBaseline(TextStyle style, double line) {
  final glyph = glyphBox(style);
  return ((line - glyph.ascent - glyph.descent) * pageRatio / 2 + 1e-6).floorToDouble() / pageRatio + glyph.ascent;
}

/// How tall Blink makes a line of `line-height: [multiple]` at [px]: the type's size to the nearest sixty-fourth,
/// times the multiple, down to the sixty-fourth below. 1.4 at 13.3948px is 18.734, where the two multiplied are
/// 18.753; over the rows of a table the difference shows.
/// On a phone both sixty-fourths are of the phone's own pixels ([pageRatio]).
double pageLine(double px, double multiple) => ((multiple + 1e-9) * (px * pageRatio * 64).roundToDouble()).floorToDouble() / 64 / pageRatio;

/// A length of CSS pixels as the page has it: down to the sixty-fourth of one of the pixels it is laid out in.
double pageFloor(double value) => (value * pageRatio * 64 + 1e-6).floorToDouble() / 64 / pageRatio;

/// A border [width] CSS pixels wide as the page draws it: a whole number of the pixels it is laid out in, down,
/// and never under one. `1px` is 1 on a desktop and 0.762 (two device pixels) on a phone at 2.625.
double pageRule([double width = 1]) {
  final device = (width * pageRatio + 1e-6).floorToDouble();
  return (device < 1 ? 1 : device) / pageRatio;
}

/// Words set as the page sets them: each line [line] tall to the fraction (`font-size` times `line-height`), and
/// the first line's baseline where Blink has it ([pageBaseline]), which is what a row that lines its items up on
/// their baselines reads. The text engine makes each line a whole number of pixels tall; the words are set in the
/// middle of the room the page gives them, a fraction of a pixel from where the page draws them.
class PageWords extends SingleChildRenderObjectWidget {
  PageWords(String text, TextStyle style, {super.key, required this.line, int? maxLines, bool softWrap = true, TextOverflow? overflow, TextAlign? align})
    : baseline = pageBaseline(style, line),
      super(
        child: Text(
          text,
          style: style.copyWith(height: line / style.fontSize!, leadingDistribution: TextLeadingDistribution.even),
          maxLines: maxLines,
          softWrap: softWrap,
          overflow: overflow,
          textAlign: align,
          textScaler: TextScaler.noScaling,
        ),
      );

  /// The same for a run of spans (a name with its tags drawn as tags).
  PageWords.rich(InlineSpan span, TextStyle style, {super.key, required this.line, int? maxLines, bool softWrap = true, TextOverflow? overflow})
    : baseline = pageBaseline(style, line),
      super(
        child: Text.rich(
          span,
          style: style.copyWith(height: line / style.fontSize!, leadingDistribution: TextLeadingDistribution.even),
          maxLines: maxLines,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: TextScaler.noScaling,
        ),
      );

  /// How tall a line is, as Blink makes it ([pageLine]).
  final double line;
  final double baseline;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderPageWords(line, baseline);

  @override
  void updateRenderObject(BuildContext context, covariant RenderPageWords renderObject) {
    renderObject
      ..line = line
      ..baseline = baseline;
  }
}

class RenderPageWords extends RenderShiftedBox {
  RenderPageWords(this._line, this._baseline) : super(null);

  double _line;
  set line(double value) {
    if (value == _line) return;
    _line = value;
    markNeedsLayout();
  }

  double _baseline;
  set baseline(double value) {
    if (value == _baseline) return;
    _baseline = value;
    markNeedsLayout();
  }

  /// How many lines the words came to.
  int lines = 1;

  int _count(double drawn) {
    final each = _line.roundToDouble();
    return each <= 0 ? 1 : math.max(1, (drawn / each).round());
  }

  @override
  double computeMinIntrinsicHeight(double width) => _count(super.computeMinIntrinsicHeight(width)) * _line;

  @override
  double computeMaxIntrinsicHeight(double width) => _count(super.computeMaxIntrinsicHeight(width)) * _line;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = child?.getDryLayout(constraints.copyWith(minHeight: 0, maxHeight: double.infinity)) ?? Size.zero;
    return constraints.constrain(Size(inner.width, _count(inner.height) * _line));
  }

  @override
  double? computeDryBaseline(covariant BoxConstraints constraints, TextBaseline baseline) => _baseline;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  void performLayout() {
    final inner = child;
    if (inner == null) {
      size = constraints.smallest;
      return;
    }
    inner.layout(constraints.copyWith(minHeight: 0, maxHeight: double.infinity), parentUsesSize: true);
    lines = _count(inner.size.height);
    size = constraints.constrain(Size(inner.size.width, lines * _line));
    (inner.parentData! as BoxParentData).offset = Offset(0, (lines * _line - inner.size.height) / 2);
  }
}

/// A box that says where its baseline is: a pill whose baseline is the foot of its mark, as a flex container's is
/// its first item's.
class Baselined extends SingleChildRenderObjectWidget {
  const Baselined({super.key, required this.baseline, required Widget super.child});

  final double baseline;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBaselined(baseline);

  @override
  void updateRenderObject(BuildContext context, covariant RenderBaselined renderObject) => renderObject.baseline = baseline;
}

class RenderBaselined extends RenderProxyBox {
  RenderBaselined(this._baseline);

  double _baseline;
  set baseline(double value) {
    if (value == _baseline) return;
    _baseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDryBaseline(covariant BoxConstraints constraints, TextBaseline baseline) => _baseline;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;
}

/// How a flex container sets its items across the line: `align-items`.
enum CssAlign { start, center, baseline, stretch }

class CssFlexData extends ContainerBoxParentData<RenderBox> {
  /// `flex-shrink`: 0 keeps the item as wide as it wants.
  double shrink = 1;

  /// The least it gives way to (`min-width`, or what `min-width: auto` comes to); null for its own width.
  double? least;

  /// `flex: 1`: takes what is left.
  bool grows = false;

  /// `margin-inline-start: auto`: what is left over goes before it.
  bool pushed = false;

  /// `margin-inline-start`, a length.
  double before = 0;

  /// `flex-basis: 100%`: a line to itself.
  bool whole = false;

  /// `align-self`, where it is not the container's.
  CssAlign? align;

  /// A margin above it, inside its line.
  double above = 0;

  /// Its padding and border across, which give way to nothing: an item is squeezed in proportion to what is inside
  /// them.
  double inset = 0;
}

/// What a flex item says of itself to [CssRow] or [CssWrap].
class CssItem extends ParentDataWidget<CssFlexData> {
  const CssItem({super.key, this.shrink = 1, this.least, this.grows = false, this.pushed = false, this.before = 0, this.whole = false, this.align, this.above = 0, this.inset = 0, required super.child});

  final double shrink;
  final double? least;
  final bool grows;
  final bool pushed;
  final double before;
  final bool whole;
  final CssAlign? align;
  final double above;
  final double inset;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as CssFlexData;
    if (data.shrink == shrink && data.least == least && data.grows == grows && data.pushed == pushed && data.before == before && data.whole == whole && data.align == align && data.above == above && data.inset == inset) return;
    data
      ..shrink = shrink
      ..least = least
      ..grows = grows
      ..pushed = pushed
      ..before = before
      ..whole = whole
      ..align = align
      ..above = above
      ..inset = inset;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => CssRow;
}

/// `display: flex` on one line: the items at their own widths with [gap] between, each giving way in proportion to
/// its width when there is not room for all (`flex-shrink: 1`), down to its least and no further; what is left
/// over goes before the item that is [CssItem.pushed], or to the one that [CssItem.grows].
class CssRow extends MultiChildRenderObjectWidget {
  const CssRow({super.key, this.gap = 0, this.align = CssAlign.center, this.minHeight = 0, this.shrinkWrap = false, super.children});

  final double gap;
  final CssAlign align;
  final double minHeight;

  /// `display: inline-flex`: as wide as its items, where a flex row is as wide as its room.
  final bool shrinkWrap;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCssFlex(gap: gap, rowGap: 0, align: align, minHeight: minHeight, wraps: false, shrinkWrap: shrinkWrap);

  @override
  void updateRenderObject(BuildContext context, covariant RenderCssFlex renderObject) {
    renderObject
      ..gap = gap
      ..align = align
      ..minHeight = minHeight
      ..shrinkWrap = shrinkWrap;
  }
}

/// `display: flex; flex-wrap: wrap`: the items at their own widths, never wider than the room, on as many lines
/// as it takes, each line's items set by [align].
class CssWrap extends MultiChildRenderObjectWidget {
  const CssWrap({super.key, this.gap = 0, this.rowGap = 0, this.align = CssAlign.baseline, this.shrinkWrap = false, this.spread = false, super.children});

  final double gap;
  final double rowGap;
  final CssAlign align;
  final bool shrinkWrap;

  /// `justify-content: space-between`.
  final bool spread;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCssFlex(gap: gap, rowGap: rowGap, align: align, minHeight: 0, wraps: true, shrinkWrap: shrinkWrap, spread: spread);

  @override
  void updateRenderObject(BuildContext context, covariant RenderCssFlex renderObject) {
    renderObject
      ..gap = gap
      ..rowGap = rowGap
      ..align = align
      ..shrinkWrap = shrinkWrap
      ..spread = spread;
  }
}

class RenderCssFlex extends RenderBox with ContainerRenderObjectMixin<RenderBox, CssFlexData>, RenderBoxContainerDefaultsMixin<RenderBox, CssFlexData> {
  RenderCssFlex({required double gap, required double rowGap, required CssAlign align, required double minHeight, required this.wraps, required bool shrinkWrap, bool spread = false})
    : _gap = gap,
      _rowGap = rowGap,
      _align = align,
      _minHeight = minHeight,
      _shrinkWrap = shrinkWrap,
      _spread = spread;

  final bool wraps;

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _rowGap;
  set rowGap(double value) {
    if (value == _rowGap) return;
    _rowGap = value;
    markNeedsLayout();
  }

  CssAlign _align;
  set align(CssAlign value) {
    if (value == _align) return;
    _align = value;
    markNeedsLayout();
  }

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  bool _shrinkWrap;
  set shrinkWrap(bool value) {
    if (value == _shrinkWrap) return;
    _shrinkWrap = value;
    markNeedsLayout();
  }

  bool _spread;
  set spread(bool value) {
    if (value == _spread) return;
    _spread = value;
    markNeedsLayout();
  }

  double? _firstBaseline;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! CssFlexData) child.parentData = CssFlexData();
  }

  List<RenderBox> get _items {
    final items = <RenderBox>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      items.add(child);
    }
    return items;
  }

  CssFlexData _data(RenderBox child) => child.parentData! as CssFlexData;

  @override
  double computeMinIntrinsicWidth(double height) {
    var most = 0.0, sum = 0.0;
    final items = _items;
    for (final child in items) {
      final data = _data(child);
      final wide = (wraps || data.shrink > 0 ? (data.least ?? child.getMinIntrinsicWidth(double.infinity)) : child.getMaxIntrinsicWidth(double.infinity)) + data.before;
      most = math.max(most, wide);
      sum += wide;
    }
    return wraps ? most : sum + _gap * math.max(0, items.length - 1);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var sum = 0.0;
    final items = _items;
    for (final child in items) {
      sum += child.getMaxIntrinsicWidth(double.infinity) + _data(child).before;
    }
    return sum + _gap * math.max(0, items.length - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _dry(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) => _dry(BoxConstraints(maxWidth: width)).height;

  Size _dry(BoxConstraints constraints) => _layout(constraints, dry: true);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _dry(constraints);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _firstBaseline;

  double? _baselineOf(RenderBox child, BoxConstraints given, {required bool dry}) =>
      dry ? child.getDryBaseline(given, TextBaseline.alphabetic) : child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final room = constraints.maxWidth;
    final items = _items;
    final given = <RenderBox, BoxConstraints>{};
    final sizes = <RenderBox, Size>{};
    Size lay(RenderBox child, BoxConstraints of) {
      given[child] = of;
      if (dry) return sizes[child] = child.getDryLayout(of);
      child.layout(of, parentUsesSize: true);
      return sizes[child] = child.size;
    }

    // The lines: one, or as many as the items take at their own widths.
    final lines = <List<RenderBox>>[];
    if (!wraps) {
      lines.add(items);
      // Each item's own width, then what there is not room for taken from those that give way, in proportion to
      // their widths, down to each one's least: the flexbox algorithm's loop.
      final base = <RenderBox, double>{for (final child in items) child: child.getMaxIntrinsicWidth(double.infinity)};
      final gaps = _gap * math.max(0, items.length - 1) + items.fold<double>(0, (sum, child) => sum + _data(child).before);
      final widths = Map<RenderBox, double>.of(base);
      if (room.isFinite) {
        final frozen = <RenderBox>{for (final child in items) if (_data(child).shrink == 0) child};
        for (var pass = 0; pass < items.length + 1; pass += 1) {
          final over = gaps + widths.values.fold<double>(0, (sum, each) => sum + each) - room;
          if (over <= 0.001) break;
          final loose = items.where((child) => !frozen.contains(child)).toList();
          final scaled = loose.fold<double>(0, (sum, child) => sum + (base[child]! - _data(child).inset) * _data(child).shrink);
          if (loose.isEmpty || scaled <= 0) break;
          // What is to come off is worked out from the widths the loose items started with.
          final off = gaps + items.fold<double>(0, (sum, child) => sum + (frozen.contains(child) ? widths[child]! : base[child]!)) - room;
          var clamped = false;
          for (final child in loose) {
            final data = _data(child);
            final least = data.least ?? base[child]!;
            final wanted = base[child]! - off * (base[child]! - data.inset) * data.shrink / scaled;
            if (wanted < least) {
              widths[child] = math.min(least, base[child]!);
              frozen.add(child);
              clamped = true;
            } else {
              widths[child] = wanted;
            }
          }
          if (!clamped) break;
        }
      }
      var used = gaps;
      RenderBox? grower;
      for (final child in items) {
        if (_data(child).grows) {
          grower = child;
          continue;
        }
        final gave = widths[child]! < base[child]! - 0.001;
        final size = lay(child, gave ? BoxConstraints(maxWidth: math.max(0, widths[child]!)) : const BoxConstraints());
        // An item that was not asked to give way is as wide as it laid out; one that was is as wide as it was told.
        if (gave) sizes[child] = Size(widths[child]!, size.height);
        used += sizes[child]!.width;
      }
      if (grower != null) {
        final wide = room.isFinite ? math.max(0.0, room - used) : base[grower]!;
        lay(grower, BoxConstraints.tightFor(width: wide));
      }
    } else {
      var line = <RenderBox>[];
      var along = 0.0;
      for (final child in items) {
        final data = _data(child);
        final size = lay(child, data.whole && room.isFinite ? BoxConstraints.tightFor(width: room) : BoxConstraints(maxWidth: room));
        final wide = size.width + data.before;
        if (line.isNotEmpty && (data.whole || along + _gap + wide > room + 0.01)) {
          lines.add(line);
          line = <RenderBox>[];
          along = 0;
        }
        along += (line.isEmpty ? 0 : _gap) + wide;
        line.add(child);
        if (data.whole) {
          lines.add(line);
          line = <RenderBox>[];
          along = 0;
        }
      }
      if (line.isNotEmpty) lines.add(line);
    }

    // Each line: as tall as its items, set on their baselines or in its middle.
    var top = 0.0;
    var widest = 0.0;
    double? firstBaseline;
    final places = <RenderBox, Offset>{};
    for (final (index, line) in lines.indexed) {
      if (index > 0) top += _rowGap;
      var above = 0.0, below = 0.0, tall = 0.0;
      final baselines = <RenderBox, double?>{};
      for (final child in line) {
        final data = _data(child);
        final how = data.align ?? _align;
        final size = sizes[child]!;
        final at = how == CssAlign.baseline ? _baselineOf(child, given[child]!, dry: dry) : null;
        baselines[child] = at;
        if (at != null) {
          above = math.max(above, at + data.above);
          below = math.max(below, size.height - at);
        } else {
          tall = math.max(tall, size.height + data.above);
        }
      }
      var height = math.max(tall, above + below);
      // One line is as tall as the row is made to be: its items are set in the middle of that.
      if (!wraps) height = math.max(height, math.max(_minHeight, constraints.minHeight));
      final wide = line.fold<double>(0, (sum, child) => sum + sizes[child]!.width + _data(child).before) + _gap * math.max(0, line.length - 1);
      final free = room.isFinite ? math.max(0.0, room - wide) : 0.0;
      final pushes = !wraps && line.any((child) => _data(child).pushed);
      final between = wraps && _spread && line.length > 1 ? free / (line.length - 1) : 0.0;
      var left = 0.0;
      for (final (place, child) in line.indexed) {
        final data = _data(child);
        final how = data.align ?? _align;
        final size = sizes[child]!;
        if (place > 0) left += _gap + between;
        left += data.before;
        if (pushes && data.pushed) {
          left += free;
        }
        final at = baselines[child];
        final down = switch (how) {
          CssAlign.baseline => at == null ? data.above : above - at,
          CssAlign.center => (height - size.height) / 2,
          _ => data.above,
        };
        places[child] = Offset(left, top + down);
        if (index == 0 && firstBaseline == null) {
          final own = at ?? _baselineOf(child, given[child]!, dry: dry);
          if (own != null) firstBaseline = down + own;
        }
        left += size.width;
      }
      widest = math.max(widest, left);
      top += height;
    }
    if (!dry) {
      _firstBaseline = firstBaseline;
      for (final child in items) {
        _data(child).offset = places[child]!;
      }
    }
    final width = _shrinkWrap || !room.isFinite ? widest : room;
    return constraints.constrain(Size(width, top));
  }

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

/// A row whose items are all as tall as the tallest: a grid's row, each item `align-self: stretch`. Each item is
/// laid out at its own height, then again at the tallest's. Flutter's own way to this (`IntrinsicHeight`) asks
/// every item how tall it would be before laying any out, which a lane that measures its own box for the smoke at
/// its foot cannot answer.
class EqualHeights extends MultiChildRenderObjectWidget {
  const EqualHeights({super.key, this.gap = 0, super.children});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderEqualHeights(gap);

  @override
  void updateRenderObject(BuildContext context, covariant RenderEqualHeights renderObject) => renderObject.gap = gap;
}

class _EqualData extends ContainerBoxParentData<RenderBox> {}

class RenderEqualHeights extends RenderBox with ContainerRenderObjectMixin<RenderBox, _EqualData>, RenderBoxContainerDefaultsMixin<RenderBox, _EqualData> {
  RenderEqualHeights(this._gap);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualData) child.parentData = _EqualData();
  }

  @override
  void performLayout() {
    var tallest = 0.0;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(loose, parentUsesSize: true);
      tallest = math.max(tallest, child.size.height);
    }
    var left = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child.size.height != tallest) child.layout(BoxConstraints.tightFor(height: tallest), parentUsesSize: true);
      if (left > 0) left += _gap;
      (child.parentData! as _EqualData).offset = Offset(left, 0);
      left += child.size.width;
    }
    size = constraints.constrain(Size(left, tallest));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
