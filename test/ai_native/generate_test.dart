// The language model through the real C functions on the Mac: `NativeAiBackend` over llama.cpp. The smallest
// model of the catalogue (Qwen3.5 2B) is downloaded from a server this test starts on 127.0.0.1 (never a real
// mirror), writes with its words streamed, is stopped mid-run, reads a spoken command under the core's grammar,
// and is removed. Needs tool/build-native.sh host and ../glyph/models/llm; says SKIPPED otherwise.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/native_backend.dart';
import 'package:ghost_md/core/native/core.dart';

import '../capture_native/support.dart';

void main() {
  const id = 'qwen3.5-2b', file = 'Qwen3.5-2B-Q4_K_M.gguf';
  const bytes = 1280835840;
  String? why;
  var opened = false;
  late TestCore held;
  late NativeAiBackend ai;
  late CuttingServer server;

  setUpAll(() async {
    why = await TestCore.missing() ?? (File('${webModels.path}/llm/$file').existsSync() ? null : 'no ${webModels.path}/llm/$file');
    if (why != null) return;
    held = await TestCore.open('ai');
    opened = true;
    if (!await held.hasVoice) {
      why = 'the Mac\'s core was built without the engines (GHOST_VOICE=0)';
      return;
    }
    server = await CuttingServer.start(Directory('${webModels.path}/llm'));
    ai = NativeAiBackend(held.core, mirrors: [server.base]);
  });

  tearDownAll(() async {
    if (!opened) return;
    if (why == null) await server.close();
    await held.close();
  });

  test('the device and the catalogue, with nothing on it yet', () async {
    if (why != null) return markTestSkipped('SKIPPED: $why');
    expect(ai.available, isTrue);
    expect(await ai.nativeGeneration(), 25);
    expect(await ai.binaryVersion(), isNotEmpty);
    final device = await ai.device();
    expect(device.cores, greaterThan(0));
    expect(device.freeDiskBytes, greaterThan(0));
    final models = await ai.models();
    expect(models.map((m) => m.id), ['qwen3.5-2b', 'qwen3.5-4b', 'qwen3.5-9b', 'gemma-4-e4b']);
    expect(models.first, ModelInfo(id: id, file: file, bytes: bytes, present: false, path: '${held.models.path}/$file'));
    // The app's own catalogue agrees with the core's, size for size.
    for (final model in models) {
      expect(modelSpec(model.id)?.bytes, model.bytes, reason: model.id);
    }
    final request = GenerateRequest(id: 'r0', model: id, system: '', prompt: 'hi', maxTokens: 4, temperature: 0);
    await expectLater(ai.generate(request), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'The model qwen3.5-2b is not on this phone yet.')));
    await expectLater(ai.fetchModel('gpt-4'), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'Glyph does not know a model called gpt-4.')));
    expect(await ai.cancel('nobody'), isFalse);
    await ai.unload();
  });

  test('a model is downloaded, writes with its words streamed, is stopped, reads a command, and is removed', () async {
    if (why != null) return markTestSkipped('SKIPPED: $why');
    // The download, from 127.0.0.1, saying how far under the model's id.
    final downloads = <Download>[];
    final unhearDownloads = ai.listen(modelProgressEvent, (payload) {
      final said = (payload as Map).cast<String, Object?>();
      downloads.add(Download(id: said['id'] as String, received: (said['receivedBytes'] as num).toInt(), total: (said['totalBytes'] as num).toInt()));
    });
    final fetching = Stopwatch()..start();
    final fetched = await ai.fetchModel(id);
    unhearDownloads();
    // ignore: avoid_print
    print('$file from 127.0.0.1: ${fetching.elapsedMilliseconds} ms, ${downloads.length} reports');
    expect(fetched.present, isTrue);
    expect(server.requests, ['/$file from 0']);
    expect(downloads.every((d) => d.id == id && d.total == bytes), isTrue);
    expect(downloads.last.received, bytes);
    expect((await ai.models()).first.present, isTrue);

    // A run: the words arrive as they are written, under the request's id.
    final heard = <Progress>[];
    final unhear = ai.listen(progressEvent, (payload) => heard.add(Progress.fromJson((payload as Map).cast<String, Object?>())));
    const request = GenerateRequest(id: 'run-1', model: id, system: 'You answer in one short sentence.', prompt: 'Count from one to five in words.', maxTokens: 24, temperature: 0);
    final running = Stopwatch()..start();
    final output = await ai.generate(request);
    final mine = heard.where((p) => p.id == 'run-1').toList();
    // ignore: avoid_print
    print('$id: ${output.outputTokens} tokens at ${output.tokensPerSecond.toStringAsFixed(1)} a second, ${output.promptTokens} prompt tokens, loaded in ${output.loadMs} ms, '
        '${output.ms} ms in the engine, ${running.elapsedMilliseconds} ms through the FFI, ${mine.length} progress events: "${output.text}"');
    expect(output.text.trim(), isNotEmpty);
    expect(output.outputTokens, inInclusiveRange(1, 24));
    expect(output.tokensPerSecond, greaterThan(0));
    final phases = <Phase>[];
    for (final progress in mine) {
      if (phases.isEmpty || phases.last != progress.phase) phases.add(progress.phase);
    }
    expect(phases.last, Phase.done);
    expect(phases, contains(Phase.generating));
    final partials = mine.where((p) => p.phase == Phase.generating && p.partial.isNotEmpty).map((p) => p.partial).toList();
    expect(partials, isNotEmpty, reason: 'tokens are streamed');
    expect(output.text.startsWith(partials.first.trim().split(' ').first), isTrue, reason: 'a partial is the output so far');

    // A long run, stopped by its request's id once it is writing.
    heard.clear();
    const long = GenerateRequest(id: 'run-2', model: id, system: '', prompt: 'Write a very long story about a lighthouse keeper.', maxTokens: 2000, temperature: 0.3);
    final stopped = expectLater(ai.generate(long), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'cancelled')));
    while (!heard.any((p) => p.id == 'run-2' && p.phase == Phase.generating)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await ai.cancel('run-2'), isTrue);
    await stopped;
    expect(heard.where((p) => p.id == 'run-2').last.phase, Phase.cancelled);
    expect(await ai.cancel('run-2'), isFalse, reason: 'an ended run is gone');
    unhear();

    // A spoken command, read under the core's own prompt and grammar.
    final read = (await ai.inferCommand(const InferCommandRequest(id: 'cmd-1', utterance: 'add eggs milk and bread to groceries', preferredModel: id)) as Map).cast<String, Object?>();
    // ignore: avoid_print
    print('ai_infer_command: $read');
    expect(read['status'], 'intent');
    expect(read['model'], id);
    final intent = (read['intent'] as Map).cast<String, Object?>();
    expect(intent['action'], 'append');
    expect('${intent['target']}'.toLowerCase(), contains('groceries'));
    final refused = await ai.inferCommand(const InferCommandRequest(id: 'cmd-2', utterance: 'delete everything in my Go note', preferredModel: id));
    expect(refused, {'status': 'intent', 'intent': {'action': 'none', 'reason': 'destructive'}, 'model': ''});

    // The write-up's configuration, where the write-up reads it; and nothing written up yet.
    await ai.keepJobConfig(const JobConfig(
      model: id,
      prompts: JobPrompts(summary: 'S', notes: '', piece: '', parts: ''),
      onePassChars: 20000,
      pieceChars: 12000,
      temperature: 0.3,
      writeUp: 'now',
      summaries: 'meetings',
    ));
    expect(File('${held.dataDir}/jobs/config.json').readAsStringSync(), contains('"onePassChars":20000'));
    expect(await ai.recordingJobState(), isEmpty);
    expect(await ai.recordingResultTake('n1'), isNull);
    expect(await ai.recordingDigest('n1'), isNull);
    final deleted = await ai.recordingDelete(['n1']);
    expect(deleted.removed, isEmpty);
    expect(deleted.freedBytes, 0);

    // Removed: the engine lets go of it first, and the catalogue says so.
    final removed = await ai.deleteModel(id);
    expect(removed.present, isFalse);
    expect(File('${held.models.path}/$file').existsSync(), isFalse);
    await ai.unload();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
