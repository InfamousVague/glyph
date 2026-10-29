/// Emacs, the Keyboard modes plugin's other way of typing (keymaps.dart; Matt, 2026-10-29: "add a vim / emac
/// controls via a plugin"): no modes, its Control and Meta keys over the editor's own typing, worked on a [KeyText]
/// with nothing of Flutter's in it. The editor hands it keys by Emacs's own names (editor_keys.dart): `C-f`, `M-f`,
/// `C-SPC`, `M-<`, `M-DEL`, and `DEL`, `RET`, `ESC`, and a character typed as itself.
///
/// What it has: `C-f C-b C-n C-p`, `M-f M-b`, `C-a C-e`, `M-< M->`; `C-d`, `C-h`, `M-DEL`, and the kills, `C-k`
/// (the line's rest, or its break at its end), `M-d`, `C-w`, `M-w`, each one after another gathered into one kill as
/// Emacs does, with `C-y` to yank the last; `C-SPC` to set the mark, the selection then following each motion until
/// `C-g`; `C-/` and `C-_` to undo; `C-s` and `C-r` searching as they are typed; `C-x C-s` to save; `C-t` and `C-o`.
///
/// One behaviour on every platform: Control-a, -e, -k and the rest are a Mac's own text keys too, and here they are
/// these, so a kill on a Mac is yanked back by `C-y` and a motion with the mark set selects. Any key it does not
/// name is the editor's and the app's, as it was. Not here: a numeric argument (`C-u`), `M-y`, the kill ring beyond
/// its last kill, registers, rectangles, and `C-x` with anything but `C-s`.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'text.dart';

/// The most kills kept.
const int emacsKillsKept = 60;

class _ISearch {
  _ISearch(this.forward, this.origin) : from = origin, to = origin;
  bool forward;
  final int origin;
  String query = '';

  /// The match found, or the origin before there is one.
  int from, to;
  bool failing = false;
}

/// Emacs over one text.
class EmacsEngine extends ChangeNotifier {
  EmacsEngine(this.target);

  final KeyText target;

  int? _mark;

  /// Whether the mark is set, and a motion selects from it.
  bool get marking => _mark != null;

  /// The kills, the last last.
  List<String> get kills => List.unmodifiable(_kills);
  final List<String> _kills = [];

  // The last command was a kill: the next is gathered into it.
  bool _killing = false;

  // `C-x` waits for its second key.
  bool _prefix = false;

  _ISearch? _search;
  String? _lastQuery;

  /// A word for the person: the mark set, a key not known. Gone with the next key.
  String? get message => _said;
  String? _said;

  /// What the badge says while something is held: the search as it is typed, the mark, a `C-x` waiting. Null while
  /// nothing is, and the badge is not drawn.
  String? get badge {
    final search = _search;
    if (search != null) return '${search.failing ? 'Failing ' : ''}I-search${search.forward ? '' : ' backward'}: ${search.query}';
    if (_prefix) return 'C-x-';
    if (_mark != null) return 'MARK';
    return null;
  }

  /// Whether the engine is changing the text or the selection itself.
  bool get busy => _busy > 0;
  int _busy = 0;
  int? _shownAnchor, _shownHead;

  /// One key, by its Emacs name. Answers whether Emacs took it.
  bool handle(String key) {
    _said = null;
    if (_search != null) {
      if (_searchKey(key)) {
        notifyListeners();
        return true;
      }
    }
    if (_prefix) {
      _prefix = false;
      _killing = false;
      switch (key) {
        case 'C-s':
          target.save();
          _said = 'Saved';
        case 'C-g':
          _said = 'Quit';
        default:
          _said = 'C-x $key is undefined';
      }
      notifyListeners();
      return true;
    }
    final wasKilling = _killing;
    _killing = false;
    final took = _run(key, wasKilling);
    // A key that stays the editor's ends a kill's run all the same; only what Emacs did is drawn again.
    if (took || badge != null) notifyListeners();
    return took;
  }

  /// The text or the selection was changed by something else: a click, the person typing. The mark is put down,
  /// a search ends where it is, and a kill's run is over.
  void moved(int anchor, int head, {bool docChanged = false}) {
    if (!docChanged && anchor == _shownAnchor && head == _shownHead) return;
    _killing = false;
    _prefix = false;
    final held = _mark != null || _search != null;
    _mark = null;
    if (_search != null) {
      _lastQuery = _search!.query.isEmpty ? _lastQuery : _search!.query;
      _search = null;
    }
    if (held) notifyListeners();
  }

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

