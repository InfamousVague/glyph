/// What a line shows, worked out from what it holds: the step CodeMirror takes in `ContentBuilder`
/// (@codemirror/view, buildview.ts) when it turns a stretch of the document and the decorations over it into
/// `LineView`s of `TextView`, `MarkView` and `WidgetView`.
///
/// A [LineProjection] is one line of the editor's layout (a document line, or several joined by a replacement that
/// covers their breaks) as a list of [Segment]s: text that is shown, with the marks round it; a hidden range; an
/// inline widget, standing at a position or in place of a range. The shown text is [LineProjection.display], in
/// which a widget takes one unit (U+FFFC), and [LineProjection.toDisplay] / [LineProjection.toDoc] go between the
/// two, which is what the caret, the selection and a tap need.
///
/// [PaintText] is the second step: the display text as the paragraph is given it, with `white-space: break-spaces`
/// spelt out (below), and its own two maps.
///
/// Offsets inside a projection are counted from the line's start, not the document's, so a line that only moved
/// (text typed above it) projects to an equal value and is not laid out again.
///
/// What differs from CodeMirror: there is no DOM to reuse, so nothing of `openStart`/`openEnd` is kept (they say
/// which mark elements continue across a boundary); block widgets are not segments but entries of their own
/// (`blocks.dart`); bidirectional text is not ordered here (the paragraph does it, and `coordsAtPos` asks it).
library;

import 'dart:typed_data';

import '../state/rangeset.dart';
import 'decoration.dart';
import 'line_breaks.dart';
import 'widget.dart';

/// What a [Segment] is.
enum SegmentKind {
  /// Text of the document, shown.
  text,

  /// A range of the document that is not shown (`Decoration.replace({})`).
  hidden,

  /// An inline widget: at a position (`Decoration.widget`) or in place of a range (`Decoration.replace({widget})`).
  widget,
}

/// One piece of a line. Document offsets ([from], [to]) and display offsets ([displayFrom], [displayTo]) are both
/// counted from the line's start.
class Segment {
  const Segment({
    required this.kind,
    required this.from,
    required this.to,
    required this.displayFrom,
    required this.displayTo,
    this.marks = const <MarkDecoration>[],
    this.widget,
    this.side = 0,
    this.atomic = false,
    this.decoration,
  });

  final SegmentKind kind;
  final int from;
  final int to;
  final int displayFrom;
  final int displayTo;

  /// The mark decorations round it, outermost first.
  final List<MarkDecoration> marks;

  /// The widget drawn, for a [SegmentKind.widget].
  final EditorWidget? widget;

  /// A point widget's side of its position: below zero it is drawn before the caret there, above zero after.
  final int side;

  /// Whether the caret steps over it as one (`EditorView.atomicRanges`).
  final bool atomic;

  /// The replace or widget decoration it came from.
  final PointDecoration? decoration;

  int get length => to - from;
  int get displayLength => displayTo - displayFrom;

  Segment _with({int? from, int? to, int? displayFrom, int? displayTo, bool? atomic}) => Segment(
    kind: kind,
    from: from ?? this.from,
    to: to ?? this.to,
    displayFrom: displayFrom ?? this.displayFrom,
    displayTo: displayTo ?? this.displayTo,
    marks: marks,
    widget: widget,
    side: side,
    atomic: atomic ?? this.atomic,
    decoration: decoration,
  );

  bool _same(Segment other) {
    if (kind != other.kind || from != other.from || to != other.to || displayFrom != other.displayFrom || atomic != other.atomic || side != other.side) {
      return false;
    }
    if (marks.length != other.marks.length) return false;
    for (var i = 0; i < marks.length; i++) {
      if (!identical(marks[i], other.marks[i]) && !marks[i].eq(other.marks[i])) return false;
    }
    final a = widget, b = other.widget;
    return identical(a, b) || (a != null && b != null && a.compare(b));
  }

