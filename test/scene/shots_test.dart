import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/capture/refine.dart' show RefineState;
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/scene/hot_phone.dart';
import 'package:ghost_md/scene/scripted.dart';
import 'package:ghost_md/scene/steps.dart';
import 'package:glacier/glacier.dart';

import 'scene_support.dart';

/// Pictures of the scene (test/scene/shots/), looked at beside AtWork.module.css and HotPhone.module.css: the
/// opening, each stage of the review and each phase of its run, the end and a failure, in light and in dark, on a
/// phone (390 x 844) and on a wide screen (the Fold opened out, 884 x 1104), and the phone alone at each warmth.
/// The words are the bench's own (scene/scripted.dart), so a line is as long as a real one.
///
/// `flutter test --update-goldens test/scene/shots_test.dart` writes them.

const _thought = '<think>Thinking Process:\n\n1. Words. The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right, and the task says the same words.\n2. Structure. The heading names the note, the to-do is a thing to';
const _writing = '<think>Thinking Process:\n\n1. Words. The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast one heard "seat bar".\n2. Structure. The heading names the note.</think>\n[{"check": "words", "what": "“seek bar”, not “seat bar”", "why": "x"}, {"check": "structure", "what": "The groceries as a li';

void main() {
  setUpAll(loadAppFonts);
  setUp(setUpScene);

  const sizes = {'phone': Size(390, 844), 'wide': Size(884, 1104)};

  for (final theme in ['light', 'dark']) {
    for (final entry in sizes.entries) {
      final at = '${entry.key}-$theme';
      final size = entry.value;
      final prefs = Preferences(theme: theme);
      Widget scene(WidgetTester tester, {stage}) => atWork(tester, heard: scriptHeard, body: scriptBody, stage: stage);
      Future<void> picture(WidgetTester tester, String name, {int settle = 1000}) async {
        await shot(tester, '$name-$at', settle: Duration(milliseconds: settle));
        await tearDownScene(tester);
      }

      testWidgets('opening, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        await show(tester, scene(tester), size: size, prefs: prefs);
        await picture(tester, 'opening');
      });

      testWidgets('listening again, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        await show(tester, scene(tester, stage: listeningAt(40)), size: size, prefs: prefs);
        await picture(tester, 'listening');
      });

      testWidgets('the better voice model coming down, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        refining.value = const RefineState(pending: <String>{}, download: (received: 12000000, total: 190000000));
        await show(tester, scene(tester, stage: listeningAt(0)), size: size, prefs: prefs);
        await picture(tester, 'download');
      });

      testWidgets('comparing, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        await show(tester, scene(tester, stage: comparingStage), size: size, prefs: prefs);
        await picture(tester, 'comparing');
      });

      testWidgets('loading the model, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        await show(tester, scene(tester, stage: comparingStage), size: size, prefs: prefs);
        await rerender(tester, scene(tester));
        await start(tester);
        await picture(tester, 'loading');
      });

      testWidgets('reading the note, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        await show(tester, scene(tester, stage: comparingStage), size: size, prefs: prefs);
        await rerender(tester, scene(tester));
        final run = await start(tester);
        run.fake.report(phase: Phase.prefill, promptTokens: 1040, promptTokensDone: 640, tokensPerSecond: 430, hardware: busy);
        await picture(tester, 'reading');
      });

      testWidgets('thinking, with a thought streamed, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        await show(tester, scene(tester, stage: comparingStage), size: size, prefs: prefs);
        await rerender(tester, scene(tester));
        final run = await start(tester);
        run.fake.report(partial: _thought, thinking: true, tokensPerSecond: 9.4, hardware: busy);
        await picture(tester, 'thinking');
      });

      testWidgets('writing what it found, $at', (tester) async {
        await tester.runAsync(() => WispKit.load(seeds: const [7]));
        await show(tester, scene(tester, stage: comparingStage), size: size, prefs: prefs);
        await rerender(tester, scene(tester));
        final run = await start(tester);
        run.fake.report(partial: _writing, thinking: true, tokensPerSecond: 9.4, hardware: const Hardware(rssBytes: 3000000000, freeBytes: 4000000000, totalBytes: 12000000000, cpuPercent: 640, threads: 6, cores: 8));
        await picture(tester, 'writing');
      });

      testWidgets('done, in the settle, $at', (tester) async {
        await show(tester, scene(tester, stage: comparingStage), size: size, prefs: prefs);
        await rerender(tester, scene(tester));
        final run = await start(tester);
        run.fake.report(partial: _writing, thinking: true, hardware: busy);
        await tester.pump();
        run.fake.finish('$_writing st"}]\n', thinking: true);
        await tester.pump();
        // Inside the hold, the die cooled and the words dimmed: the scene starts to leave at 900 ms.
        await picture(tester, 'done', settle: 700);
      });

      testWidgets('failed, $at', (tester) async {
        await show(tester, scene(tester, stage: comparingStage), size: size, prefs: prefs);
        await rerender(tester, scene(tester));
        final run = await start(tester);
        run.fake.report(partial: _thought, thinking: true, hardware: busy);
        await tester.pump();
        run.fake.fail('The model stopped.');
        await tester.pump();
        await picture(tester, 'failed', settle: 700);
      });
    }

    for (final warmth in Warmth.values) {
      testWidgets('the phone, ${warmth.name}, $theme', (tester) async {
        final glow = switch (warmth) { Warmth.cold => 0, Warmth.warm => 2, Warmth.hot => 5 };
        final step = switch (warmth) { Warmth.cold => StepId.listen, Warmth.warm => StepId.load, Warmth.hot => StepId.think };
        await show(
          tester,
          Builder(
            builder: (context) => ColoredBox(
              color: context.tokens.color('app-paper'),
              child: Center(child: SizedBox(width: 300, height: 680, child: HotPhone(warmth: warmth, glowStep: glow, litPins: glow + 1, pins: 8, step: step, still: false))),
            ),
          ),
          prefs: Preferences(theme: theme),
        );
        await shot(tester, 'phone-${warmth.name}-$theme');
      });
    }
  }
}
