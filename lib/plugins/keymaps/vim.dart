/// Vim, the Keyboard modes plugin's first way of typing (keymaps.dart; Matt, 2026-10-29: "add vim controls to the
/// app via a plugin as well"): its modes and its everyday keys, worked on a [KeyText] key by key, with nothing of
/// Flutter's or the editor's in it, so a test drives it with plain strings. The editor hands it keys by name
/// (editor_keys.dart): a character as itself (`w`, `$`, `W`), and [vimEscape], [vimEnter], [vimBackspace], [vimTab]
/// and [vimRedo] for the keys that type nothing.
///
/// What it has:
/// - **Normal**: `h j k l`, `w b e W B E ge`, `0 ^ $ g_ |`, `gg G`, `f F t T ; ,`, `{ }`, `%`, `+ - _` and Enter,
///   `gj gk` by the lines as drawn, counts (`3w`, `5j`); `i a I A o O`, `x X D C s S Y`, `dd cc yy >> <<`,
///   `d c y > <` with any motion or a text object (`iw aw iW aW`, quotes, brackets, `ip ap`), `p P`, `J`, `r`, `~`,
///   `u` and Ctrl-r through the note's own undo, `.` to repeat the last change, `ZZ ZQ`;
/// - **Insert**: the editor's own typing, untouched, until Esc (or Ctrl-[, or `jk` where that is switched on);
/// - **Visual**, by character (`v`) and by line (`V`): the motions and the text objects, `o`, and `d x y c s > < ~ u
///   U J p r` on what is selected;
/// - **the command line**: `/` and `?` with `n N * #`, and `:w`, `:q`, `:wq`, `:x`, `:q!`, a line's number, `:$`.
///
/// What it leaves out: registers other than the one it yanks to and puts from, marks, macros, `:s`, counts on an
/// insert (`3ix`), a text object with a count, and repeating a change made in Visual. A search is for the words as
/// typed, not a pattern, and is of any case while it is all lower case (smartcase).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'text.dart';

/// Vim's modes, with the words the badge shows for each.
enum VimMode {
  normal('NORMAL'),
  insert('INSERT'),
  visual('VISUAL'),
  visualLine('VISUAL LINE');

  const VimMode(this.label);

  final String label;

  bool get isVisual => this == VimMode.visual || this == VimMode.visualLine;
}

/// The names of the keys that type nothing.
const String vimEscape = '<Esc>';
const String vimEnter = '<CR>';
const String vimBackspace = '<BS>';
const String vimTab = '<Tab>';
const String vimRedo = '<C-r>';

/// What was yanked or deleted last, and whether it was whole lines.
@immutable
class VimRegister {
  const VimRegister(this.text, {this.linewise = false});
  final String text;
  final bool linewise;
}

/// A stretch an operator works on: [from] to [to] by character, or the lines [from] and [to] are on and those
/// between when [linewise].
class _Range {
  const _Range(this.from, this.to, {this.linewise = false});
  final int from;
  final int to;
  final bool linewise;
}

/// Where a motion went, whether it takes whole lines, and whether the place it went to is in what an operator takes.
class _Went {
  const _Went(this.to, {this.linewise = false, this.inclusive = false});
  final int to;
  final bool linewise;
  final bool inclusive;
}

/// A motion's keys as read: its name, its character where it takes one (`f`x), and where its keys end.
class _MotionKeys {
  const _MotionKeys(this.name, this.arg, this.end);
  final String name;
  final String? arg;
  final int end;
}

enum _Read { more, bad, done }

/// The motions that are one key.
const Set<String> _singleMotions = {'h', 'j', 'k', 'l', 'w', 'W', 'b', 'B', 'e', 'E', '0', '^', r'$', 'G', '|', '_', '+', '-', ';', ',', '{', '}', '%', 'n', 'N', '*', '#', vimBackspace, ' ', vimEnter};


/// How long `j` waits for the `k` of `jk` (Vim's `timeoutlen`).
const Duration vimJkWait = Duration(seconds: 1);

/// Vim over one text.
class VimEngine extends ChangeNotifier {
  VimEngine(this.target, {VimMode start = VimMode.normal, bool Function()? jk, DateTime Function()? now})
      : _mode = start == VimMode.insert ? VimMode.insert : VimMode.normal,
        _jk = jk ?? (() => false),
        _now = now ?? DateTime.now;

  final KeyText target;
  final bool Function() _jk;
  final DateTime Function() _now;

  VimMode _mode;
  VimMode get mode => _mode;

  /// The command line while it is open, with its first character (`:wq`, `/word`); null while it is not.
  String? get commandLine => _line;
  String? _line;

  /// A word for the person: a search that went round, a command not known. Gone with the next command.
  String? get message => _said;
  String? _said;

  /// The keys of a command typed so far (Vim's `showcmd`): `2d`, `ci`.
  String get pending => _keys.join();
  final List<String> _keys = [];

  /// What `p` puts.
  VimRegister? get register => _register;
  VimRegister? _register;

  /// Whether the engine is changing the text or the selection itself: what the editor hears meanwhile is its own.
  bool get busy => _busy > 0;
  int _busy = 0;

  // Visual's ends, each on a character.
  int _vAnchor = 0, _vHead = 0;

  // `j` and `k` keep their column; `$` keeps the line's end.
  int? _goal, _goalNext;

  ({String kind, String char})? _lastFind;
  ({String pattern, bool forward, bool whole})? _lastSearch;

  // The last change, for `.`: its keys, and what was typed after them where they began an insert.
  ({List<String> keys, String? inserted})? _lastChange;
  List<String>? _insertKeys;
  int _insertFrom = 0, _insertLength = 0;
  bool _replaying = false;

  // `jk`: where the `j` went in, and when.
  int? _jAt;
  DateTime? _jWhen;

  // The selection the engine last made, so that the editor's echo of it is not taken for the person's.
  int? _shownAnchor, _shownHead;

  /// One key, by its name. Answers whether Vim took it; a key it did not take is the editor's, as it always was.
  bool handle(String key) {
    final bool took;
    if (_line != null) {
      took = _lineKey(key);
    } else if (_mode == VimMode.insert) {
      took = _insertKey(key);
    } else {
      if (_keys.isEmpty) _said = null;
      _keys.add(key);
      if (_run() != _Read.more) _keys.clear();
      took = true;
    }
    if (took) notifyListeners();
    return took;
  }

