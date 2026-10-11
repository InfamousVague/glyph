import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;

import 'support/capture_backend_fake.dart';

/// The transcriber's engines (lib/capture/engine.dart): Whisper over the native capture, as the phone runs it - the
/// one native capture and who owns it, the recording kept or not by the binary's generation, the voice model
/// fetched - and the base64 envelope every chunk crosses in. Case for case with the web's `capture/engine.test.ts`.
/// The bridge is a stand-in: the backend answers what the test says Rust would, and `say` speaks as Rust.
///
/// Where the web counts the three event names it stopped listening to, this counts the one subscription the Dart
/// engine makes to the one stream: stopped once, and nobody left listening.

bool native = true;
final backend = FakeCaptureBackend();
Preferences prefs = Preferences.defaults;

/// The binary's generation, here per test.
int generation = 7;

/// The engine, on a binary of [on].
CaptureEngine engine([int on = 7]) {
  generation = on;
  return CaptureEngine(
    backend: native ? backend : null,
    hasNativeGeneration: (wanted) async => native && generation >= wanted,
    preferences: () => prefs,
  );
}

class Heard {
  final List<String> partials = [];
  final List<Segment> segments = [];
  final List<String> errors = [];
  final List<(int, int)> progress = [];

  CaptureHandlers get handlers => CaptureHandlers(
        onPartial: partials.add,
        onSegment: segments.add,
        onError: errors.add,
        onModelProgress: (received, total) => progress.add((received, total)),
      );
}

CaptureHandlers handlers() => Heard().handlers;
List<Map<String, Object?>> pushes() => backend.calls('capture_push');

Float32List filled(int length, double value) => Float32List(length)..fillRange(0, length, value);
Uint8List bytesOf(Float32List samples) => samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes);

