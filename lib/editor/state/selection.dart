/// Where the caret and the selected text are: CodeMirror's `SelectionRange` and `EditorSelection`
/// (@codemirror/state, selection.ts), ported line for line. A selection can hold several ranges, as CodeMirror's
/// can, though a state keeps only the main one unless `EditorState.allowMultipleSelections` is on.
library;

import 'change.dart';

// RangeFlag
const int _bidiLevelMask = 7;
const int _assocBefore = 8;
const int _assocAfter = 16;
const int _inverted = 32;
const int _undirectional = 64;

/// CodeMirror's `SelectionRange`: one range of a selection, or a caret when it is empty.
class SelectionRange {
  SelectionRange._(this.from, this.to, this.flags, this.goalColumn);

  /// CodeMirror's `SelectionRange.create`, internal there: use [EditorSelection.range] or [EditorSelection.cursor].
  factory SelectionRange.create(int from, int to, int flags, [int? goalColumn]) => SelectionRange._(from, to, flags, goalColumn);

  /// The lower end of the range.
  final int from;

  /// The upper end of the range.
  final int to;

  /// CodeMirror's packed flags: bidi level, which side the caret holds to, inverted, undirectional.
  final int flags;

  /// The column a vertical move is keeping to, if one is.
  final int? goalColumn;

  /// The end that stays put when the selection is extended.
  int get anchor => flags & _inverted != 0 ? to : from;

  /// The end that moves.
  int get head => flags & _inverted != 0 ? from : to;

  /// True when anchor and head are the same place: a caret.
  bool get empty => from == to;

  /// Which side of its position a caret holds to at a line wrap or a direction change: -1 before, 1 after, 0 either.
  int get assoc => flags & _assocBefore != 0
      ? -1
      : flags & _assocAfter != 0
      ? 1
      : 0;

  /// True for a range with no head or anchor of its own ([EditorSelection.undirectionalRange]).
  bool get undirectional => flags & _undirectional > 0;

  /// The bidi level of the text beside a caret, when one was recorded.
  int? get bidiLevel {
    final level = flags & _bidiLevelMask;
    return level == 7 ? null : level;
  }

  /// This range after `change`. A caret holds to the side `assoc` says; a range shrinks away from insertions at its
  /// edges.
  SelectionRange map(ChangeDesc change, [int assoc = -1]) {
    int from, to;
    if (empty) {
      from = to = change.mapPos(this.from, assoc);
    } else {
      from = change.mapPos(this.from, 1);
      to = change.mapPos(this.to, -1);
    }
    return from == this.from && to == this.to ? this : SelectionRange._(from, to, flags, goalColumn);
  }

  /// This range stretched to take in `from`-`to`.
  SelectionRange extend(int from, [int? to, int assoc = 0]) {
    to ??= from;
    if (from <= anchor && to >= anchor) return EditorSelection.range(from, to, null, null, assoc);
    final head = (from - anchor).abs() > (to - anchor).abs() ? from : to;
    return EditorSelection.range(anchor, head, null, null, assoc);
  }

  /// Whether two ranges are the same; a caret's side counts only when `includeAssoc`.
  bool eq(SelectionRange other, [bool includeAssoc = false]) =>
      anchor == other.anchor &&
      head == other.head &&
      goalColumn == other.goalColumn &&
      (!includeAssoc || !empty || assoc == other.assoc);

  /// `{anchor, head}`, as CodeMirror's `toJSON`.
  Map<String, Object?> toJson() => <String, Object?>{'anchor': anchor, 'head': head};

  /// Reads what [toJson] wrote.
  static SelectionRange fromJson(Object? json) {
    if (json is! Map || json['anchor'] is! int || json['head'] is! int) {
      throw RangeError('Invalid JSON representation for SelectionRange');
    }
    return EditorSelection.range(json['anchor'] as int, json['head'] as int);
  }

  @override
  String toString() => empty ? 'SelectionRange($from)' : 'SelectionRange($anchor -> $head)';
}

/// CodeMirror's `EditorSelection`: one or more ranges, kept sorted and apart, one of them the main one.
class EditorSelection {
  EditorSelection._(this.ranges, this.mainIndex);

  /// The ranges, sorted by position; never empty and never overlapping. Not to be changed.
  final List<SelectionRange> ranges;

  /// Which of [ranges] is the main one: usually the range last added.
  final int mainIndex;

  /// This selection after `change`.
  EditorSelection map(ChangeDesc change, [int assoc = -1]) {
    if (change.empty) return this;
    return EditorSelection.create(<SelectionRange>[for (final r in ranges) r.map(change, assoc)], mainIndex);
  }

  /// Whether two selections are the same.
  bool eq(EditorSelection other, [bool includeAssoc = false]) {
    if (ranges.length != other.ranges.length || mainIndex != other.mainIndex) return false;
    for (var i = 0; i < ranges.length; i++) {
      if (!ranges[i].eq(other.ranges[i], includeAssoc)) return false;
    }
    return true;
  }

  /// The main range.
  SelectionRange get main => ranges[mainIndex];

