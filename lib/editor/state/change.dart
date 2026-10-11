/// Changes to a document and what they do to positions in it: CodeMirror's `ChangeDesc`, `ChangeSet`, `MapMode` and
/// `ChangeSpec` (@codemirror/state, change.ts), ported line for line.
///
/// What differs from the TypeScript, all of it Dart's typing:
/// - a change written as `{from, to, insert}` is a [ChangeSpec] (`ChangeSpec(from: 3, insert: 'x')`); where
///   CodeMirror takes "a spec, a set, or an array of them" the parameter is an `Object?` and a `List` nests as it
///   does there;
/// - `mapPos` with a tracking mode can return null, so it is its own method, [ChangeDesc.mapPosTracked]; plain
///   [ChangeDesc.mapPos] always returns a position;
/// - `touchesRange` answers with a [Touch] where CodeMirror answers `false | true | "cover"`.
library;

import 'text.dart';

/// CodeMirror's `MapMode`: what mapping a position does when the text around it was deleted.
enum MapMode {
  /// Map to a valid new position even when its context was deleted.
  simple,

  /// Null when a deletion happens across the position.
  trackDel,

  /// Null when the character before the position is deleted.
  trackBefore,

  /// Null when the character after the position is deleted.
  trackAfter,
}

/// What [ChangeDesc.touchesRange] found: CodeMirror's `false`, `true` and `"cover"`.
enum Touch {
  /// No change touches the range.
  none,

  /// A change touches it.
  touches,

  /// One change covers the whole of it.
  cover;

  /// Whether anything touched the range: CodeMirror's truthiness of the answer.
  bool get touched => this != none;
}

/// Called for each unchanged stretch by [ChangeDesc.iterGaps].
typedef GapCallback = void Function(int posA, int posB, int length);

/// Called for each changed range by [ChangeDesc.iterChangedRanges].
typedef ChangedRangeCallback = void Function(int fromA, int toA, int fromB, int toB);

/// Called for each change by [ChangeSet.iterChanges], with the text it put in.
typedef ChangeCallback = void Function(int fromA, int toA, int fromB, int toB, Doc inserted);

/// CodeMirror's `ChangeDesc`: a change set without the inserted text. It cannot be applied, but positions map
/// through it and it is cheap to keep.
class ChangeDesc {
  // Sections are encoded as pairs of integers. The first is the length in the current document, and the second is -1
  // for unaffected sections, and the length of the replacement content otherwise. So an insertion would be (0, n>0),
  // a deletion (n>0, 0), and a replacement two positive numbers.
  ChangeDesc._(this.sections);

  /// CodeMirror's `ChangeDesc.create`, internal there; the encoding is in the comment above.
  factory ChangeDesc.create(List<int> sections) = ChangeDesc._;

  /// The encoded sections, pairs of (length, inserted length or -1). Not to be changed.
  final List<int> sections;

  /// The length of the document before the change.
  int get length {
    var result = 0;
    for (var i = 0; i < sections.length; i += 2) {
      result += sections[i];
    }
    return result;
  }

  /// The length of the document after the change.
  int get newLength {
    var result = 0;
    for (var i = 0; i < sections.length; i += 2) {
      final ins = sections[i + 1];
      result += ins < 0 ? sections[i] : ins;
    }
    return result;
  }

  /// True when nothing changes (CodeMirror's `empty`).
  bool get empty => sections.isEmpty || sections.length == 2 && sections[1] < 0;

  /// Calls `f` for each unchanged stretch: where it was (`posA`), where it is now (`posB`), how long.
  void iterGaps(GapCallback f) {
    for (var i = 0, posA = 0, posB = 0; i < sections.length;) {
      final len = sections[i++], ins = sections[i++];
      if (ins < 0) {
        f(posA, posB, len);
        posB += len;
      } else {
        posB += ins;
      }
      posA += len;
    }
  }