  /// The selection was moved by something else (a pointer, the keyboard's own keys): a range selected in Normal is
  /// taken up as Visual, and a caret ends Visual.
  void moved(int anchor, int head) {
    if (anchor == _shownAnchor && head == _shownHead) return;
    _jAt = null;
    if (_mode == VimMode.insert || _line != null) return;
    _keys.clear();
    if (anchor == head) {
      if (_mode.isVisual) {
        _mode = VimMode.normal;
        notifyListeners();
      }
      return;
    }
    _vAnchor = anchor;
    _vHead = head > anchor ? head - 1 : head;
    if (_mode != VimMode.visualLine) _mode = VimMode.visual;
    notifyListeners();
  }

  /// Starts again in [mode], with nothing pending: the plugin switched, another way of typing chosen.
  void reset(VimMode mode) {
    _mode = mode == VimMode.insert ? VimMode.insert : VimMode.normal;
    _keys.clear();
    _line = null;
    _said = null;
    notifyListeners();
  }

  // ---- the text, through the target ------------------------------------------------------------------------------

  void _select(int anchor, int head) {
    _busy++;
    try {
      target.select(anchor, head);
    } finally {
      _busy--;
    }
    _shownAnchor = target.anchor;
    _shownHead = target.head;
  }

  bool _change(List<KeyEdit> edits, int caret) {
    if (target.readOnly) {
      _said = 'This note can’t be changed';
      return false;
    }
    _busy++;
    try {
      target.change(edits, caret);
    } finally {
      _busy--;
    }
    _shownAnchor = target.anchor;
    _shownHead = target.head;
    return true;
  }

  /// A caret on a character of its line, as Normal keeps it: never past the last, unless the line is empty.
  static int _onChar(String t, int p) {
    final at = p.clamp(0, t.length);
    final s = startOfLine(t, at), e = endOfLine(t, at);
    return e > s ? math.min(at, e - 1) : s;
  }

  /// Where the cursor is: Visual's moving end, or Normal's caret.
  int get _cursor => _mode.isVisual ? _vHead : _onChar(target.text, target.head);

  /// Puts the cursor at [p]: Normal's caret, or Visual's moving end.
  void _place(int p) {
    final t = target.text;
    if (_mode.isVisual) {
      _vHead = _onChar(t, p);
      _showVisual();
    } else {
      final at = _onChar(t, p);
      _select(at, at);
    }
  }

  void _showVisual() {
    final t = target.text, n = t.length;
    final lo = math.min(_vAnchor, _vHead), hi = math.max(_vAnchor, _vHead);
    if (_mode == VimMode.visualLine) {
      final s = startOfLine(t, lo), e = endOfLine(t, hi), past = e < n ? e + 1 : e;
      _vHead >= _vAnchor ? _select(s, past) : _select(past, s);
    } else {
      final end = math.min(hi + 1, n);
      _vHead >= _vAnchor ? _select(lo, end) : _select(end, lo);
    }
  }

  // ---- Insert ----------------------------------------------------------------------------------------------------

  bool _insertKey(String key) {
    if (key == vimEscape) {
      _leaveInsert();
      return true;
    }
    if (_jk()) {
      final at = _jAt, when = _jWhen;
      if (key == 'k' && at != null && when != null && _now().difference(when) <= vimJkWait) {
        final t = target.text;
        if (target.head == at + 1 && at < t.length && t[at] == 'j') {
          _jAt = null;
          _change([(from: at, to: at + 1, insert: '')], at);
          _leaveInsert();
          return true;
        }
      }
      if (key == 'j') {
        _jAt = math.min(target.anchor, target.head);
        _jWhen = _now();
      } else {
        _jAt = null;
      }
    }
    return false;
  }

  void _enterInsert(int at) {
    _mode = VimMode.insert;
    _select(at, at);
    _insertFrom = at;
    _insertLength = target.text.length;
    _jAt = null;
  }

  void _leaveInsert() {
    final t = target.text, head = target.head;
    if (!_replaying && _insertKeys != null) {
      final grown = t.length - _insertLength;
      final typed = grown >= 0 && head >= _insertFrom && head - _insertFrom == grown ? t.substring(_insertFrom, head) : null;
      _lastChange = (keys: _insertKeys!, inserted: typed ?? '');
    }
    _insertKeys = null;
    _mode = VimMode.normal;
    _jAt = null;
    _place(head > startOfLine(t, head) ? head - 1 : head);
  }

  // ---- Normal and Visual -----------------------------------------------------------------------------------------

  /// Reads [_keys] as one command and does it: [_Read.more] while it is not whole yet, [_Read.bad] for keys that
  /// are no command.
  _Read _run() {
    final k = _keys;
    var i = 0;
    int? count() {
      var digits = '';
      while (i < k.length && k[i].length == 1 && '0123456789'.contains(k[i]) && !(digits.isEmpty && k[i] == '0')) {
        digits += k[i++];
      }
      return digits.isEmpty ? null : int.parse(digits);
    }

    final c1 = count();
    if (i == k.length) return _Read.more;
    final first = k[i++];
    final visual = _mode.isVisual;
    _goalNext = null;
    final read = visual ? _visual(first, c1, k, i) : _normal(first, c1, k, i);
    if (read == _Read.done) _goal = _goalNext;
    if (read == _Read.bad) _goal = null;
    return read;
  }

