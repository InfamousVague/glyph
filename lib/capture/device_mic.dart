/// The phone's microphone for dictation: the [MicrophoneInput] audio.dart is written against, over the Kotlin
/// `AudioRecord` in android/…/glyph/capture/DictationMic.kt (16 kHz, mono, float, 200 ms chunks). The web app had
/// no such file: its microphone was the page's `getUserMedia`.
///
/// NO ALWAYS-ON MICROPHONE. The device is opened by [DeviceMic.open] / [DeviceMic.openWith], which the recorder
/// calls when a person starts recording, and let go by [close] (its pause, stop and cancel). Android lets go of it
/// too whenever the app is no longer visible ([closed] then says "background"). Nothing here opens it at launch.
///
/// Two ways the samples travel, chosen at [openWith]:
///
/// - **Through Dart** (the default, and what [open] does): each chunk arrives here and is handed to [onSamples],
///   so `openMicrophone` (audio.dart) measures it and the capture engine pushes it to the core, exactly as the web
///   app's recorder did. This is what `CaptureEngine` and `CaptureSession` as ported expect: they hold what is
///   heard while the model loads and count what they push.
/// - **Straight into the core** (`direct: true`): Kotlin pushes each chunk into the Rust capture over JNI
///   (`ghost_capture_push`), with no base64 and no hop through two isolates, and Dart hears only [levels]. Chunks
///   heard before the capture has started are held in Kotlin (thirty seconds at most) until [flow] is called,
///   which the caller does once `capture_start` has resolved. [onSamples] is given nothing. For a recorder that
///   does not need the samples itself; its position is [samples] at 16 kHz.
///
/// ```dart
/// final mic = await openMicrophone(handlers, open: DeviceMic.open);   // as the recorder does
/// ```
///
/// The permission is asked for the first time a recording is started ([DeviceMic.request], inside [openWith]); a
/// refusal is a [MicrophoneRefused], whose [MicrophoneRefused.blocked] says the phone will not ask again and only
/// its settings change that ([DeviceMic.openSettings]).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/mac_app.dart';
import 'audio.dart';

/// The microphone was not allowed, or would not open. [message] is for the recorder to show.
class MicrophoneRefused implements Exception {
  const MicrophoneRefused(this.message, {this.blocked = false});

  final String message;

  /// Refused for good: Android will show no dialog again, and only the phone's settings change it.
  final bool blocked;

  @override
  String toString() => message;
}

/// What the device heard in all, said when it is let go.
typedef MicTotals = ({int samples, int pushed, int refused});

class DeviceMic implements MicrophoneInput {
  DeviceMic._(this.sampleRate, this.direct);

  static const MethodChannel channel = MethodChannel('ghost_md/mic');
  static const EventChannel eventChannel = EventChannel('ghost_md/mic/events');

  /// Whether this platform has a microphone behind the channel: Kotlin's on Android, Swift's in the Mac app
  /// (macos/Runner/MicChannel.swift, the same contract over `AVAudioEngine`).
  static bool get supported => Platform.isAndroid || runsAsMacApp;

  /// "granted", "ask" (the system's dialog can still be shown) or "blocked" (it cannot).
  static Future<String> permission() async => await channel.invokeMethod<String>('permission') ?? 'blocked';

  /// Shows the system's dialog and answers "granted", "denied" or "blocked".
  static Future<String> request() async => await channel.invokeMethod<String>('request') ?? 'blocked';

  /// Opens the app's page in the phone's settings, where a blocked microphone is allowed again.
  static Future<bool> openSettings() async => await channel.invokeMethod<bool>('openSettings') ?? false;

  /// An [OpenMicrophoneInput]: the device through Dart, asking for the permission if it has not been answered.
  /// The rate and the chunk are the ones audio.dart asks for (16 kHz, 3,200 samples), which are the device's own.
  static Future<MicrophoneInput> open(MicrophoneConstraints constraints, {required int sampleRate, required int chunk}) => openWith(constraints);