  /// Calls `f` for each changed range, in the old document (`fromA`/`toA`) and the new (`fromB`/`toB`). Adjacent
  /// changes are joined unless `individual`.
  void iterChangedRanges(ChangedRangeCallback f, [bool individual = false]) {
    _iterChanges(this, (fromA, toA, fromB, toB, _) => f(fromA, toA, fromB, toB), individual);
  }

  /// The description of the change that undoes this one.
  ChangeDesc get invertedDesc {
    final sections = <int>[];
    for (var i = 0; i < this.sections.length;) {
      final len = this.sections[i++], ins = this.sections[i++];
      if (ins < 0) {
        sections
          ..add(len)
          ..add(ins);
      } else {
        sections
          ..add(ins)
          ..add(len);
      }
    }
    return ChangeDesc._(sections);
  }

  /// This description followed by `other`, which must start where this one ends.
  ChangeDesc composeDesc(ChangeDesc other) => empty
      ? other
      : other.empty
      ? this
      : _composeSets(this, other);

  /// This description moved over `other`, which starts in the same document. When both insert at one place, this
  /// one's insertion comes first when `before`.
  ChangeDesc mapDesc(ChangeDesc other, [bool before = false]) => other.empty ? this : _mapSet(this, other, before);

  /// Where `pos` is after these changes. `assoc` says which side of an insertion at `pos` it stays on: before it
  /// (-1, the default) or after it (1).
  int mapPos(int pos, [int assoc = -1]) => mapPosTracked(pos, assoc, MapMode.simple)!;

  /// CodeMirror's `mapPos` with a `mode`: null when the mode says the position was deleted.
  int? mapPosTracked(int pos, [int assoc = -1, MapMode mode = MapMode.simple]) {
    var posA = 0, posB = 0;
    for (var i = 0; i < sections.length;) {
      final len = sections[i++], ins = sections[i++], endA = posA + len;
      if (ins < 0) {
        if (endA > pos) return posB + (pos - posA);
        posB += len;
      } else {
        if (mode != MapMode.simple &&
            endA >= pos &&
            (mode == MapMode.trackDel && posA < pos && endA > pos ||
                mode == MapMode.trackBefore && posA < pos ||
                mode == MapMode.trackAfter && endA > pos)) {
          return null;
        }
        if (endA > pos || endA == pos && assoc < 0 && len == 0) return pos == posA || assoc < 0 ? posB : posB + ins;
        posB += ins;
      }
      posA = endA;
    }
    if (pos > posA) throw RangeError('Position $pos is out of range for changeset of length $posA');
    return posB;
  }

  /// Whether a change touches `from`-`to`, and whether one covers it whole.
  Touch touchesRange(int from, [int? to]) {
    to ??= from;
    for (var i = 0, pos = 0; i < sections.length && pos <= to;) {
      final len = sections[i++], ins = sections[i++], end = pos + len;
      if (ins >= 0 && pos <= to && end >= from) return pos < from && end > to ? Touch.cover : Touch.touches;
      pos = end;
    }
    return Touch.none;
  }

  @override
  String toString() {
    final result = StringBuffer();
    for (var i = 0; i < sections.length;) {
      final len = sections[i++], ins = sections[i++];
      if (result.isNotEmpty) result.write(' ');
      result.write(len);
      if (ins >= 0) result.write(':$ins');
    }
    return result.toString();
  }

  /// The sections, as CodeMirror's `toJSON` gives them.
  Object toJson() => sections;

  /// Reads what [toJson] wrote.
  static ChangeDesc fromJson(Object? json) {
    if (json is! List || json.length.isOdd || json.any((a) => a is! int)) {
      throw RangeError('Invalid JSON representation of ChangeDesc');
    }
    return ChangeDesc._(List<int>.from(json));
  }
}

/// CodeMirror's `ChangeSpec`: one replacement, written there as `{from, to, insert}`. A [ChangeSet] is one too, and
/// so is a `List` of them wherever a parameter is documented as taking "changes".
abstract interface class ChangeSpec {
  /// Replace `from`-`to` (`to` defaults to `from`) with `insert`: a `String`, a [Doc], or nothing for a deletion.
  const factory ChangeSpec({required int from, int? to, Object? insert}) = Change;
}

