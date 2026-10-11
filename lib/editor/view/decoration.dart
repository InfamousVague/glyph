/// How the text is dressed: CodeMirror's `Decoration`, `DecorationSet` and `BlockType` (@codemirror/view,
/// decoration.ts). The four kinds, their sides, their mapping and their equality are ported as they are, because
/// the order of decorations at one position and what survives an edit both come from them; drawing them is the
/// view's (`lib/editor/view/`, piece C).
///
/// - [Decoration.mark] styles a stretch of text: a style-class name and attributes, which the view's theme turns
///   into a `TextStyle` and paint.
/// - [Decoration.line] does the same for a whole line; its range is the empty range at the line's start.
/// - [Decoration.widget] draws an [EditorWidget] at a position.
/// - [Decoration.replace] hides a range, or draws a widget in its place.
///
/// What differs: the spec is named parameters, kept on the decoration as a [DecorationSpec]; `class` is
/// `className` (a keyword); attributes are strings by name, read by the view's theme where the DOM read them (a
/// `style` attribute has no meaning by itself here). `Decoration.none` and `Decoration.set` are as in CodeMirror.
///
/// Flutter's painting library has a `Decoration` too (the parent of `BoxDecoration`). A file that draws and also
/// decorates imports `package:flutter/widgets.dart` with `hide Decoration`; `BoxDecoration` and the rest are
/// untouched by that.
library;

import '../state/change.dart';
import '../state/rangeset.dart';
import 'widget.dart';

/// CodeMirror's `DecorationSet`: a range set of decorations.
typedef DecorationSet = RangeSet<Decoration>;

// Side
const int _nonIncEnd = -600000000; // (end of non-inclusive range)
const int _gapStart = -500000000;
const int _blockBefore = -400000000; // + widget side option (block widget before)
const int _blockIncStart = -300000000; // (start of inclusive block range)
const int _line = -200000000; // (line widget)
const int _inlineBefore = -100000000; // + widget side (inline widget before)
const int _inlineIncStart = -1; // (start of inclusive inline range)
const int _inlineIncEnd = 1; // (end of inclusive inline range)
const int _inlineAfter = 100000000; // + widget side (inline widget after)
const int _blockIncEnd = 200000000; // (end of inclusive block range)
const int _blockAfter = 300000000; // + widget side (block widget after)
const int _gapEnd = 400000000;
const int _nonIncStart = 500000000; // (start of non-inclusive range)

/// CodeMirror's `BlockType`: what kind of block a line of the view's layout is.
enum BlockType {
  /// A line of text.
  text,

  /// A block widget before a position.
  widgetBefore,

  /// A block widget after a position.
  widgetAfter,

  /// A block widget that replaces a range.
  widgetRange,
}

/// What a decoration was made with: CodeMirror's spec object, which it keeps as `decoration.spec`.
class DecorationSpec {
  const DecorationSpec({
    this.className,
    this.attributes,
    this.tagName,
    this.inclusive,
    this.inclusiveStart,
    this.inclusiveEnd,
    this.widget,
    this.side = 0,
    this.block = false,
    this.inlineOrder = false,
    this.isBlockGap = false,
    this.data,
  });

  /// The style-class name (CodeMirror's `class`); several are separated by spaces.
  final String? className;

  /// Attributes by name.
  final Map<String, String>? attributes;

  /// A mark's element name in CodeMirror (`span` by default). Kept because marks with different names are
  /// different marks; nothing is drawn from it.
  final String? tagName;

  /// Whether text typed at the range's edges becomes part of it; [inclusiveStart] and [inclusiveEnd] say it for one
  /// edge.
  final bool? inclusive;
  final bool? inclusiveStart;
  final bool? inclusiveEnd;

  /// The widget of a widget or replace decoration.
  final EditorWidget? widget;

  /// A widget's side of its position: below zero before the caret there, above zero after it; also its order among
  /// widgets at the same position.
  final int side;

  /// Whether a widget or replacement is a block, on lines of its own.
  final bool block;

  /// For a block widget: ordered among inline content by [side] instead of before or after all of it.
  final bool inlineOrder;

  /// The view's own gap replacements.
  final bool isBlockGap;

  /// Anything else an extension wants to find on its decoration again: CodeMirror's "other properties".
  final Object? data;
}