  @override
  String toString() => '${kind.name}($from-$to @$displayFrom-$displayTo${marks.isEmpty ? '' : ' ${marks.map((m) => m.attrs['class'] ?? '').join('>')}'})';
}

/// The placeholder a widget takes in [LineProjection.display]: U+FFFC, the object replacement character.
const String widgetPlaceholder = '￼';

/// A line of the editor's layout, as what it shows.
class LineProjection {
  LineProjection._(this.length, this.source, this.display, this.segments, this.lineDecorations, this.className, this.attributes);

  /// How much of the document the line covers.
  final int length;

  /// The document's text over the line.
  final String source;

  /// The text shown, a widget as one [widgetPlaceholder].
  final String display;
  final List<Segment> segments;

  /// The display offsets where hidden syntax stands inside the line between two runs of words, for [PaintText]:
  /// places a line may break. Not beside a widget: a widget is a place to break already, and the piece drawn there
  /// (a blank's square, a chip) measures what stands next to it.
  late final Set<int> hiddenBreaks = () {
    final out = <int>{};
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.kind != SegmentKind.hidden || segment.displayFrom <= 0 || segment.displayFrom >= display.length) continue;
      var before = i - 1, after = i + 1;
      while (before >= 0 && segments[before].kind == SegmentKind.hidden) {
        before--;
      }
      while (after < segments.length && segments[after].kind == SegmentKind.hidden) {
        after++;
      }
      if (before < 0 || after >= segments.length) continue;
      if (segments[before].kind == SegmentKind.text && segments[after].kind == SegmentKind.text) out.add(segment.displayFrom);
    }
    return out;
  }();

  /// The line decorations on the line, in precedence order.
  final List<LineDecoration> lineDecorations;

  /// Their classes, joined: the line element's `class`.
  final String className;

  /// Their attributes, combined as CodeMirror combines them (`class` and `style` joined, the rest the first said).
  final Map<String, String> attributes;

  /// Projects `source`, the text of the document from `from` on, under `sets`. `atomic` are the ranges the caret
  /// skips (document offsets, sorted).
  factory LineProjection.build(String source, int from, List<DecorationSet> sets, {List<(int, int)> atomic = const <(int, int)>[]}) {
    assert(_built());
    final builder = _Builder(source, from);
    if (sets.isNotEmpty) {
      RangeSet.spans<Decoration>(sets, from, from + source.length, builder);
    } else {
      builder.span(from, from + source.length, const <Decoration>[], 0);
    }
    return builder.finish(atomic);
  }

  /// How many lines were projected, counted in a debug build only: a test holds a keystroke to its own line.
  static int builds = 0;

  static bool _built() {
    builds += 1;
    return true;
  }

  /// A line of plain text, with no decorations.
  factory LineProjection.plain(String source) => LineProjection.build(source, 0, const <DecorationSet>[]);

  /// Whether nothing is drawn on the line: the page's `<br>` alone.
  bool get isEmpty => display.isEmpty;

  /// Where document offset `pos` (from the line's start) is in [display]. `side` says which way a position leans
  /// where it could be either side of something: below zero before, above zero after. It matters at a point
  /// widget drawn at `pos` and inside a replaced range.
  int toDisplay(int pos, [int side = 1]) {
    if (pos <= 0 && segments.isEmpty) return 0;
    for (final seg in segments) {
      switch (seg.kind) {
        case SegmentKind.text:
          if (pos < seg.to) return seg.displayFrom + (pos < seg.from ? 0 : pos - seg.from);
        case SegmentKind.hidden:
          if (pos < seg.to) return seg.displayFrom;
        case SegmentKind.widget:
          if (seg.from == seg.to) {
            // A widget at a position: the caret there is after it when the widget's side is before the caret.
            if (pos < seg.from || (pos == seg.from && seg.side >= 0)) return seg.displayFrom;
          } else if (pos < seg.to) {
            return pos <= seg.from || side < 0 ? seg.displayFrom : seg.displayTo;
          }
      }
    }
    return display.length;
  }

  /// The document offset (from the line's start) of display offset `at`. Where a hidden range or a widget makes
  /// several document positions one display position, `bias` picks: below zero the first of them, above zero the
  /// last.
  int toDoc(int at, [int bias = -1]) {
    int? first, last;
    for (final seg in segments) {
      if (at < seg.displayFrom) break;
      if (at > seg.displayTo) continue;
      int a, b;
      switch (seg.kind) {
        case SegmentKind.text:
          a = b = seg.from + (at - seg.displayFrom);
        case SegmentKind.hidden:
          a = seg.from;
          b = seg.to;
        case SegmentKind.widget:
          a = at == seg.displayFrom ? seg.from : seg.to;
          b = at == seg.displayTo ? seg.to : seg.from;
          if (b < a) b = a;
      }
      first ??= a;
      last = b;
    }
    if (first == null) return at <= 0 ? 0 : length;
    return bias < 0 ? first : last!;
  }

  /// The segment a position's caret is drawn by: the one `pos` is inside, or at an edge the one before it (`side`
  /// below zero) or after it.
  Segment? segmentAt(int pos, [int side = 1]) {
    Segment? before, after;
    for (final seg in segments) {
      if (seg.from < pos && pos < seg.to) return seg;
      if (seg.to == pos && seg.from < pos) before = seg;
      if (seg.from == pos && seg.to > pos && after == null) after = seg;
      if (seg.from == pos && seg.to == pos) {
        if (seg.side < 0) {
          before = seg;
        } else {
          after ??= seg;
        }
      }
    }
    return side < 0 ? (before ?? after) : (after ?? before);
  }

  /// Whether `other` shows the same thing: the same text under the same marks and widgets, on a line of the same
  /// classes. A line for which this holds need not be laid out again.
  bool same(LineProjection other) {
    if (identical(this, other)) return true;
    if (display != other.display || length != other.length || className != other.className || segments.length != other.segments.length) return false;
    if (!attrsEq(attributes, other.attributes)) return false;
    for (var i = 0; i < segments.length; i++) {
      if (!segments[i]._same(other.segments[i])) return false;
    }
    return true;
  }

  @override
  String toString() => 'LineProjection(${segments.join(', ')})';
}