/// The plain-object form of [ChangeSpec].
class Change implements ChangeSpec {
  const Change({required this.from, this.to, this.insert});

  /// Where the replaced range starts.
  final int from;

  /// Where it ends; `from` when left out.
  final int? to;

  /// What goes in: a `String`, a [Doc], or null.
  final Object? insert;
}

/// CodeMirror's `ChangeSet`: changes to a document, with the text they insert.
class ChangeSet extends ChangeDesc implements ChangeSpec {
  ChangeSet._(super.sections, this.inserted) : super._();

  /// CodeMirror's `ChangeSet.createSet`, internal there.
  factory ChangeSet.createSet(List<int> sections, List<Doc> inserted) = ChangeSet._;

  /// The inserted text, one entry per section up to the last insertion. Not to be changed.
  final List<Doc> inserted;

  /// The document these changes make of `doc`, which must have the length they start from.
  Doc apply(Doc doc) {
    if (length != doc.length) throw RangeError('Applying change set to a document with the wrong length');
    _iterChanges(this, (fromA, toA, fromB, toB, text) => doc = doc.replace(fromB, fromB + (toA - fromA), text), false);
    return doc;
  }

  @override
  ChangeDesc mapDesc(ChangeDesc other, [bool before = false]) => _mapSet(this, other, before, true);

  /// The change set that undoes this one, given the document it was made for.
  ChangeSet invert(Doc doc) {
    final sections = List<int>.of(this.sections), inserted = <Doc>[];
    for (var i = 0, pos = 0; i < sections.length; i += 2) {
      final len = sections[i], ins = sections[i + 1];
      if (ins >= 0) {
        sections[i] = ins;
        sections[i + 1] = len;
        final index = i >> 1;
        while (inserted.length < index) {
          inserted.add(Doc.empty);
        }
        inserted.add(len > 0 ? doc.slice(pos, pos + len) : Doc.empty);
      }
      pos += len;
    }
    return ChangeSet._(sections, inserted);
  }

  /// These changes followed by `other`, which must start in the document these produce.
  ChangeSet compose(ChangeSet other) => empty
      ? other
      : other.empty
      ? this
      : _composeSets(this, other, true) as ChangeSet;

  /// These changes moved over `other`, so that they apply after it; both start in the same document. When both
  /// insert at one place, this set's insertion comes first when `before`.
  ChangeSet map(ChangeDesc other, [bool before = false]) => other.empty ? this : _mapSet(this, other, before, true) as ChangeSet;

  /// Calls `f` for each change with the text it inserts. Adjacent changes are joined unless `individual`.
  void iterChanges(ChangeCallback f, [bool individual = false]) => _iterChanges(this, f, individual);

  /// This set without its text.
  ChangeDesc get desc => ChangeDesc._(sections);

  /// Takes out the changes inside `ranges` (pairs of from, to): what is left, and a description of what was removed.
  ({ChangeSet changes, ChangeDesc filtered}) filter(List<int> ranges) {
    final resultSections = <int>[], resultInserted = <Doc>[], filteredSections = <int>[];
    final iter = _SectionIter(this);
    done:
    for (var i = 0, pos = 0;;) {
      final next = i == ranges.length ? 1000000000 : ranges[i++];
      while (pos < next || pos == next && iter.len == 0) {
        if (iter.done) break done;
        final len = iter.len < next - pos ? iter.len : next - pos;
        _addSection(filteredSections, len, -1);
        final ins = iter.ins == -1
            ? -1
            : iter.off == 0
            ? iter.ins
            : 0;
        _addSection(resultSections, len, ins);
        if (ins > 0) _addInsert(resultInserted, resultSections, iter.text);
        iter.forward(len);
        pos += len;
      }
      // CodeMirror reads past the array here on the last round, getting `undefined`, and its loop then does not run.
      final end = i < ranges.length ? ranges[i++] : -1;
      while (pos < end) {
        if (iter.done) break done;
        final len = iter.len < end - pos ? iter.len : end - pos;
        _addSection(resultSections, len, -1);
        _addSection(
          filteredSections,
          len,
          iter.ins == -1
              ? -1
              : iter.off == 0
              ? iter.ins
              : 0,
        );
        iter.forward(len);
        pos += len;
      }
    }
    return (changes: ChangeSet._(resultSections, resultInserted), filtered: ChangeDesc._(filteredSections));
  }