  _Read _normal(String first, int? c1, List<String> k, int at) {
    var i = at;
    final n = c1 ?? 1;
    final t = target.text, c = _cursor;
    if (first == vimEscape) return _Read.done;
    if (first.length == 1 && 'dcy<>'.contains(first)) {
      var digits = '';
      while (i < k.length && k[i].length == 1 && '0123456789'.contains(k[i]) && !(digits.isEmpty && k[i] == '0')) {
        digits += k[i++];
      }
      if (i == k.length) return _Read.more;
      final c2 = digits.isEmpty ? null : int.parse(digits);
      final times = (c1 ?? 1) * (c2 ?? 1);
      final given = c1 == null && c2 == null ? null : times;
      final second = k[i++];
      if (second == first) {
        if (i != k.length) return _Read.bad;
        final last = startOfLineNumber(t, lineNumberAt(t, c) + times - 1);
        _operate(first, _Range(c, last, linewise: true), yankAt: c);
        _record(first != 'y');
        return _Read.done;
      }
      if (second == 'i' || second == 'a') {
        if (i == k.length) return _Read.more;
        final object = k[i++];
        if (i != k.length) return _Read.bad;
        final range = _object(second == 'a', object, c);
        if (range == null) return _Read.bad;
        _operate(first, range, yankAt: math.min(range.from, range.to));
        _record(first != 'y');
        return _Read.done;
      }
      final motion = _readMotion(k, i - 1);
      if (motion == null) return _Read.bad;
      if (motion.end > k.length) return _Read.more;
      if (motion.end != k.length) return _Read.bad;
      final range = _motionRange(first, motion, times, given);
      if (range == null) return _Read.bad;
      _operate(first, range, yankAt: math.min(range.from, range.to));
      _record(first != 'y');
      return _Read.done;
    }
    final s = startOfLine(t, c), e = endOfLine(t, c);
    switch (first) {
      case 'i':
        return _inserting(c);
      case 'a':
        return _inserting(e > c ? c + 1 : c);
      case 'I':
        return _inserting(firstNonBlank(t, c));
      case 'A':
        return _inserting(e);
      case 'o' || 'O':
        if (target.readOnly) return _refused();
        final indent = t.substring(s, firstNonBlank(t, c));
        if (first == 'o') {
          _change([(from: e, to: e, insert: '\n$indent')], e + 1 + indent.length);
        } else {
          _change([(from: s, to: s, insert: '$indent\n')], s + indent.length);
        }
        _enterInsert(target.head);
        _record(true);
        return _Read.done;
      case 'x':
        if (e == s) return _Read.done;
        _operate('d', _Range(c, math.min(c + n, e)), yankAt: c);
        _record(true);
        return _Read.done;
      case 'X':
        if (c == s) return _Read.done;
        _operate('d', _Range(math.max(s, c - n), c), yankAt: c);
        _record(true);
        return _Read.done;
      case 'D' || 'C':
        final end = endOfLine(t, startOfLineNumber(t, lineNumberAt(t, c) + n - 1));
        _operate(first == 'D' ? 'd' : 'c', _Range(c, end), yankAt: c);
        _record(true);
        return _Read.done;
      case 's':
        _operate('c', _Range(c, math.min(c + n, e)), yankAt: c);
        _record(true);
        return _Read.done;
      case 'S' || 'Y':
        final last = startOfLineNumber(t, lineNumberAt(t, c) + n - 1);
        _operate(first == 'S' ? 'c' : 'y', _Range(c, last, linewise: true), yankAt: c);
        _record(first == 'S');
        return _Read.done;
      case 'p' || 'P':
        if (_paste(first == 'p', n)) _record(true);
        return _Read.done;
      case 'J':
        if (_join(c, math.max(1, n - 1))) _record(true);
        return _Read.done;
      case 'r':
        if (i == k.length) return _Read.more;
        final char = k[i];
        if (char.length != 1 && char.runes.length != 1) return _Read.bad;
        if (c + n > e) return _Read.bad;
        if (_change([(from: c, to: c + n, insert: char * n)], c + n - 1)) _record(true);
        return _Read.done;
      case '~':
        if (e == s) return _Read.done;
        final to = math.min(c + n, e);
        if (_change([(from: c, to: to, insert: _toggled(t.substring(c, to)))], math.min(to, e - 1))) _record(true);
        return _Read.done;
      case 'u':
        _undo(n, redo: false);
        return _Read.done;
      case vimRedo:
        _undo(n, redo: true);
        return _Read.done;
      case '.':
        _repeat(c1);
        return _Read.done;
      case 'v':
        _mode = VimMode.visual;
        _vAnchor = _vHead = c;
        _showVisual();
        return _Read.done;
      case 'V':
        _mode = VimMode.visualLine;
        _vAnchor = _vHead = c;
        _showVisual();
        return _Read.done;
      case ':' || '/' || '?':
        _openLine(first);
        return _Read.done;
      case 'Z':
        if (i == k.length) return _Read.more;
        if (k[i] == 'Z') {
          target.save();
          target.close();
        } else if (k[i] == 'Q') {
          target.close();
        } else {
          return _Read.bad;
        }
        return _Read.done;
      case vimTab:
        return _Read.done;
    }
    return _moving(k, at - 1, n, c1);
  }

  _Read _inserting(int at) {
    if (target.readOnly) return _refused();
    _enterInsert(at);
    _record(true);
    return _Read.done;
  }

  _Read _refused() {
    _said = 'This note can’t be changed';
    return _Read.done;
  }

  /// A motion, alone: the cursor goes there.
  _Read _moving(List<String> k, int at, int n, int? given) {
    final motion = _readMotion(k, at);
    if (motion == null) return _Read.bad;
    if (motion.end > k.length) return _Read.more;
    if (motion.end != k.length) return _Read.bad;
    if ((motion.name == 'gj' || motion.name == 'gk') && !_mode.isVisual) {
      for (var j = 0; j < n; j++) {
        _busy++;
        try {
          if (!target.vertical(motion.name == 'gj', extend: false)) break;
        } finally {
          _busy--;
        }
      }
      _place(target.head);
      return _Read.done;
    }
    final went = _go(motion, n, given, _cursor);
    if (went == null) return _Read.bad;
    _place(went.to);
    return _Read.done;
  }

