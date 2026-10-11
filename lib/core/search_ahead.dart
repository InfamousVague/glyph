/// What a search reads of every note (note_text.dart `searchText`), made before the first letter is typed: as a
/// search field takes the keyboard, a millisecond and a half of it after each frame until every note is read.
///
/// The first letter typed made every note's reading in its own frame (measured walking the Mac's profile build over
/// 354 notes, tool/perf.sh: 7.9 ms for the reading, where a letter typed once the readings were kept took 0.3).
/// Nothing is read for a search nobody begins: the home page and All notes each begin this as their field is
/// focused, and a field focused again finds every note read and reads none.
library;

import 'package:flutter/scheduler.dart';

import 'note.dart';
import 'note_text.dart';

class SearchAhead {
  bool _reading = false;

  /// Reads [notes] (asked for again at each turn, since the library may hand over another list meanwhile) until
  /// they are all read or [alive] says whoever asked has gone.
  void begin(List<Note> Function() notes, {required bool Function() alive}) {
    if (_reading) return;
    _reading = true;
    var at = 0;
    void some(Duration _) {
      if (!alive()) {
        _reading = false;
        return;
      }
      final all = notes();
      final clock = Stopwatch()..start();
      while (at < all.length && clock.elapsedMicroseconds < 1500) {
        searchText(all[at]);
        at += 1;
      }
      if (at >= all.length) {
        _reading = false;
        return;
      }
      SchedulerBinding.instance
        ..addPostFrameCallback(some)
        ..scheduleFrame();
    }

    SchedulerBinding.instance.addPostFrameCallback(some);
  }
}
