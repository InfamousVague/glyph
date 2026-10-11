// Both engines through the real C functions on the Mac (native/src/smoke.rs, the `voice` feature): whisper.cpp
// over the web app's fixture recording with base.en, and llama.cpp writing a few tokens with the smallest GGUF
// there is, the words arriving as `ai://progress` events. Needs tool/build-native.sh host, and the web app's
// models in tauri/models (or GLYPH_MODELS_DIR); says SKIPPED for whichever is missing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

const _library = 'native/target/debug/libghost_core.dylib';

void main() {
  final built = File(_library).existsSync();
  final models = Directory(Platform.environment['GLYPH_MODELS_DIR'] ?? 'tauri/models').absolute;
  final whisper = File('${models.path}/ggml-base.en-q5_1.bin');
  final wav = File('${models.path}/fixture.wav');
  final llmDir = Directory('${models.path}/llm');
  final ggufs = llmDir.existsSync() ? (llmDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf')).toList()..sort((a, b) => a.lengthSync().compareTo(b.lengthSync()))) : <File>[];

  late GhostCore core;
  var voice = false;

  setUpAll(() async {
    if (!built) return;
    core = await GhostCore.open(libraryPath: File(_library).absolute.path);
    // A library built without `voice` (GHOST_VOICE=0) has no such command; with it, the command wants arguments.
    try {
      await core.invoke('engine_smoke_transcribe');
    } on CoreError catch (e) {
      voice = !e.message.contains('no command named') && !e.message.contains('not open yet');
    }
  });

  tearDownAll(() async {
    if (built) await core.close();
  });

  String? missing(List<File> files) {
    if (!built) return 'the Mac\'s core is not built: run tool/build-native.sh host';
    if (!voice) return 'the Mac\'s core was built without the engines (GHOST_VOICE=0)';
    for (final file in files) {
      if (!file.existsSync()) return 'no ${file.path}';
    }
    return null;
  }

  test('whisper transcribes the fixture recording, as a job that ends with its words', () async {
    final why = missing([whisper, wav]);
    if (why != null) return markTestSkipped('SKIPPED: $why');
    final whole = Stopwatch()..start();
    final job = await core.startJob('engine_smoke_transcribe', {'model': whisper.path, 'wav': wav.path});
    final asked = whole.elapsedMilliseconds;
    final events = job.events.toList();
    final said = (await job.done as Map).cast<String, Object?>();
    // ignore: avoid_print
    print('whisper ${whisper.uri.pathSegments.last}: ${said['audioMs']} ms of audio transcribed in ${said['ms']} ms on ${said['threads']} threads, model loaded in ${said['loadMs']} ms, ${whole.elapsedMilliseconds} ms through the FFI in all (id back in $asked ms): "${said['text']}"');
    expect(asked, lessThan(said['ms'] as int), reason: 'the id comes back before the work');
    expect((said['text'] as String).split(RegExp(r'\s+')).length, greaterThanOrEqualTo(5));
    final segments = said['segments'] as List;
    expect(segments, isNotEmpty);
    expect((segments.first as Map)['endMs'], greaterThan(0));
    expect((await events).map((e) => e.event), ['engine://loaded']);
    // The library was never opened in this process: the engines need none.
    await expectLater(core.invoke('list_notes'), throwsA(isA<CoreError>()));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the language model writes a few tokens, streamed as ai://progress', () async {
    final why = missing(ggufs.take(1).toList()) ?? (ggufs.isEmpty ? 'no .gguf in ${llmDir.path}' : null);
    if (why != null) return markTestSkipped('SKIPPED: $why');
    final model = ggufs.first;
    final whole = Stopwatch()..start();
    final job = await core.startJob('engine_smoke_generate', {'model': model.path, 'prompt': 'Count from one to five in words.', 'maxTokens': 16});
    final partials = <String>[];
    final phases = <String>[];
    int? firstWordAt;
    final sub = job.events.listen((e) {
      expect(e.event, 'ai://progress');
      final phase = e.map['phase'] as String;
      if (phases.isEmpty || phases.last != phase) phases.add(phase);
      final partial = e.map['partial'] as String;
      if (partial.isNotEmpty) {
        firstWordAt ??= whole.elapsedMilliseconds;
        partials.add(partial);
      }
    });
    final said = (await job.done as Map).cast<String, Object?>();
    await sub.cancel();
    // ignore: avoid_print
    print('llama ${model.uri.pathSegments.last}: ${said['outputTokens']} tokens at ${(said['tokensPerSecond'] as num).toStringAsFixed(1)} a second, model loaded in ${said['loadMs']} ms, prefill ${said['prefillMs']} ms, ${said['ms']} ms in the engine and ${whole.elapsedMilliseconds} ms through the FFI in all, first words after $firstWordAt ms: ${said['text']}');
    expect(said['outputTokens'], inInclusiveRange(1, 16));
    expect((said['text'] as String).trim(), isNotEmpty);
    expect(phases.last, 'done');
    expect(phases, contains('generating'));
    expect(partials.length, greaterThanOrEqualTo(1), reason: 'the words arrive while they are written');
    expect(said['text'], startsWith(partials.first.trim()), reason: 'each report is the text so far');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a model that is not there is refused before any job starts', () async {
    final why = missing(const []);
    if (why != null) return markTestSkipped('SKIPPED: $why');
    await expectLater(
      core.startJob('engine_smoke_generate', {'model': '/nowhere/m.gguf', 'prompt': 'hello'}),
      throwsA(isA<CoreError>().having((e) => e.message, 'message', 'There is no language model at /nowhere/m.gguf.')),
    );
    expect(await core.invoke('jobs_running'), isEmpty);
  });
}
