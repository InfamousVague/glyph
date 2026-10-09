import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/review_stage.dart';
import 'package:ghost_md/scene/scripted.dart';

/// The script the bench plays: the stages and then the run's phases in order, at the engine's cadence, with the
/// phone's readings from the first prefill tick on, a temperature only when asked for, and a clean stop. The cases
/// of `src/app/scene/scripted.test.ts`, by name, on a clock the test turns: `testWidgets` runs its body on a
/// pretend clock, as the page's fake timers were, and fails a test that ends with a timer still waiting, which is
/// what `vi.getTimerCount()` asked at the end of each.

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  group('the stages', () {
    testWidgets('listen again in tens every quarter second, compare for a moment, then clear', (tester) async {
      final seen = <ReviewStage?>[];
      scriptedStages(seen.add);
      expect(seen[0]?.what, 'Listening again');
      expect(seen[0]?.percent, 0);
      await tester.pump(_ms(250));
      expect(seen.last?.what, 'Listening again');
      expect(seen.last?.percent, 10);
      await tester.pump(_ms(2250));
      expect(seen.last?.what, 'Listening again');
      expect(seen.last?.percent, 100);
      await tester.pump(_ms(250));
      expect(seen.last, const ReviewStage(what: 'Comparing', detail: '3 places where the two models heard different words.', percent: null));
      await tester.pump(_ms(600));
      expect(seen.last, isNull);
    });

    testWidgets('can be stopped', (tester) async {
      final seen = <ReviewStage?>[];
      final stop = scriptedStages(seen.add);
      await tester.pump(_ms(500));
      stop();
      final were = seen.length;
      await tester.pump(_ms(5000));
      expect(seen.length, were);
    });
  });

  group('the run', () {
    ({List<Progress> reports, Run run}) play(WidgetTester tester, SceneScript script) {
      final reports = <Progress>[];
      final run = scriptedReview(script, now: () => tester.binding.clock.now().millisecondsSinceEpoch)(RunOptions(model: 'qwen3.5-4b', system: '', prompt: 'p', maxTokens: 1900, temperature: 0.2, onProgress: reports.add));
      return (reports: reports, run: run);
    }

    /// `rejects.toThrow('cancelled')`: the run ended, and by being cancelled.
    final cancelled = throwsA(predicate((Object failure) => failure.toString() == 'cancelled'));

    testWidgets('reports loading, then reading in ticks, then the thought and the findings, then done', (tester) async {
      final played = play(tester, SceneScript.heat);
      final reports = played.reports;
      expect([for (final r in reports) r.phase], [Phase.loading]);
      expect(reports[0].hardware, isNull);
      await tester.pump(_ms(1800 + 2400 + 10));
      final prefill = reports.where((r) => r.phase == Phase.prefill).toList();
      expect(prefill.length, 9);
      expect([for (final r in prefill) r.promptTokensDone], [128, 256, 384, 512, 640, 768, 896, 1024, 1040]);
      // The first sample is a new sampler's and reads 0; the rest ramp to six and a half cores busy.
      expect(prefill[0].hardware?.cpuPercent, 0);
      expect(prefill.last.hardware?.cpuPercent, 640);
      expect(prefill.last.hardware?.cores, 8);
      expect(prefill.last.hardware?.threads, 6);
      expect(prefill.last.hardware?.tempC, greaterThan(31));
      await tester.pump(_ms(30000));
      final generating = reports.where((r) => r.phase == Phase.generating).toList();
      expect(generating.length, greaterThan(20));
      expect(generating[0].partial.startsWith('<think>'), isTrue);
      expect(generating[0].thinking, isTrue);
      expect(generating.last.partial, contains('"what"'));
      final output = await played.run.done;
      expect(output.text, contains('</think>'));
      expect((jsonDecode(output.text.substring(output.text.indexOf('</think>') + '</think>'.length)) as List).length, 2);
      expect(output.promptTokens, 1040);
      expect(output.thinking, isTrue);
    });

    testWidgets('carries a temperature only for the heat script, and no readings at all for none', (tester) async {
      final cold = play(tester, SceneScript.cold);
      final none = play(tester, SceneScript.none);
      await tester.pump(_ms(1800 + 2400 + 500));
      final coldRead = cold.reports.firstWhere((r) => r.phase == Phase.generating);
      expect(coldRead.hardware, isNotNull);
      expect(coldRead.hardware?.tempC, isNull);
      final noneRead = none.reports.firstWhere((r) => r.phase == Phase.generating);
      expect(noneRead.hardware, isNull);
      cold.run.cancel();
      none.run.cancel();
      await expectLater(cold.run.done, cancelled);
      await expectLater(none.run.done, cancelled);
    });

    testWidgets('answers cancelled at once when stopped, and leaves no timer', (tester) async {
      final played = play(tester, SceneScript.heat);
      await tester.pump(_ms(3000));
      final were = played.reports.length;
      played.run.cancel();
      await expectLater(played.run.done, cancelled);
      await tester.pump(_ms(5000));
      expect(played.reports.length, were);
    });

    test('has a transcript with the mishearing in it, and the note those words made', () {
      expect(scriptHeard, contains('seat bar'));
      expect(scriptBody, contains('seat bar'));
      expect(scriptBody.startsWith('# '), isTrue);
    });
  });

  group('the query', () {
    test('reads ?scene= in a browser, and nothing under Tauri', () {
      expect(sceneQuery(address: Uri.parse('/')), isNull);
      expect(sceneQuery(address: Uri.parse('/?scene=heat')), SceneScript.heat);
      expect(sceneQuery(address: Uri.parse('/?scene=none')), SceneScript.none);
      expect(sceneQuery(address: Uri.parse('/?scene=other')), isNull);
      // The phone has no address to read, as the page had none worth reading under Tauri.
      expect(sceneQuery(), isNull);
    });
  });
}
