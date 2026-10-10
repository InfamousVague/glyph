/// The recorder's microphone and transcriber, opened once per recorder in the order that keeps a voice note's first
/// words. A port of the logic of `src/app/capture/useCaptureSession.ts`.
///
/// Opened by a held side key, so everything here is ordered around one promise: the microphone is listening before
/// anything else is ready. It is opened first, the model loads while it listens, and samples captured in the
/// meantime are held and replayed rather than dropped - the first words of a voice note are usually its subject, and
/// a recorder that needs a second to warm up loses exactly them. A start that is called off (the screen closed at
/// once, or started twice) stops its own microphone rather than leaving it feeding the next start's session.
///
/// What was heard goes to `events`, always the newest given; what the pipeline did is counted in `counts` for the
/// diagnostics line (diagnostics.dart). The screen stops or cancels the session itself at Done and Discard, after
/// which `isFinished` answers true; a recorder closed without either cancels it here.
///
/// No always-on microphone: the microphone is opened by [CaptureSessionState.start] and let go by Done, Discard or
/// [CaptureSessionState.close], and nothing here opens one at any other time.
///
/// What differs:
/// - The web's is a React hook; this is the plain class a widget will wrap. The hook's state is its fields, with
///   listeners told when one changes ([CaptureSessionState] is a `ChangeNotifier`); its effect is [start], and the
///   effect's cleanup is [close]. As in React, a start may be called off and made again on the same object, and each
///   start keeps what it hears to itself.
/// - What the hook imports is given: whether there is a native core (`isTauri()`), whether a simulation was asked
///   for (`?simulate`), `openMicrophone` (audio.dart), `startCapture` (engine.dart), the haptic
///   (`core/haptics.ts` `fireNativeHaptic`), and where a line is logged (`console.info`, `console.warn`).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'audio.dart';
import 'diagnostics.dart';
import 'engine.dart';
import 'markdown.dart' show Segment;

/// Where the recorder is; `name` is the web's word.
enum Phase { starting, listening, finishing, failed }

/// What a session tells its screen.
class SessionEvents {
  const SessionEvents({required this.onPartial, required this.onSegment, required this.onLevel, this.onMicrophoneLost});

  /// A guess at the words not yet committed; '' when it clears.
  final void Function(String text) onPartial;

  /// A committed phrase.
  final void Function(Segment segment) onSegment;

  /// The microphone's level for a chunk: `level` 0 to 1 for drawing, and the `rms` it came from.
  final void Function(double level, double rms) onLevel;

  /// The microphone of the take under way closed without being asked to: the phone took it, or it failed
  /// (`Microphone.lost`), with why. Nothing more will be heard, so the screen keeps what was (as Done does).
  final void Function(String reason)? onMicrophoneLost;
}

/// One start's own: whether it was called off, and what its microphone heard before its engine was up.
class _Start {
  bool cancelled = false;
  final List<Float32List> held = <Float32List>[];
}

/// The recorder's session as its screen holds it (`CaptureSessionState`, what `useCaptureSession` answers).
class CaptureSessionState extends ChangeNotifier {
  CaptureSessionState({
    required this.fromAssistant,
    required this.isFinished,
    required this.events,
    required this.native,
    this.simulate = false,
    required this.openMicrophone,
    required this.startCapture,
    this.fireNativeHaptic,
    this.info,
    this.warn,
  });

  /// Opened by the side key, where the OS has already buzzed: no buzz of its own as it starts.
  final bool fromAssistant;

  /// Whether Done or Discard has begun, and so owns stopping the session. Read when it is asked, so the newest
  /// given is the one that answers.
  bool Function() isFinished;

  /// Who hears what was heard: the newest given.
  SessionEvents events;

  /// Whether there is a native core, whose engine wants the microphone's samples (`isTauri()`).
  final bool native;

  /// Whether a simulation was asked for, which opens no microphone (`?simulate`).
  final bool simulate;

  final Future<Microphone> Function(MicrophoneHandlers handlers) openMicrophone;
  final Future<CaptureSession> Function(CaptureHandlers handlers) startCapture;

  /// The phone's buzz, by its kind: `medium` as a recording starts, `error` when it cannot.
  final void Function(String kind)? fireNativeHaptic;
  final void Function(String line)? info;
  final void Function(String line)? warn;

  Phase _phase = Phase.starting;
  EngineKind? _engine;
  ({int received, int total})? _download;
  String? _error;

  Phase get phase => _phase;
  void setPhase(Phase phase) => _set(() => _phase = phase);

