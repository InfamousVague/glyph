/// "Stop when I go quiet": a recording that has heard someone speak saves itself once they have been quiet for a few
/// seconds. A port of `src/app/capture/quiet.ts`.
///
/// Two kinds of evidence of speech. The microphone's level, against a noise floor that follows the room (quickly
/// down, slowly up, so a fan does not count as talking and a raised voice does not become the floor); and words
/// arriving from the recogniser, which lag speech by a second or two and so only ever make the wait longer, never
/// shorter. Nothing stops before the first word: opening the recorder and thinking is not the end of a note.
///
/// What differs: nothing. The clock is the caller's, as it is on the web: every method takes `now` in ms.
library;

import 'dart:math' as math;

class QuietWatch {
  QuietWatch(this.quietMs);

  final num quietMs;
  double _floor = 0.01;
  num? _lastVoice;

  /// Words have come back at least once: before that, nothing stops.
  bool _spoke = false;

  /// A microphone level (RMS, 0 to 1) at [now] ms.
  void level(num rms, num now) {
    _floor = rms < _floor ? _floor * 0.8 + rms * 0.2 : _floor * 0.995 + rms * 0.005;
    if (rms > math.max(0.02, _floor * 3)) _lastVoice = now;
  }

  /// Words came back from the recogniser at [now].
  void words(num now) {
    _spoke = true;
    _lastVoice = math.max(_lastVoice ?? 0, now);
  }

  /// Whether the recording should stop now.
  bool due(num now) {
    final lastVoice = _lastVoice;
    return _spoke && lastVoice != null && now - lastVoice >= quietMs;
  }

  /// How long until it stops, for a countdown; null when nothing has been said.
  num? remaining(num now) {
    final lastVoice = _lastVoice;
    return !_spoke || lastVoice == null ? null : math.max(0, quietMs - (now - lastVoice));
  }
}