class _Builder implements SpanIterator<Decoration> {
  _Builder(this.source, this.base);

  final String source;
  final int base;
  final List<Segment> segments = <Segment>[];
  final List<LineDecoration> lines = <LineDecoration>[];
  final StringBuffer display = StringBuffer();
  int shown = 0;

  static List<MarkDecoration> _marks(List<Decoration> active) {
    if (active.isEmpty) return const <MarkDecoration>[];
    // CodeMirror wraps the text in `active[0]` first: the last of them is the outermost.
    final marks = <MarkDecoration>[];
    for (var i = active.length - 1; i >= 0; i--) {
      final value = active[i];
      if (value is MarkDecoration) marks.add(value);
    }
    return marks;
  }

  @override
  void span(int from, int to, List<Decoration> active, int openStart) {
    if (to <= from) return;
    final text = source.substring(from - base, to - base);
    segments.add(Segment(kind: SegmentKind.text, from: from - base, to: to - base, displayFrom: shown, displayTo: shown + text.length, marks: _marks(active)));
    display.write(text);
    shown += text.length;
  }

  @override
  void point(int from, int to, Decoration value, List<Decoration> active, int openStart, int index) {
    if (value is LineDecoration) {
      // A line decoration counts where its line starts.
      if (from == base) lines.add(value);
      return;
    }
    if (value is! PointDecoration || value.block) return;
    final widget = value.widget;
    if (widget == null) {
      if (to > from) segments.add(Segment(kind: SegmentKind.hidden, from: from - base, to: to - base, displayFrom: shown, displayTo: shown, marks: _marks(active), decoration: value));
      return;
    }
    segments.add(
      Segment(
        kind: SegmentKind.widget,
        from: from - base,
        to: to - base,
        displayFrom: shown,
        displayTo: shown + 1,
        marks: _marks(active),
        widget: widget,
        side: value.isReplace ? 0 : (value.startSide < 0 ? -1 : 1),
        decoration: value,
      ),
    );
    display.write(widgetPlaceholder);
    shown += 1;
  }