  /// The caret goes to [p], selecting from the mark while it is set.
  void _go(int p) {
    final at = p.clamp(0, target.text.length);
    _select(_mark ?? at, at);
  }

  bool _run(String key, bool wasKilling) {
    final t = target.text, n = t.length, p = target.head;
    switch (key) {
      case 'C-f':
        _go(math.min(p + 1, n));
      case 'C-b':
        _go(math.max(p - 1, 0));
      case 'M-f':
        _go(_forwardWord(t, p));
      case 'M-b':
        _go(_backwardWord(t, p));
      case 'C-a':
        _go(startOfLine(t, p));
      case 'C-e':
        _go(endOfLine(t, p));
      case 'M-<':
        _go(0);
      case 'M->':
        _go(n);
      case 'C-n' || 'C-p':
        _busy++;
        try {
          target.vertical(key == 'C-n', extend: _mark != null);
        } finally {
          _busy--;
        }
        _shownAnchor = target.anchor;
        _shownHead = target.head;
      case 'C-d':
        _mark = null;
        if (target.anchor != target.head) return false;
        if (p < n) _change([(from: p, to: p + 1, insert: '')], p);
      case 'C-h':
        _mark = null;
        if (target.anchor != target.head) return false;
        if (p > 0) _change([(from: p - 1, to: p, insert: '')], p - 1);
      case 'DEL':
        // The editor's own Backspace; it ends a kill's run, and takes the region with it.
        return false;
      case 'M-DEL':
        _kill(_backwardWord(t, p), p, wasKilling, backward: true);
      case 'M-d':
        _kill(p, _forwardWord(t, p), wasKilling);
      case 'C-k':
        final e = endOfLine(t, p);
        final to = t.substring(p, e).trim().isEmpty && e < n ? e + 1 : e;
        if (to == p) {
          _said = 'End of buffer';
          _killing = wasKilling;
        } else {
          _kill(p, to, wasKilling);
        }
      case 'C-w':
        final mark = _mark;
        if (mark != null) {
          _kill(math.min(mark, p), math.max(mark, p), wasKilling, backward: p < mark);
        } else if (target.anchor != target.head) {
          _kill(math.min(target.anchor, target.head), math.max(target.anchor, target.head), wasKilling);
        } else {
          _said = 'The mark is not set now';
        }
      case 'M-w':
        final mark = _mark;
        final (a, b) = mark != null ? (math.min(mark, p), math.max(mark, p)) : (math.min(target.anchor, p), math.max(target.anchor, p));
        if (a == b) {
          _said = 'The mark is not set now';
        } else {
          _keep(t.substring(a, b), wasKilling, backward: false);
          _killing = true;
          _mark = null;
          _select(p, p);
          _said = 'Copied';
        }
      case 'C-y':
        if (_kills.isEmpty) {
          _said = 'Kill ring is empty';
        } else {
          _mark = null;
          final words = _kills.last;
          final a = math.min(target.anchor, target.head);
          _change([(from: a, to: math.max(target.anchor, target.head), insert: words)], a + words.length);
        }
      case 'C-SPC':
        if (_mark == p && target.anchor == target.head) {
          _mark = null;
          _said = 'Mark deactivated';
        } else {
          _mark = p;
          _select(p, p);
          _said = 'Mark set';
        }
      case 'C-g':
        _mark = null;
        _select(p, p);
        _said = 'Quit';
      case 'ESC':
        if (_mark == null) return false;
        _mark = null;
        _select(p, p);
      case 'C-/' || 'C-_':
        _mark = null;
        _busy++;
        try {
          if (!target.undo()) _said = 'No further undo information';
        } finally {
          _busy--;
        }
        final at = math.min(target.anchor, target.head);
        _select(at, at);
      case 'C-s' || 'C-r':
        _mark = null;
        _search = _ISearch(key == 'C-s', p);
      case 'C-x':
        _prefix = true;
      case 'C-t':
        _mark = null;
        final s = startOfLine(t, p), e = endOfLine(t, p);
        if (p == s || n < 2) return true;
        // At a line's end, the two before; else the one before and the one after, and the caret steps past them.
        final at = p == e ? p - 2 : p - 1;
        if (at < s) return true;
        _change([(from: at, to: at + 2, insert: '${t[at + 1]}${t[at]}')], at + 2);
      case 'C-o':
        _mark = null;
        _change([(from: p, to: p, insert: '\n')], p);
      default:
        return false;
    }
    return true;
  }

