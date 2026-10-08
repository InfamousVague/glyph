/// Ranges with values, kept sorted and moved through changes: CodeMirror's `RangeValue`, `Range`, `RangeSet`,
/// `RangeSetBuilder`, `RangeCursor`, `RangeComparator` and `SpanIterator` (@codemirror/state, rangeset.ts), ported
/// line for line. Decorations are range sets (`lib/editor/view/decoration.dart`).
///
/// A set is layers of chunks of at most 250 ranges; ranges that overlap one already in a layer spill into the next.
/// Mapping a set through a change touches only the chunks the change touches.
///
/// What Dart makes different:
/// - `RangeSet.empty` is [RangeSet.empty], a constructor: a set is typed by its values, so there is one empty set
///   per type and per call, and "is this the empty set" is [RangeSet.isEmpty], never identity;
/// - the static `RangeSet.iter(sets, from)` is [RangeSet.iterSets], because the instance has an [RangeSet.iter];
/// - a `between` callback stops the walk by returning `false`; one that returns nothing goes on.
library;

import 'change.dart';

const int _far = 1000000000; // C.Far
const int _chunkSize = 250; // C.ChunkSize

/// CodeMirror's `RangeValue`: what a range in a set carries. Subclasses say which side of their position they sit
/// on, whether they are points, and how they map.
abstract class RangeValue {
  const RangeValue();

  /// Whether this value is the same as `other`. Identity unless overridden; the set only asks values of one class.
  bool eq(RangeValue other) => identical(this, other);

  /// Which side of its start the range sits on, against others at the same position: lower comes first.
  int get startSide => 0;

  /// Which side of its end.
  int get endSide => 0;

  /// What happens to an empty range when the text around it is deleted.
  MapMode get mapMode => MapMode.trackDel;

  /// Whether this is a point: something that covers its range instead of styling it (a widget, a replacement).
  bool get point => false;

  /// A range holding this value.
  Range<RangeValue> range(int from, [int? to]) => Range<RangeValue>._(from, to ?? from, this);
}

bool _cmpVal(RangeValue a, RangeValue b) => identical(a, b) || a.runtimeType == b.runtimeType && a.eq(b);

/// CodeMirror's `Range`: a value and where it is.
class Range<T extends RangeValue> {
  Range._(this.from, this.to, this.value);

  /// CodeMirror's `Range.create`, internal there: `value.range(from, to)` is the usual way.
  factory Range.create(int from, int to, T value) = Range<T>._;

  final int from;
  final int to;
  final T value;

  @override
  String toString() => 'Range($from, $to, $value)';
}

int _cmpRange(Range<RangeValue> a, Range<RangeValue> b) {
  final d = a.from - b.from;
  return d != 0 ? d : a.value.startSide - b.value.startSide;
}

// JavaScript's sort is stable; Dart's is not promised to be. Ties keep the order they came in.
List<Range<T>> _sortedRanges<T extends RangeValue>(List<Range<T>> ranges) {
  final indexed = <(int, Range<T>)>[for (var i = 0; i < ranges.length; i++) (i, ranges[i])];
  indexed.sort((a, b) {
    final d = _cmpRange(a.$2, b.$2);
    return d != 0 ? d : a.$1 - b.$1;
  });
  return <Range<T>>[for (final e in indexed) e.$2];
}

class _Chunk<T extends RangeValue> {
  _Chunk(
    this.from,
    this.to,
    this.value,
    // Chunks are marked with the largest point that occurs in them (or -1 for no points), so that scans that are
    // only interested in points (such as the heightmap-related logic) can skip range-only chunks.
    this.maxPoint,
  );

  final List<int> from;
  final List<int> to;
  final List<T> value;
  final int maxPoint;

  int get length => to[to.length - 1];