  /// CodeMirror's `toJSON`: a number for an unchanged stretch, `[length, ...inserted lines]` for a change.
  @override
  Object toJson() {
    final parts = <Object>[];
    for (var i = 0; i < sections.length; i += 2) {
      final len = sections[i], ins = sections[i + 1];
      if (ins < 0) {
        parts.add(len);
      } else if (ins == 0) {
        parts.add(<Object>[len]);
      } else {
        parts.add(<Object>[len, ...inserted[i >> 1].toJson()]);
      }
    }
    return parts;
  }

  /// A change set from "changes" (a [ChangeSpec], or a `List` of them, nested as deep as it likes) for a document of
  /// `length`. Every spec's positions are in the starting document, as in CodeMirror. `lineSep` splits inserted
  /// strings; the default is any of `\r\n`, `\r`, `\n`.
  static ChangeSet of(Object? changes, int length, [String? lineSep]) {
    var sections = <int>[], inserted = <Doc>[];
    var pos = 0;
    ChangeSet? total;
    void flush([bool force = false]) {
      if (!force && sections.isEmpty) return;
      if (pos < length) _addSection(sections, length - pos, -1);
      final set = ChangeSet._(sections, inserted);
      total = total != null ? total!.compose(set.map(total!)) : set;
      sections = <int>[];
      inserted = <Doc>[];
      pos = 0;
    }

    void process(Object? spec) {
      if (spec == null) return;
      if (spec is List) {
        for (final sub in spec) {
          process(sub);
        }
      } else if (spec is ChangeSet) {
        if (spec.length != length) {
          throw RangeError('Mismatched change set length (got ${spec.length}, expected $length)');
        }
        flush();
        total = total != null ? total!.compose(spec.map(total!)) : spec;
      } else if (spec is Change) {
        final from = spec.from, to = spec.to ?? spec.from, insert = spec.insert;
        if (from > to || from < 0 || to > length) {
          throw RangeError('Invalid change range $from to $to (in doc of length $length)');
        }
        final Doc insText;
        if (insert == null || insert == '') {
          insText = Doc.empty;
        } else if (insert is String) {
          insText = Doc.of(insert.split(lineSep ?? defaultSplit));
        } else if (insert is Doc) {
          insText = insert;
        } else {
          throw ArgumentError.value(insert, 'insert', 'A change inserts a String or a Doc');
        }
        final insLen = insText.length;
        if (from == to && insLen == 0) return;
        if (from < pos) flush();
        if (from > pos) _addSection(sections, from - pos, -1);
        _addSection(sections, to - from, insLen);
        _addInsert(inserted, sections, insText);
        pos = to;
      } else {
        throw ArgumentError.value(spec, 'changes', 'Not a ChangeSpec, a ChangeSet or a List of them');
      }
    }

    process(changes);
    flush(total == null);
    return total!;
  }

  /// A set that changes nothing in a document of `length`: CodeMirror's `ChangeSet.empty(length)`, renamed because
  /// Dart will not have a static beside the getter [empty].
  static ChangeSet emptyOf(int length) => ChangeSet._(length > 0 ? <int>[length, -1] : <int>[], <Doc>[]);

