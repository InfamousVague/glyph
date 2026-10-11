/// The editor's vertical structure: which lines of the document are entries of the layout, what block widgets
/// stand round them, and how tall each is. The part of CodeMirror's `HeightMap` and `BlockInfo` (@codemirror/view,
/// heightmap.ts) the view needs, kept by line number.
///
/// An ENTRY is one thing in the column of the editor, named by the number of its first document line: a line of
/// text (or several, joined by a replacement that covers their breaks), or a block widget standing in place of a
/// range of lines, with the block widgets set before and after it. Lines swallowed by an entry that started
/// earlier are COVERED: they have no entry and no height.
///
/// [BlockStructure] is read from the decorations a state gives directly (state fields), which is where CodeMirror
/// requires block decorations and break-covering replacements to come from: a view plugin's decorations are only
/// worked out for what is on screen and so cannot say how tall the rest is. [HeightMap] holds a height for every
/// line: measured, for a line that has been laid out at the current width, and estimated from its length
/// otherwise.
///
/// What differs from CodeMirror: its height map is a balanced tree of gaps and lines updated through the changed
/// ranges; this is a flat list of doubles with running sums made again when asked after a change. A note of
/// 100,000 lines makes the sums in well under a millisecond, and nothing here is asked more than once a frame.
library;

import 'dart:typed_data';

import '../state/change.dart';
import '../state/rangeset.dart';
import '../state/text.dart';
import 'decoration.dart';

/// A block widget that says which class its element has on the page, for the stylesheet rules that ask what
/// stands before a line (`.cm-frontFold + .cm-line.lineH1`). The frozen `EditorWidget` has no word for it.
abstract interface class ClassedBlockWidget {
  String get className;
}

/// A block decoration, and where it is.
class BlockSpec {
  const BlockSpec(this.decoration, this.from, this.to);

  final PointDecoration decoration;
  final int from;
  final int to;

  BlockType get type => decoration.type;
  String? get className => switch (decoration.widget) {
    final ClassedBlockWidget w => w.className,
    _ => null,
  };
}

/// What is special about an entry: lines it covers beyond its first, a block widget in place of its text, block
/// widgets before and after it.
class EntryInfo {
  EntryInfo(this.line);

  /// The entry's first line.
  final int line;

  /// Its last: the same, unless it covers more.
  int lastLine = 0;

  /// The block widget drawn in place of the entry's lines.
  BlockSpec? replace;
  final List<BlockSpec> before = <BlockSpec>[];
  final List<BlockSpec> after = <BlockSpec>[];
}

/// Which lines are entries, and what blocks they carry.
class BlockStructure {
  BlockStructure._(this.special, this._coveredFrom, this._coveredTo);

  static final BlockStructure none = BlockStructure._(const <int, EntryInfo>{}, Int32List(0), Int32List(0));

  /// The entries that are not a plain line of text, by first line.
  final Map<int, EntryInfo> special;

  // Covered stretches of line numbers, in order: `_coveredFrom[i]`-`_coveredTo[i]`, both included.
  final Int32List _coveredFrom;
  final Int32List _coveredTo;

  bool get isEmpty => special.isEmpty;

  /// Reads the structure from `direct`, the decoration sets a state provides as values.
  static BlockStructure compute(Doc doc, List<DecorationSet> direct) {
    if (direct.every((set) => set.isEmpty || set.maxPoint < 0)) return none;
    final reader = _BlockReader(doc);
    RangeSet.spans<Decoration>(direct, 0, doc.length, reader, 0);
    if (reader.special.isEmpty) return none;
    final lines = reader.special.keys.toList()..sort();
    final from = <int>[], to = <int>[];
    for (final line in lines) {
      final info = reader.special[line]!;
      if (info.lastLine <= line) continue;
      // Entries inside a stretch an earlier entry covers are that entry's.
      if (to.isNotEmpty && line <= to.last) {
        if (info.lastLine > to.last) to[to.length - 1] = info.lastLine;
        continue;
      }
      from.add(line + 1);
      to.add(info.lastLine);
    }
    return BlockStructure._(reader.special, Int32List.fromList(from), Int32List.fromList(to));
  }

  EntryInfo? at(int line) => special[line];

  int _coveredIndex(int line) {
    var low = 0, high = _coveredFrom.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (line < _coveredFrom[mid]) {
        high = mid - 1;
      } else if (line > _coveredTo[mid]) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  /// Whether `line` is inside an entry that started on an earlier line.
  bool isCovered(int line) => _coveredFrom.isNotEmpty && _coveredIndex(line) >= 0;

  /// The first line of the entry `line` is in.
  int entryOf(int line) {
    if (_coveredFrom.isEmpty) return line;
    final i = _coveredIndex(line);
    return i < 0 ? line : _coveredFrom[i] - 1;
  }

  /// The last line of the entry that starts at `line`.
  int lastLineOf(int line) {
    final info = special[line];
    return info == null || info.lastLine < line ? line : info.lastLine;
  }

  /// Calls `visit` with every covered stretch of lines.
  void forEachCovered(void Function(int from, int to) visit) {
    for (var i = 0; i < _coveredFrom.length; i++) {
      visit(_coveredFrom[i], _coveredTo[i]);
    }
  }
}

class _BlockReader implements SpanIterator<Decoration> {
  _BlockReader(this.doc);

