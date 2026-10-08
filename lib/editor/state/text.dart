/// The note's text as a tree of lines: CodeMirror's `Text` (@codemirror/state, text.ts), ported by structure.
///
/// It is called [Doc] here because Flutter already has a `Text`. Everything else keeps its name: `lineAt`, `line`,
/// `replace`, `slice`, `sliceString`, `iter`, `iterRange`, `iterLines`, `eq`, `toJson`, `Doc.of`, `Doc.empty`. Offsets
/// are UTF-16 code units, which is what a Dart `String` counts in too, so an offset from the web app's tests is the
/// same offset here. A line break counts as one unit whatever it was in the file.
///
/// The tree is CodeMirror's: leaves of at most 32 lines under nodes that keep themselves balanced, so replacing a
/// word in a 400 kB note copies one leaf and the path to it, not the note.
library;

const int _branch = 32; // Tree.Branch
const int _branchShift = 5; // Tree.BranchShift

const int _openFrom = 1; // Open.From
const int _openTo = 2; // Open.To

/// CodeMirror's `Text`: an immutable document, a tree of lines.
abstract class Doc {
  Doc._();

  /// The length of the text, line breaks counted as one unit each.
  int get length;

  /// How many lines there are; never less than one.
  int get lines;

  /// A node's children, or null for a leaf (CodeMirror's `children`).
  List<Doc>? get children;

  /// The line around `pos` (CodeMirror's `lineAt`).
  Line lineAt(int pos) {
    if (pos < 0 || pos > length) throw RangeError('Invalid position $pos in document of length $length');
    return _lineInner(pos, false, 1, 0);
  }

  /// The line with the given number, counted from 1 (CodeMirror's `line`).
  Line line(int n) {
    if (n < 1 || n > lines) throw RangeError('Invalid line number $n in $lines-line document');
    return _lineInner(n, true, 1, 0);
  }

  /// This text with `from`-`to` replaced by `text`.
  Doc replace(int from, int to, Doc text) => _replaceBase(from, to, text);

  Doc _replaceBase(int from, int to, Doc text) {
    from = _clipFrom(this, from);
    to = _clipTo(this, from, to);
    final parts = <Doc>[];
    _decompose(0, from, parts, _openTo);
    if (text.length > 0) text._decompose(0, text.length, parts, _openFrom | _openTo);
    _decompose(to, length, parts, _openFrom);
    return _TextNode.from(parts, length - (to - from) + text.length);
  }

  /// This text with `other` after it.
  Doc append(Doc other) => replace(length, length, other);

  /// The text between two points, as a [Doc].
  Doc slice(int from, [int? to]) {
    from = _clipFrom(this, from);
    final end = _clipTo(this, from, to ?? length);
    final parts = <Doc>[];
    _decompose(from, end, parts, 0);
    return _TextNode.from(parts, end - from);
  }

  /// The text between two points as a string, its lines joined by `lineSep`.
  String sliceString(int from, [int? to, String lineSep = '\n']);

  /// Whether this is the same text as `other` (CodeMirror's `eq`). Shared subtrees are skipped, not read.
  bool eq(Doc other) {
    if (identical(other, this)) return true;
    if (other.length != length || other.lines != lines) return false;
    final start = _scanIdentical(other, 1), end = length - _scanIdentical(other, -1);
    final a = _RawTextCursor(this), b = _RawTextCursor(other);
    for (var skip = start, pos = start;;) {
      a.next(skip);
      b.next(skip);
      skip = 0;
      if (a.lineBreak != b.lineBreak || a.done != b.done || a.value != b.value) return false;
      pos += a.value.length;
      if (a.done || pos >= end) return true;
    }
  }

  /// Walks the text, lines and the breaks between them as separate strings; backwards when `dir` is -1.
  TextIterator iter([int dir = 1]) => _RawTextCursor(this, dir);

  /// Walks a range of the text; in reverse when `from` is after `to`.
  TextIterator iterRange(int from, [int? to]) => _PartialTextCursor(this, from, to ?? length);

  /// Walks lines `from` up to (not including) `to`, both 1-based, without the breaks; an empty line is an empty string.
  TextIterator iterLines([int? from, int? to]) {
    TextIterator inner;
    if (from == null) {
      inner = iter();
    } else {
      to ??= lines + 1;
      final start = line(from).from;
      final end = to == lines + 1
          ? length
          : to <= 1
          ? 0
          : line(to - 1).to;
      inner = iterRange(start, start > end ? start : end);
    }
    return _LineCursor(inner);
  }

