import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/audio.dart';

/// The microphone as the recorder opens it (lib/capture/audio.dart `openMicrophone`), against a stand-in for the
/// device: what it asks the platform for, what it hands on per chunk, what it does with a device the platform left
/// suspended, and what it lets go of at the end. Case for case with the web's `capture/microphone.test.ts`.
///
/// The web's stand-ins are the Web Audio parts jsdom lacks (a context, a worklet node, a gain); the Dart
/// microphone is one [MicrophoneInput], so what the web checks of the graph between them is checked of that.

class FakeInput implements MicrophoneInput {
  FakeInput({required this.sampleRate, required this.state, required this.resumeSettles});

  @override
  final num sampleRate;
  @override
  AudioContextState state;
  final bool resumeSettles;

  void Function(Float32List samples)? handler;
  bool handlerSet = false;
  int resumes = 0;
  int closes = 0;

  @override
  set onSamples(void Function(Float32List samples)? next) {
    handler = next;
    handlerSet = true;
  }

  @override
  Future<void> resume() {
    resumes += 1;
    if (!resumeSettles) return Completer<void>().future;
    return Future<void>.value().then((_) {
      state = AudioContextState.running;
    });
  }

  @override
  void close() => closes += 1;
}

List<FakeInput> inputs = [];
List<(MicrophoneConstraints, int, int)> asked = [];
num rate = 16000;
bool startsSuspended = false;
bool resumeSettles = true;
Object? declines;

Future<MicrophoneInput> open(MicrophoneConstraints constraints, {required int sampleRate, required int chunk}) async {
  asked.add((constraints, sampleRate, chunk));
  if (declines != null) throw declines!;
  final input = FakeInput(sampleRate: rate, state: startsSuspended ? AudioContextState.suspended : AudioContextState.running, resumeSettles: resumeSettles);
  inputs.add(input);
  return input;
}

MicrophoneHandlers quiet() => MicrophoneHandlers(onChunk: (_) {}, onLevel: (_) {});

void main() {
  setUp(() {
    inputs = [];
    asked = [];
    rate = 16000;
    startsSuspended = false;
    resumeSettles = true;
    declines = null;
  });

  group('the microphone', () {
    // The silent sink the web's tap feeds, and the Blob URL its worklet loads from, are the browser's and have no
    // counterpart: what is asked of the device is the whole of this case here.
    test('asks for one channel with noise suppressed and no echo cancelling, and feeds a silent sink', () async {
      await openMicrophone(quiet(), open: open);
      expect(asked, [(const MicrophoneConstraints(channelCount: 1, noiseSuppression: true, autoGainControl: true, echoCancellation: false), 16000, 3200)]);
      expect(inputs, hasLength(1));
    });

    test('hands on each chunk with its level, as the context gives it at 16 kHz', () async {
      final chunks = <Float32List>[];
      final levels = <double>[];
      final microphone = await openMicrophone(MicrophoneHandlers(onChunk: chunks.add, onLevel: levels.add), open: open);
      expect(microphone.deviceRate, 16000);
      inputs[0].handler?.call(Float32List.fromList([0.5, -0.5, 0.5, -0.5]));
      expect(chunks[0], Float32List.fromList([0.5, -0.5, 0.5, -0.5]));
      expect(levels, [0.5]);
    });

    test('brings a WebView’s 48 kHz down to 16 kHz when it ignored the rate asked for', () async {
      rate = 48000;
      final chunks = <Float32List>[];
      final microphone = await openMicrophone(MicrophoneHandlers(onChunk: chunks.add, onLevel: (_) {}), open: open);
      expect(microphone.deviceRate, 48000);
      inputs[0].handler?.call(Float32List(4800)..fillRange(0, 4800, 0.25));
      final samples = chunks[0];
      expect(samples, hasLength(1600));
      expect(samples.every((sample) => (sample - 0.25).abs() < 1e-6), true);
    });

    testWidgets('wakes a context the platform left suspended, and gives up waiting on a resume that never answers', (tester) async {
      startsSuspended = true;
      final woken = await openMicrophone(quiet(), open: open);
      expect(inputs[0].resumes, 1);
      expect(woken.state(), AudioContextState.running);
      // The wait the first open raced its resume against, still on the clock.
      await tester.pump(const Duration(milliseconds: 1500));

      resumeSettles = false;
      final opening = openMicrophone(quiet(), open: open);
      await tester.pump(const Duration(milliseconds: 1500));
      final stuck = await opening;
      expect(stuck.state(), AudioContextState.suspended);
    });

    test('lets go of everything when stopped, and hands on nothing after', () async {
      final chunks = <Float32List>[];
      final microphone = await openMicrophone(MicrophoneHandlers(onChunk: chunks.add, onLevel: (_) {}), open: open);
      microphone.stop();
      expect(inputs[0].closes, 1);
      expect(inputs[0].handler, isNull);
      expect(inputs[0].handlerSet, true);
    });

    test('rejects when the person declines the microphone, for the recorder to say why', () async {
      declines = Exception('Permission denied');
      await expectLater(openMicrophone(quiet(), open: open), throwsA(predicate((Object error) => '$error'.contains('Permission denied'))));
      expect(inputs, isEmpty);
    });
  });
}
