// The native capture through the real C functions on the Mac: `NativeCaptureBackend` under the app's own
// `CaptureEngine`, Whisper (base.en) hearing the web app's fixture recording as a microphone would hand it over,
// in 200 ms chunks. Then the rest of the backend: the tape kept and moved, a rewind, a cancel, a pass with the
// larger model. Needs tool/build-native.sh host and ../glyph/models; says SKIPPED otherwise.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/native_backend.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/preferences.dart';

import 'support.dart';

void main() {
  const live = 'ggml-base.en-q5_1.bin', larger = 'ggml-small.en-q5_1.bin';
  final wav = File('${webModels.path}/fixture.wav');
  String? why;
  var opened = false;
  late TestCore held;
  late NativeCaptureBackend backend;

  setUpAll(() async {
    why = await TestCore.missing();
    for (final name in [live, larger, 'fixture.wav']) {
      if (why == null && !File('${webModels.path}/$name').existsSync()) why = 'no ${webModels.path}/$name';
    }
    if (why != null) return;
    held = await TestCore.open('dictation', link: [live, larger]);
    opened = true;
    if (!await held.hasVoice) {
      why = 'the Mac\'s core was built without the engines (GHOST_VOICE=0)';
      return;
    }
    backend = NativeCaptureBackend(held.core, mirrors: const ['http://127.0.0.1:9']);
  });

  tearDownAll(() async {
    if (opened) await held.close();
  });

  /// Runs [body], or says why it cannot run here.
  void guarded(String name, Future<void> Function() body, Duration limit) {
    test(name, () async {
      if (why != null) return markTestSkipped('SKIPPED: $why');
      await body();
    }, timeout: Timeout(limit));
  }

  guarded('a whole dictation: partials, segments, the final transcript and the kept tape', () async {
    final samples = wavSamples(wav);
    final audioMs = samples.length * 1000 ~/ 16000;
    final engine = CaptureEngine(backend: backend, hasNativeGeneration: (wanted) async => wanted <= 25, preferences: () => const Preferences());
    final partials = <String>[];
    final segments = <Segment>[];
    final errors = <String>[];
    final whole = Stopwatch()..start();
    final session = await engine.startCapture(CaptureHandlers(onPartial: partials.add, onSegment: segments.add, onError: errors.add));
    final startedMs = whole.elapsedMilliseconds;
    expect(session.kind, EngineKind.whisper);
    expect(session.keepsAudio, isTrue);
    // A microphone's chunks, four times as fast as one speaks them.
    for (final chunk in chunksOf(samples)) {
      session.push(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(session.positionMs(), closeTo(audioMs, 1));
    final stopped = await session.stop(const StopOptions(recordAs: 'take-1'));
    // ignore: avoid_print
    print('dictation of $audioMs ms: capture started in $startedMs ms, ${partials.where((p) => p.isNotEmpty).length} partials, ${segments.length} segments, '
        '${whole.elapsedMilliseconds} ms in all: "${stopped.transcript}"');
    expect(errors, isEmpty);
    expect(partials.where((p) => p.isNotEmpty), isNotEmpty, reason: 'the words arrive before they are committed');
    expect(segments, isNotEmpty);
    expect(segments.every((s) => s.text.isNotEmpty && s.endMs >= s.startMs), isTrue);
    expect(stopped.transcript!.toLowerCase(), contains('oat milk'));
    expect(stopped.recordedMs, audioMs, reason: 'the tape is every sample pushed');
    expect(File('${held.recordings.path}/take-1.wav').lengthSync(), 44 + samples.length * 2);

    // The take turns out to belong to a note.
    expect(await engine.reassignRecording('take-1', 'note-1', false), audioMs);
    expect(File('${held.recordings.path}/take-1.wav').existsSync(), isFalse);
    expect(await engine.reassignRecording('nothing', 'note-1', false), isNull);

    // The whole file in one pass, the model already loaded.
    final measured = await backend.transcribeWav(wav.path);
    // ignore: avoid_print
    print('transcribe_wav: ${measured.audioMs} ms of audio in ${measured.elapsedMs} ms with ${measured.model}');
    expect(measured.model, live);
    expect(measured.text.toLowerCase(), contains('plumber'));

    // The larger model over the kept tape, saying how far it is under the note's id.
    final percents = <num>[];
    final sub = backend.events.listen((event) {
      if (event is CaptureEventRefineProgress && event.id == 'note-1') percents.add(event.percent);
    });
    final refined = await backend.refine(id: 'note-1', fromMs: 0, promptTail: '');
    await sub.cancel();
    // ignore: avoid_print
    print('refine with $larger: ${refined.length} phrases, progress $percents');
    expect(refined, isNotEmpty);
    expect(refined.map((s) => s.text).join(' ').toLowerCase(), contains('monday morning'));
    expect(percents.last, 100);
    expect((await backend.refineModelStatus()).present, isTrue);

    await engine.discardRecording('note-1');
    expect(File('${held.recordings.path}/note-1.wav').existsSync(), isFalse);
  }, const Duration(minutes: 6));

  guarded('pushes are refused outside a capture, a rewind replaces the list, a cancel lets go', () async {
    final samples = wavSamples(wav);
    Future<void> refused(Future<void> asked, String sentence) => expectLater(asked, throwsA(isA<CoreError>().having((e) => e.message, 'message', sentence)));
    await refused(backend.push(toBase64(const [0, 0, 0, 0])), 'No capture is running - await capture_start before pushing audio.');
    await refused(backend.stop(const StopOptions(recordAs: 'n')), 'No capture is running.');
    await refused(backend.rewind(0), 'No capture is running.');
    await backend.cancel();

    await backend.start();
    await refused(backend.refine(id: 'note-1', fromMs: 0, promptTail: ''), 'busy');
    final rewound = Completer<CaptureEventRewound>();
    final sub = backend.events.listen((event) {
      if (event is CaptureEventRewound && !rewound.isCompleted) rewound.complete(event);
    });
    for (final chunk in chunksOf(samples).take(20)) {
      await backend.push(toBase64(chunk.buffer.asUint8List(chunk.offsetInBytes, chunk.lengthInBytes)));
    }
    await backend.rewind(1000);
    expect(rewound.isCompleted, isTrue, reason: 'the event has gone out by the time the rewind resolves');
    expect((await rewound.future).toMs, 1000);
    await sub.cancel();
    // A start with one running replaces it; then nothing is kept of a cancelled capture.
    await backend.start();
    await backend.cancel();
    await refused(backend.push(toBase64(const [0, 0, 0, 0])), 'No capture is running - await capture_start before pushing audio.');
    expect(held.recordings.existsSync() ? held.recordings.listSync() : const [], isEmpty);
  }, const Duration(minutes: 3));
}