void main() {
  setUp(() {
    native = true;
    backend.reset();
    backend.answers['capture_model_status'] = (_) => const ModelStatus(present: true, name: 'base.en', path: '/models/base.en', bytes: 1);
    backend.answers['capture_start'] = (_) => null;
    backend.answers['capture_push'] = (_) => null;
    backend.answers['capture_cancel'] = (_) => null;
  });

  tearDown(() => prefs = Preferences.defaults.copyWith(localOnly: false));

  group('Whisper on the phone', () {
    test('hands on what Rust hears: guesses, phrases and errors', () async {
      final on = Heard();
      await engine().startCapture(on.handlers);
      backend.say(const CaptureEventPartial('Oat mi'));
      backend.say(const CaptureEventSegment(Segment(text: 'Oat milk.', startMs: 0, endMs: 900)));
      backend.say(const CaptureEventError('decoder stalled'));
      expect(on.partials, ['Oat mi']);
      expect(on.segments, [const Segment(text: 'Oat milk.', startMs: 0, endMs: 900)]);
      expect(on.errors, ['decoder stalled']);
    });

    test('sends every chunk as base64, in order, and counts the recording by what it sent', () async {
      final session = await engine().startCapture(handlers());
      final first = filled(16000, 0.25);
      final second = filled(8000, -0.5);
      session.push(first);
      session.push(second);
      backend.answers['capture_stop'] = (_) => const CaptureStopped(transcript: '', recordedMs: 1500);
      await session.stop();
      expect(pushes().map((call) => (call['args'] as Map)['pcm']), [toBase64(bytesOf(first)), toBase64(bytesOf(second))]);
      expect(session.positionMs(), 1500);
    });

    test('sends nothing still queued once the session is cancelled', () async {
      final session = await engine().startCapture(handlers());
      session.push(filled(1600, 0.25));
      session.push(filled(1600, -0.25));
      await session.cancel();
      // A macrotask, so every queued push has had its turn.
      await Future<void>.delayed(Duration.zero);
      expect(pushes(), isEmpty);
      expect(backend.invoked.any((call) => call['command'] == 'capture_cancel'), true);
    });

    test('keeps the recording under the note’s id on a binary that can, and gives back its final words', () async {
      final session = await engine(6).startCapture(handlers());
      expect(session.keepsAudio, true);
      backend.answers['capture_stop'] = (_) => const CaptureStopped(transcript: '  Pack sunscreen.  ', recordedMs: 4200);
      expect(await session.stop(const StopOptions(recordAs: 'n1', append: true)), const Stopped(recordedMs: 4200, transcript: 'Pack sunscreen.'));
      expect(backend.invoked.last, {
        'command': 'capture_stop',
        'args': {'recordAs': 'n1', 'append': true},
      });
      // The web's three unlisteners, which are one subscription here.
      expect(backend.unlistened, 1);
      expect(backend.listening, 0);
    });

    test('asks an older binary to stop with nothing, and keeps nothing', () async {
      final session = await engine(5).startCapture(handlers());
      expect(session.keepsAudio, false);
      backend.answers['capture_stop'] = (_) => null;
      expect(await session.stop(const StopOptions(recordAs: 'n1')), const Stopped(recordedMs: null, transcript: null));
      expect(backend.invoked.last, {'command': 'capture_stop', 'args': null});
    });

    test('answers an empty final decode as none', () async {
      final session = await engine().startCapture(handlers());
      backend.answers['capture_stop'] = (_) => const CaptureStopped(transcript: '   ', recordedMs: 900);
      expect(await session.stop(), const Stopped(recordedMs: 900, transcript: null));
      expect(backend.invoked.last['args'], {'recordAs': null, 'append': false});
    });

    test('lets a replaced session neither push into the new one’s capture nor cancel it', () async {
      final capture = engine();
      final old = await capture.startCapture(handlers());
      final current = await capture.startCapture(handlers());
      old.push(Float32List(160));
      await old.cancel();
      expect(pushes(), isEmpty);
      expect(backend.invoked.any((call) => call['command'] == 'capture_cancel'), false);
      current.push(Float32List(160));
      backend.answers['capture_stop'] = (_) => const CaptureStopped(transcript: '', recordedMs: 10);
      await current.stop();
      expect(pushes(), hasLength(1));
      final again = await capture.startCapture(handlers());
      await again.cancel();
      expect(backend.invoked.last['command'], 'capture_cancel');
    });

    test('stops listening when the native capture will not start, and says why', () async {
      backend.answers['capture_start'] = (_) => throw Exception('microphone busy');
      await expectLater(engine().startCapture(handlers()), throwsA(predicate((Object error) => '$error'.contains('microphone busy'))));
      expect(backend.unlistened, 1);
      expect(backend.listening, 0);
    });

    test('reports a push Rust refused as an error, and keeps sending the rest', () async {
      final on = Heard();
      final session = await engine().startCapture(on.handlers);
      var tries = 0;
      backend.answers['capture_push'] = (_) {
        tries += 1;
        // Rust's rejection reaches the page as the string it returned.
        // ignore: only_throw_errors
        if (tries == 1) throw 'capture_push rejected';
        return null;
      };
      session.push(Float32List(160));
      session.push(Float32List(160));
      backend.answers['capture_stop'] = (_) => const CaptureStopped(transcript: '', recordedMs: 20);
      await session.stop();
      expect(on.errors, ['capture_push rejected']);
      expect(pushes(), hasLength(2));
    });
  });

  group('the voice model', () {
    test('is left alone when it is on the phone', () async {
      expect((await engine().ensureModel())?.present, true);
      expect(backend.invoked.any((call) => call['command'] == 'capture_fetch_model'), false);
    });

    test('is fetched when it is not, with its progress told as it comes', () async {
      backend.answers['capture_model_status'] = (_) => const ModelStatus(present: false, name: 'base.en', path: '', bytes: 60000000);
      backend.answers['capture_fetch_model'] = (_) {
        backend.say(const CaptureEventModelProgress(receivedBytes: 30000000, totalBytes: 60000000));
        return const ModelStatus(present: true, name: 'base.en', path: '/models/base.en', bytes: 60000000);
      };
      final progress = <(int, int)>[];
      expect((await engine().ensureModel((received, total) => progress.add((received, total))))?.present, true);
      expect(progress, [(30000000, 60000000)]);
      // The web's `['capture://model-progress']`: the one listener it made, gone.
      expect(backend.unlistened, 1);
      expect(backend.listening, 0);
    });

    test('is not downloaded with Local only on, and the recorder is told why', () async {
      backend.answers['capture_model_status'] = (_) => const ModelStatus(present: false, name: 'base.en', path: '', bytes: 60000000);
      prefs = Preferences.defaults.copyWith(localOnly: true);
      await expectLater(
        engine().ensureModel(),
        throwsA(predicate((Object error) => '$error'.contains('Local only is on, so the voice model was not downloaded. Turn it off in Settings to get it.'))),
      );
      expect(backend.invoked.any((call) => call['command'] == 'capture_fetch_model'), false);
    });

    test('is nothing to ask about in a browser', () async {
      native = false;
      expect(await engine().ensureModel(), isNull);
      expect(backend.invoked, isEmpty);
    });
  });

  group('a recording a command did not keep', () {
    test('goes to the note the command was confirmed for, or is thrown away', () async {
      backend.answers['capture_reassign_recording'] = (_) => 5400;
      backend.answers['capture_discard_recording'] = (_) => null;
      expect(await engine().reassignRecording('tmp', 'n1', true), 5400);
      await engine().discardRecording('tmp');
      expect(backend.invoked, [
        {
          'command': 'capture_reassign_recording',
          'args': {'fromId': 'tmp', 'toId': 'n1', 'append': true},
        },
        {
          'command': 'capture_discard_recording',
          'args': {'id': 'tmp'},
        },
      ]);
      native = false;
      expect(await engine().reassignRecording('tmp', 'n1', false), isNull);
    });
  });

  /// The audio envelope. Rust decodes exactly what this produces back into f32 samples, so a byte out of place here
  /// is noise in every transcription.
  group('toBase64', () {
    test('matches the platform encoder on float PCM bytes', () {
      final samples = Float32List.fromList([0, 0.5, -0.5, 1, -1, 0.123456]);
      final bytes = bytesOf(samples);
      expect(toBase64(bytes), base64.encode(bytes));
    });

    // A 200 ms chunk is 12,800 bytes, and the web slices its encoding to stay under an argument limit.
    test('round-trips a chunk far larger than one slice', () {
      final samples = Float32List.fromList([for (var i = 0; i < 16000 * 3; i += 1) math.sin(i / 40)]);
      final bytes = bytesOf(samples);
      final decoded = Float32List.view(Uint8List.fromList(base64.decode(toBase64(bytes))).buffer);
      expect(decoded, samples);
    });
  });
}
