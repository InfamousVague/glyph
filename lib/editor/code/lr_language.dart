/// A language read by a Lezer grammar: the work of `lezer/lr.dart` on a block, and the classes
/// `lezer/highlight.dart` reads off it.
library;

import 'lezer/highlight.dart' as lezer;
import 'lezer/lr.dart';
import 'work.dart';

/// Which nodes of a parse are another language's: given the node's number, where it is, the code, and a cursor on
/// it (null for the top node, which is not in the record) to look around from with [RecordCursor.fork].
typedef Mounter = lezer.Mount<CodeLanguage>? Function(LrWork work, int id, int start, int end, RecordCursor? cursor);

class LrLanguage extends CodeLanguage {
  LrLanguage(super.name, this._load, {this.mounter});

  final LRParser Function() _load;

  /// The grammar, its tables decoded the first time a block needs them.
  late final LRParser parser = _load();

  final Mounter? mounter;

  @override
  CodeWork start(String code) {
    CodeStats.started++;
    return LrWork._(this, Parse(parser, code), null, 0, 0);
  }

  @override
  CodeWork resume(CodeWork old, String code) {
    if (old is! LrWork || !identical(old.language, this)) return start(code);
    final before = old.code, shorter = before.length < code.length ? before.length : code.length;
    var same = 0;
    while (same < shorter && before.codeUnitAt(same) == code.codeUnitAt(same)) {
      same++;
    }
    if (same == before.length && same == code.length) return old;
    final found = old._parse.checkpointBefore(same);
    if (found == null) {
      CodeStats.started++;
      return LrWork._(this, Parse(parser, code), old, same, code.length - before.length);
    }
    CodeStats.resumed++;
    return LrWork._(this, Parse.resume(parser, code, found.$1, found.$2), old, same, code.length - before.length);
  }
}

/// Another language's stretch of a block: its text, its work, and where each piece of the text is in the block.
class _Inner {
  _Inner(this.language, this.text, this.work, this.ranges);

  final CodeLanguage language;
  final String text;
  CodeWork work;

  /// The stretches of the block the text is made of, a start and an end for each; null when it is one stretch.
  final List<int>? ranges;
}

class LrWork extends CodeWork implements lezer.Nester<CodeLanguage> {
  LrWork._(this.language, this._parse, LrWork? carried, this._changedAt, this._delta) : _carried = carried?._inner, _read = _parse.parsedPos;

  @override
  final LrLanguage language;
  final Parse _parse;

  /// The other languages' stretches found so far, by where each starts in the block.
  final Map<int, _Inner> _inner = <int, _Inner>{};

  /// The ones the work this was resumed from had found, where the text changed and by how much: a stretch the
  /// change did not touch keeps its work.
  final Map<int, _Inner>? _carried;
  final int _changedAt, _delta;

  /// What the parse had read when its record was last asked for, and the record.
  int _viewAt = -1;
  ParsedCode? _view;
  int _read;

  /// The stretches of other languages not read to their ends, and how far each is wanted.
  bool _innerPending = false;
  Budget? _budget;

  @override
  String get code => _parse.stream.input;

  @override
  int get parsedTo => _parse.done != null ? code.length : _parse.parsedPos;

  @override
  bool get done => _parse.done != null && !_innerPending;

  @override
  void work(int upTo, Budget budget) {
    var steps = 0;
    while (_parse.done == null && _parse.parsedPos <= upTo) {
      _parse.advance();
      if ((++steps & 63) == 0 && budget.spent) break;
    }
    final now = parsedTo;
    if (now > _read) {
      CodeStats.read += now - _read;
      _read = now;
    }
    if (_innerPending && !budget.spent) {
      _innerPending = false;
      for (final inner in _inner.values) {
        if (inner.work.done) continue;
        inner.work.work(inner.text.length, budget);
        if (!inner.work.done) _innerPending = true;
      }
    }
  }

  ParsedCode get _parsed {
    final done = _parse.done;
    if (done != null) return done;
    final at = _parse.parsedPos;
    if (_view == null || _viewAt != at) {
      _view = _parse.snapshot();
      _viewAt = at;
    }
    return _view!;
  }

  @override
  void spans(int from, int to, SpanSink sink, {String inherited = '', Budget? budget}) {
    _budget = budget;
    lezer.highlightCode<CodeLanguage>(_parsed, from, to, sink, inherited: inherited, nester: language.mounter == null ? null : this);
    _budget = null;
  }