  /// The whole text, lines joined by `\n`.
  @override
  String toString() => sliceString(0);

  /// The lines as a list (CodeMirror's `toJSON`), which [Doc.of] reads back.
  List<String> toJson() {
    final lines = <String>[];
    _flatten(lines);
    return lines;
  }

  /// A document of these lines (CodeMirror's `Text.of`). There must be at least one.
  static Doc of(List<String> text) {
    if (text.isEmpty) throw RangeError('A document must have at least one line');
    if (text.length == 1 && text[0].isEmpty) return empty;
    return text.length <= _branch ? _TextLeaf(text) : _TextNode.from(_TextLeaf.split(text, <Doc>[]));
  }

  /// A document from a string, split where CodeMirror splits by default: `\r\n`, `\r` or `\n`.
  static Doc ofString(String text) => of(text.split(defaultSplit));

  /// The empty document (CodeMirror's `Text.empty`).
  static final Doc empty = _TextLeaf(<String>[''], 0);

  Line _lineInner(int target, bool isLine, int line, int offset);
  void _decompose(int from, int to, List<Doc> target, int open);
  void _flatten(List<String> target);
  int _scanIdentical(Doc other, int dir);
}

/// CodeMirror's `DefaultSplit`: the line breaks a pasted or loaded string is split on.
final RegExp defaultSplit = RegExp(r'\r\n?|\n');

// Leaves store an array of line strings. There are always line breaks between these strings. Leaves are limited in
// size and have to be contained in TextNode instances for bigger documents.
class _TextLeaf extends Doc {
  _TextLeaf(this.text, [int? length]) : length = length ?? _textLength(text), super._();

  final List<String> text;

  @override
  final int length;

  @override
  int get lines => text.length;

  @override
  List<Doc>? get children => null;

  @override
  Line _lineInner(int target, bool isLine, int line, int offset) {
    for (var i = 0; ; i++) {
      final string = text[i], end = offset + string.length;
      if ((isLine ? line : end) >= target) return Line._(offset, end, line, string);
      offset = end + 1;
      line++;
    }
  }

  @override
  void _decompose(int from, int to, List<Doc> target, int open) {
    final _TextLeaf text = from <= 0 && to >= length
        ? this
        : _TextLeaf(_sliceText(this.text, from, to), (to < length ? to : length) - (from > 0 ? from : 0));
    if (open & _openFrom != 0) {
      final prev = target.removeLast() as _TextLeaf;
      final joined = _appendText(text.text, List<String>.of(prev.text), 0, text.length);
      if (joined.length <= _branch) {
        target.add(_TextLeaf(joined, prev.length + text.length));
      } else {
        final mid = joined.length >> 1;
        target
          ..add(_TextLeaf(joined.sublist(0, mid)))
          ..add(_TextLeaf(joined.sublist(mid)));
      }
    } else {
      target.add(text);
    }
  }

  @override
  Doc replace(int from, int to, Doc text) {
    if (text is! _TextLeaf) return _replaceBase(from, to, text);
    from = _clipFrom(this, from);
    to = _clipTo(this, from, to);
    final lines = _appendText(this.text, _appendText(text.text, _sliceText(this.text, 0, from)), to);
    final newLen = length + text.length - (to - from);
    if (lines.length <= _branch) return _TextLeaf(lines, newLen);
    return _TextNode.from(split(lines, <Doc>[]), newLen);
  }

  @override
  String sliceString(int from, [int? to, String lineSep = '\n']) {
    from = _clipFrom(this, from);
    final end = _clipTo(this, from, to ?? length);
    final result = StringBuffer();
    for (var pos = 0, i = 0; pos <= end && i < text.length; i++) {
      final line = text[i], lineEnd = pos + line.length;
      if (pos > from && i > 0) result.write(lineSep);
      if (from < lineEnd && end > pos) {
        final a = from - pos > 0 ? from - pos : 0, b = end - pos < line.length ? end - pos : line.length;
        result.write(line.substring(a, b));
      }
      pos = lineEnd + 1;
    }
    return result.toString();
  }

  @override
  void _flatten(List<String> target) => target.addAll(text);

  @override
  int _scanIdentical(Doc other, int dir) => 0;