  /// [from] to [to] out of the text and into the kills: gathered into the last kill where [wasKilling], after it or,
  /// [backward], before it.
  void _kill(int from, int to, bool wasKilling, {bool backward = false}) {
    _mark = null;
    if (to <= from) {
      _killing = wasKilling;
      return;
    }
    final t = target.text;
    if (!_change([(from: from, to: to, insert: '')], from)) return;
    _keep(t.substring(from, to), wasKilling, backward: backward);
    _killing = true;
  }

  void _keep(String words, bool wasKilling, {required bool backward}) {
    if (wasKilling && _kills.isNotEmpty) {
      _kills[_kills.length - 1] = backward ? words + _kills.last : _kills.last + words;
    } else {
      _kills.add(words);
      if (_kills.length > emacsKillsKept) _kills.removeAt(0);
    }
  }

  // ---- incremental search ----------------------------------------------------------------------------------------

  /// A key while searching: true where the search took it; false where it ended the search, and the key is then
  /// what it always is.
  bool _searchKey(String key) {
    final search = _search!;
    if (key.runes.length == 1 && !key.startsWith('C-') && !key.startsWith('M-')) {
      search.query += key;
      _find(search, search.forward ? search.from : search.from + 1);
      return true;
    }
    switch (key) {
      case 'C-s' || 'C-r':
        final forward = key == 'C-s';
        if (search.query.isEmpty) {
          if (_lastQuery == null) {
            search.forward = forward;
            return true;
          }
          search.query = _lastQuery!;
          search.forward = forward;
          _find(search, search.origin);
          return true;
        }
        final turned = search.forward != forward;
        search.forward = forward;
        if (search.failing) {
          // Searched again after failing: round from the other end.
          _find(search, forward ? 0 : target.text.length + 1);
        } else if (!turned) {
          _find(search, forward ? search.from + 1 : search.from);
        } else {
          _find(search, forward ? search.from : search.from + 1);
        }
        return true;
      case 'DEL':
        if (search.query.isEmpty) return true;
        search.query = search.query.substring(0, search.query.length - 1);
        if (search.query.isEmpty) {
          search.failing = false;
          search.from = search.to = search.origin;
          _select(search.origin, search.origin);
        } else {
          _find(search, search.origin);
        }
        return true;
      case 'C-g':
        _search = null;
        _select(search.origin, search.origin);
        _said = 'Quit';
        return true;
      case 'RET' || 'ESC':
        _end();
        return true;
    }
    _end();
    return false;
  }

  void _end() {
    final search = _search!;
    _search = null;
    if (search.query.isNotEmpty) _lastQuery = search.query;
    final at = target.head;
    _select(at, at);
  }

  /// The query from [from]: forward, the first match starting there or after; backward, the last starting before
  /// it. Found, it is selected with the caret at its far end; not, the search is failing where it was.
  void _find(_ISearch search, int from) {
    final t = target.text, query = search.query;
    final re = RegExp(RegExp.escape(query), caseSensitive: query.toLowerCase() != query);
    Match? found;
    if (search.forward) {
      found = re.firstMatch(t.substring(math.max(0, from)));
      if (found != null) {
        final start = math.max(0, from) + found.start;
        _show(search, start, start + found.end - found.start);
        return;
      }
    } else {
      for (final m in re.allMatches(t)) {
        if (m.start >= from) break;
        found = m;
      }
      if (found != null) {
        _show(search, found.start, found.end);
        return;
      }
    }
    search.failing = true;
  }

  void _show(_ISearch search, int from, int to) {
    search
      ..failing = false
      ..from = from
      ..to = to;
    search.forward ? _select(from, to) : _select(to, from);
  }
}

/// Emacs's `forward-word`: over what is not a word, then to the word's end.
int _forwardWord(String t, int p) {
  var i = p;
  while (i < t.length && !isWordUnit(t.codeUnitAt(i))) {
    i++;
  }
  while (i < t.length && isWordUnit(t.codeUnitAt(i))) {
    i++;
  }
  return i;
}

/// `backward-word`: back over what is not a word, then to the word's start.
int _backwardWord(String t, int p) {
  var i = p;
  while (i > 0 && !isWordUnit(t.codeUnitAt(i - 1))) {
    i--;
  }
  while (i > 0 && isWordUnit(t.codeUnitAt(i - 1))) {
    i--;
  }
  return i;
}
