// Whether the AI can run here (lib/ai/available.dart). A port of `src/app/ai/available.test.tsx`, case for case. A
// browser until a test says the app is on a phone, whose binary and catalogue the scripted engine then answers for;
// `useAvailability` is an `AvailabilityController`.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/available.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/support/runnable.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';

import 'fake_backend.dart';

ModelInfo model(String id, bool present) => ModelInfo(id: id, file: '$id.gguf', bytes: 1, present: present, path: '');
const Where phone = Where(tauri: true, ios: false, localOnly: false, generation: 19);

/// Waits until [check] passes, as the web's `waitUntil` did: a few turns of the event loop at most.
Future<void> waitUntil(void Function() check) async {
  for (var n = 0; n < 50; n += 1) {
    try {
      check();
      return;
    } on TestFailure {
      await Future<void>.delayed(Duration.zero);
    }
  }
  check();
}

void main() {
  late FakeAiBackend engine;

  setUp(() {
    engine = FakeAiBackend(native: false);
    engine.answers['ota_status'] = {'nativeGeneration': 19};
    useAiBackend(engine);
    useStored(MemoryStored());
    forgetBinaryVersion();
  });

  group('which model runs', () {
    test('is the chosen one when it is on the phone', () {
      expect(modelFor(['qwen3.5-2b', 'qwen3.5-4b'], 'qwen3.5-4b'), 'qwen3.5-4b');
    });

    test('else the biggest no bigger than it, else the smallest there is', () {
      expect(modelFor(['qwen3.5-2b', 'qwen3.5-9b'], 'qwen3.5-4b'), 'qwen3.5-2b');
      expect(modelFor(['qwen3.5-9b', 'gemma-4-e4b'], 'qwen3.5-2b'), 'gemma-4-e4b');
      expect(modelFor([], 'qwen3.5-4b'), isNull);
    });

    test('is chosen from the models the catalogue says are on the phone, and the gist takes the smallest', () {
      final catalogue = [model('qwen3.5-9b', true), model('qwen3.5-4b', false), model('qwen3.5-2b', true)];
      expect(presentIds(catalogue), ['qwen3.5-9b', 'qwen3.5-2b']);
      expect(smallestOf(presentIds(catalogue)), 'qwen3.5-2b');
      expect(smallestOf([]), isNull);
    });
  });

  group('whether the AI can run here', () {
    test('runs on the phone with a model on it', () {
      expect(availability([model('qwen3.5-4b', true)], 'qwen3.5-4b', phone), const Available(model: 'qwen3.5-4b', chosen: 'qwen3.5-4b'));
      expect(availability([model('qwen3.5-2b', true)], 'qwen3.5-4b', phone), const Available(model: 'qwen3.5-2b', chosen: 'qwen3.5-4b'));
    });

    test('says why not, in a sentence, where it cannot', () {
      final browser = availability([], 'qwen3.5-4b', phone.copyWith(tauri: false));
      expect(browser.ok, isFalse);
      expect(browser.reason, contains('Install Ghost.md on Android'));
      expect(browser.get, isNull);
      final ios = availability([], 'qwen3.5-4b', phone.copyWith(ios: true));
      expect(ios.ok, isFalse);
      expect(ios.reason, 'The AI is not on iOS yet.');
      final old = availability([model('qwen3.5-4b', true)], 'qwen3.5-4b', phone.copyWith(generation: 9));
      expect(old.ok, isFalse);
      expect(old.reason, contains('newest Ghost.md'));
      expect(availability([model('qwen3.5-4b', true)], 'qwen3.5-4b', phone.copyWith(generation: 10)).ok, isTrue);
    });

    test('waits while the catalogue is read, and offers the chosen model when none is here', () {
      final reading = availability([], 'qwen3.5-4b', phone);
      expect(reading.ok, isFalse);
      expect(reading.waiting, isTrue);
      final none = availability([model('qwen3.5-4b', false)], 'qwen3.5-4b', phone);
      expect(none.ok, isFalse);
      expect(none.get, 'qwen3.5-4b');
      expect(none.waiting, isFalse);
      final local = availability([model('qwen3.5-4b', false)], 'qwen3.5-4b', phone.copyWith(localOnly: true));
      expect(local.ok, isFalse);
      expect(local.get, isNull);
      expect(local.reason, contains('Local only'));
    });
  });

  group('the answer as a screen sees it', () {
    /// What the controller answers now: the hook on its latest render.
    AvailabilityController mounted() {
      final seen = AvailabilityController(ios: false);
      addTearDown(seen.dispose);
      return seen;
    }

    test('says the AI runs on the phone, in a browser', () async {
      engine.native = false;
      final seen = mounted();
      await waitUntil(() {
        expect(seen.availability.ok, isFalse);
        expect(seen.availability.reason, contains('runs on the phone'));
      });
    });

    test('runs the chosen model on a phone that has it, and the next one down when it does not', () async {
      engine.native = true;
      engine.answers['ai_models'] = [model('qwen3.5-2b', true), model('qwen3.5-4b', true)];
      preferences.update((p) => p.copyWith(formatModel: 'qwen3.5-4b'));
      final seen = mounted();
      await waitUntil(() => expect(seen.availability, const Available(model: 'qwen3.5-4b', chosen: 'qwen3.5-4b')));
      expect([for (final m in seen.models) m.id], ['qwen3.5-2b', 'qwen3.5-4b']);
      // With no controller, from the catalogue as last read: the same rule.
      expect(modelNow([model('qwen3.5-2b', true), model('qwen3.5-4b', false)]), 'qwen3.5-2b');
    });
  });
}