  _Read _visual(String first, int? c1, List<String> k, int at) {
    var i = at;
    final n = c1 ?? 1;
    switch (first) {
      case vimEscape:
        _leaveVisual();
        return _Read.done;
      case 'o':
        final was = _vAnchor;
        _vAnchor = _vHead;
        _vHead = was;
        _showVisual();
        return _Read.done;
      case 'v' || 'V':
        final wanted = first == 'v' ? VimMode.visual : VimMode.visualLine;
        if (_mode == wanted) {
          _leaveVisual();
        } else {
          _mode = wanted;
          _showVisual();
        }
        return _Read.done;
      case 'i' || 'a':
        if (i == k.length) return _Read.more;
        final range = _object(first == 'a', k[i], _vHead);
        if (range == null) return _Read.bad;
        if (range.linewise) {
          _mode = VimMode.visualLine;
          _vAnchor = range.from;
          _vHead = range.to;
        } else {
          if (range.to <= range.from) return _Read.bad;
          _vAnchor = range.from;
          _vHead = range.to - 1;
        }
        _showVisual();
        return _Read.done;
      case 'd' || 'x' || 'X' || 'D' || 'y' || 'Y' || 'c' || 's' || 'C' || 'S' || 'R':
        final lines = _mode == VimMode.visualLine || 'XDYCSR'.contains(first);
        final op = switch (first) { 'd' || 'x' || 'X' || 'D' => 'd', 'y' || 'Y' => 'y', _ => 'c' };
        final range = _visualRange(lines);
        _leaveVisual(keepCursor: false);
        _operate(op, range, yankAt: math.min(range.from, range.to));
        return _Read.done;
      case '>' || '<':
        final range = _visualRange(true);
        _leaveVisual(keepCursor: false);
        _indent(first == '>', range.from, range.to, n);
        return _Read.done;
      case '~' || 'u' || 'U':
        final range = _visualRange(_mode == VimMode.visualLine);
        _leaveVisual(keepCursor: false);
        _recase(first, range);
        return _Read.done;
      case 'J':
        final lo = math.min(_vAnchor, _vHead), hi = math.max(_vAnchor, _vHead), t = target.text;
        final joins = math.max(1, lineNumberAt(t, hi) - lineNumberAt(t, lo));
        _leaveVisual(keepCursor: false);
        _join(lo, joins);
        return _Read.done;
      case 'p' || 'P':
        final range = _visualRange(_mode == VimMode.visualLine);
        _leaveVisual(keepCursor: false);
        _replaceWithRegister(range);
        return _Read.done;
      case 'r':
        if (i == k.length) return _Read.more;
        final char = k[i];
        if (char.runes.length != 1) return _Read.bad;
        final range = _visualRange(_mode == VimMode.visualLine);
        _leaveVisual(keepCursor: false);
        final t = target.text;
        final (from, to) = _span(t, range);
        if (_change([(from: from, to: to, insert: t.substring(from, to).replaceAll(RegExp(r'[^\n]'), char))], from)) _place(from);
        return _Read.done;
      case ':':
        _leaveVisual();
        _openLine(':');
        return _Read.done;
      case '/' || '?':
        _openLine(first);
        return _Read.done;
    }
    return _moving(k, at - 1, n, c1);
  }

  void _leaveVisual({bool keepCursor = true}) {
    final head = _vHead;
    _mode = VimMode.normal;
    if (keepCursor) _place(head);
  }

  _Range _visualRange(bool lines) {
    final lo = math.min(_vAnchor, _vHead), hi = math.max(_vAnchor, _vHead);
    return lines ? _Range(lo, hi, linewise: true) : _Range(lo, math.min(hi + 1, target.text.length));
  }

  /// [r] as a stretch of the text: whole lines with the break after the last.
  (int, int) _span(String t, _Range r) {
    if (!r.linewise) return (r.from, r.to);
    return (startOfLine(t, math.min(r.from, r.to)), endOfLine(t, math.max(r.from, r.to)));
  }

  /// The last change becomes what `.` does again: its keys, and where they began an insert, what is typed until Esc.
  void _record(bool change) {
    if (!change || _replaying) return;
    if (_mode == VimMode.insert) {
      _insertKeys = [..._keys];
    } else {
      _lastChange = (keys: [..._keys], inserted: null);
    }
  }

  void _repeat(int? given) {
    final last = _lastChange;
    if (last == null) return;
    var keys = last.keys;
    if (given != null) {
      var i = 0;
      while (i < keys.length && keys[i].length == 1 && '0123456789'.contains(keys[i]) && !(i == 0 && keys[i] == '0')) {
        i++;
      }
      keys = [...given.toString().split(''), ...keys.sublist(i)];
    }
    _replaying = true;
    try {
      _keys.clear();
      for (final key in keys) {
        _keys.add(key);
        if (_run() != _Read.more) _keys.clear();
      }
      if (_mode == VimMode.insert) {
        final words = last.inserted ?? '';
        final at = target.head;
        if (words.isNotEmpty) _change([(from: at, to: at, insert: words)], at + words.length);
        _leaveInsert();
      }
    } finally {
      _replaying = false;
    }
  }

  void _undo(int n, {required bool redo}) {
    var any = false;
    for (var j = 0; j < n; j++) {
      _busy++;
      try {
        if (!(redo ? target.redo() : target.undo())) break;
      } finally {
        _busy--;
      }
      any = true;
    }
    if (!any) _said = redo ? 'Already at newest change' : 'Already at oldest change';
    _mode = VimMode.normal;
    _place(math.min(target.anchor, target.head));
  }

  // ---- motions ---------------------------------------------------------------------------------------------------

  /// The motion that starts at [at] in [k], or null where none does there. Its end is past [k] while it waits for
  /// a key.
  _MotionKeys? _readMotion(List<String> k, int at) {
    final key = k[at];
    if (key == 'g') {
      if (at + 1 >= k.length) return _MotionKeys('g', null, at + 2);
      final next = k[at + 1];
      return const {'g', 'e', 'E', 'j', 'k', '_'}.contains(next) ? _MotionKeys('g$next', null, at + 2) : null;
    }
    if (key == 'f' || key == 'F' || key == 't' || key == 'T') {
      if (at + 1 >= k.length) return _MotionKeys(key, null, at + 2);
      final arg = k[at + 1];
      return arg.runes.length == 1 ? _MotionKeys(key, arg, at + 2) : null;
    }
    return _singleMotions.contains(key) ? _MotionKeys(key, null, at + 1) : null;
  }

