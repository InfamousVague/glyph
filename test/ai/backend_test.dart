// The on-device model from the app's side (lib/ai/backend.dart): the catalogue and what is on the phone, a download
// and a removal, and a run streaming its progress. A port of `src/app/core/ai.test.tsx`, case for case. A phone is
// the scripted engine (fake_backend.dart), which is the web tests' `core/tauri.ts` and `core/events.ts` mocked, so a
// test can say what Rust reports and when. `useModels` is a `ModelsController`; the hook's first read and the app
// coming back to the front (`visibilitychange`) are both its `refresh()`.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/guide/guide_models.dart' show PhoneGuideModels;
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/support/failure.dart';
import 'package:ghost_md/ai/support/runnable.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';

import 'fake_backend.dart';

const ModelInfo here = ModelInfo(id: 'qwen3.5-2b', file: 'q2.gguf', bytes: 1280835840, present: true, path: '/models/q2.gguf');
const ModelInfo away = ModelInfo(id: 'qwen3.5-4b', file: 'q4.gguf', bytes: 2740937888, present: false, path: '/models/q4.gguf');

/// Lets what is queued land.
Future<void> flush() => Future<void>.delayed(Duration.zero);

/// What [future] fails with, as the words a person would read.
Future<String> failureOf(Future<Object?> future) async {
  try {
    await future;
  } catch (failure) {
    return failureText(failure);
  }
  fail('It did not fail.');
}

