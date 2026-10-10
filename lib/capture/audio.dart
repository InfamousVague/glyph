/// The microphone, as 16 kHz mono float samples. A port of `src/app/capture/audio.ts`.
///
/// 16 kHz because that is what Whisper consumes. Samples are handed over in chunks of about 200 ms: smaller chunks
/// cost a trip to the engine each for no gain in latency, since it only looks at the buffer every 600-800 ms; larger
/// ones delay the first partial.
///
/// No always-on microphone: one is opened by [openMicrophone], between a recording's start and its stop or cancel,
/// and at no other time.
///
/// What differs:
/// - On the web the microphone IS the page's: `getUserMedia`, an `AudioContext` asked for 16 kHz, and a worklet
///   (`GlyphTap`) that copies samples into 3,200-sample chunks, feeding a silent gain so the platform pulls it. None
///   of that exists here. What opens the device is a parameter, [OpenMicrophoneInput], answering a
///   [MicrophoneInput]: the stream, the context and the tap as one thing that says its rate and its state, hands
///   over chunks, can be woken and can be let go. The Flutter app's real one is a Kotlin `AudioRecord` (piece 8D),
///   which may push straight into the Rust core and never come through here at all; then this file's part is the
///   resampler and the interface the session is written against.
/// - The worklet's source text, the Blob URL and the silent sink are left out with the browser they are for.
/// - Everything else is the web's: what is asked of the device ([MicrophoneConstraints]), the rate checked and
///   brought to 16 kHz when the platform ignored it, the level of each chunk, and a resume that is waited for no
///   longer than a second and a half.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// The rate Whisper consumes (`SAMPLE_RATE`).
const int _sampleRate = 16000;

/// Samples a chunk: 200 ms (`CHUNK`).
const int _chunk = 3200;

/// An audio context's state, in the web's words (`AudioContextState`).
enum AudioContextState { suspended, running, closed }

/// An open microphone, as the recorder holds it.
class Microphone {
  const Microphone({required this.stop, required this.deviceRate, required this.state, this.lost});

  final void Function() stop;

  /// Settles with why, if the device closes without [stop] being asked: the phone took it away, or it failed
  /// ([LosableInput]). Never settles for a device let go by [stop]; null for one that cannot say. The page's stream
  /// had no such word (nothing there listened for a track's `ended`), so a recorder whose microphone had died went
  /// on counting; here the recorder is told, and keeps what it heard (capture_session.dart).
  final Future<String>? lost;

  /// The rate the device actually runs at, before any resampling to 16 kHz.
  final num deviceRate;

  /// The device's state now: one that stays suspended delivers nothing.
  final AudioContextState Function() state;
}

/// A streaming resampler to 16 kHz, for a platform that ignores the rate it was asked for.
///
/// When a platform does not honour the rate the failure is silent and total: 48 kHz samples labelled 16 kHz reach
/// Whisper as speech slowed to a third of its speed, which it hears as noise and transcribes as nothing. So the
/// actual rate is checked, and anything else is brought to 16 kHz here.
///
/// Each output sample is the mean of the input samples its window covers. A box average is a crude low-pass, but it
/// is the low-pass decimation needs to stop high frequencies folding back into the speech band, and Whisper was
/// trained on far rougher audio than this. State carries across calls, so a chunk boundary never produces a click or
/// a dropped sample.
Float32List Function(Float32List input) createResampler(num fromRate, num toRate) {
  if (fromRate == toRate) return (input) => input;
  final step = fromRate / toRate;
  var carry = Float32List(0);
  var position = 0.0;
  return (input) {
    final buffer = Float32List(carry.length + input.length);
    buffer.setAll(0, carry);
    buffer.setAll(carry.length, input);
    final out = <double>[];
    while (position + step <= buffer.length) {
      final start = position.floor();
      final end = (position + step).floor();
      if (end <= start) {
        out.add(start < buffer.length ? buffer[start] : 0);
      } else {
        var sum = 0.0;
        for (var i = start; i < end; i += 1) {
          sum += i < buffer.length ? buffer[i] : 0;
        }
        out.add(sum / (end - start));
      }
      position += step;
    }
    final consumed = position.floor();
    carry = Float32List.fromList(buffer.sublist(math.min(consumed, buffer.length)));
    position -= consumed;
    return Float32List.fromList(out);
  };
}

