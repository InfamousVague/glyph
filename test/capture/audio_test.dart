import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/audio.dart';

/// The resampler exists for the platform that ignores the rate it was asked for. If it is wrong, Whisper hears
/// speech at the wrong speed and transcribes nothing, with no error anywhere - so its arithmetic is pinned here,
/// case for case with the web's `capture/audio.test.ts`.

Float32List sine(int rate, double seconds, int hz) =>
    Float32List.fromList([for (var i = 0; i < (rate * seconds).round(); i += 1) math.sin((2 * math.pi * hz * i) / rate)]);

void main() {
  group('createResampler', () {
    test('passes 16 kHz through untouched', () {
      final input = sine(16000, 0.1, 440);
      expect(identical(createResampler(16000, 16000)(input), input), true);
    });

    test('turns one second at 48 kHz into one second at 16 kHz', () {
      final out = createResampler(48000, 16000)(sine(48000, 1, 440));
      expect(out.length, 16000);
    });

    test('handles a non-integer ratio (44.1 kHz) without drifting', () {
      final out = createResampler(44100, 16000)(sine(44100, 2, 440));
      expect((out.length - 32000).abs(), lessThanOrEqualTo(1));
    });

    // The device hands over 200 ms at a time. Resampling chunk by chunk has to give the same samples as resampling
    // the whole, or every boundary is a click.
    test('gives the same output whether fed whole or in chunks', () {
      final input = sine(48000, 1, 300);
      final whole = createResampler(48000, 16000)(input);
      final chunked = createResampler(48000, 16000);
      final parts = <double>[];
      for (var i = 0; i < input.length; i += 9600) {
        parts.addAll(chunked(Float32List.sublistView(input, i, math.min(i + 9600, input.length))));
      }
      expect(parts.length, whole.length);
      var worst = 0.0;
      for (var i = 0; i < parts.length; i += 1) {
        worst = math.max(worst, (parts[i] - whole[i]).abs());
      }
      expect(worst, lessThan(1e-6));
    });

    test('keeps a speech-band tone recognisable after decimation', () {
      final out = createResampler(48000, 16000)(sine(48000, 0.5, 300));
      final expected = sine(16000, 0.5, 300);
      // Box averaging over 3 samples attenuates 300 Hz by well under 1 dB, and shifts phase by one input sample;
      // correlation stays close to 1.
      var dot = 0.0;
      var a = 0.0;
      var b = 0.0;
      for (var i = 0; i < out.length; i += 1) {
        final want = i < expected.length ? expected[i] : 0.0;
        dot += out[i] * want;
        a += out[i] * out[i];
        b += want * want;
      }
      expect(dot / math.sqrt(a * b), greaterThan(0.98));
    });
  });
}
