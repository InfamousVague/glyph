/// What the recorder's pipeline has actually done, counted where it happens (capture/capture_session.dart) and
/// copied to the screen a few times a second. A port of `src/app/capture/diagnostics.ts`.
///
/// The line it makes is essential: the first real capture on the Fold transcribed nothing and said "Listening" the
/// whole time, because an error during listening was stored and never shown. "Heard 8.2 s · 0 phrases" and "heard
/// 0.0 s" point at different halves of the chain - the microphone, or the model - which is the whole diagnosis
/// without a debugger attached. A tap on the top line shows it; a capture that has heard a while and made nothing of
/// it, or has had an error, shows it without being asked.
///
/// What differs: [Diagnostics] is a class whose fields can be written, since the session counts into one in place
/// (the web's `counts.current.partials += 1`); `EMPTY_DIAGNOSTICS` is the getter [emptyDiagnostics], a fresh one
/// each time, where the web spreads its constant; `ENGINE_LABEL` is the function [engineLabel] over the enum.
library;

import 'engine.dart' show EngineKind;

/// The counts, written in place by the session that makes them.
class Diagnostics {
  Diagnostics({this.heardSamples = 0, this.deviceRate, this.partials = 0, this.segments = 0, this.errors = 0, this.lastError});

  /// Samples the microphone handed over, at 16 kHz.
  int heardSamples;

  /// The rate the microphone really ran at, before resampling; null until it opened.
  num? deviceRate;

  /// Guesses at words not yet committed.
  int partials;

  /// Phrases committed.
  int segments;
  int errors;
  String? lastError;

  /// The web's spread: these counts with some of them said again. [lastError] is given in a function, so that null
  /// can be said.
  Diagnostics copyWith({int? heardSamples, num? deviceRate, int? partials, int? segments, int? errors, String? Function()? lastError}) => Diagnostics(
        heardSamples: heardSamples ?? this.heardSamples,
        deviceRate: deviceRate ?? this.deviceRate,
        partials: partials ?? this.partials,
        segments: segments ?? this.segments,
        errors: errors ?? this.errors,
        lastError: lastError == null ? this.lastError : lastError(),
      );

  @override
  bool operator ==(Object other) =>
      other is Diagnostics &&
      other.heardSamples == heardSamples &&
      other.deviceRate == deviceRate &&
      other.partials == partials &&
      other.segments == segments &&
      other.errors == errors &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(heardSamples, deviceRate, partials, segments, errors, lastError);

  @override
  String toString() => 'Diagnostics(${countsLine(this)})';
}

/// Nothing heard and nothing made of it (`EMPTY_DIAGNOSTICS`): a new one at each reading.
Diagnostics get emptyDiagnostics => Diagnostics();

/// Which engine is listening, in words a person can tell apart: a real on-device transcription from a fallback
/// (`ENGINE_LABEL`).
String engineLabel(EngineKind engine) => switch (engine) {
      EngineKind.whisper => 'On-device Whisper',
      EngineKind.browser => 'Browser speech recognition',
      EngineKind.simulated => 'Simulated voice',
    };

/// "heard 8.2 s at 48 kHz · 3 guesses · 1 phrase", plus the last error if there is one.
String countsLine(Diagnostics d) {
  final rate = d.deviceRate;
  final parts = ['heard ${(d.heardSamples / 16000).toStringAsFixed(1)} s${rate != null && rate != 0 ? ' at ${(rate / 1000).round()} kHz' : ''}'];
  parts.add('${d.partials} ${d.partials == 1 ? 'guess' : 'guesses'}');
  parts.add('${d.segments} ${d.segments == 1 ? 'phrase' : 'phrases'}');
  if (d.errors != 0) parts.add('${d.errors} ${d.errors == 1 ? 'error' : 'errors'}: ${d.lastError ?? ''}');
  return parts.join(' · ');
}

/// Whisper has heard more than eight seconds and made no guess and no phrase of it: the capture worth explaining
/// unasked.
bool soundsSilent(EngineKind? engine, Diagnostics d) =>
    engine == EngineKind.whisper && d.heardSamples > 8 * 16000 && d.partials == 0 && d.segments == 0;

/// The whole line: the engine, then what the pipeline has done.
String diagnosticsLine(EngineKind? engine, Diagnostics d) => [if (engine != null) engineLabel(engine), countsLine(d)].join(' · ');