  // Find the index of the given position and side. Use the ranges' `from` pos when `end == false`, `to` when
  // `end == true`.
  int findIndex(int pos, int side, bool end, [int startAt = 0]) {
    final arr = end ? to : from;
    for (var lo = startAt, hi = arr.length;;) {
      if (lo == hi) return lo;
      final mid = (lo + hi) >> 1;
      var diff = arr[mid] - pos;
      if (diff == 0) diff = (end ? value[mid].endSide : value[mid].startSide) - side;
      if (mid == lo) return diff >= 0 ? lo : hi;
      if (diff >= 0) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
  }

  bool between(int offset, int from, int to, bool? Function(int from, int to, T value) f) {
    for (var i = findIndex(from, -_far, true), e = findIndex(to, _far, false, i); i < e; i++) {
      if (f(this.from[i] + offset, this.to[i] + offset, value[i]) == false) return false;
    }
    return true;
  }

  ({_Chunk<T>? mapped, int pos}) map(int offset, ChangeDesc changes, int basePos, int baseSide, void Function(int from, int to, T value) spill) {
    final value = <T>[], from = <int>[], to = <int>[];
    var newPos = -1, maxPoint = -1;
    iter:
    for (var i = 0; i < this.value.length; i++) {
      final val = this.value[i], curFrom = this.from[i] + offset, curTo = this.to[i] + offset;
      int newFrom, newTo;
      if (curFrom == curTo) {
        final mapped = changes.mapPosTracked(curFrom, val.startSide, val.mapMode);
        if (mapped == null) continue;
        newFrom = newTo = mapped;
        if (val.startSide != val.endSide) {
          newTo = changes.mapPos(curFrom, val.endSide);
          if (newTo < newFrom) continue;
        }
      } else {
        newFrom = changes.mapPos(curFrom, val.startSide);
        newTo = changes.mapPos(curTo, val.endSide);
        if (newFrom > newTo || newFrom == newTo && val.startSide > 0 && val.endSide <= 0) continue;
      }
      if ((newTo - newFrom != 0 ? newTo - newFrom : val.endSide - val.startSide) < 0) continue;
      if (newPos < 0) newPos = newFrom;
      if (val.point && newTo - newFrom > maxPoint) maxPoint = newTo - newFrom;
      if ((newFrom - basePos != 0 ? newFrom - basePos : val.startSide - baseSide) >= 0) {
        value.add(val);
        from.add(newFrom - newPos);
        to.add(newTo - newPos);
        basePos = newTo;
        baseSide = val.endSide;
      } else {
        if (newFrom == newTo) {
          // Try to reorder points to fit in here
          for (var j = value.length; j > 0; j--) {
            final afterPrev = newFrom - (to[j - 1] + newPos);
            if ((afterPrev != 0 ? afterPrev : val.startSide - value[j - 1].endSide) >= 0) {
              value.insert(j, val);
              from.insert(j, newFrom - newPos);
              to.insert(j, newTo - newPos);
              continue iter;
            }
            final afterStart = newFrom - (from[j - 1] + newPos);
            if ((afterStart != 0 ? afterStart : val.endSide - value[j - 1].startSide) > 0) break;
          }
        }
        // Otherwise, spill into a new layer
        spill(newFrom, newTo, val);
      }
    }
    return (mapped: value.isNotEmpty ? _Chunk<T>(from, to, value, maxPoint) : null, pos: newPos);
  }
}

/// CodeMirror's `RangeCursor`: walks ranges in order. Past the end, [value] is null.
abstract class RangeCursor<T extends RangeValue> {
  /// Moves to the next range.
  void next();

  /// The current range's value, or null at the end.
  T? get value;

  /// Where the current range starts.
  int get from;

  /// Where it ends.
  int get to;
}

/// CodeMirror's `RangeComparator`: told where two collections of sets differ by [RangeSet.compare].
abstract class RangeComparator<T extends RangeValue> {
  /// The values covering `from`-`to` differ between the old sets and the new.
  void compareRange(int from, int to, List<T> activeA, List<T> activeB);

  /// A point differs: there is one on only one side, or two that are not equal.
  void comparePoint(int from, int to, T? pointA, T? pointB);

  /// Whether [boundChange] should be called: CodeMirror's "is the optional method there".
  bool get tracksBounds => false;

  /// The ranges covering `pos` are the same but start or end differently there.
  void boundChange(int pos) {}
}

/// CodeMirror's `SpanIterator`: told about each stretch of content by [RangeSet.spans].
abstract class SpanIterator<T extends RangeValue> {
  /// `from`-`to` is covered by `active`, of which the first `openStart` were open before `from`.
  void span(int from, int to, List<T> active, int openStart);

  /// A point covers `from`-`to`. `index` says which of the sets given it came from.
  void point(int from, int to, T value, List<T> active, int openStart, int index);
}

/// CodeMirror's `RangeSet`: an immutable collection of ranges with values.
class RangeSet<T extends RangeValue> {
  RangeSet._(this.chunkPos, this.chunk, this._nextLayer, this.maxPoint);

  /// The empty set: CodeMirror's `RangeSet.empty`.
  RangeSet.empty() : chunkPos = const <int>[], chunk = const [], _nextLayer = null, maxPoint = -1;

