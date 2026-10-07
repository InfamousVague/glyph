/// Feeling a detent coming: light ticks while a drag closes on it, further apart far off and closer and closer
/// together as it nears, then the firm click of arriving. A port of `src/app/core/detentFeel.ts`: none in the first
/// third of the way, one every 240 ms from there, down to one every 40 ms just short of it, and only on the way out.
/// Pure, so the pacing is a test. Nothing differs.
library;

/// How far along the way a drag must be before the ticks begin.
const double _approachFrom = 0.35;
const int _slowestMs = 240;
const int _fastestMs = 40;

/// Where a drag at [distance] is between detents: the detent it is heading for, and how far along it is from the one
/// before it (or from rest), 0 to 1. Null past the last. [detents] are nearest first, as fractions of the width.
({int index, double progress})? approach(List<double> detents, double distance) {
  var from = 0.0;
  for (var index = 0; index < detents.length; index += 1) {
    final to = detents[index];
    if (distance < to) {
      final progress = to > from ? (distance - from) / (to - from) : 0.0;
      return (index: index, progress: progress < 0 ? 0 : progress);
    }
    from = to;
  }
  return null;
}

/// The gap between ticks at [progress], in milliseconds, or null where there are none.
int? tickGap(double progress) {
  if (progress < _approachFrom || progress >= 1) return null;
  final near = (progress - _approachFrom) / (1 - _approachFrom);
  // Eased, so most of the speeding up is in the last stretch, where it helps.
  return (_slowestMs - (_slowestMs - _fastestMs) * near * near).round();
}

/// What a drag remembers between moves (`Approaching`).
class Approaching {
  Approaching({this.lastTickAt = double.negativeInfinity, this.lastDistance = 0});
  double lastTickAt;
  double lastDistance;
}

/// Whether to tick now, for a drag at [distance] heading for [detents]. Moves [state] on. [now] is in milliseconds.
bool tickNow(Approaching state, List<double> detents, double distance, double now) {
  final outward = distance > state.lastDistance;
  state.lastDistance = distance;
  if (!outward) return false;
  final heading = approach(detents, distance);
  final gap = heading == null ? null : tickGap(heading.progress);
  if (gap == null || now - state.lastTickAt < gap) return false;
  state.lastTickAt = now;
  return true;
}
