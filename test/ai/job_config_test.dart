// What the phone's write-up is told (lib/ai/job_config.dart): the prompts each in its own place, the model the page
// would pick from what is on the phone, the two preferences; sent only where the write-up runs, only when it changed,
// and again when a model arrives, since a download changes the model without any preference changing. A port of
// src/app/ai/jobConfig.test.ts, case for case.
//
// The page mocked `invoke` and `isAndroid`; here the engine is the scripted one (fake_backend.dart), answering the
// same three commands, and the platform is Flutter's own override. One case is the port's own, at the foot: the text
// that is sent, held against what the page's `JSON.stringify` writes (fixtures/job_config_web.json, made by a one-off
// script from the web module).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/job_config.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/format/prompt.dart' show notesContext, pieceContext, recordingNotesPrompt, recordingSummaryPrompt;

import 'fake_backend.dart';

const generation = 20;
List<ModelInfo> onPhone = [];
final List<Map<String, Object?>> kept = [];
late FakeAiBackend engine;

/// The platform the page's `isAndroid` answered for.
set android(bool on) => debugDefaultTargetPlatformOverride = on ? TargetPlatform.android : TargetPlatform.macOS;

/// What Claude is read from, changing when the case says.
class _Heard extends ChangeNotifier {
  void tell() => notifyListeners();
}

ModelInfo model(String id, bool present) => ModelInfo(id: id, file: '$id.gguf', bytes: 0, present: present, path: '');

Future<void> settle() async {
  for (var i = 0; i < 20; i += 1) {
    await Future<void>.value();
  }
}

Preferences prefs({required String formatModel, required String writeUp, required String summaries}) =>
    Preferences.defaults.copyWith(formatModel: formatModel, writeUp: writeUp, summaries: summaries);

void main() {
  setUp(() {
    useStored(MemoryStored());
    preferences.forget();
    forgetSentJobConfig();
    android = true;
    onPhone = [];
    kept.clear();
    engine = FakeAiBackend();
    engine.answers['ota_status'] = () => {'nativeGeneration': generation};
    engine.answers['ai_models'] = () => onPhone;
    engine.answers['ai_keep_job_config'] = (Object? args) {
      kept.add((((args as Map)['config']) as Map).cast<String, Object?>());
      return null;
    };
    useAiBackend(engine);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    useAiBackend(const NoAiBackend());
    preferences.forget();
  });

  group('the config', () {
    test('puts each prompt where the write-up reads it, and names the model the page would run', () {
      final config = jobConfigFor([model('qwen3.5-2b', true), model('qwen3.5-4b', false)], prefs(formatModel: 'qwen3.5-4b', writeUp: 'now', summaries: 'meetings'));
      expect(config.prompts.toJson(), {'summary': recordingSummaryPrompt, 'notes': recordingNotesPrompt, 'piece': pieceContext, 'parts': notesContext});
      expect(config.model, 'qwen3.5-2b');
      expect([config.writeUp, config.summaries], ['now', 'meetings']);
      // No model at all: the one chosen, which the phone reports it needs.
      expect(jobConfigFor([], prefs(formatModel: 'qwen3.5-4b', writeUp: 'charging', summaries: 'off')).model, 'qwen3.5-4b');
    });
  });

  group('sending it', () {
    test('goes to Android with the write-up, once for each change, and never elsewhere', () async {
      await sendJobConfig();
      expect(kept, hasLength(1));
      await sendJobConfig();
      expect(kept, hasLength(1));
      preferences.update((now) => now.copyWith(writeUp: 'now'));
      await sendJobConfig();
      expect([for (final config in kept) config['writeUp']], ['charging', 'now']);
      android = false;
      preferences.update((now) => now.copyWith(writeUp: 'charging'));
      await sendJobConfig();
      expect(kept, hasLength(2));
    });

    test('is sent again when a model arrives, and not for a preference that has nothing to do with it', () async {
      final stop = keepJobConfigCurrent();
      await settle();
      expect([for (final config in kept) config['model']], ['qwen3.5-4b']);
      engine.invoked.clear();
      preferences.update((now) => now.copyWith(openNotes: ['n1']));
      await settle();
      expect(engine.calls('ai_models'), isEmpty);
      onPhone = [model('qwen3.5-2b', true)];
      announceModelsChanged();
      await settle();
      expect([for (final config in kept) config['model']], ['qwen3.5-4b', 'qwen3.5-2b']);
      stop();
    });
  });

  // Not in the web's file: meetings Claude writes up (lib/ai/summary_claude.dart), for which the phone writes none.
  group('with Claude chosen for meetings', () {
    test('says summaries off, is sent again when Claude is chosen or let go, and not for anything else Claude hears', () async {
      var chosen = false;
      final changed = _Heard();
      final stop = keepJobConfigCurrent(claude: () async => chosen, claudeChanged: changed);
      await settle();
      expect([for (final config in kept) config['summaries']], ['meetings']);
      engine.invoked.clear();
      // Heard, and nothing of it changed: nothing is read or sent.
      changed.tell();
      await settle();
      expect(engine.calls('ai_models'), isEmpty);
      chosen = true;
      changed.tell();
      await settle();
      expect([for (final config in kept) config['summaries']], ['meetings', 'off']);
      chosen = false;
      changed.tell();
      await settle();
      expect([for (final config in kept) config['summaries']], ['meetings', 'off', 'meetings']);
      stop();
      changed.dispose();
    });
  });

  // Not in the web's file: the port's own check that what is sent, and compared with the last one sent, is the text
  // the page's `JSON.stringify(config)` writes, keys in its order.
  group('the text', () {
    test('is the page’s, byte for byte, and so is the key the three preferences make', () {
      final cases = jsonDecode(File('test/ai/fixtures/job_config_web.json').readAsStringSync()) as List;
      expect(cases, isNotEmpty);
      for (final one in cases.cast<Map<String, Object?>>()) {
        final models = [for (final m in one['models']! as List) ModelInfo.fromJson((m as Map).cast<String, Object?>())];
        final said = (one['prefs']! as Map).cast<String, Object?>();
        final chosen = prefs(formatModel: said['formatModel']! as String, writeUp: said['writeUp']! as String, summaries: said['summaries']! as String);
        expect(jsonEncode(jobConfigFor(models, chosen).toJson()), one['sent']);
        expect(jobConfigKey(chosen), one['key']);
      }
    });
  });
}