  final List<int> chunkPos;
  // ignore: library_private_types_in_public_api
  final List<_Chunk<T>> chunk;
  final RangeSet<T>? _nextLayer;
  final int maxPoint;

  /// The layer under this one; the empty set's is itself, as in CodeMirror.
  RangeSet<T> get nextLayer => _nextLayer ?? this;

  /// The end of the last range.
  int get length {
    final last = chunk.length - 1;
    if (last < 0) return 0;
    final end = chunkEnd(last), next = nextLayer.length;
    return end > next ? end : next;
  }

  /// How many ranges there are.
  int get size {
    if (isEmpty) return 0;
    var size = nextLayer.size;
    for (final c in chunk) {
      size += c.value.length;
    }
    return size;
  }

  int chunkEnd(int index) => chunkPos[index] + chunk[index].length;

  /// This set with ranges added and filtered out. `add` must be sorted by `from` and start side unless `sort`.
  /// `filter` is asked about each range between `filterFrom` and `filterTo`, and those it refuses are dropped.
  RangeSet<T> update({
    List<Range<T>> add = const [],
    bool sort = false,
    bool Function(int from, int to, T value)? filter,
    int filterFrom = 0,
    int? filterTo,
  }) {
    filterTo ??= length;
    if (add.isEmpty && filter == null) return this;
    if (sort) add = _sortedRanges(add);
    if (isEmpty) return add.isNotEmpty ? RangeSet.of<T>(add) : this;
    final cur = _LayerCursor<T>(this, null, -1)..goto(0);
    var i = 0;
    final spill = <Range<T>>[];
    final builder = RangeSetBuilder<T>();
    while (cur.value != null || i < add.length) {
      if (i < add.length && (cur.from - add[i].from != 0 ? cur.from - add[i].from : cur.startSide - add[i].value.startSide) >= 0) {
        final range = add[i++];
        if (!builder._addInner(range.from, range.to, range.value, false)) spill.add(range);
      } else if (cur.rangeIndex == 1 &&
          cur.chunkIndex < chunk.length &&
          (i == add.length || chunkEnd(cur.chunkIndex) < add[i].from) &&
          (filter == null || filterFrom > chunkEnd(cur.chunkIndex) || filterTo < chunkPos[cur.chunkIndex]) &&
          builder._addChunk(chunkPos[cur.chunkIndex], chunk[cur.chunkIndex])) {
        cur.nextChunk();
      } else {
        if (filter == null || filterFrom > cur.to || filterTo < cur.from || filter(cur.from, cur.to, cur.value as T)) {
          if (!builder._addInner(cur.from, cur.to, cur.value as T, false)) spill.add(Range<T>._(cur.from, cur.to, cur.value as T));
        }
        cur.next();
      }
    }
    return builder._finishInner(
      nextLayer.isEmpty && spill.isEmpty
          ? RangeSet<T>.empty()
          : nextLayer.update(add: spill, filter: filter, filterFrom: filterFrom, filterTo: filterTo),
    );
  }

  /// This set after `changes`: every range moved, the ones whose text is gone dropped.
  RangeSet<T> map(ChangeDesc changes) {
    if (changes.empty || isEmpty) return this;
    final chunks = <_Chunk<T>>[], chunkPos = <int>[];
    var maxPoint = -1;
    RangeSetBuilder<T>? spilled;
    void spill(int from, int to, T value) {
      (spilled ??= RangeSetBuilder<T>())._addRange(from, to, value, false);
    }

    for (var i = 0; i < chunk.length; i++) {
      final start = this.chunkPos[i], c = chunk[i];
      final touch = changes.touchesRange(start, start + c.length);
      if (touch == Touch.none) {
        if (c.maxPoint > maxPoint) maxPoint = c.maxPoint;
        chunks.add(c);
        chunkPos.add(changes.mapPos(start));
      } else if (touch == Touch.touches) {
        final prevPos = chunks.isEmpty ? -1 : chunkPos.last + chunks.last.length;
        final prevSide = chunks.isEmpty ? -1 : chunks.last.value.last.endSide;
        final result = c.map(start, changes, prevPos, prevSide, spill);
        final mapped = result.mapped;
        if (mapped != null) {
          if (mapped.maxPoint > maxPoint) maxPoint = mapped.maxPoint;
          chunks.add(mapped);
          chunkPos.add(result.pos);
        }
      }
    }
    var next = nextLayer.map(changes);
    if (spilled != null) next = spilled!._finishInner(next);
    return chunks.isEmpty ? next : RangeSet<T>._(chunkPos, chunks, next, maxPoint);
  }

