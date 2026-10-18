/// The ear an ask said aloud is heard with (lib/claude/claude_voice.dart [ClaudeEar]): the recorder's own, the cheapest
/// way to words this app has on the phone. The recorder's session (capture/capture_session.dart
/// [CaptureSessionState]) opens the phone's microphone first and the transcriber while it listens, holding what is
/// heard until it is up, so the first word is never lost; the transcriber is Whisper in the Rust core, on the phone,
/// whose guesses at the words still coming arrive as they are made and are shown as they come. Nothing is sent
/// anywhere to be heard, and the ask needs no model of its own: it is the voice model a voice note uses, fetched once.
///
/// What differs from a voice note: nothing is kept. The take is stopped without a note to keep its tape in (no
/// `recordAs`, so the core keeps no audio), and its words go to Claude, not into a note. While it listens, the better
/// words' pass over an earlier recording waits, as it waits for the recorder: the same cores.
///
/// No always-on microphone: the microphone is opened when the ear is (a press), and let go by [ClaudeHearing.finish]
/// or [ClaudeHearing.cancel].
library;

import 'dart:async';

import '../capture/audio.dart' show Microphone, MicrophoneHandlers;
import '../capture/capture_session.dart';
import '../capture/engine.dart' show CaptureHandlers, CaptureSession;
import '../capture/markdown.dart' show Segment;
import 'claude_voice.dart';

/// An ear over the recorder's microphone and transcriber. [setLive] holds the better words' pass while it listens;
/// [haptic] is the phone's buzz as listening starts and if it cannot.
ClaudeEar recorderEar({
  required Future<Microphone> Function(MicrophoneHandlers handlers)? openMicrophone,
  required Future<CaptureSession> Function(CaptureHandlers handlers) startCapture,
  required bool native,
  bool simulate = false,
  void Function(bool live)? setLive,
  void Function(String kind)? haptic,
  void Function(String line)? warn,
}) =>
    (heard) => _RecorderHearing(heard, openMicrophone: openMicrophone, startCapture: startCapture, native: native, simulate: simulate, setLive: setLive, haptic: haptic, warn: warn);

class _RecorderHearing implements ClaudeHearing {
  _RecorderHearing(
    this.heard, {
    required Future<Microphone> Function(MicrophoneHandlers handlers)? openMicrophone,
    required Future<CaptureSession> Function(CaptureHandlers handlers) startCapture,
    required bool native,
    required bool simulate,
    this.setLive,
    void Function(String kind)? haptic,
    void Function(String line)? warn,
  }) {
    setLive?.call(true);
    _state = CaptureSessionState(
      fromAssistant: false,
      isFinished: () => _finished,
      events: SessionEvents(
        onPartial: (text) {
          _partial = text;
          heard.words(_all);
        },
        onSegment: (Segment segment) {
          if (segment.text.trim().isNotEmpty) _committed.add(segment.text.trim());
          _partial = '';
          heard.words(_all);
        },
        onLevel: heard.level,
        onMicrophoneLost: (_) => heard.ended?.call(),
      ),
      native: native && openMicrophone != null,
      simulate: simulate,
      openMicrophone: openMicrophone ?? (_) => Future<Never>.error(StateError('This build has no microphone.')),
      startCapture: startCapture,
      fireNativeHaptic: haptic,
      info: warn,
      warn: warn,
    )..addListener(_changed);
    _state.start();
  }

  final ClaudeHeard heard;
  final void Function(bool live)? setLive;
  late final CaptureSessionState _state;

  final List<String> _committed = [];
  String _partial = '';
  bool _finished = false;
  bool _closed = false;

  String get _all => [..._committed, if (_partial.trim().isNotEmpty) _partial.trim()].join(' ');

  void _changed() {
    if (_closed) return;
    if (_state.phase == Phase.failed) {
      heard.problem(_state.error ?? 'The microphone would not open.');
      return;
    }
    final download = _state.download;
    if (download != null) heard.download?.call(download.received, download.total);
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _state
      ..removeListener(_changed)
      ..close();
    setLive?.call(false);
  }

  @override
  Future<String> finish() async {
    if (_closed) return _all;
    _finished = true;
    final session = _state.session;
    String? transcript;
    if (session != null) {
      try {
        // No note to keep it in: the core keeps no audio.
        transcript = (await session.stop()).transcript;
      } catch (_) {
        transcript = null;
      }
    } else {
      // Still starting (the model loading): the microphone goes now, and the start, called off, lets its engine go.
      _state.microphone?.stop();
    }
    final said = (transcript ?? '').trim();
    final words = said.isNotEmpty ? said : _all;
    _close();
    return words;
  }

  @override
  void cancel() {
    _finished = false;
    _close();
  }
}