  final Doc doc;
  final Map<int, EntryInfo> special = <int, EntryInfo>{};

  EntryInfo _entry(int line) => special.putIfAbsent(line, () => EntryInfo(line)..lastLine = line);

  @override
  void span(int from, int to, List<Decoration> active, int openStart) {}

  @override
  void point(int from, int to, Decoration value, List<Decoration> active, int openStart, int index) {
    if (value is! PointDecoration) return;
    if (!value.block) {
      // An inline replacement that covers a line break joins its lines into one entry.
      if (!value.isReplace || to <= from) return;
      final first = doc.lineAt(from);
      if (to <= first.to) return;
      final entry = _entry(first.number);
      final last = doc.lineAt(to).number;
      if (last > entry.lastLine) entry.lastLine = last;
      return;
    }
    final first = doc.lineAt(from);
    final spec = BlockSpec(value, from, to);
    final entry = _entry(first.number);
    switch (value.type) {
      case BlockType.widgetRange:
        entry.replace = spec;
        final last = doc.lineAt(to).number;
        if (last > entry.lastLine) entry.lastLine = last;
      case BlockType.widgetBefore:
        entry.before.add(spec);
      case BlockType.widgetAfter:
        entry.after.add(spec);
      case BlockType.text:
        break;
    }
  }
}

/// A height for every line of the document.
class HeightMap {
  HeightMap(Doc doc, {this.lineHeight = 28, this.charsPerLine = 40}) {
    _reset(doc);
  }

  /// What an unmeasured visual line is taken to be tall, and how many characters fit across.
  double lineHeight;
  double charsPerLine;

  /// The width the measured heights were measured at.
  double width = -1;

  final List<double> _heights = <double>[0];
  final List<bool> _measured = <bool>[false];
  Float64List? _sums;

  int get lines => _heights.length - 1;

  double _estimate(int length) => (length <= charsPerLine ? 1 : (length / charsPerLine).ceil()) * lineHeight;

  void _reset(Doc doc) {
    _heights
      ..clear()
      ..add(0);
    _measured
      ..clear()
      ..add(false);
    for (var n = 1; n <= doc.lines; n++) {
      _heights.add(_estimate(doc.line(n).length));
      _measured.add(false);
    }
    _sums = null;
  }

  /// A new width, or a new look: every measurement is out of date. The heights are kept as the estimates they now
  /// are, unless `again`, which estimates every line from `doc` afresh.
  void invalidate(double width, {Doc? again}) {
    this.width = width;
    if (again != null) {
      _reset(again);
      return;
    }
    for (var i = 1; i < _measured.length; i++) {
      _measured[i] = false;
    }
  }

  /// Follows a change of the document: the lines a change touched are estimated again, the others keep what they
  /// had.
  void applyChanges(ChangeDesc changes, Doc before, Doc after) {
    final edits = <(int, int, int, int)>[];
    changes.iterChangedRanges((fromA, toA, fromB, toB) {
      edits.add((before.lineAt(fromA).number, before.lineAt(toA).number, after.lineAt(fromB).number, after.lineAt(toB).number));
    });
    // Back to front, so the earlier line numbers still mean what they did.
    for (final (firstA, lastA, firstB, lastB) in edits.reversed) {
      final heights = <double>[], measured = <bool>[];
      final same = lastA - firstA == lastB - firstB;
      for (var n = firstB; n <= lastB; n++) {
        // A line edited in place keeps its height until it is measured again: nothing below it jumps meanwhile.
        heights.add(same ? _heights[firstA + (n - firstB)] : _estimate(after.line(n).length));
        measured.add(false);
      }
      _heights.replaceRange(firstA, lastA + 1, heights);
      _measured.replaceRange(firstA, lastA + 1, measured);
    }
    _sums = null;
  }

  /// Lines `from` to `to` have no height of their own: an entry above covers them.
  void cover(int from, int to) {
    for (var n = from; n <= to && n < _heights.length; n++) {
      if (_heights[n] != 0) {
        _heights[n] = 0;
        _sums = null;
      }
      _measured[n] = true;
    }
  }

  /// A line that was covered and no longer is.
  void uncover(int line, int length) {
    if (line < _heights.length && _heights[line] == 0 && _measured[line]) {
      _heights[line] = _estimate(length);
      _measured[line] = false;
      _sums = null;
    }
  }

  bool isMeasured(int line) => _measured[line];

  double heightOf(int line) => _heights[line];

  /// Records what line `line` was laid out to. Answers whether that changed anything.
  bool setMeasured(int line, double height) {
    _measured[line] = true;
    if ((_heights[line] - height).abs() < 0.001) return false;
    _heights[line] = height;
    _sums = null;
    return true;
  }

  Float64List get _running {
    var sums = _sums;
    if (sums != null) return sums;
    sums = Float64List(_heights.length + 1);
    var total = 0.0;
    for (var i = 1; i < _heights.length; i++) {
      sums[i] = total;
      total += _heights[i];
    }
    sums[_heights.length] = total;
    return _sums = sums;
  }

  /// The height of everything.
  double get total => _running[_heights.length];

  /// How far down line `line` starts.
  double offsetOf(int line) => _running[line.clamp(1, _heights.length)];

  /// The line at `offset` down: the last line that starts at or before it.
  int lineAt(double offset) {
    final sums = _running;
    var low = 1, high = lines;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (sums[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}