  /// Where [m] goes from [from], [n] times ([given] is the count as typed, which `G` and `gg` read as a line).
  _Went? _go(_MotionKeys m, int n, int? given, int from) {
    final t = target.text, len = t.length;
    switch (m.name) {
      case 'h' || vimBackspace:
        return _Went(math.max(startOfLine(t, from), from - n));
      case 'l' || ' ':
        return _Went(math.min(endOfLine(t, from), from + n));
      case 'j' || 'k' || 'gj' || 'gk':
        final down = m.name.endsWith('j');
        final column = _goal ?? (from - startOfLine(t, from));
        var s = startOfLine(t, from), moved = 0;
        for (; moved < n; moved++) {
          if (down) {
            final e = endOfLine(t, s);
            if (e >= len) break;
            s = e + 1;
          } else {
            if (s == 0) break;
            s = startOfLine(t, s - 1);
          }
        }
        if (moved == 0) return null;
        _goalNext = column;
        final e = endOfLine(t, s);
        return _Went(math.min(s + column, e > s ? e - 1 : s), linewise: true);
      case 'w' || 'W':
        var p = from;
        for (var j = 0; j < n; j++) {
          p = _wordForward(t, p, m.name == 'W');
        }
        return _Went(p);
      case 'b' || 'B':
        var p = from;
        for (var j = 0; j < n; j++) {
          p = _wordBackward(t, p, m.name == 'B');
        }
        return _Went(p);
      case 'e' || 'E':
        var p = from;
        for (var j = 0; j < n; j++) {
          p = _wordEnd(t, p, m.name == 'E');
        }
        return _Went(p, inclusive: true);
      case 'ge' || 'gE':
        var p = from;
        for (var j = 0; j < n; j++) {
          p = _wordEndBackward(t, p, m.name == 'gE');
        }
        return _Went(p, inclusive: true);
      case '0':
        return _Went(startOfLine(t, from));
      case '^':
        return _Went(firstNonBlank(t, from));
      case r'$':
        _goalNext = 1 << 30;
        return _Went(endOfLine(t, startOfLineNumber(t, lineNumberAt(t, from) + n - 1)));
      case 'g_':
        final s = startOfLineNumber(t, lineNumberAt(t, from) + n - 1);
        var e = endOfLine(t, s);
        while (e > s && isBlank(t.codeUnitAt(e - 1))) {
          e--;
        }
        return _Went(math.max(s, e - 1), inclusive: true);
      case '|':
        final s = startOfLine(t, from);
        return _Went(math.min(s + n - 1, endOfLine(t, from)));
      case 'gg' || 'G':
        final line = given ?? (m.name == 'gg' ? 1 : lineNumberAt(t, len));
        return _Went(firstNonBlank(t, startOfLineNumber(t, line)), linewise: true);
      case '_':
        return _Went(firstNonBlank(t, startOfLineNumber(t, lineNumberAt(t, from) + n - 1)), linewise: true);
      case '+' || vimEnter || '-':
        final line = lineNumberAt(t, from) + (m.name == '-' ? -n : n);
        if (line < 1 || line > lineNumberAt(t, len)) return null;
        return _Went(firstNonBlank(t, startOfLineNumber(t, line)), linewise: true);
      case 'f' || 'F' || 't' || 'T':
        final to = _findInLine(t, from, m.name, m.arg!, n);
        if (to == null) return null;
        _lastFind = (kind: m.name, char: m.arg!);
        return _Went(to, inclusive: m.name == 'f' || m.name == 't');
      case ';' || ',':
        final last = _lastFind;
        if (last == null) return null;
        final kind = m.name == ';' ? last.kind : (last.kind == last.kind.toUpperCase() ? last.kind.toLowerCase() : last.kind.toUpperCase());
        final to = _findInLine(t, from, kind, last.char, n, again: true);
        if (to == null) return null;
        return _Went(to, inclusive: kind == 'f' || kind == 't');
      case '}':
        var p = from;
        for (var j = 0; j < n; j++) {
          p = _paragraphForward(t, p);
        }
        return _Went(p);
      case '{':
        var p = from;
        for (var j = 0; j < n; j++) {
          p = _paragraphBackward(t, p);
        }
        return _Went(p);
      case '%':
        final to = _matchBracket(t, from);
        return to == null ? null : _Went(to, inclusive: true);
      case 'n' || 'N':
        final last = _lastSearch;
        if (last == null) {
          _said = 'No previous search';
          return null;
        }
        final to = _search(from, m.name == 'n' ? last.forward : !last.forward, n);
        return to == null ? null : _Went(to);
      case '*' || '#':
        final word = _object(false, 'w', from);
        if (word == null || word.to <= word.from || charKind(t, word.from) != 1) return null;
        _lastSearch = (pattern: t.substring(word.from, word.to), forward: m.name == '*', whole: true);
        final to = _search(m.name == '*' ? from : word.from, m.name == '*', n);
        return to == null ? null : _Went(to);
    }
    return null;
  }

  /// What an operator with motion [m] takes from the cursor: Vim's own two exceptions in it, `cw` stopping at the
  /// word's end and `dw` not reaching past the line its last word ends.
  _Range? _motionRange(String op, _MotionKeys m, int n, int? given) {
    final t = target.text, from = _cursor;
    if (op == 'c' && (m.name == 'w' || m.name == 'W') && from < t.length && charKind(t, from) != 0) {
      final big = m.name == 'W';
      var p = from;
      for (var j = 0; j < n; j++) {
        p = j == 0 ? _endOfThisWord(t, p, big) : _wordEnd(t, p, big);
      }
      return _Range(from, math.min(p + 1, t.length));
    }
    final went = _go(m, n, given, from);
    if (went == null) return null;
    if (went.linewise) return _Range(math.min(from, went.to), math.max(from, went.to), linewise: true);
    var a = math.min(from, went.to), b = math.max(from, went.to);
    if (went.inclusive) b = math.min(b + 1, t.length);
    if ((m.name == 'w' || m.name == 'W') && b > a) {
      final lastBreak = t.lastIndexOf('\n', b - 1);
      if (lastBreak >= a && b <= t.length && (b == t.length || startOfLine(t, b) > lastBreak)) b = math.max(a, lastBreak);
    }
    return _Range(a, b);
  }

  // ---- operators -------------------------------------------------------------------------------------------------