void main() {
  late FakeAiBackend engine;
  late MemoryStored storage;

  setUp(() {
    engine = FakeAiBackend();
    useAiBackend(engine);
    storage = MemoryStored();
    useStored(storage);
    forgetBinaryVersion();
    preferences.update((p) => p.copyWith(localOnly: false));
  });

  group('the catalogue', () {
    test('names a model by its id, and a size as a person reads it', () {
      expect(modelName('qwen3.5-9b'), 'Qwen3.5 9B');
      expect(modelName('someone-elses'), 'someone-elses');
      expect(gb(2740937888), '2.7 GB');
    });

    test('is empty in a browser, which has no engine, and the phone’s own list on a phone', () async {
      engine.native = false;
      expect(await listModels(), isEmpty);
      expect(engine.invoked, isEmpty);
      engine.native = true;
      engine.answers['ai_models'] = [here.toJson(), away.toJson()];
      expect(await listModels(), [here, away]);
    });
  });

  group('the models on the phone', () {
    late ModelsController models;

    setUp(() {
      models = ModelsController();
      engine.answers['ai_models'] = [here, away];
    });

    tearDown(() => models.dispose());

    test('reads what is on the phone at once, and again when the app comes back', () async {
      unawaited(models.refresh());
      await flush();
      expect(models.models, [here, away]);
      engine.answers['ai_models'] = [here, away.copyWith(present: true)];
      unawaited(models.refresh());
      await flush();
      expect(models.models[1].present, isTrue);
    });

    test('downloads a model with its own progress shown, then reads the phone again', () async {
      final finish = Completer<void>();
      engine.answers['ai_fetch_model'] = (Object? args) => finish.future;
      unawaited(models.refresh());
      await flush();
      final fetching = models.fetch('qwen3.5-4b');
      await flush();
      expect(models.download, const Download(id: 'qwen3.5-4b', received: 0, total: 2740937888));
      engine.emit('ai://model-progress', {'id': 'qwen3.5-9b', 'receivedBytes': 5, 'totalBytes': 9});
      engine.emit('ai://model-progress', {'id': 'qwen3.5-4b', 'receivedBytes': 1000, 'totalBytes': 2000});
      expect(models.download, const Download(id: 'qwen3.5-4b', received: 1000, total: 2000));
      // A second tap while one is coming is not a second download.
      await models.fetch('qwen3.5-2b');
      engine.answers['ai_models'] = [here, away.copyWith(present: true)];
      finish.complete();
      await fetching;
      expect(models.download, isNull);
      expect(models.models[1].present, isTrue);
      final fetches = engine.calls('ai_fetch_model');
      expect(fetches, hasLength(1));
      expect(fetches.single.args, {'id': 'qwen3.5-4b'});
      expect(engine.unlistened, 1);
    });

    test('is what the walkthrough\'s model page reads, through its own few words (lib/guide/guide_models.dart)', () async {
      final finish = Completer<void>();
      engine.answers['ai_fetch_model'] = (Object? args) => finish.future;
      final page = PhoneGuideModels(models);
      var told = 0;
      page.addListener(() => told += 1);
      unawaited(models.refresh());
      await flush();
      expect(page.offered, isTrue);
      expect(page.present(here.id), isTrue);
      expect(page.present(away.id), isFalse);
      expect(told, greaterThan(0));
      page.fetch(away.id);
      await flush();
      expect(page.download?.id, away.id);
      engine.answers['ai_models'] = [here, away.copyWith(present: true)];
      finish.complete();
      await flush();
      expect(page.download, isNull);
      expect(page.present(away.id), isTrue);
      expect(page.problem, isNull);
      page.dispose();
    });

    test('a download is a job on the app\'s record of running work: how far, then ready, or red with Retry', () async {
      final record = Activity(store: () => MemoryStored());
      useActivity(record);
      addTearDown(() => useActivity(Activity()));
      final finish = Completer<void>();
      engine.answers['ai_fetch_model'] = (Object? args) => finish.future;
      unawaited(models.refresh());
      await flush();
      final fetching = models.fetch('qwen3.5-4b');
      await flush();
      final job = record['model:qwen3.5-4b']!;
      expect((job.kind, job.personStarted, job.fraction), (JobKind.downloads, true, 0.0));
      engine.emit('ai://model-progress', {'id': 'qwen3.5-4b', 'receivedBytes': 1000000, 'totalBytes': 4000000});
      expect(record['model:qwen3.5-4b']!.fraction, 0.25);
      expect(record['model:qwen3.5-4b']!.liveLine, 'Downloading, 1 MB of 4 MB');
      finish.complete();
      await fetching;
      expect(record.value, isEmpty);
      expect(record.log.today.words, '1 model downloaded');
      engine.answers['ai_fetch_model'] = (Object? args) => throw StateError('The phone ran out of room.');
      await models.fetch('qwen3.5-4b');
      expect(record['model:qwen3.5-4b']!.cause, 'The phone ran out of room.');
      expect(record['model:qwen3.5-4b']!.fix!.kind, JobFixKind.retry);
    });

    test('says why a download or a removal failed, and downloads nothing with Nothing leaves the phone on', () async {
      engine.answers['ai_fetch_model'] = (Object? args) => throw StateError('The phone ran out of room.');
      engine.answers['ai_delete_model'] = (Object? args) => throw StateError('The model is in use.');
      unawaited(models.refresh());
      await flush();
      await models.fetch('qwen3.5-4b');
      expect(models.problem, 'The phone ran out of room.');
      expect(models.download, isNull);
      await models.remove('qwen3.5-2b');
      expect(models.problem, 'The model is in use.');

      preferences.update((p) => p.copyWith(localOnly: true));
      engine.invoked.clear();
      await models.fetch('qwen3.5-4b');
      expect(models.problem, 'Local only is on, so nothing is downloaded. Turn it off in Settings to get a model.');
      expect(engine.invoked, isEmpty);
    });

    test('removes a model and reads the phone again', () async {
      unawaited(models.refresh());
      await flush();
      engine.answers['ai_models'] = [here.copyWith(present: false), away];
      await models.remove('qwen3.5-2b');
      expect(engine.commands, contains('ai_delete_model'));
      expect(models.models[0].present, isFalse);
      expect(models.problem, isNull);
    });
  });

  group('a run', () {
    RunOptions options({String model = 'qwen3.5-4b', void Function(Progress progress)? onProgress}) =>
        RunOptions(model: model, system: 'Be brief.', prompt: 'Tidy this.', maxTokens: 64, temperature: 0.2, onProgress: onProgress ?? (_) {});

    test('listens before it asks, hears only its own reports, and stops listening when it ends', () async {
      final heard = <Progress>[];
      engine.answers['ai_generate'] = (Object? args) {
        Map<String, Object?> report(Object? id) => {'id': id, 'phase': 'generating', 'promptTokens': 3, 'promptTokensDone': 3, 'outputTokens': 1, 'tokensPerSecond': 9, 'elapsedMs': 5, 'partial': 'T'};
        engine.emit('ai://progress', report('someone-else'));
        engine.emit('ai://progress', report(((args as Map)['request'] as Map)['id']));
        return {'text': 'Tidied.', 'promptTokens': 3, 'outputTokens': 2, 'ms': 10, 'cachedTokens': 0, 'prefillMs': 1, 'loadMs': 1, 'tokensPerSecond': 9, 'truncated': false};
      };
      final run = generate(options(onProgress: heard.add));
      expect((await run.done).text, 'Tidied.');
      expect(engine.invokedWhenListening, [<String>[]]);
      expect(heard, hasLength(1));
      expect(engine.unlistened, 1);
      expect(engine.invoked[0].command, 'ai_generate');
      expect(engine.invoked[0].args, {
        'request': {'id': heard[0].id, 'model': 'qwen3.5-4b', 'system': 'Be brief.', 'context': null, 'prompt': 'Tidy this.', 'maxTokens': 64, 'temperature': 0.2, 'think': false, 'thinkBudget': 0},
      });
    });

    test('answers with the engine’s sentence when it fails, and still stops listening', () async {
      engine.answers['ai_generate'] = (Object? args) => throw StateError('cancelled');
      final run = generate(options());
      expect(await failureOf(run.done), 'cancelled');
      expect(engine.unlistened, 1);
    });

    test('says a model whose chat template this build cannot apply in words, and remembers it to pass it over', () async {
      engine.answers['ai_generate'] = (Object? args) => throw StateError('cannot apply the chat template: ffi error -1');
      final run = generate(options(model: 'gemma-4-e4b'));
      expect(await failureOf(run.done), 'Gemma 4 E4B can’t run in this version of Ghost.md. Choose another model in Settings › AI, or install the newest Ghost.md.');
      // Remembered against this binary's version, read once a launch.
      await flush();
      expect(jsonDecode(storage.getItem('glyph-models-cannot-run') ?? '{}'), containsPair('gemma-4-e4b', anything));
      storage.removeItem('glyph-models-cannot-run');
    });

    test('is cancelled by its own id, and each run has one of its own', () async {
      engine.answers['ai_generate'] = (Object? args) => Completer<Object?>().future;
      final one = generate(options());
      generate(options());
      await flush();
      one.cancel();
      final ids = [for (final request in engine.requests) request['id']];
      expect(ids.toSet(), hasLength(2));
      expect(engine.invoked.last.command, 'ai_cancel');
      expect(engine.invoked.last.args, {'id': ids[0]});
    });

    test('refuses in a browser, where there is no engine, and cancelling there does nothing', () async {
      engine.native = false;
      final run = generate(options());
      expect(await failureOf(run.done), 'Formatting runs on the phone. Install Ghost.md to use it.');
      run.cancel();
      expect(engine.invoked, isEmpty);
    });
  });
}