  /// Reads what [toJson] wrote.
  static ChangeSet fromJson(Object? json) {
    if (json is! List) throw RangeError('Invalid JSON representation of ChangeSet');
    final sections = <int>[], inserted = <Doc>[];
    for (var i = 0; i < json.length; i++) {
      final part = json[i];
      if (part is int) {
        sections
          ..add(part)
          ..add(-1);
      } else if (part is! List || part.isEmpty || part[0] is! int || part.skip(1).any((e) => e is! String)) {
        throw RangeError('Invalid JSON representation of ChangeSet');
      } else if (part.length == 1) {
        sections
          ..add(part[0] as int)
          ..add(0);
      } else {
        while (inserted.length < i) {
          inserted.add(Doc.empty);
        }
        final text = Doc.of(List<String>.from(part.skip(1)));
        inserted.add(text);
        sections
          ..add(part[0] as int)
          ..add(text.length);
      }
    }
    return ChangeSet._(sections, inserted);
  }
}

void _addSection(List<int> sections, int len, int ins, [bool forceJoin = false]) {
  if (len == 0 && ins <= 0) return;
  final last = sections.length - 2;
  if (last >= 0 && ins <= 0 && ins == sections[last + 1]) {
    sections[last] += len;
  } else if (last >= 0 && len == 0 && sections[last] == 0) {
    sections[last + 1] += ins;
  } else if (forceJoin) {
    sections[last] += len;
    sections[last + 1] += ins;
  } else {
    sections
      ..add(len)
      ..add(ins);
  }
}

void _addInsert(List<Doc> values, List<int> sections, Doc value) {
  if (value.length == 0) return;
  final index = (sections.length - 2) >> 1;
  if (index < values.length) {
    values[values.length - 1] = values[values.length - 1].append(value);
  } else {
    while (values.length < index) {
      values.add(Doc.empty);
    }
    values.add(value);
  }
}

void _iterChanges(ChangeDesc desc, ChangeCallback f, bool individual) {
  final inserted = desc is ChangeSet ? desc.inserted : null;
  final sections = desc.sections;
  for (var posA = 0, posB = 0, i = 0; i < sections.length;) {
    var len = sections[i++], ins = sections[i++];
    if (ins < 0) {
      posA += len;
      posB += len;
    } else {
      var endA = posA, endB = posB;
      var text = Doc.empty;
      for (;;) {
        endA += len;
        endB += ins;
        if (ins > 0 && inserted != null) text = text.append(inserted[(i - 2) >> 1]);
        if (individual || i == sections.length || sections[i + 1] < 0) break;
        len = sections[i++];
        ins = sections[i++];
      }
      f(posA, endA, posB, endB, text);
      posA = endA;
      posB = endB;
    }
  }
}

ChangeDesc _mapSet(ChangeDesc setA, ChangeDesc setB, bool before, [bool mkSet = false]) {
  // Produce a copy of setA that applies to the document after setB has been applied (assuming both start at the
  // same document).
  final sections = <int>[];
  final insert = mkSet ? <Doc>[] : null;
  final a = _SectionIter(setA), b = _SectionIter(setB);
  // Iterate over both sets in parallel. inserted tracks, for changes in A that have to be processed piece-by-piece,
  // whether their content has been inserted already, and refers to the section index.
  for (var inserted = -1;;) {
    if (a.done && b.len != 0 || b.done && a.len != 0) {
      throw StateError('Mismatched change set lengths');
    } else if (a.ins == -1 && b.ins == -1) {
      // Move across ranges skipped by both sets.
      final len = a.len < b.len ? a.len : b.len;
      _addSection(sections, len, -1);
      a.forward(len);
      b.forward(len);
    } else if (b.ins >= 0 && (a.ins < 0 || inserted == a.i || a.off == 0 && (b.len < a.len || b.len == a.len && !before))) {
      // If there's a change in B that comes before the next change in A (ordered by start pos, then len, then before
      // flag), skip that (and process any changes in A it covers).
      var len = b.len;
      _addSection(sections, b.ins, -1);
      while (len > 0) {
        final piece = a.len < len ? a.len : len;
        if (a.ins >= 0 && inserted < a.i && a.len <= piece) {
          _addSection(sections, 0, a.ins);
          if (insert != null) _addInsert(insert, sections, a.text);
          inserted = a.i;
        }
        a.forward(piece);
        len -= piece;
      }
      b.next();
    } else if (a.ins >= 0) {
      // Process the part of a change in A up to the start of the next non-deletion change in B (if overlapping).
      var len = 0, left = a.len;
      while (left > 0) {
        if (b.ins == -1) {
          final piece = left < b.len ? left : b.len;
          len += piece;
          left -= piece;
          b.forward(piece);
        } else if (b.ins == 0 && b.len < left) {
          left -= b.len;
          b.next();
        } else {
          break;
        }
      }
      _addSection(sections, len, inserted < a.i ? a.ins : 0);
      if (insert != null && inserted < a.i) _addInsert(insert, sections, a.text);
      inserted = a.i;
      a.forward(a.len - left);
    } else if (a.done && b.done) {
      return insert != null ? ChangeSet._(sections, insert) : ChangeDesc._(sections);
    } else {
      throw StateError('Mismatched change set lengths');
    }
  }
}

