/// The pace Claude's words are let into a note at (docs/CLAUDE_APP.md, "Typing as Claude writes"): between the
/// stream and the editor, so the words come at a steady rate a person can read rather than in the bursts the stream
/// hands them over in. Matt (2026-10-17): "slow down the input in a queue as well so it looks nicer for humans to
/// read".
///
/// Words are let out whole, a word and the spaces after it at a time, at [pacerRestRate] letters a second while the
/// stream keeps up. When it runs ahead the rate rises, easing up over [pacerEase] rather than jumping, as far as it
/// takes for every letter to be out within about [pacerMostBehind] of arriving; and falls back the same way once
/// it has caught up. A word still arriving (nothing after it yet) waits [pacerWordWait] for its end before it goes
/// as it is, at once when [finish] says nothing more is coming; a word longer than [pacerLongestPiece] goes in
/// pieces. [flush] lets everything out at once (Stop, a stream that broke).
///
/// Nothing here knows a clock: the caller says what time it is, so a test's is exact (lib/claude/live_typing.dart
/// counts its frames).
library;

import 'dart:collection';
import 'dart:math' as math;

/// Letters a second Claude's words go in at while the stream keeps up: a quick reader's pace, about ten words a
/// second.
const double pacerRestRate = 60;

/// At most about this far behind the stream: the rate rises so that every letter is out within it of arriving
/// (give or take [pacerEase], which the rate takes to rise).
const Duration pacerMostBehind = Duration(milliseconds: 2000);

/// How quickly the rate follows the one it needs: it closes most of the gap over about this long, so a burst from
/// the stream speeds the words up smoothly, and they slow down as smoothly once it is through.
const Duration pacerEase = Duration(milliseconds: 250);

/// A word longer than this many letters (a link, a line of code with no spaces) goes in pieces of this size.
const int pacerLongestPiece = 24;

/// A word with nothing after it yet waits this long since anything last arrived for its end, then goes as it is.
const Duration pacerWordWait = Duration(milliseconds: 300);

/// The shortest time left a letter is counted as having: one already late is let out quickly, not all at once.
const Duration _soonest = Duration(milliseconds: 100);

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// A queue of Claude's words, let out at a reading pace ([release]).
class TypingPacer {
  /// What has arrived and not been let out.
  String _pending = '';

  /// How many letters have arrived, and been let out, since the start.
  int _received = 0;
  int _released = 0;

  /// When each piece arrived, by where it ends among everything received.
  final Queue<({int end, Duration at})> _arrivals = Queue<({int end, Duration at})>();

  Duration? _lastAsked;
  Duration _lastArrived = Duration.zero;
  double _rate = pacerRestRate;

  /// Letters earned and not yet spent: a word goes once there are as many as it has.
  double _credit = 0;
  bool _finished = false;

  /// Whether everything that arrived has been let out.
  bool get isEmpty => _pending.isEmpty;

  /// How many letters wait.
  int get backlog => _pending.length;

  /// The rate words are going in at now, letters a second.
  double get rate => _rate;

  /// More of Claude's words, arrived at [now].
  void add(String text, Duration now) {
    if (text.isEmpty) return;
    if (_pending.isEmpty) {
      // Nothing was waiting: no letters are banked from the quiet, and it starts at a reader's pace.
      _credit = 0;
      _rate = pacerRestRate;
      _lastAsked = now;
    }
    _finished = false;
    _pending += text;
    _received += text.length;
    _arrivals.add((end: _received, at: now));
    _lastArrived = now;
  }

  /// Nothing more is coming: a word left waiting for its end goes as it is.
  void finish() => _finished = true;

  /// What goes into the note at [now]: whole words, as many as the pace has earned since it was last asked, or
  /// nothing.
  String release(Duration now) {
    final last = _lastAsked ?? now;
    _lastAsked = now;
    if (_pending.isEmpty) {
      _credit = 0;
      return '';
    }
    final dt = math.max(0.0, _seconds(now - last));
    final ease = 1 - math.exp(-dt / _seconds(pacerEase));
    _rate += (_needed(now) - _rate) * ease;
    _credit += _rate * dt;
    var take = 0;
    while (take < _pending.length) {
      final unit = _unit(take, now);
      if (unit == 0) {
        // A word waiting for its end banks no more than a frame or so of letters, so it does not go out in a rush
        // with the next ones when it comes.
        _credit = math.min(_credit, _rate * 0.05);
        break;
      }
      if (unit > _credit + 1e-9) break;
      _credit -= unit;
      take += unit;
    }
    if (take == 0) return '';
    return _let(take);
  }

  /// Everything waiting, at once.
  String flush() => _pending.isEmpty ? '' : _let(_pending.length);

  String _let(int take) {
    final out = _pending.substring(0, take);
    _pending = _pending.substring(take);
    _released += take;
    while (_arrivals.isNotEmpty && _arrivals.first.end <= _released) {
      _arrivals.removeFirst();
    }
    if (_pending.isEmpty) _credit = 0;
    return out;
  }

  /// The rate that has every letter out within [pacerMostBehind] (less the time the rate takes to rise) of its
  /// arriving, and never less than a reader's pace.
  double _needed(Duration now) {
    var needed = pacerRestRate;
    final window = _seconds(pacerMostBehind - pacerEase);
    for (final piece in _arrivals) {
      final letters = piece.end - _released;
      if (letters <= 0) continue;
      final left = math.max(_seconds(_soonest), window - _seconds(now - piece.at));
      needed = math.max(needed, letters / left);
    }
    return needed;
  }

  /// How long the next piece is from [start] of what waits: spaces before a word, the word, and the spaces after
  /// it; or 0 while its word may not have ended.
  int _unit(int start, Duration now) {
    final text = _pending;
    var i = start;
    while (i < text.length && _space(text.codeUnitAt(i))) {
      i += 1;
    }
    var j = i;
    while (j < text.length && !_space(text.codeUnitAt(j)) && j - i < pacerLongestPiece) {
      j += 1;
    }
    if (j - i >= pacerLongestPiece && j < text.length && !_space(text.codeUnitAt(j))) {
      // A long word's piece: never half a letter.
      final unit = text.codeUnitAt(j - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) j += 1;
      return j - start;
    }
    if (j >= text.length) {
      // The word (or the spaces) may go on: wait for more, unless nothing more is coming or it has been a while.
      final waited = now - _lastArrived >= pacerWordWait;
      return _finished || waited ? text.length - start : 0;
    }
    var k = j;
    while (k < text.length && _space(text.codeUnitAt(k))) {
      k += 1;
    }
    return k - start;
  }

  static bool _space(int unit) => unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D || unit == 0xA0 || unit == 0x3000;
}