  static List<Doc> split(List<String> text, List<Doc> target) {
    var part = <String>[];
    var len = -1;
    for (final line in text) {
      part.add(line);
      len += line.length + 1;
      if (part.length == _branch) {
        target.add(_TextLeaf(part, len));
        part = <String>[];
        len = -1;
      }
    }
    if (len > -1) target.add(_TextLeaf(part, len));
    return target;
  }
}

// Nodes provide the tree structure of the `Text` type. They store a number of other nodes or leaves, taking care to
// balance themselves on changes. There are implied line breaks _between_ the children of a node (but not before the
// first or after the last child).
class _TextNode extends Doc {
  _TextNode(this.children, this.length) : lines = _countLines(children), super._();

  @override
  final List<Doc> children;

  @override
  final int length;

  @override
  final int lines;

  static int _countLines(List<Doc> children) {
    var lines = 0;
    for (final child in children) {
      lines += child.lines;
    }
    return lines;
  }

  @override
  Line _lineInner(int target, bool isLine, int line, int offset) {
    for (var i = 0; ; i++) {
      final child = children[i], end = offset + child.length, endLine = line + child.lines - 1;
      if ((isLine ? endLine : end) >= target) return child._lineInner(target, isLine, line, offset);
      offset = end + 1;
      line = endLine + 1;
    }
  }

  @override
  void _decompose(int from, int to, List<Doc> target, int open) {
    for (var i = 0, pos = 0; pos <= to && i < children.length; i++) {
      final child = children[i], end = pos + child.length;
      if (from <= end && to >= pos) {
        final childOpen = open & ((pos <= from ? _openFrom : 0) | (end >= to ? _openTo : 0));
        if (pos >= from && end <= to && childOpen == 0) {
          target.add(child);
        } else {
          child._decompose(from - pos, to - pos, target, childOpen);
        }
      }
      pos = end + 1;
    }
  }

  @override
  Doc replace(int from, int to, Doc text) {
    from = _clipFrom(this, from);
    to = _clipTo(this, from, to);
    if (text.lines < lines) {
      for (var i = 0, pos = 0; i < children.length; i++) {
        final child = children[i], end = pos + child.length;
        // Fast path: if the change only affects one child and the child's size remains in the acceptable range, only
        // update that child
        if (from >= pos && to <= end) {
          final updated = child.replace(from - pos, to - pos, text);
          final totalLines = lines - child.lines + updated.lines;
          if (updated.lines < (totalLines >> (_branchShift - 1)) && updated.lines > (totalLines >> (_branchShift + 1))) {
            final copy = List<Doc>.of(children);
            copy[i] = updated;
            return _TextNode(copy, length - (to - from) + text.length);
          }
          return _replaceBase(pos, end, updated);
        }
        pos = end + 1;
      }
    }
    return _replaceBase(from, to, text);
  }

  @override
  String sliceString(int from, [int? to, String lineSep = '\n']) {
    from = _clipFrom(this, from);
    final end = _clipTo(this, from, to ?? length);
    final result = StringBuffer();
    for (var i = 0, pos = 0; i < children.length && pos <= end; i++) {
      final child = children[i], childEnd = pos + child.length;
      if (pos > from && i > 0) result.write(lineSep);
      if (from < childEnd && end > pos) result.write(child.sliceString(from - pos, end - pos, lineSep));
      pos = childEnd + 1;
    }
    return result.toString();
  }

  @override
  void _flatten(List<String> target) {
    for (final child in children) {
      child._flatten(target);
    }
  }

  @override
  int _scanIdentical(Doc other, int dir) {
    if (other is! _TextNode) return 0;
    var length = 0;
    var iA = dir > 0 ? 0 : children.length - 1, iB = dir > 0 ? 0 : other.children.length - 1;
    final eA = dir > 0 ? children.length : -1, eB = dir > 0 ? other.children.length : -1;
    for (; ; iA += dir, iB += dir) {
      if (iA == eA || iB == eB) return length;
      final chA = children[iA], chB = other.children[iB];
      if (!identical(chA, chB)) return length + chA._scanIdentical(chB, dir);
      length += chA.length + 1;
    }
  }