  LineProjection finish(List<(int, int)> atomic) {
    final classes = <String>[];
    Map<String, String> attributes = const <String, String>{};
    for (final line in lines) {
      final name = line.spec.className;
      if (name != null && name.isNotEmpty) classes.add(name);
      final attrs = line.spec.attributes;
      if (attrs != null && attrs.isNotEmpty) {
        attributes = combineAttrs(attrs, attributes.isEmpty ? <String, String>{} : attributes);
      }
    }
    final own = atomic.isEmpty ? segments : _markAtomic(segments, atomic, base);
    return LineProjection._(source.length, source, display.toString(), List<Segment>.unmodifiable(own), List<LineDecoration>.unmodifiable(lines), classes.join(' '), attributes);
  }

  static List<Segment> _markAtomic(List<Segment> segments, List<(int, int)> atomic, int base) {
    final out = <Segment>[];
    for (final seg in segments) {
      var rest = seg;
      var whole = false;
      for (final (aFrom, aTo) in atomic) {
        final from = aFrom - base, to = aTo - base;
        if (to <= rest.from && !(from == to && from == rest.from)) continue;
        if (from >= rest.to && rest.to > rest.from) break;
        if (rest.kind != SegmentKind.text) {
          if (from <= rest.from && to >= rest.to) whole = true;
          continue;
        }
        // Text: cut at the atomic range's edges.
        if (from > rest.from) {
          final cut = from - rest.from;
          out.add(rest._with(to: from, displayTo: rest.displayFrom + cut));
          rest = rest._with(from: from, displayFrom: rest.displayFrom + cut);
        }
        final end = to < rest.to ? to : rest.to;
        if (end > rest.from) {
          final cut = end - rest.from;
          out.add(rest._with(to: end, displayTo: rest.displayFrom + cut, atomic: true));
          rest = rest._with(from: end, displayFrom: rest.displayFrom + cut);
        }
        if (rest.from >= rest.to) break;
      }
      if (rest.kind != SegmentKind.text) {
        out.add(whole ? rest._with(atomic: true) : rest);
      } else if (rest.to > rest.from) {
        out.add(rest);
      }
    }
    return out;
  }
}

/// The display text as the paragraph is given it: `white-space: break-spaces`, which is how the editor's lines
/// wrap (CodeMirror's `EditorView.lineWrapping`), spelt out for an engine that has no such mode.
///
/// On the page a space at the end of a visual line takes its room and the line may break after any space, so a
/// run of spaces wraps like words do and a caret after a trailing space is where the space ended. A paragraph of
/// Flutter's hangs trailing spaces past the edge and gives them no width. So each space is set as a no-break space
/// (the same advance, never hung) followed by a zero-width space (where the line may break), and a tab as the
/// spaces to its next stop. And where the page may break a line between two ASCII characters and the paragraph
/// may not, or the other way about, the paragraph is told (`line_breaks.dart`). [toPaint] and [toDisplay] go
/// between the two texts.
///
/// And a word too long for a line. The lines wrap `overflow-wrap: anywhere`: a word that does not fit in the room
/// left on its line goes to the next line first, as any word does, and is cut where a line ends only if it is
/// longer than a whole line. A paragraph of Flutter's cuts it where it stands, filling the line it began on. So
/// the line that lays the words out says where the page would have ended a line before such a word ([forced]),
/// and a line feed is written there (`line.dart` `_lateBreak`).
///
/// What differs: a tab's stops are counted in characters from the line's start, which is right for the monospace
/// faces a tab is ever drawn in (a block of code) and near enough elsewhere.
class PaintText {
  PaintText._(this.text, this._toPaint, this._toDisplay, [this.forced = const <int>{}]);