  /// Which engine is listening, once one is.
  EngineKind? get engine => _engine;

  /// The voice model's download, while one is under way.
  ({int received, int total})? get download => _download;

  String? get error => _error;
  void setError(String? error) => _set(() => _error = error);

  /// The running session, its microphone, and the pipeline's counts: the hook's three refs.
  CaptureSession? session;
  Microphone? microphone;
  Diagnostics counts = emptyDiagnostics;

  bool _closed = false;
  _Start? _current;

  void _set(void Function() change) {
    change();
    if (!_closed) notifyListeners();
  }

  /// Opens the microphone, then the engine (the hook's effect). Started once per recorder; a new capture is a new
  /// one.
  void start() {
    _closed = false;
    final mine = _Start();
    _current = mine;
    unawaited(_start(mine));
  }

  Future<void> _start(_Start mine) async {
    try {
      if (native && !simulate) {
        final handlers = MicrophoneHandlers(
          onChunk: (samples) {
            // A start that was called off keeps nothing it hears (see the microphone opening below).
            if (mine.cancelled) return;
            counts.heardSamples += samples.length;
            final running = session;
            if (running != null) {
              running.push(samples);
            } else {
              mine.held.add(samples);
            }
          },
          // Five a second, straight to the screen: too many for a meter nobody reads precisely to be rebuilt for.
          onLevel: (rms) => events.onLevel(math.min(1, rms * 8), rms),
        );
        final opened = await openMicrophone(handlers);
        // Called off while the microphone was opening (the screen closed at once, or a start made twice): this
        // start's microphone goes, rather than living on unowned and feeding the next start's session a second copy
        // of every chunk, interleaved - a take that plays back choppy at half speed, and that the voice model hears
        // as nonsense.
        if (mine.cancelled) {
          opened.stop();
          return;
        }
        microphone = opened;
        counts.deviceRate = opened.deviceRate;
        // The device closing by itself is heard: the web's recorder went on counting over a dead stream.
        unawaited(opened.lost?.then<void>((reason) => _lost(mine, opened, reason)));
        info?.call('[glyph] microphone open at ${opened.deviceRate} Hz, context ${opened.state().name}');
      }
      final started = await startCapture(CaptureHandlers(
        onPartial: (text) {
          if (text.isNotEmpty) counts.partials += 1;
          events.onPartial(text);
        },
        onSegment: (segment) {
          counts.segments += 1;
          counts.lastError = null;
          events.onSegment(segment);
        },
        onError: (message) {
          counts.errors += 1;
          counts.lastError = message;
          warn?.call('[glyph] capture error: $message');
          setError(message);
        },
        onModelProgress: (received, total) => _set(() => _download = (received: received, total: total)),
      ));
      if (mine.cancelled) {
        unawaited(Future<void>.sync(started.cancel));
        microphone?.stop();
        return;
      }
      session = started;
      if (started.wantsSamples) {
        final heard = List<Float32List>.of(mine.held);
        mine.held.clear();
        for (final samples in heard) {
          started.push(samples);
        }
      } else {
        microphone?.stop();
      }
      _set(() {
        _engine = started.kind;
        _download = null;
        _phase = Phase.listening;
      });
      info?.call('[glyph] capture started with ${started.kind.name}');
      if (!fromAssistant) fireNativeHaptic?.call('medium');
    } catch (failure) {
      if (mine.cancelled) return;
      microphone?.stop();
      _set(() {
        _error = _failureText(failure);
        _phase = Phase.failed;
      });
      fireNativeHaptic?.call('error');
    }
  }

  /// [opened] closed by itself. Only the take that is still this one's, still running and not already being
  /// ended, hears of it.
  void _lost(_Start mine, Microphone opened, String reason) {
    if (mine.cancelled || _closed || !identical(microphone, opened) || isFinished()) return;
    warn?.call('[glyph] the microphone closed by itself: $reason');
    events.onMicrophoneLost?.call(reason);
  }

  /// The recorder went (the effect's cleanup): the start under way is called off, and unless Done or Discard has
  /// begun, the session is cancelled and the microphone let go.
  void close() {
    _current?.cancelled = true;
    _closed = true;
    if (!isFinished()) {
      final running = session;
      if (running != null) unawaited(Future<void>.sync(running.cancel));
      microphone?.stop();
    }
  }
}

/// A caught thing as words (`core/failure.ts` `failureText`): an error's message, or the thing itself as text.
String _failureText(Object failure) {
  if (failure is String) return failure;
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'Bad state: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}