  static Doc from(List<Doc> children, [int? knownLength]) {
    var length = knownLength ?? -1;
    if (knownLength == null) {
      for (final ch in children) {
        length += ch.length + 1;
      }
    }
    var lines = 0;
    for (final ch in children) {
      lines += ch.lines;
    }
    if (lines < _branch) {
      final flat = <String>[];
      for (final ch in children) {
        ch._flatten(flat);
      }
      return _TextLeaf(flat, length);
    }
    final chunk = _branch > (lines >> _branchShift) ? _branch : lines >> _branchShift;
    final maxChunk = chunk << 1, minChunk = chunk >> 1;
    final chunked = <Doc>[];
    var currentLines = 0, currentLen = -1;
    var currentChunk = <Doc>[];
    void flush() {
      if (currentLines == 0) return;
      chunked.add(currentChunk.length == 1 ? currentChunk[0] : from(currentChunk, currentLen));
      currentLen = -1;
      currentLines = 0;
      // CodeMirror empties the array in place; the node made above keeps its children, so this one is a new list.
      currentChunk = <Doc>[];
    }

    void add(Doc child) {
      if (child.lines > maxChunk && child is _TextNode) {
        for (final node in child.children) {
          add(node);
        }
      } else if (child.lines > minChunk && (currentLines > minChunk || currentLines == 0)) {
        flush();
        chunked.add(child);
      } else if (child is _TextLeaf &&
          currentLines > 0 &&
          currentChunk.last is _TextLeaf &&
          child.lines + currentChunk.last.lines <= _branch) {
        final last = currentChunk.last as _TextLeaf;
        currentLines += child.lines;
        currentLen += child.length + 1;
        currentChunk[currentChunk.length - 1] = _TextLeaf(<String>[...last.text, ...child.text], last.length + 1 + child.length);
      } else {
        if (currentLines + child.lines > chunk) flush();
        currentLines += child.lines;
        currentLen += child.length + 1;
        currentChunk.add(child);
      }
    }

    for (final child in children) {
      add(child);
    }
    flush();
    return chunked.length == 1 ? chunked[0] : _TextNode(chunked, length);
  }
}

int _textLength(List<String> text) {
  var length = -1;
  for (final line in text) {
    length += line.length + 1;
  }
  return length;
}

List<String> _appendText(List<String> text, List<String> target, [int from = 0, int to = 1000000000]) {
  for (var pos = 0, i = 0, first = true; i < text.length && pos <= to; i++) {
    var line = text[i];
    final end = pos + line.length;
    if (end >= from) {
      if (end > to) line = line.substring(0, to - pos);
      if (pos < from) line = line.substring(from - pos);
      if (first) {
        target[target.length - 1] += line;
        first = false;
      } else {
        target.add(line);
      }
    }
    pos = end + 1;
  }
  return target;
}

List<String> _sliceText(List<String> text, int from, int to) => _appendText(text, <String>[''], from, to);

int _clipFrom(Doc text, int from) => from < 0 ? 0 : (from > text.length ? text.length : from);

int _clipTo(Doc text, int clippedFrom, int to) {
  final t = to > text.length ? text.length : to;
  return t < clippedFrom ? clippedFrom : t;
}

/// CodeMirror's `TextIterator`: what [Doc.iter], [Doc.iterRange] and [Doc.iterLines] return. `next` moves on (first
/// skipping `skip` units) and returns the iterator itself, as it does in CodeMirror; [value], [done] and [lineBreak]
/// describe where it stands.
abstract class TextIterator {
  /// Moves to the next piece, skipping `skip` units first.
  TextIterator next([int skip = 0]);

  /// The current piece: a line's text (or part of it), or `\n` for a break.
  String get value;

  /// Whether the end was reached; [value] is then empty.
  bool get done;

  /// Whether the current piece is a line break.
  bool get lineBreak;

  /// The pieces from here on, for a `for` loop (JavaScript's iterator protocol on the cursor).
  Iterable<String> get rest sync* {
    while (!next().done) {
      yield value;
    }
  }
}

class _RawTextCursor extends TextIterator {
  _RawTextCursor(Doc text, [this.dir = 1]) : nodes = <Doc>[text], offsets = <int>[dir > 0 ? 1 : _size(text) << 1];

  final int dir;
  final List<Doc> nodes;
  final List<int> offsets;

  @override
  bool done = false;
  @override
  bool lineBreak = false;
  @override
  String value = '';

  static int _size(Doc node) => node is _TextLeaf ? node.text.length : node.children!.length;

