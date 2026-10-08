/// The microphone's level while recording, for what draws it: 0 (silence) to 1 (talking up close), about five times
/// a second (capture/audio.dart `onLevel`). A port of `src/app/capture/voiceLevel.ts`.
///
/// Drawings that do more than scale with it (the rings behind the mic, which are sent out by the voice) subscribe
/// here instead of polling a style.
///
/// What differs: nothing. The listeners are the library's own, as they are the module's on the web.
library;

import 'dart:math' as math;

final Set<void Function(double level)> _listeners = <void Function(double level)>{};

void publishVoiceLevel(double level) {
  for (final listener in _listeners.toList()) {
    listener(level);
  }
}

/// Hears every level published; answers the way to stop.
void Function() onVoiceLevel(void Function(double level) listener) {
  _listeners.add(listener);
  return () {
    _listeners.remove(listener);
  };
}

/// One ring the voice sends out: how far it travels, how bright, how thick, how long.
class RingShape {
  const RingShape({required this.reach, required this.opacity, required this.stroke, required this.durationMs});

  final double reach;
  final double opacity;
  final double stroke;
  final double durationMs;

  @override
  bool operator ==(Object other) =>
      other is RingShape && other.reach == reach && other.opacity == opacity && other.stroke == stroke && other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(reach, opacity, stroke, durationMs);

  @override
  String toString() => 'RingShape(reach: $reach, opacity: $opacity, stroke: $stroke, durationMs: $durationMs)';
}

/// What paces the rings from frame to frame; `paceRings` changes it in place, as the web does.
class RingPacer {
  RingPacer({required this.smooth, required this.lastRingAt});

  /// The level eased toward what the microphone last said, frame by frame.
  double smooth;
  double lastRingAt;
}

/// Below this the voice is quiet, and the rings keep the slow resting beat (`TALKING`).
const double talking = 0.12;
const double _restingGapMs = 2700;

/// Frame by frame: ease the level, and decide whether a ring goes out now. Talking sends rings out closer together
/// the louder it is (every 220 ms at full voice, 540 ms just above quiet), each wider, brighter and quicker; a pause
/// falls back to one faint ring every 2.7 seconds, so the screen still shows it is listening.
RingShape? paceRings(RingPacer pacer, double level, double now) {
  pacer.smooth += (level - pacer.smooth) * 0.25;
  final voice = math.max(0.0, math.min(1.0, pacer.smooth));
  final isTalking = voice > talking;
  final gap = isTalking ? 220 + (1 - voice) * 360 : _restingGapMs;
  if (now - pacer.lastRingAt < gap) return null;
  pacer.lastRingAt = now;
  final strength = isTalking ? voice : 0.0;
  return RingShape(
    reach: 0.5 + strength * 0.5,
    opacity: 0.16 + strength * 0.5,
    stroke: 1.5 + strength * 2.5,
    durationMs: 2700 - strength * 1000,
  );
}
