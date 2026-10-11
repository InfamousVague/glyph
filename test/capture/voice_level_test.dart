import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/voice_level.dart';

/// The rings the voice sends out (lib/capture/voice_level.dart), case for case with the web's
/// `capture/voiceLevel.test.ts`.

/// Rings sent out over [ms] at a steady [level], a frame every 16 ms.
List<RingShape> ringsOver(double level, int ms) {
  final pacer = RingPacer(smooth: level, lastRingAt: double.negativeInfinity);
  final rings = <RingShape>[];
  for (var now = 0; now <= ms; now += 16) {
    final ring = paceRings(pacer, level, now.toDouble());
    if (ring != null) rings.add(ring);
  }
  return rings;
}

void main() {
  group('rings sent out by the voice', () {
    test('keeps a slow faint beat in silence', () {
      final rings = ringsOver(0, 6000);
      expect(rings.length, 3);
      expect(rings[0].opacity, closeTo(0.16, 0.005));
    });

    test('sends more, wider, brighter rings the louder the voice', () {
      final soft = ringsOver(0.3, 3000);
      final loud = ringsOver(1, 3000);
      expect(loud.length, greaterThan(soft.length));
      expect(soft.length, greaterThan(ringsOver(0, 3000).length));
      expect(loud[0].reach, greaterThan(soft[0].reach));
      expect(loud[0].opacity, greaterThan(soft[0].opacity));
      expect(loud[0].durationMs, lessThan(soft[0].durationMs));
    });

    test('eases toward a new level instead of jumping', () {
      final pacer = RingPacer(smooth: 0, lastRingAt: 0);
      paceRings(pacer, 1, 10);
      expect(pacer.smooth, greaterThan(0));
      expect(pacer.smooth, lessThan(0.5));
    });

    test('hands the level to whoever listens, until they stop', () {
      final heard = <double>[];
      final off = onVoiceLevel(heard.add);
      publishVoiceLevel(0.4);
      off();
      publishVoiceLevel(0.9);
      expect(heard, [0.4]);
    });
  });
}