  /// Calls `f` for every range that touches `from`-`to`, in no promised order across layers. `f` returning `false`
  /// stops the walk.
  void between(int from, int to, bool? Function(int from, int to, T value) f) {
    if (isEmpty) return;
    for (var i = 0; i < chunk.length; i++) {
      final start = chunkPos[i], c = chunk[i];
      if (to >= start && from <= start + c.length && !c.between(start, from - start, to - start, f)) return;
    }
    nextLayer.between(from, to, f);
  }

  /// A cursor over this set's ranges in order, from `from` on.
  RangeCursor<T> iter([int from = 0]) => _HeapCursor.of<T>(<RangeSet<T>>[this])..goto(from);

  /// Whether this is the empty set.
  bool get isEmpty => _nextLayer == null;

  /// CodeMirror's static `RangeSet.iter`: a cursor over several sets at once, in order.
  static RangeCursor<T> iterSets<T extends RangeValue>(List<RangeSet<T>> sets, [int from = 0]) => _HeapCursor.of<T>(sets)..goto(from);

  /// Tells `comparator` where the old sets and the new differ, the old ones moved through `textDiff` first. Chunks
  /// the two share are skipped unread.
  static void compare<T extends RangeValue>(
    List<RangeSet<T>> oldSets,
    List<RangeSet<T>> newSets,
    ChangeDesc textDiff,
    RangeComparator<T> comparator, [
    int minPointSize = -1,
  ]) {
    final a = <RangeSet<T>>[
      for (final set in oldSets)
        if (set.maxPoint > 0 || !set.isEmpty && set.maxPoint >= minPointSize) set,
    ];
    final b = <RangeSet<T>>[
      for (final set in newSets)
        if (set.maxPoint > 0 || !set.isEmpty && set.maxPoint >= minPointSize) set,
    ];
    final sharedChunks = _findSharedChunks(a, b, textDiff);
    final sideA = _SpanCursor<T>(a, sharedChunks, minPointSize);
    final sideB = _SpanCursor<T>(b, sharedChunks, minPointSize);
    textDiff.iterGaps((fromA, fromB, length) => _compare(sideA, fromA, sideB, fromB, length, comparator));
    if (textDiff.empty && textDiff.length == 0) _compare(sideA, 0, sideB, 0, 0, comparator);
  }

  /// Whether two collections of sets hold the same ranges between `from` and `to`.
  static bool eq<T extends RangeValue>(List<RangeSet<T>> oldSets, List<RangeSet<T>> newSets, [int from = 0, int? to]) {
    to ??= _far - 1;
    final a = <RangeSet<T>>[
      for (final set in oldSets)
        if (!set.isEmpty && !newSets.any((s) => identical(s, set))) set,
    ];
    final b = <RangeSet<T>>[
      for (final set in newSets)
        if (!set.isEmpty && !oldSets.any((s) => identical(s, set))) set,
    ];
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    final sharedChunks = _findSharedChunks(a, b, null);
    final sideA = _SpanCursor<T>(a, sharedChunks, 0)..goto(from), sideB = _SpanCursor<T>(b, sharedChunks, 0)..goto(from);
    for (;;) {
      if (sideA.to != sideB.to ||
          !_sameValues(sideA.active, sideB.active) ||
          sideA.point != null && (sideB.point == null || !_cmpVal(sideA.point!, sideB.point!))) {
        return false;
      }
      if (sideA.to > to) return true;
      sideA.next();
      sideB.next();
    }
  }

  /// Walks `from`-`to` as stretches of content, telling `iterator` which values cover each and where the points
  /// are. Returns how many ranges were still open at the end.
  static int spans<T extends RangeValue>(List<RangeSet<T>> sets, int from, int to, SpanIterator<T> iterator, [int minPointSize = -1]) {
    final cursor = _SpanCursor<T>(sets, null, minPointSize)..goto(from);
    var pos = from;
    var openRanges = cursor.openStart;
    for (;;) {
      final curTo = cursor.to < to ? cursor.to : to;
      final point = cursor.point;
      if (point != null) {
        final active = cursor.activeForPoint(cursor.to);
        final openCount = cursor.pointFrom < from
            ? active.length + 1
            : point.startSide < 0
            ? active.length
            : (active.length < openRanges ? active.length : openRanges);
        iterator.point(pos, curTo, point, active, openCount, cursor.pointRank);
        final open = cursor.openEnd(curTo);
        openRanges = open < active.length ? open : active.length;
      } else if (curTo > pos) {
        iterator.span(pos, curTo, cursor.active, openRanges);
        openRanges = cursor.openEnd(curTo);
      }
      if (cursor.to > to) return openRanges + (cursor.point != null && cursor.to > to ? 1 : 0);
      pos = cursor.to;
      cursor.next();
    }
  }