  _RawTextCursor nextInner(int skip, int dir) {
    done = lineBreak = false;
    for (;;) {
      final last = nodes.length - 1;
      final top = nodes[last], offsetValue = offsets[last], offset = offsetValue >> 1;
      final size = _size(top);
      if (offset == (dir > 0 ? size : 0)) {
        if (last == 0) {
          done = true;
          value = '';
          return this;
        }
        if (dir > 0) offsets[last - 1]++;
        nodes.removeLast();
        offsets.removeLast();
      } else if ((offsetValue & 1) == (dir > 0 ? 0 : 1)) {
        offsets[last] += dir;
        if (skip == 0) {
          lineBreak = true;
          value = '\n';
          return this;
        }
        skip--;
      } else if (top is _TextLeaf) {
        // Move to the next string
        final next = top.text[offset + (dir < 0 ? -1 : 0)];
        offsets[last] += dir;
        if (next.length > (skip > 0 ? skip : 0)) {
          value = skip == 0
              ? next
              : dir > 0
              ? next.substring(skip)
              : next.substring(0, next.length - skip);
          return this;
        }
        skip -= next.length;
      } else {
        final next = top.children![offset + (dir < 0 ? -1 : 0)];
        if (skip > next.length) {
          skip -= next.length;
          offsets[last] += dir;
        } else {
          if (dir < 0) offsets[last]--;
          nodes.add(next);
          offsets.add(dir > 0 ? 1 : _size(next) << 1);
        }
      }
    }
  }

  @override
  _RawTextCursor next([int skip = 0]) {
    if (skip < 0) {
      nextInner(-skip, -dir);
      skip = value.length;
    }
    return nextInner(skip, dir);
  }
}

class _PartialTextCursor extends TextIterator {
  _PartialTextCursor(Doc text, int start, int end)
    : cursor = _RawTextCursor(text, start > end ? -1 : 1),
      pos = start > end ? text.length : 0,
      from = start < end ? start : end,
      to = start > end ? start : end;

  final _RawTextCursor cursor;
  int pos;
  final int from;
  final int to;

  @override
  String value = '';
  @override
  bool done = false;

  _PartialTextCursor nextInner(int skip, int dir) {
    if (dir < 0 ? pos <= from : pos >= to) {
      value = '';
      done = true;
      return this;
    }
    final gap = dir < 0 ? pos - to : from - pos;
    skip += gap > 0 ? gap : 0;
    var limit = dir < 0 ? pos - from : to - pos;
    if (skip > limit) skip = limit;
    limit -= skip;
    final v = cursor.next(skip).value;
    pos += (v.length + skip) * dir;
    value = v.length <= limit
        ? v
        : dir < 0
        ? v.substring(v.length - limit)
        : v.substring(0, limit);
    done = value.isEmpty;
    return this;
  }

  @override
  _PartialTextCursor next([int skip = 0]) {
    if (skip < 0) {
      if (skip < from - pos) skip = from - pos;
    } else if (skip > 0) {
      if (skip > to - pos) skip = to - pos;
    }
    return nextInner(skip, cursor.dir);
  }

  @override
  bool get lineBreak => cursor.lineBreak && value != '';
}

class _LineCursor extends TextIterator {
  _LineCursor(this.inner);

  final TextIterator inner;
  bool afterBreak = true;

  @override
  String value = '';
  @override
  bool done = false;

  @override
  _LineCursor next([int skip = 0]) {
    inner.next(skip);
    final done = inner.done, lineBreak = inner.lineBreak, value = inner.value;
    if (done && afterBreak) {
      this.value = '';
      afterBreak = false;
    } else if (done) {
      this.done = true;
      this.value = '';
    } else if (lineBreak) {
      if (afterBreak) {
        this.value = '';
      } else {
        afterBreak = true;
        next();
      }
    } else {
      this.value = value;
      afterBreak = false;
    }
    return this;
  }

  @override
  bool get lineBreak => false;
}

/// CodeMirror's `Line`: one line of a document, made when it is asked for ([Doc.lineAt], [Doc.line]).
class Line {
  Line._(this.from, this.to, this.number, this.text);

  /// Where the line starts.
  final int from;

  /// Where it ends: before its line break, or the end of the document for the last line.
  final int to;

  /// The line's number, counted from 1.
  final int number;

  /// The line's words, without its break.
  final String text;

  /// The line's length, without its break.
  int get length => to - from;

  @override
  String toString() => 'Line($number, $from-$to)';
}