  /// Opens the device. [direct] sends the samples straight into the core (see the library's header). [testWav] is
  /// a debug build's only: a 16 kHz mono PCM16 WAV file played in place of the device, for an emulator with no
  /// audio. Throws [MicrophoneRefused].
  static Future<DeviceMic> openWith(MicrophoneConstraints constraints, {bool direct = false, String? testWav}) async {
    if (!supported) throw const MicrophoneRefused('This device has no microphone Ghost.md can open.');
    if (testWav == null) {
      var allowed = await permission();
      if (allowed == 'ask') allowed = await request();
      if (allowed != 'granted') {
        throw MicrophoneRefused('Ghost.md needs the microphone to record.', blocked: allowed == 'blocked');
      }
    }
    // Listening from before the device opens, so its first chunk is heard.
    final early = <Object?>[];
    DeviceMic? mic;
    final heard = eventChannel.receiveBroadcastStream().listen((event) => mic == null ? early.add(event) : mic._heard(event));
    try {
      final opened = await channel.invokeMapMethod<String, Object?>('open', {
        'direct': direct,
        'noiseSuppression': constraints.noiseSuppression,
        'autoGainControl': constraints.autoGainControl,
        'testWav': ?testWav,
      });
      final made = DeviceMic._((opened?['sampleRate'] as num?) ?? 16000, direct).._subscription = heard;
      mic = made;
      early.forEach(made._heard);
      return made;
    } on PlatformException catch (failure) {
      await heard.cancel();
      throw MicrophoneRefused(failure.message ?? 'The microphone could not be opened.', blocked: false);
    }
  }

  @override
  final num sampleRate;

  /// Whether the samples go straight into the core, and not to [onSamples].
  final bool direct;

  StreamSubscription<Object?>? _subscription;
  void Function(Float32List samples)? _onSamples;
  AudioContextState _state = AudioContextState.running;
  int _samples = 0;
  final StreamController<({double rms, int samples})> _levels = StreamController<({double rms, int samples})>.broadcast(sync: true);
  final Completer<String> _closed = Completer<String>();
  final Completer<MicTotals?> _totals = Completer<MicTotals?>();

  /// Running until it is let go: an `AudioRecord` that opened is never left suspended.
  @override
  AudioContextState get state => _state;

  @override
  set onSamples(void Function(Float32List samples)? handler) => _onSamples = handler;

  /// How loud each chunk was (root mean square, 0-1) and how many samples have been heard since the device opened:
  /// the meter's feed when the samples themselves go straight into the core.
  Stream<({double rms, int samples})> get levels => _levels.stream;

  /// Samples heard since the device opened.
  int get samples => _samples;

  /// Why the device was let go: "closed" by [close], "background" when the app left the screen, "error" when the
  /// device failed.
  Future<String> get closed => _closed.future;

  /// What was heard in all, once [close] has been answered: null when Android had let go of it already.
  Future<MicTotals?> get totals => _totals.future;

  /// Direct only: the capture has started, so what was held goes to the core, in order, and the rest follows.
  Future<void> flow() => channel.invokeMethod<void>('flow');

  /// Nothing to wake: the device runs from the moment it opens.
  @override
  Future<void> resume() async {}

  @override
  void close() {
    if (_state == AudioContextState.closed) return;
    _end('closed');
    unawaited(channel.invokeMapMethod<String, Object?>('close').then<void>((said) {
      _totals.complete(said == null ? null : (samples: (said['samples'] as num).toInt(), pushed: (said['pushed'] as num).toInt(), refused: (said['refused'] as num).toInt()));
    }, onError: (Object _) => _totals.complete(null)));
  }

  void _end(String reason) {
    _state = AudioContextState.closed;
    _onSamples = null;
    unawaited(_subscription?.cancel());
    unawaited(_levels.close());
    if (!_closed.isCompleted) _closed.complete(reason);
  }

  void _heard(Object? event) {
    if (event is! Map || _state == AudioContextState.closed) return;
    switch (event['event']) {
      case 'chunk':
        _samples = (event['samples'] as num?)?.toInt() ?? _samples;
        _levels.add((rms: (event['rms'] as num?)?.toDouble() ?? 0, samples: _samples));
        final pcm = event['pcm'];
        if (pcm is Uint8List) {
          // A copy, aligned: the channel's bytes may sit at any offset of a larger buffer.
          final floats = Float32List(pcm.lengthInBytes ~/ 4);
          floats.buffer.asUint8List().setAll(0, pcm);
          _onSamples?.call(floats);
        }
      case 'closed':
        _end(event['reason'] as String? ?? 'error');
        if (!_totals.isCompleted) _totals.complete(null);
    }
  }
}