  /// Only the main range, the others dropped.
  EditorSelection asSingle() => ranges.length == 1 ? this : EditorSelection._(<SelectionRange>[main], 0);

  /// This selection with one more range, which becomes the main one unless `main` is false.
  EditorSelection addRange(SelectionRange range, [bool main = true]) =>
      EditorSelection.create(<SelectionRange>[range, ...ranges], main ? 0 : mainIndex + 1);

  /// This selection with one range (the main one by default) replaced.
  EditorSelection replaceRange(SelectionRange range, [int? which]) {
    final ranges = List<SelectionRange>.of(this.ranges);
    ranges[which ?? mainIndex] = range;
    return EditorSelection.create(ranges, mainIndex);
  }

  /// `{ranges, main}`, as CodeMirror's `toJSON`.
  Map<String, Object?> toJson() => <String, Object?>{
    'ranges': <Object?>[for (final r in ranges) r.toJson()],
    'main': mainIndex,
  };

  /// Reads what [toJson] wrote.
  static EditorSelection fromJson(Object? json) {
    if (json is! Map || json['ranges'] is! List || json['main'] is! int || (json['main'] as int) >= (json['ranges'] as List).length) {
      throw RangeError('Invalid JSON representation for EditorSelection');
    }
    return EditorSelection._(<SelectionRange>[for (final r in json['ranges'] as List) SelectionRange.fromJson(r)], json['main'] as int);
  }

  /// A selection of one range: a caret at `anchor`, or `anchor` to `head`.
  static EditorSelection single(int anchor, [int? head]) =>
      EditorSelection._(<SelectionRange>[EditorSelection.range(anchor, head ?? anchor)], 0);

  /// A selection of these ranges, sorted and merged if they are not already.
  static EditorSelection create(List<SelectionRange> ranges, [int mainIndex = 0]) {
    if (ranges.isEmpty) throw RangeError('A selection needs at least one range');
    for (var pos = 0, i = 0; i < ranges.length; i++) {
      final range = ranges[i];
      if (range.empty ? range.from <= pos : range.from < pos) {
        return EditorSelection._normalized(List<SelectionRange>.of(ranges), mainIndex);
      }
      pos = range.to;
    }
    return EditorSelection._(ranges, mainIndex);
  }

  /// A caret at `pos`. `assoc` is the side it holds to where a position is in two places on screen.
  static SelectionRange cursor(int pos, [int assoc = 0, int? bidiLevel, int? goalColumn]) => SelectionRange._(
    pos,
    pos,
    (assoc == 0
            ? 0
            : assoc < 0
            ? _assocBefore
            : _assocAfter) |
        (bidiLevel == null ? 7 : (bidiLevel < 6 ? bidiLevel : 6)),
    goalColumn,
  );

  /// A range from `anchor` to `head`, either way round.
  static SelectionRange range(int anchor, int head, [int? goalColumn, int? bidiLevel, int? assoc]) {
    var flags = bidiLevel == null ? 7 : (bidiLevel < 6 ? bidiLevel : 6);
    var side = assoc ?? 0;
    if (side == 0 && anchor != head) side = head < anchor ? 1 : -1;
    if (side != 0) flags |= side < 0 ? _assocBefore : _assocAfter;
    return head < anchor
        ? SelectionRange._(head, anchor, flags | _inverted, goalColumn)
        : SelectionRange._(anchor, head, flags, goalColumn);
  }

  /// A range with no direction (CodeMirror's `undirectionalRange`).
  static SelectionRange undirectionalRange(int from, int to) => SelectionRange._(from, to, _undirectional, null);

  static EditorSelection _normalized(List<SelectionRange> ranges, [int mainIndex = 0]) {
    final main = ranges[mainIndex];
    _stableSort(ranges);
    mainIndex = ranges.indexOf(main);
    for (var i = 1; i < ranges.length; i++) {
      final range = ranges[i], prev = ranges[i - 1];
      if (range.empty ? range.from <= prev.to : range.from < prev.to) {
        final from = prev.from, to = range.to > prev.to ? range.to : prev.to;
        if (i <= mainIndex) mainIndex--;
        ranges.replaceRange(
          --i,
          i + 2,
          <SelectionRange>[range.anchor > range.head ? EditorSelection.range(to, from) : EditorSelection.range(from, to)],
        );
      }
    }
    return EditorSelection._(ranges, mainIndex);
  }

  @override
  String toString() => 'EditorSelection($ranges, main: $mainIndex)';
}

// JavaScript's sort is stable and Dart's is not promised to be: ranges that start at one place keep their order.
void _stableSort(List<SelectionRange> ranges) {
  for (var i = 1; i < ranges.length; i++) {
    final item = ranges[i];
    var j = i - 1;
    while (j >= 0 && ranges[j].from > item.from) {
      ranges[j + 1] = ranges[j];
      j--;
    }
    ranges[j + 1] = item;
  }
}

/// CodeMirror's `checkSelection`: a selection may not reach past the document.
void checkSelection(EditorSelection selection, int docLength) {
  for (final range in selection.ranges) {
    if (range.to > docLength) throw RangeError('Selection points outside of document');
  }
}