  /// A set of these ranges, which must be sorted by `from` and start side unless `sort`.
  static RangeSet<T> of<T extends RangeValue>(List<Range<T>> ranges, [bool sort = false]) {
    final build = RangeSetBuilder<T>();
    for (final range in sort ? _lazySort(ranges) : ranges) {
      build.add(range.from, range.to, range.value);
    }
    return build.finish();
  }

  /// One set with every layer of `sets` in it.
  static RangeSet<T> join<T extends RangeValue>(List<RangeSet<T>> sets) {
    if (sets.isEmpty) return RangeSet<T>.empty();
    var result = sets.last;
    for (var i = sets.length - 2; i >= 0; i--) {
      for (var layer = sets[i]; !layer.isEmpty; layer = layer.nextLayer) {
        result = RangeSet<T>._(layer.chunkPos, layer.chunk, result, layer.maxPoint > result.maxPoint ? layer.maxPoint : result.maxPoint);
      }
    }
    return result;
  }
}

List<Range<T>> _lazySort<T extends RangeValue>(List<Range<T>> ranges) {
  if (ranges.length > 1) {
    for (var prev = ranges[0], i = 1; i < ranges.length; i++) {
      final cur = ranges[i];
      if (_cmpRange(prev, cur) > 0) return _sortedRanges(ranges);
      prev = cur;
    }
  }
  return ranges;
}

/// CodeMirror's `RangeSetBuilder`: makes a set from ranges added in order.
class RangeSetBuilder<T extends RangeValue> {
  final List<_Chunk<T>> _chunks = <_Chunk<T>>[];
  final List<int> _chunkPos = <int>[];
  int _chunkStart = -1;
  T? _last;
  int _lastFrom = -_far;
  int _lastTo = -_far;
  List<int> _from = <int>[];
  List<int> _to = <int>[];
  List<T> _value = <T>[];
  int _maxPoint = -1;
  int _setMaxPoint = -1;
  RangeSetBuilder<T>? _nextLayer;
  bool _finished = false;

  void _finishChunk(bool newArrays) {
    _chunks.add(_Chunk<T>(_from, _to, _value, _maxPoint));
    _chunkPos.add(_chunkStart);
    _chunkStart = -1;
    if (_maxPoint > _setMaxPoint) _setMaxPoint = _maxPoint;
    _maxPoint = -1;
    if (newArrays) {
      _from = <int>[];
      _to = <int>[];
      _value = <T>[];
    }
  }

  /// Adds a range. Ranges must come sorted by `from`, then by their value's start side.
  void add(int from, int to, T value) => _addRange(from, to, value, true);

  void _addRange(int from, int to, T value, bool strict) {
    if (!_addInner(from, to, value, strict)) (_nextLayer ??= RangeSetBuilder<T>())._addRange(from, to, value, strict);
  }

  bool _addInner(int from, int to, T value, bool strict) {
    // CodeMirror nulls its arrays when the set is finished, so that a later `add` fails; this says why.
    if (_finished) throw StateError('This RangeSetBuilder was already finished');
    final last = _last;
    var diff = from - _lastTo;
    if (diff == 0) diff = value.startSide - last!.endSide;
    if (strict && diff <= 0) {
      var order = from - _lastFrom;
      if (order == 0) order = value.startSide - last!.startSide;
      if (order < 0) throw StateError('Ranges must be added sorted by `from` position and `startSide`');
    }
    if (diff < 0) return false;
    if (_from.length == _chunkSize) _finishChunk(true);
    if (_chunkStart < 0) _chunkStart = from;
    _from.add(from - _chunkStart);
    _to.add(to - _chunkStart);
    _last = value;
    _lastFrom = from;
    _lastTo = to;
    _value.add(value);
    if (value.point && to - from > _maxPoint) _maxPoint = to - from;
    return true;
  }

