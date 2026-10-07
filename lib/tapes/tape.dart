/// A tape's geometry, kept apart from its drawing so it can be tested. A port of `src/app/capture/tape.ts`:
/// recording moves tape from the left reel to the right, so the right pack grows with the note and the left shrinks,
/// and each reel turns at the tape speed over its own radius. Geometry is in the drawing's own units (320 by 204).
/// Nothing differs.
library;

import 'dart:math' as math;

/// How much recording fills the tape when nobody says otherwise (`TAPE_MS`).
const int tapeMs = 300000;
const double hubR = 15;

/// The smallest a pack gets: a thin ring of leader tape around the hub.
const double packMinR = 18;
const double packMaxR = 44;
const double reelY = 88;
const double leftX = 104;
const double rightX = 216;

/// Tape speed, in units per millisecond: a half-full reel turns about once every 2.5 s.
const double _tapeSpeed = 0.075;

/// Pack radii for a recorded length on a tape [lengthMs] long. The tape's area is conserved, so the radii move as
/// square roots.
({double supply, double takeup}) packRadii(num positionMs, [num lengthMs = tapeMs]) {
  final f = (positionMs / math.max(1, lengthMs)).clamp(0.0, 1.0);
  final span = packMaxR * packMaxR - packMinR * packMinR;
  return (supply: math.sqrt(packMaxR * packMaxR - f * span), takeup: math.sqrt(packMinR * packMinR + f * span));
}

/// Degrees each reel turns in [ms] of tape passing, at the radii for [positionMs] on a tape [lengthMs] long.
({double supply, double takeup}) reelTurn(num positionMs, num ms, [num lengthMs = tapeMs]) {
  final packs = packRadii(positionMs, lengthMs);
  double deg(double r) => ((ms * _tapeSpeed) / r) * (180 / math.pi);
  return (supply: deg(packs.supply), takeup: deg(packs.takeup));
}

/// The tape counter: "0:07", "12:40", "1:02:03".
String counter(num ms) {
  final total = math.max(0, (ms / 1000).floor());
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
