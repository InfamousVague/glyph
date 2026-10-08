import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/diagnostics.dart';
import 'package:ghost_md/capture/engine.dart' show EngineKind;

/// The recorder's diagnostics line (lib/capture/diagnostics.dart): the one that told the Fold's silent capture
/// apart. Case for case with the web's `capture/diagnostics.test.ts`.
void main() {
  group('what the pipeline has done, in a line', () {
    test('says how much was heard, at what rate, and what came of it, one or many', () {
      expect(countsLine(emptyDiagnostics.copyWith(heardSamples: 131200, deviceRate: 48000, partials: 3, segments: 1)), 'heard 8.2 s at 48 kHz · 3 guesses · 1 phrase');
      expect(countsLine(emptyDiagnostics.copyWith(partials: 1, segments: 2)), 'heard 0.0 s · 1 guess · 2 phrases');
    });

    test('ends with the errors and the last of them', () {
      expect(countsLine(emptyDiagnostics.copyWith(errors: 2, lastError: () => 'capture_push rejected')), 'heard 0.0 s · 0 guesses · 0 phrases · 2 errors: capture_push rejected');
      expect(countsLine(emptyDiagnostics.copyWith(errors: 1, lastError: () => null)), matches(RegExp(r'1 error: $')));
    });

    test('opens with the engine once one is listening', () {
      expect(diagnosticsLine(EngineKind.whisper, emptyDiagnostics), 'On-device Whisper · heard 0.0 s · 0 guesses · 0 phrases');
      expect(diagnosticsLine(null, emptyDiagnostics), 'heard 0.0 s · 0 guesses · 0 phrases');
    });
  });

  group('a capture worth explaining unasked', () {
    final heardLong = emptyDiagnostics.copyWith(heardSamples: 8 * 16000 + 1);

    test('is Whisper hearing more than eight seconds and making nothing of it', () {
      expect(soundsSilent(EngineKind.whisper, heardLong), true);
    });

    test('is not one that made a guess or a phrase, heard less, or ran on another engine', () {
      expect(soundsSilent(EngineKind.whisper, heardLong.copyWith(partials: 1)), false);
      expect(soundsSilent(EngineKind.whisper, heardLong.copyWith(segments: 1)), false);
      expect(soundsSilent(EngineKind.whisper, heardLong.copyWith(heardSamples: 8 * 16000)), false);
      expect(soundsSilent(EngineKind.browser, heardLong), false);
      expect(soundsSilent(null, heardLong), false);
    });
  });
}