  bool _addChunk(int from, _Chunk<T> chunk) {
    var diff = from - _lastTo;
    if (diff == 0) diff = chunk.value[0].startSide - _last!.endSide;
    if (diff < 0) return false;
    if (_from.isNotEmpty) _finishChunk(true);
    if (chunk.maxPoint > _setMaxPoint) _setMaxPoint = chunk.maxPoint;
    _chunks.add(chunk);
    _chunkPos.add(from);
    final last = chunk.value.length - 1;
    _last = chunk.value[last];
    _lastFrom = chunk.from[last] + from;
    _lastTo = chunk.to[last] + from;
    return true;
  }

  /// The set. The builder cannot be used after this.
  RangeSet<T> finish() => _finishInner(RangeSet<T>.empty());

  RangeSet<T> _finishInner(RangeSet<T> next) {
    if (_from.isNotEmpty) _finishChunk(false);
    if (_chunks.isEmpty) return next;
    final result = RangeSet<T>._(_chunkPos, _chunks, _nextLayer != null ? _nextLayer!._finishInner(next) : next, _setMaxPoint);
    _finished = true; // Make sure further `add` calls produce errors
    return result;
  }
}

Set<_Chunk<T>> _findSharedChunks<T extends RangeValue>(List<RangeSet<T>> a, List<RangeSet<T>> b, ChangeDesc? textDiff) {
  final inA = Map<_Chunk<T>, int>.identity();
  for (final set in a) {
    for (var i = 0; i < set.chunk.length; i++) {
      if (set.chunk[i].maxPoint <= 0) inA[set.chunk[i]] = set.chunkPos[i];
    }
  }
  final shared = Set<_Chunk<T>>.identity();
  for (final set in b) {
    for (var i = 0; i < set.chunk.length; i++) {
      final known = inA[set.chunk[i]];
      if (known != null &&
          (textDiff != null ? textDiff.mapPos(known) : known) == set.chunkPos[i] &&
          !(textDiff != null && textDiff.touchesRange(known, known + set.chunk[i].length).touched)) {
        shared.add(set.chunk[i]);
      }
    }
  }
  return shared;
}

abstract class _Cursor<T extends RangeValue> implements RangeCursor<T> {
  @override
  int from = 0;
  @override
  int to = 0;
  @override
  T? value;

  int get rank;
  int get startSide => value?.startSide ?? 0;
  void goto(int pos, [int side = -_far]);
  void forward(int pos, int side);
}

class _LayerCursor<T extends RangeValue> extends _Cursor<T> {
  _LayerCursor(this.layer, this.skip, this.minPoint, [this.rank = 0]);

  final RangeSet<T> layer;
  final Set<_Chunk<T>>? skip;
  final int minPoint;
  @override
  final int rank;

  int chunkIndex = 0;
  int rangeIndex = 0;

  int get endSide => value?.endSide ?? 0;

  @override
  void goto(int pos, [int side = -_far]) {
    chunkIndex = rangeIndex = 0;
    gotoInner(pos, side, false);
  }

  void gotoInner(int pos, int side, bool forward) {
    while (chunkIndex < layer.chunk.length) {
      final next = layer.chunk[chunkIndex];
      if (!(skip != null && skip!.contains(next) || layer.chunkEnd(chunkIndex) < pos || next.maxPoint < minPoint)) break;
      chunkIndex++;
      forward = false;
    }
    if (chunkIndex < layer.chunk.length) {
      final rangeIndex = layer.chunk[chunkIndex].findIndex(pos - layer.chunkPos[chunkIndex], side, true);
      if (!forward || this.rangeIndex < rangeIndex) setRangeIndex(rangeIndex);
    }
    next();
  }

  @override
  void forward(int pos, int side) {
    if ((to - pos != 0 ? to - pos : endSide - side) < 0) gotoInner(pos, side, true);
  }

  @override
  void next() {
    for (;;) {
      if (chunkIndex == layer.chunk.length) {
        from = to = _far;
        value = null;
        break;
      } else {
        final chunkPos = layer.chunkPos[chunkIndex], chunk = layer.chunk[chunkIndex];
        from = chunkPos + chunk.from[rangeIndex];
        to = chunkPos + chunk.to[rangeIndex];
        final v = value = chunk.value[rangeIndex];
        setRangeIndex(rangeIndex + 1);
        if (minPoint < 0 || v.point && to - from >= minPoint) break;
      }
    }
  }

  void setRangeIndex(int index) {
    if (index == layer.chunk[chunkIndex].value.length) {
      chunkIndex++;
      if (skip != null) {
        while (chunkIndex < layer.chunk.length && skip!.contains(layer.chunk[chunkIndex])) {
          chunkIndex++;
        }
      }
      rangeIndex = 0;
    } else {
      rangeIndex = index;
    }
  }