  /// [op] (`d`, `c`, `y`, `>`, `<`) on [r]; a yank leaves the cursor at [yankAt].
  void _operate(String op, _Range r, {required int yankAt}) {
    if (op == '>' || op == '<') {
      _indent(op == '>', r.from, r.to, 1);
      return;
    }
    final t = target.text, n = t.length;
    if (r.linewise) {
      final s = startOfLine(t, math.min(r.from, r.to)), e = endOfLine(t, math.max(r.from, r.to));
      _register = VimRegister(t.substring(s, e), linewise: true);
      switch (op) {
        case 'y':
          _place(yankAt);
        case 'd':
          final ok = e < n
              ? _change([(from: s, to: e + 1, insert: '')], s)
              : s > 0
                  ? _change([(from: s - 1, to: e, insert: '')], s - 1)
                  : _change([(from: 0, to: e, insert: '')], 0);
          if (ok) {
            final after = target.text;
            _place(firstNonBlank(after, startOfLine(after, math.min(s, after.length))));
          }
        case 'c':
          final indent = t.substring(s, firstNonBlank(t, s));
          if (_change([(from: s, to: e, insert: indent)], s + indent.length)) _enterInsert(s + indent.length);
      }
      return;
    }
    final a = math.min(r.from, r.to), b = math.max(r.from, r.to);
    _register = VimRegister(t.substring(a, b));
    switch (op) {
      case 'y':
        _place(yankAt);
      case 'd':
        if (b > a && _change([(from: a, to: b, insert: '')], a)) _place(a);
      case 'c':
        if (target.readOnly) {
          _said = 'This note can’t be changed';
        } else {
          if (b > a) _change([(from: a, to: b, insert: '')], a);
          _enterInsert(a);
        }
    }
  }

  /// One level of indentation more ([more]) or less, [times], on the lines [a] and [b] are on and those between.
  void _indent(bool more, int a, int b, int times) {
    final t = target.text, unit = target.indentUnit;
    final first = startOfLine(t, math.min(a, b)), last = startOfLine(t, math.max(a, b));
    final edits = <KeyEdit>[];
    var s = first;
    while (true) {
      final e = endOfLine(t, s);
      if (more) {
        if (e > s) edits.add((from: s, to: s, insert: unit * times));
      } else {
        var i = s, levels = 0;
        while (i < e && levels < times) {
          if (t[i] == '\t') {
            i++;
            levels++;
            continue;
          }
          var spaces = 0;
          while (i < e && t[i] == ' ' && spaces < unit.length) {
            i++;
            spaces++;
          }
          if (spaces == 0) break;
          levels++;
        }
        if (i > s) edits.add((from: s, to: i, insert: ''));
      }
      if (s >= last || e >= t.length) break;
      s = e + 1;
    }
    if (edits.isEmpty) {
      _place(firstNonBlank(t, first));
      return;
    }
    if (_change(edits, first)) {
      final after = target.text;
      _place(firstNonBlank(after, first));
    }
  }

  void _recase(String how, _Range r) {
    final t = target.text;
    final (from, to) = _span(t, r);
    final words = t.substring(from, to);
    final next = switch (how) { 'u' => words.toLowerCase(), 'U' => words.toUpperCase(), _ => _toggled(words) };
    if (_change([(from: from, to: to, insert: next)], from)) _place(from);
  }

  static String _toggled(String words) {
    final out = StringBuffer();
    for (final rune in words.runes) {
      final char = String.fromCharCode(rune), upper = char.toUpperCase();
      out.write(char == upper ? char.toLowerCase() : upper);
    }
    return out.toString();
  }

  /// `p` and `P`, [n] times.
  bool _paste(bool after, int n) {
    final r = _register;
    if (r == null) {
      _said = 'Nothing to put yet';
      return false;
    }
    final t = target.text, c = _cursor;
    if (r.linewise) {
      final block = List<String>.filled(n, r.text).join('\n');
      if (after) {
        final e = endOfLine(t, c);
        if (!_change([(from: e, to: e, insert: '\n$block')], e + 1)) return false;
        _place(firstNonBlank(target.text, e + 1));
      } else {
        final s = startOfLine(t, c);
        if (!_change([(from: s, to: s, insert: '$block\n')], s)) return false;
        _place(firstNonBlank(target.text, s));
      }
      return true;
    }
    final words = r.text * n;
    final at = after && endOfLine(t, c) > c ? c + 1 : c;
    if (!_change([(from: at, to: at, insert: words)], at + words.length)) return false;
    _place(math.max(at, at + words.length - 1));
    return true;
  }

  void _replaceWithRegister(_Range r) {
    final reg = _register;
    if (reg == null) {
      _said = 'Nothing to put yet';
      return;
    }
    final t = target.text;
    final (from, to) = _span(t, r);
    final words = reg.linewise && !r.linewise ? '\n${reg.text}\n' : reg.text;
    if (_change([(from: from, to: to, insert: words)], from)) {
      _register = VimRegister(t.substring(from, to), linewise: r.linewise);
      _place(from);
    }
  }

  /// `J`: [joins] lines joined to the one [pos] is on, a space between where the line ends in none.
  bool _join(int pos, int joins) {
    final t = target.text;
    final edits = <KeyEdit>[];
    var e = endOfLine(t, pos), shift = 0, caret = e;
    for (var j = 0; j < joins; j++) {
      if (e >= t.length) break;
      final next = e + 1, nextEnd = endOfLine(t, next);
      var words = next;
      while (words < nextEnd && (t[words] == ' ' || t[words] == '\t')) {
        words++;
      }
      final s = startOfLine(t, e);
      final bare = e == s || t[e - 1] == ' ' || t[e - 1] == '\t' || words == nextEnd || t[words] == ')';
      final space = bare ? '' : ' ';
      edits.add((from: e, to: words, insert: space));
      caret = e - shift;
      shift += (words - e) - space.length;
      e = nextEnd;
    }
    if (edits.isEmpty) return false;
    if (!_change(edits, caret)) return false;
    _place(caret);
    return true;
  }

  // ---- text objects ----------------------------------------------------------------------------------------------