/// What the recorder is told as the microphone hears.
class MicrophoneHandlers {
  const MicrophoneHandlers({required this.onChunk, required this.onLevel});

  final void Function(Float32List samples) onChunk;

  /// Root-mean-square level of the latest chunk, 0-1, for the meter.
  final void Function(double rms) onLevel;
}

/// What is asked of the device (the web's `getUserMedia` constraints): one channel, with noise suppression and gain
/// control, which help recognition in a pocket or a street, and no echo cancellation, which does nothing useful when
/// nothing is playing and can clip the first syllable while it converges.
class MicrophoneConstraints {
  const MicrophoneConstraints({this.channelCount = 1, this.noiseSuppression = true, this.autoGainControl = true, this.echoCancellation = false});

  final int channelCount;
  final bool noiseSuppression;
  final bool autoGainControl;
  final bool echoCancellation;

  @override
  bool operator ==(Object other) =>
      other is MicrophoneConstraints &&
      other.channelCount == channelCount &&
      other.noiseSuppression == noiseSuppression &&
      other.autoGainControl == autoGainControl &&
      other.echoCancellation == echoCancellation;

  @override
  int get hashCode => Object.hash(channelCount, noiseSuppression, autoGainControl, echoCancellation);

  @override
  String toString() =>
      'MicrophoneConstraints(channelCount: $channelCount, noiseSuppression: $noiseSuppression, autoGainControl: $autoGainControl, echoCancellation: $echoCancellation)';
}

/// The device, open: what stands here for the web's stream, its `AudioContext` and the tap between them.
abstract class MicrophoneInput {
  /// The rate it really runs at, whatever was asked for.
  num get sampleRate;

  AudioContextState get state;

  /// Who is handed each chunk, at [sampleRate]; null hands them to nobody (the tap's `port.onmessage`).
  set onSamples(void Function(Float32List samples)? handler);

  /// Wake a device the platform left suspended. A resume the platform declines may never settle.
  Future<void> resume();

  /// Let go of all of it: the tap, the tracks, the context.
  void close();
}

/// Opens the device with what [openMicrophone] asks of it: the constraints, the rate wanted, and how many samples a
/// chunk. Rejects when the person declines the microphone or the platform has none.
/// A [MicrophoneInput] that can say it was closed without being asked to.
abstract interface class LosableInput {
  /// Settles with the reason when the device closes by itself: `error` when it failed, `background` when the phone
  /// let go of it with the app's window. Never settles for a device let go by `close`.
  Future<String> get lost;
}

typedef OpenMicrophoneInput = Future<MicrophoneInput> Function(MicrophoneConstraints constraints, {required int sampleRate, required int chunk});

/// Start capturing. Rejects when the person declines the microphone or the platform has none; the caller shows why.
Future<Microphone> openMicrophone(MicrophoneHandlers handlers, {required OpenMicrophoneInput open}) async {
  final input = await open(const MicrophoneConstraints(), sampleRate: _sampleRate, chunk: _chunk);

  final resample = createResampler(input.sampleRate, _sampleRate);
  input.onSamples = (data) {
    final samples = resample(data);
    if (samples.isEmpty) return;
    var sum = 0.0;
    for (var i = 0; i < samples.length; i += 1) {
      sum += samples[i] * samples[i];
    }
    handlers.onLevel(math.sqrt(sum / samples.length));
    handlers.onChunk(samples);
  };

  // A suspended device delivers no audio at all. Resuming is bounded, because a resume the platform declines never
  // settles, and an unbounded await here would leave the capture screen reading "Starting" forever with no error.
  if (input.state == AudioContextState.suspended) {
    await Future.any<void>([input.resume(), Future<void>.delayed(const Duration(milliseconds: 1500))]);
  }

  return Microphone(
    deviceRate: input.sampleRate,
    state: () => input.state,
    stop: () {
      input.onSamples = null;
      input.close();
    },
    lost: input is LosableInput ? (input as LosableInput).lost : null,
  );
}