  void nextChunk() {
    chunkIndex++;
    rangeIndex = 0;
    next();
  }

  int compare(_LayerCursor<T> other) {
    var d = from - other.from;
    if (d != 0) return d;
    d = startSide - other.startSide;
    if (d != 0) return d;
    d = rank - other.rank;
    if (d != 0) return d;
    d = to - other.to;
    if (d != 0) return d;
    return endSide - other.endSide;
  }
}

class _HeapCursor<T extends RangeValue> extends _Cursor<T> {
  _HeapCursor(this.heap);

  final List<_LayerCursor<T>> heap;

  @override
  int rank = 0;

  static _Cursor<T> of<T extends RangeValue>(List<RangeSet<T>> sets, [Set<_Chunk<T>>? skip, int minPoint = -1]) {
    final heap = <_LayerCursor<T>>[];
    for (var i = 0; i < sets.length; i++) {
      for (var cur = sets[i]; !cur.isEmpty; cur = cur.nextLayer) {
        if (cur.maxPoint >= minPoint) heap.add(_LayerCursor<T>(cur, skip, minPoint, i));
      }
    }
    return heap.length == 1 ? heap[0] : _HeapCursor<T>(heap);
  }

  @override
  void goto(int pos, [int side = -_far]) {
    for (final cur in heap) {
      cur.goto(pos, side);
    }
    for (var i = heap.length >> 1; i >= 0; i--) {
      _heapBubble(heap, i);
    }
    next();
  }

  @override
  void forward(int pos, int side) {
    for (final cur in heap) {
      cur.forward(pos, side);
    }
    for (var i = heap.length >> 1; i >= 0; i--) {
      _heapBubble(heap, i);
    }
    if ((to - pos != 0 ? to - pos : value!.endSide - side) < 0) next();
  }

  @override
  void next() {
    if (heap.isEmpty) {
      from = to = _far;
      value = null;
      rank = -1;
    } else {
      final top = heap[0];
      from = top.from;
      to = top.to;
      value = top.value;
      rank = top.rank;
      if (top.value != null) top.next();
      _heapBubble(heap, 0);
    }
  }
}

void _heapBubble<T extends RangeValue>(List<_LayerCursor<T>> heap, int index) {
  if (index >= heap.length) return;
  for (final cur = heap[index];;) {
    var childIndex = (index << 1) + 1;
    if (childIndex >= heap.length) break;
    var child = heap[childIndex];
    if (childIndex + 1 < heap.length && child.compare(heap[childIndex + 1]) >= 0) {
      child = heap[childIndex + 1];
      childIndex++;
    }
    if (cur.compare(child) < 0) break;
    heap[childIndex] = cur;
    heap[index] = child;
    index = childIndex;
  }
}

class _SpanCursor<T extends RangeValue> {
  _SpanCursor(List<RangeSet<T>> sets, Set<_Chunk<T>>? skip, this.minPoint) : cursor = _HeapCursor.of<T>(sets, skip, minPoint);

  final _Cursor<T> cursor;
  final int minPoint;

  List<T> active = <T>[];
  final List<int> activeTo = <int>[];
  final List<int> activeRank = <int>[];
  int minActive = -1;

  // A currently active point range, if any
  T? point;
  int pointFrom = 0;
  int pointRank = 0;

  int to = -_far;
  int endSide = 0;
  // The amount of open active ranges at the start of the iterator. Not including points.
  int openStart = -1;

  void goto(int pos, [int side = -_far]) {
    cursor.goto(pos, side);
    // CodeMirror empties `active` in place; a list handed to a span callback before stays as it was here.
    active = <T>[];
    activeTo.clear();
    activeRank.clear();
    minActive = -1;
    to = pos;
    endSide = side;
    openStart = -1;
    next();
  }

  void forward(int pos, int side) {
    while (minActive > -1 && (activeTo[minActive] - pos != 0 ? activeTo[minActive] - pos : active[minActive].endSide - side) < 0) {
      removeActive(minActive);
    }
    cursor.forward(pos, side);
  }

  void removeActive(int index) {
    active.removeAt(index);
    activeTo.removeAt(index);
    activeRank.removeAt(index);
    minActive = _findMinIndex(active, activeTo);
  }