  /// [breaks] are the display offsets where something hidden stands between two characters ([hiddenBreaks]): the
  /// page draws hidden syntax as an empty element between two of CodeMirror's `<img class="cm-widgetBuffer">`, and
  /// a line may break either side of an image whatever the characters round it, so "`code`." may end a line after
  /// `code` and start the next with the full stop, which no rule for the pair `e.` allows.
  ///
  /// [forced] are the display offsets a visual line is made to start at: a line feed stands before each.
  factory PaintText(String display, {int tabSize = 4, Set<int> breaks = const <int>{}, Set<int> forced = const <int>{}}) {
    // Most lines are words and spaces; a line with neither a space, a tab nor a pair to be told about is itself.
    var plain = forced.isEmpty;
    for (final at in breaks) {
      if (at > 0 && at < display.length) plain = false;
    }
    for (var i = 0; i < display.length && plain; i++) {
      final unit = display.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x09) {
        plain = false;
      } else if (i + 1 < display.length && unit >= 0x21 && unit <= 0x7e) {
        if (breakFix(i > 0 ? display.codeUnitAt(i - 1) : -1, unit, display.codeUnitAt(i + 1)) != BreakFix.none) plain = false;
      }
    }
    if (plain) return PaintText._(display, null, null);
    final out = StringBuffer();
    final toPaint = Int32List(display.length + 1);
    final back = <int>[];
    var column = 0;
    for (var i = 0; i < display.length; i++) {
      toPaint[i] = back.length;
      final unit = display.codeUnitAt(i);
      if (unit == 0x20) {
        out.write('\u00A0\u200B');
        back
          ..add(i)
          ..add(i + 1);
        column += 1;
      } else if (unit == 0x09) {
        final width = tabSize - column % tabSize;
        for (var n = 0; n < width; n++) {
          out.write('\u00A0');
          back.add(n == 0 ? i : i + 1);
        }
        out.write('\u200B');
        back.add(i + 1);
        column += width;
      } else {
        out.writeCharCode(unit);
        back.add(i);
        column += 1;
        // Where the page's lines may break between two ASCII characters and the paragraph's may not, or the
        // other way about (line_breaks.dart).
        if (i + 1 < display.length && breaks.contains(i + 1)) {
          // Something hidden stands here: a place to break, whatever the pair.
          out.write(zeroWidthSpace);
          back.add(i + 1);
        } else if (i + 1 < display.length && unit >= 0x21 && unit <= 0x7e) {
          final fix = breakFix(i > 0 ? display.codeUnitAt(i - 1) : -1, unit, display.codeUnitAt(i + 1));
          if (fix != BreakFix.none) {
            out.write(fix == BreakFix.allow ? zeroWidthSpace : wordJoiner);
            back.add(i + 1);
          }
        }
      }
      if (i + 1 < display.length && forced.contains(i + 1)) {
        out.write('\n');
        back.add(i + 1);
      }
    }
    toPaint[display.length] = back.length;
    back.add(display.length);
    return PaintText._(out.toString(), toPaint, Int32List.fromList(back), forced);
  }

  /// The display offsets a line feed was written before.
  final Set<int> forced;

  /// Whether the character at paint offset `at` is a line feed written for [forced]: the display text has none of
  /// its own.
  bool feedAt(int at) => forced.isNotEmpty && at >= 0 && at < text.length && text.codeUnitAt(at) == 0x0a;

  /// What the paragraph lays out.
  final String text;
  final Int32List? _toPaint;
  final Int32List? _toDisplay;

  /// The paint offset of display offset `at`: after everything a space before it became.
  int toPaint(int at) => _toPaint == null ? at : _toPaint[at.clamp(0, _toPaint.length - 1)];

  /// The display offset of paint offset `at`. An offset inside what one space became is the nearer edge of the
  /// space: before it only at its very start.
  int toDisplay(int at) => _toDisplay == null ? at : _toDisplay[at.clamp(0, _toDisplay.length - 1)];
}