  /// A cursor at the end of what is read so far, for a [Mounter] that has to look through the whole record.
  RecordCursor cursor() => _parsed.cursor();

  Object? _memo;
  ParsedCode? _memoOf;

  /// Something a [Mounter] works out from the whole record, kept until more of the block is read.
  T memo<T extends Object>(T Function() compute) {
    final parsed = _parsed;
    if (!identical(_memoOf, parsed) || _memo is! T) {
      _memo = compute();
      _memoOf = parsed;
    }
    return _memo! as T;
  }

  /// Calls `each` for the named nodes directly inside the node `cursor` is on (inside the whole record, for a
  /// null cursor), last first, with a cursor on each that `each` must leave where it is. A repeat's node is not
  /// named: what is inside it is the node's own. Stops when `each` answers false.
  void eachChild(RecordCursor? cursor, bool Function(RecordCursor child) each) {
    final at = cursor == null ? this.cursor() : cursor.fork();
    final until = cursor == null ? 0 : at.pos - at.size;
    final minRepeat = parser.minRepeatTerm;
    if (cursor != null) at.next();
    while (at.pos > until) {
      final size = at.size;
      if (size < 0 || at.id >= minRepeat) {
        at.next();
        continue;
      }
      if (!each(at)) return;
      at.moveTo(at.pos - size);
    }
  }

  /// The grammar the block is read by.
  LRParser get parser => language.parser;

  @override
  lezer.Mount<CodeLanguage>? mountOn(int id, int start, int end, RecordCursor? cursor) => language.mounter!(this, id, start, end, cursor);

  @override
  void nested(lezer.Mount<CodeLanguage> mount, int start, int end, int from, int to, String inherited, SpanSink sink) {
    final ranges = mount.ranges;
    final key = ranges == null ? start : ranges[0];
    final String text;
    if (ranges == null) {
      text = code.substring(start, end);
    } else if (ranges.length == 2) {
      text = code.substring(ranges[0], ranges[1]);
    } else {
      final buffer = StringBuffer();
      for (var i = 0; i < ranges.length; i += 2) {
        buffer.write(code.substring(ranges[i], ranges[i + 1]));
      }
      text = buffer.toString();
    }
    var inner = _inner[key];
    if (inner == null || !identical(inner.language, mount.language) || inner.text != text) {
      final was = inner ?? _carried?[key < _changedAt ? key : key - _delta];
      final CodeWork work;
      if (was != null && identical(was.language, mount.language)) {
        work = was.text == text ? was.work : mount.language.resume(was.work, text);
      } else {
        work = mount.language.start(text);
      }
      inner = _inner[key] = _Inner(mount.language, text, work, ranges != null && ranges.length > 2 ? ranges : null);
    }
    // Where the stretch asked for is in the inner text, and back.
    final pieces = inner.ranges;
    if (pieces == null) {
      final base = key;
      final work = inner.work;
      if (work.parsedTo < to - base && !work.done) work.work(to - base, _budget ?? Budget.none());
      if (!work.done) _innerPending = true;
      work.spans(from - base, to - base, (a, b, cls) => sink(a + base, b + base, cls), inherited: inherited);
      return;
    }
    // Several stretches: the inner text is them end to end.
    var innerFrom = -1, innerTo = -1, at = 0;
    for (var i = 0; i < pieces.length; i += 2) {
      final a = pieces[i], b = pieces[i + 1];
      if (innerFrom < 0 && from < b) innerFrom = at + (from > a ? from - a : 0);
      if (to > a) innerTo = at + (to < b ? to - a : b - a);
      at += b - a;
    }
    if (innerFrom < 0 || innerTo <= innerFrom) return;
    final work = inner.work;
    if (work.parsedTo < innerTo && !work.done) work.work(innerTo, _budget ?? Budget.none());
    if (!work.done) _innerPending = true;
    work.spans(innerFrom, innerTo, (a, b, cls) {
      // A run may cross from one stretch to the next: a piece of it for each.
      var at = 0;
      for (var i = 0; i < pieces.length && at < b; i += 2) {
        final length = pieces[i + 1] - pieces[i];
        if (a < at + length) {
          final pieceFrom = pieces[i] + (a > at ? a - at : 0), pieceTo = pieces[i] + (b - at < length ? b - at : length);
          if (pieceTo > pieceFrom) sink(pieceFrom, pieceTo, cls);
        }
        at += length;
      }
    }, inherited: inherited);
  }
}