  /// The text object [name] round [at]: `a` ([around]) with what surrounds it, `i` without.
  _Range? _object(bool around, String name, int at) {
    final t = target.text;
    if (t.isEmpty) return null;
    final p = at.clamp(0, t.length - 1);
    switch (name) {
      case 'w' || 'W':
        final big = name == 'W';
        final s = startOfLine(t, p), e = endOfLine(t, p);
        if (e == s) return _Range(p, p);
        int kind(int i) => t[i] == '\n' ? -1 : charKind(t, i, big: big);
        final k = kind(p);
        var from = p, to = p + 1;
        while (from > s && kind(from - 1) == k) {
          from--;
        }
        while (to < e && kind(to) == k) {
          to++;
        }
        if (around) {
          if (k == 0) {
            if (to < e) {
              final next = kind(to);
              while (to < e && kind(to) == next) {
                to++;
              }
            }
          } else {
            final was = to;
            while (to < e && kind(to) == 0) {
              to++;
            }
            if (to == was) {
              while (from > s && kind(from - 1) == 0) {
                from--;
              }
            }
          }
        }
        return _Range(from, to);
      case '"' || "'" || '`':
        final s = startOfLine(t, p), e = endOfLine(t, p);
        final quotes = <int>[];
        for (var i = s; i < e; i++) {
          if (t[i] == name && (i == s || t[i - 1] != '\\')) quotes.add(i);
        }
        int? open, close;
        for (var j = 0; j + 1 < quotes.length; j += 2) {
          if (quotes[j] <= p && p <= quotes[j + 1]) {
            open = quotes[j];
            close = quotes[j + 1];
            break;
          }
        }
        if (open == null) {
          for (var j = 0; j + 1 < quotes.length; j += 2) {
            if (quotes[j] > p) {
              open = quotes[j];
              close = quotes[j + 1];
              break;
            }
          }
        }
        if (open == null || close == null) return null;
        if (!around) return _Range(open + 1, close);
        var to = close + 1, from = open;
        while (to < e && (t[to] == ' ' || t[to] == '\t')) {
          to++;
        }
        if (to == close + 1) {
          while (from > s && (t[from - 1] == ' ' || t[from - 1] == '\t')) {
            from--;
          }
        }
        return _Range(from, to);
      case '(' || ')' || 'b' || '[' || ']' || '{' || '}' || 'B' || '<' || '>':
        final (openChar, closeChar) = switch (name) { '(' || ')' || 'b' => ('(', ')'), '[' || ']' => ('[', ']'), '<' || '>' => ('<', '>'), _ => ('{', '}') };
        int? open;
        var depth = 0;
        for (var i = p; i >= 0; i--) {
          if (t[i] == closeChar && i != p) {
            depth++;
          } else if (t[i] == openChar) {
            if (depth == 0) {
              open = i;
              break;
            }
            depth--;
          }
        }
        if (open == null) return null;
        int? close;
        depth = 0;
        for (var i = open + 1; i < t.length; i++) {
          if (t[i] == openChar) {
            depth++;
          } else if (t[i] == closeChar) {
            if (depth == 0) {
              close = i;
              break;
            }
            depth--;
          }
        }
        if (close == null) return null;
        if (around) return _Range(open, close + 1);
        var from = open + 1, to = close;
        // Over lines, as `{` and `}` on lines of their own: the lines between.
        if (from < t.length && t[from] == '\n') {
          final closeLine = startOfLine(t, close);
          if (firstNonBlank(t, closeLine) == close && closeLine > from) {
            from++;
            to = closeLine;
          }
        }
        return _Range(from, to);
      case 'p':
        bool blank(int s) => firstNonBlank(t, s) == endOfLine(t, s);
        final here = startOfLine(t, p), kind = blank(here);
        var first = here, last = here;
        while (first > 0 && blank(startOfLine(t, first - 1)) == kind) {
          first = startOfLine(t, first - 1);
        }
        while (endOfLine(t, last) < t.length && blank(endOfLine(t, last) + 1) == kind) {
          last = endOfLine(t, last) + 1;
        }
        if (around && !kind) {
          var more = last;
          while (endOfLine(t, more) < t.length && blank(endOfLine(t, more) + 1)) {
            more = endOfLine(t, more) + 1;
          }
          if (more != last) {
            last = more;
          } else {
            while (first > 0 && blank(startOfLine(t, first - 1))) {
              first = startOfLine(t, first - 1);
            }
          }
        }
        return _Range(first, last, linewise: true);
    }
    return null;
  }

  // ---- the command line ------------------------------------------------------------------------------------------

  void _openLine(String first) {
    _line = first;
    _said = null;
  }

  bool _lineKey(String key) {
    final line = _line!;
    switch (key) {
      case vimEscape:
        _line = null;
      case vimBackspace:
        _line = line.length <= 1 ? null : line.substring(0, line.length - 1);
      case vimEnter:
        _line = null;
        _runLine(line);
      default:
        if (key.startsWith('<') && key.length > 1) return true;
        _line = line + key;
    }
    return true;
  }

  void _runLine(String line) {
    final kind = line[0], rest = line.substring(1);
    if (kind == ':') {
      _ex(rest.trim());
      return;
    }
    final pattern = rest.isEmpty ? _lastSearch?.pattern : rest;
    if (pattern == null || pattern.isEmpty) {
      _said = 'No previous search';
      return;
    }
    _lastSearch = (pattern: pattern, forward: kind == '/', whole: false);
    final to = _search(_cursor, kind == '/', 1);
    if (to != null) _place(to);
  }

  void _ex(String command) {
    switch (command) {
      case '':
        return;
      case 'w' || 'w!' || 'write' || 'up' || 'update':
        target.save();
        _said = 'Saved';
      case 'q' || 'q!' || 'quit' || 'quit!' || 'close':
        target.close();
      case 'wq' || 'wq!' || 'x' || 'x!' || 'xit' || 'exit':
        target.save();
        target.close();
      case 'noh' || 'nohlsearch':
        return;
      case r'$':
        final t = target.text;
        _place(firstNonBlank(t, startOfLineNumber(t, lineNumberAt(t, t.length))));
      default:
        final line = int.tryParse(command);
        if (line != null) {
          final t = target.text;
          _place(firstNonBlank(t, startOfLineNumber(t, math.max(1, line))));
        } else {
          _said = 'Not an editor command: $command';
        }
    }
  }