({bool start, bool end}) _getInclusive(DecorationSpec spec, [bool block = false]) {
  final start = spec.inclusiveStart ?? spec.inclusive, end = spec.inclusiveEnd ?? spec.inclusive;
  return (start: start ?? block, end: end ?? block);
}

const Map<String, String> _noAttrs = <String, String>{};

/// CodeMirror's `attrsEq`: the same names with the same values.
bool attrsEq(Map<String, String>? a, Map<String, String>? b) {
  if (identical(a, b)) return true;
  a ??= _noAttrs;
  b ??= _noAttrs;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

/// CodeMirror's `combineAttrs`: `source` written over `target`, except that classes are joined with a space and
/// styles with a semicolon. Changes and returns `target`.
Map<String, String> combineAttrs(Map<String, String> source, Map<String, String> target) {
  source.forEach((name, value) {
    final current = target[name];
    if (name == 'class' && current != null && current.isNotEmpty) {
      target[name] = '$current $value';
    } else if (name == 'style' && current != null && current.isNotEmpty) {
      target[name] = '$current;$value';
    } else {
      target[name] = value;
    }
  });
  return target;
}

/// CodeMirror's `Decoration`: a value in a [DecorationSet] that says how a range is drawn.
abstract class Decoration extends RangeValue {
  Decoration._(this.startSide, this.endSide, this.widget, this.spec);

  @override
  final int startSide;

  @override
  final int endSide;

  /// The widget drawn, for a widget decoration or a replacement that has one.
  final EditorWidget? widget;

  /// What the decoration was made with.
  final DecorationSpec spec;

  /// Whether the decoration changes the height of what it is on.
  bool get heightRelevant => false;

  /// Styles the text in a range. Not inclusive unless said: text typed at its edges stays outside.
  factory Decoration.mark({
    String? className,
    Map<String, String>? attributes,
    bool? inclusive,
    bool? inclusiveStart,
    bool? inclusiveEnd,
    String? tagName,
    Object? data,
  }) => MarkDecoration._(
    DecorationSpec(
      className: className,
      attributes: attributes,
      inclusive: inclusive,
      inclusiveStart: inclusiveStart,
      inclusiveEnd: inclusiveEnd,
      tagName: tagName,
      data: data,
    ),
  );

  /// Draws `widget` at a position. `side` below zero puts it before the caret at that position, above zero after;
  /// `block` gives it lines of its own.
  factory Decoration.widget({required EditorWidget widget, int side = 0, bool block = false, bool inlineOrder = false, Object? data}) {
    var s = side < -10000 ? -10000 : (side > 10000 ? 10000 : side);
    s += (block && !inlineOrder) ? (s > 0 ? _blockAfter : _blockBefore) : (s > 0 ? _inlineAfter : _inlineBefore);
    return PointDecoration._(
      DecorationSpec(widget: widget, side: side, block: block, inlineOrder: inlineOrder, data: data),
      s,
      s,
      block,
      widget,
      false,
    );
  }

  /// Hides a range, or draws `widget` in its place. A block replacement is inclusive unless said, an inline one is
  /// not.
  factory Decoration.replace({
    EditorWidget? widget,
    bool? inclusive,
    bool? inclusiveStart,
    bool? inclusiveEnd,
    bool block = false,
    bool isBlockGap = false,
    Object? data,
  }) {
    final spec = DecorationSpec(
      widget: widget,
      inclusive: inclusive,
      inclusiveStart: inclusiveStart,
      inclusiveEnd: inclusiveEnd,
      block: block,
      isBlockGap: isBlockGap,
      data: data,
    );
    int startSide, endSide;
    if (isBlockGap) {
      startSide = _gapStart;
      endSide = _gapEnd;
    } else {
      final inc = _getInclusive(spec, block);
      startSide = (inc.start ? (block ? _blockIncStart : _inlineIncStart) : _nonIncStart) - 1;
      endSide = (inc.end ? (block ? _blockIncEnd : _inlineIncEnd) : _nonIncEnd) + 1;
    }
    return PointDecoration._(spec, startSide, endSide, block, widget, true);
  }

  /// Styles a whole line. Its range is the empty range at the line's start.
  factory Decoration.line({String? className, Map<String, String>? attributes, Object? data}) =>
      LineDecoration._(DecorationSpec(className: className, attributes: attributes, data: data));

  /// A set of decorations from ranges, which must be sorted unless `sort`.
  static DecorationSet set(List<Range<Decoration>> of, [bool sort = false]) => RangeSet.of<Decoration>(of, sort);

  /// No decorations: CodeMirror's `Decoration.none`.
  static final DecorationSet none = RangeSet<Decoration>.empty();

  /// Whether the decoration has a widget that knows its height.
  bool hasHeight() => widget != null ? widget!.estimatedHeight > -1 : false;

  @override
  Range<Decoration> range(int from, [int? to]) => Range<Decoration>.create(from, to ?? from, this);
}

/// A [Decoration.mark].
class MarkDecoration extends Decoration {
  MarkDecoration._(DecorationSpec spec) : this._sided(spec, _getInclusive(spec));

  MarkDecoration._sided(DecorationSpec spec, ({bool start, bool end}) inc)
    : tagName = spec.tagName ?? 'span',
      attrs = spec.className != null && spec.attributes != null
          ? combineAttrs(spec.attributes!, <String, String>{'class': spec.className!})
          : spec.className != null
          ? <String, String>{'class': spec.className!}
          : spec.attributes ?? _noAttrs,
      super._(inc.start ? _inlineIncStart : _nonIncStart, inc.end ? _inlineIncEnd : _nonIncEnd, null, spec);

  /// CodeMirror's element name for the mark; `span` unless said.
  final String tagName;

  /// The mark's attributes with its class among them, as `class`.
  final Map<String, String> attrs;

  @override
  bool eq(RangeValue other) =>
      identical(this, other) || other is MarkDecoration && tagName == other.tagName && attrsEq(attrs, other.attrs);

  @override
  Range<Decoration> range(int from, [int? to]) {
    to ??= from;
    if (from >= to) throw RangeError('Mark decorations may not be empty');
    return super.range(from, to);
  }
}

/// A [Decoration.line].
class LineDecoration extends Decoration {
  LineDecoration._(DecorationSpec spec) : super._(_line, _line, null, spec);

  @override
  MapMode get mapMode => MapMode.trackBefore;

  @override
  bool get point => true;

  @override
  bool eq(RangeValue other) =>
      other is LineDecoration && spec.className == other.spec.className && attrsEq(spec.attributes, other.spec.attributes);

  @override
  Range<Decoration> range(int from, [int? to]) {
    to ??= from;
    if (to != from) throw RangeError('Line decoration ranges must be zero-length');
    return super.range(from, to);
  }
}

/// A [Decoration.widget] or a [Decoration.replace].
class PointDecoration extends Decoration {
  PointDecoration._(DecorationSpec spec, int startSide, int endSide, this.block, EditorWidget? widget, this.isReplace)
    : mapMode = !block
          ? MapMode.trackDel
          : startSide <= 0
          ? MapMode.trackBefore
          : MapMode.trackAfter,
      super._(startSide, endSide, widget, spec);

  /// Whether it is a block.
  final bool block;

  /// Whether it replaces its range (a [Decoration.replace]) or sits at a position (a [Decoration.widget]).
  final bool isReplace;

  @override
  final MapMode mapMode;

  @override
  bool get point => true;

  /// For a block: which kind. Only meaningful when [block].
  BlockType get type => startSide != endSide
      ? BlockType.widgetRange
      : startSide <= 0
      ? BlockType.widgetBefore
      : BlockType.widgetAfter;

  @override
  bool get heightRelevant => block || widget != null && (widget!.estimatedHeight >= 5 || widget!.lineBreaks > 0);

  @override
  bool eq(RangeValue other) =>
      other is PointDecoration &&
      _widgetsEq(widget, other.widget) &&
      block == other.block &&
      startSide == other.startSide &&
      endSide == other.endSide;

  @override
  Range<Decoration> range(int from, [int? to]) {
    to ??= from;
    if (isReplace && (from > to || (from == to && startSide > 0 && endSide <= 0))) {
      throw RangeError('Invalid range for replacement decoration');
    }
    if (!isReplace && to != from) throw RangeError('Widget decorations can only have zero-length ranges');
    return super.range(from, to);
  }
}

bool _widgetsEq(EditorWidget? a, EditorWidget? b) => identical(a, b) || (a != null && b != null && a.compare(b));