  void addActive(List<int>? trackOpen) {
    var i = 0;
    final value = cursor.value as T, to = cursor.to, rank = cursor.rank;
    // Organize active marks by rank first, then by size
    while (i < activeRank.length && (rank - activeRank[i] != 0 ? rank - activeRank[i] : to - activeTo[i]) > 0) {
      i++;
    }
    active.insert(i, value);
    activeTo.insert(i, to);
    activeRank.insert(i, rank);
    trackOpen?.insert(i, cursor.from);
    minActive = _findMinIndex(active, activeTo);
  }

  // After calling this, if `this.point` != null, the next range is a point. Otherwise, it's a regular range, covered
  // by `this.active`.
  void next() {
    final from = to, wasPoint = point;
    point = null;
    final trackOpen = openStart < 0 ? <int>[] : null;
    for (;;) {
      final a = minActive;
      if (a > -1 && (activeTo[a] - cursor.from != 0 ? activeTo[a] - cursor.from : active[a].endSide - cursor.startSide) < 0) {
        if (activeTo[a] > from) {
          to = activeTo[a];
          endSide = active[a].endSide;
          break;
        }
        removeActive(a);
        trackOpen?.removeAt(a);
      } else if (cursor.value == null) {
        to = endSide = _far;
        break;
      } else if (cursor.from > from) {
        to = cursor.from;
        endSide = cursor.startSide;
        break;
      } else {
        final nextVal = cursor.value as T;
        if (!nextVal.point) {
          // Opening a range
          addActive(trackOpen);
          cursor.next();
        } else if (wasPoint != null && cursor.to == to && cursor.from < cursor.to) {
          // Ignore any non-empty points that end precisely at the end of the prev point
          cursor.next();
        } else {
          // New point
          point = nextVal;
          pointFrom = cursor.from;
          pointRank = cursor.rank;
          to = cursor.to;
          endSide = nextVal.endSide;
          cursor.next();
          forward(to, endSide);
          break;
        }
      }
    }
    if (trackOpen != null) {
      openStart = 0;
      for (var i = trackOpen.length - 1; i >= 0 && trackOpen[i] < from; i--) {
        openStart++;
      }
    }
  }

  List<T> activeForPoint(int to) {
    if (active.isEmpty) return active;
    final result = <T>[];
    for (var i = active.length - 1; i >= 0; i--) {
      if (activeRank[i] < pointRank) break;
      if (activeTo[i] > to || activeTo[i] == to && active[i].endSide >= point!.endSide) result.add(active[i]);
    }
    return result.reversed.toList();
  }

  int openEnd(int to) {
    var open = 0;
    for (var i = activeTo.length - 1; i >= 0 && activeTo[i] > to; i--) {
      open++;
    }
    return open;
  }
}

void _compare<T extends RangeValue>(_SpanCursor<T> a, int startA, _SpanCursor<T> b, int startB, int length, RangeComparator<T> comparator) {
  a.goto(startA);
  b.goto(startB);
  final endB = startB + length;
  var pos = startB;
  final dPos = startB - startA;
  final bounds = comparator.tracksBounds;
  for (var boundChange = false;;) {
    final dEnd = (a.to + dPos) - b.to, diff = dEnd != 0 ? dEnd : a.endSide - b.endSide;
    final end = diff < 0 ? a.to + dPos : b.to, clipEnd = end < endB ? end : endB;
    final aPoint = a.point, bPoint = b.point;
    if (aPoint != null || bPoint != null) {
      if (!(aPoint != null && bPoint != null && _cmpVal(aPoint, bPoint) && _sameValues(a.activeForPoint(a.to), b.activeForPoint(b.to)))) {
        comparator.comparePoint(pos, clipEnd, aPoint, bPoint);
      }
      boundChange = false;
    } else {
      if (boundChange) comparator.boundChange(pos);
      if (clipEnd > pos && !_sameValues(a.active, b.active)) comparator.compareRange(pos, clipEnd, a.active, b.active);
      if (bounds && clipEnd < endB && (dEnd != 0 || a.openEnd(end) != b.openEnd(end))) boundChange = true;
    }
    if (end > endB) break;
    pos = end;
    if (diff <= 0) a.next();
    if (diff >= 0) b.next();
  }
}

bool _sameValues(List<RangeValue> a, List<RangeValue> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i]) && !_cmpVal(a[i], b[i])) return false;
  }
  return true;
}

int _findMinIndex(List<RangeValue> value, List<int> array) {
  var found = -1, foundPos = _far;
  for (var i = 0; i < array.length; i++) {
    final d = array[i] - foundPos;
    if ((d != 0 ? d : value[i].endSide - value[found].endSide) < 0) {
      found = i;
      foundPos = array[i];
    }
  }
  return found;
}