  /// The [n]th match of the last search from [from], on round the text's end where it has to.
  int? _search(int from, bool forward, int n) {
    final last = _lastSearch!;
    final t = target.text;
    final re = RegExp(RegExp.escape(last.pattern), caseSensitive: last.pattern.toLowerCase() != last.pattern);
    final starts = [
      for (final m in re.allMatches(t))
        if (!last.whole || ((m.start == 0 || !isWordUnit(t.codeUnitAt(m.start - 1))) && (m.end == t.length || !isWordUnit(t.codeUnitAt(m.end))))) m.start,
    ];
    if (starts.isEmpty) {
      _said = 'Pattern not found: ${last.pattern}';
      return null;
    }
    var p = from;
    for (var j = 0; j < n; j++) {
      int? next;
      if (forward) {
        for (final s in starts) {
          if (s > p) {
            next = s;
            break;
          }
        }
        if (next == null) {
          next = starts.first;
          _said = 'Search hit the end, went on from the top';
        }
      } else {
        for (final s in starts.reversed) {
          if (s < p) {
            next = s;
            break;
          }
        }
        if (next == null) {
          next = starts.last;
          _said = 'Search hit the top, went on from the end';
        }
      }
      p = next;
    }
    return p;
  }
}

// ---- where the motions go ----------------------------------------------------------------------------------------

bool _emptyLineAt(String t, int i) => t.codeUnitAt(i) == 0x0A && (i == 0 || t.codeUnitAt(i - 1) == 0x0A);

int _wordForward(String t, int pos, bool big) {
  final n = t.length;
  if (pos >= n) return n;
  var i = pos;
  final kind = charKind(t, i, big: big);
  if (kind != 0) {
    while (i < n && charKind(t, i, big: big) == kind) {
      i++;
    }
  }
  while (i < n && charKind(t, i, big: big) == 0) {
    if (i != pos && _emptyLineAt(t, i)) return i;
    i++;
  }
  return i;
}

int _wordBackward(String t, int pos, bool big) {
  if (pos <= 0) return 0;
  var i = math.min(pos, t.length) - 1;
  while (i > 0 && charKind(t, i, big: big) == 0) {
    if (_emptyLineAt(t, i)) return i;
    i--;
  }
  final kind = charKind(t, i, big: big);
  if (kind == 0) return i;
  while (i > 0 && charKind(t, i - 1, big: big) == kind) {
    i--;
  }
  return i;
}

int _wordEnd(String t, int pos, bool big) {
  final n = t.length;
  var i = pos + 1;
  while (i < n && charKind(t, i, big: big) == 0) {
    i++;
  }
  if (i >= n) return math.max(0, n - 1);
  final kind = charKind(t, i, big: big);
  while (i + 1 < n && charKind(t, i + 1, big: big) == kind) {
    i++;
  }
  return i;
}

int _endOfThisWord(String t, int pos, bool big) {
  final kind = charKind(t, pos, big: big);
  var i = pos;
  while (i + 1 < t.length && charKind(t, i + 1, big: big) == kind) {
    i++;
  }
  return i;
}

int _wordEndBackward(String t, int pos, bool big) {
  if (t.isEmpty) return 0;
  var i = math.min(pos, t.length - 1);
  if (i <= 0) return 0;
  final kind = charKind(t, i, big: big);
  if (kind != 0) {
    while (i > 0 && charKind(t, i - 1, big: big) == kind) {
      i--;
    }
  }
  i--;
  while (i > 0 && charKind(t, i, big: big) == 0) {
    i--;
  }
  return math.max(0, i);
}

/// `f`, `F`, `t` and `T` on the line [from] is on; [again] for `;` and `,`, where a `t` steps past the character it
/// stands before.
int? _findInLine(String t, int from, String kind, String char, int n, {bool again = false}) {
  final s = startOfLine(t, from), e = endOfLine(t, from);
  final forward = kind == 'f' || kind == 't';
  var p = from;
  if (again && (kind == 't' || kind == 'T')) p += forward ? 1 : -1;
  for (var j = 0; j < n; j++) {
    final at = forward ? t.indexOf(char, p + 1) : (p - 1 < s ? -1 : t.lastIndexOf(char, p - 1));
    if (at < 0 || at >= e || at < s) return null;
    p = at;
  }
  return switch (kind) { 'f' || 'F' => p, 't' => p - 1, _ => p + 1 };
}

int _paragraphForward(String t, int p) {
  final n = t.length;
  var i = startOfLine(t, p);
  while (i < n && endOfLine(t, i) == i) {
    i++;
  }
  while (i < n) {
    final e = endOfLine(t, i);
    if (e == i) return i;
    i = e + 1;
  }
  return n;
}

int _paragraphBackward(String t, int p) {
  var s = startOfLine(t, p);
  if (s == 0) return 0;
  s = startOfLine(t, s - 1);
  while (s > 0 && endOfLine(t, s) == s) {
    s = startOfLine(t, s - 1);
  }
  while (s > 0) {
    if (endOfLine(t, s) == s) return s;
    s = startOfLine(t, s - 1);
  }
  return 0;
}

int? _matchBracket(String t, int from) {
  const opens = '([{', closes = ')]}';
  final e = endOfLine(t, from);
  var i = from;
  while (i < e && !opens.contains(t[i]) && !closes.contains(t[i])) {
    i++;
  }
  if (i >= e) return null;
  final open = opens.indexOf(t[i]);
  if (open >= 0) {
    var depth = 0;
    for (var j = i + 1; j < t.length; j++) {
      if (t[j] == opens[open]) {
        depth++;
      } else if (t[j] == closes[open]) {
        if (depth == 0) return j;
        depth--;
      }
    }
    return null;
  }
  final close = closes.indexOf(t[i]);
  var depth = 0;
  for (var j = i - 1; j >= 0; j--) {
    if (t[j] == closes[close]) {
      depth++;
    } else if (t[j] == opens[close]) {
      if (depth == 0) return j;
      depth--;
    }
  }
  return null;
}