ChangeDesc _composeSets(ChangeDesc setA, ChangeDesc setB, [bool mkSet = false]) {
  final sections = <int>[];
  final insert = mkSet ? <Doc>[] : null;
  final a = _SectionIter(setA), b = _SectionIter(setB);
  for (var open = false;;) {
    if (a.done && b.done) {
      return insert != null ? ChangeSet._(sections, insert) : ChangeDesc._(sections);
    } else if (a.ins == 0) {
      // Deletion in A
      _addSection(sections, a.len, 0, open);
      a.next();
    } else if (b.len == 0 && !b.done) {
      // Insertion in B
      _addSection(sections, 0, b.ins, open);
      if (insert != null) _addInsert(insert, sections, b.text);
      b.next();
    } else if (a.done || b.done) {
      throw StateError('Mismatched change set lengths');
    } else {
      final len = a.len2 < b.len ? a.len2 : b.len, sectionLen = sections.length;
      if (a.ins == -1) {
        final insB = b.ins == -1
            ? -1
            : b.off != 0
            ? 0
            : b.ins;
        _addSection(sections, len, insB, open);
        if (insert != null && insB != 0) _addInsert(insert, sections, b.text);
      } else if (b.ins == -1) {
        _addSection(sections, a.off != 0 ? 0 : a.len, len, open);
        if (insert != null) _addInsert(insert, sections, a.textBit(len));
      } else {
        _addSection(sections, a.off != 0 ? 0 : a.len, b.off != 0 ? 0 : b.ins, open);
        if (insert != null && b.off == 0) _addInsert(insert, sections, b.text);
      }
      open = (a.ins > len || b.ins >= 0 && b.len > len) && (open || sections.length > sectionLen);
      a.forward2(len);
      b.forward(len);
    }
  }
}

class _SectionIter {
  _SectionIter(this.set) {
    next();
  }

  final ChangeDesc set;
  int i = 0;
  int len = 0;
  int ins = -2;
  int off = 0;

  void next() {
    final sections = set.sections;
    if (i < sections.length) {
      len = sections[i++];
      ins = sections[i++];
    } else {
      len = 0;
      ins = -2;
    }
    off = 0;
  }

  bool get done => ins == -2;

  int get len2 => ins < 0 ? len : ins;

  Doc get text {
    final inserted = (set as ChangeSet).inserted, index = (i - 2) >> 1;
    return index >= inserted.length ? Doc.empty : inserted[index];
  }

  Doc textBit(int len) {
    final inserted = (set as ChangeSet).inserted, index = (i - 2) >> 1;
    return index >= inserted.length && len == 0 ? Doc.empty : inserted[index].slice(off, off + len);
  }

  void forward(int len) {
    if (len == this.len) {
      next();
    } else {
      this.len -= len;
      off += len;
    }
  }

  void forward2(int len) {
    if (ins == -1) {
      forward(len);
    } else if (len == ins) {
      next();
    } else {
      ins -= len;
      off += len;
    }
  }
}
