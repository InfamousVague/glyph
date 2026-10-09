// The status strip (lib/ai/ai_strip.dart). A port of `src/app/ai/AiStrip.test.tsx`, case for case, then what it is
// drawn with, held to AiStrip.module.css's own numbers, and pictures in shots/ to lay beside the page.
//
// A model that answers when the test says so is ai/runs.dart's `simulateRuns`, as in runs_test.dart.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_strip.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/review_stage.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/format/ai_card.dart';
import 'package:ghost_md/format/device_facts.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
/// A model that answers when the test says so.
class Model {
  Model(this.options);

  final RunOptions options;
  final Completer<Output> _done = Completer<Output>();

  Run get run => Run(done: _done.future, cancel: cancel);

  void complete(Output output) => _done.complete(output);
  void fail(String message) => _done.completeError(StateError(message));
  void cancel() {
    if (!_done.isCompleted) _done.completeError(StateError('cancelled'));
  }
}

final List<Model> fakes = [];

/// The strip on a phone's page, under where the header would end.
Future<void> show(WidgetTester tester, Widget strip, {String theme = 'light', Size size = const Size(390, 844)}) async {
  await pumpApp(
    tester,
    size: size,
    prefs: AppPreferences(theme: theme),
    home: Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('app-paper'),
        child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 96), child: strip)),
      ),
    ),
  );
  debugDisableShadows = true;
  await tester.pump();
}

/// Every word the strip draws, in order.
String words(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.descendant(of: find.byType(AiStrip), matching: find.byType(Text))))
        text.data ?? text.textSpan!.toPlainText(),
    ].join(' | ');

Finder keyed(String key) => find.byKey(ValueKey<String>(key));

/// The share of the foot's bar that is filled, once its glide is done.
double filled(WidgetTester tester) => tester.widget<FractionallySizedBox>(find.ancestor(of: keyed('ai-strip-fill'), matching: find.byType(FractionallySizedBox)).first).widthFactor!;

Future<void> tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

RunRequest ask(RunKind kind, {String model = 'qwen3.5-4b', bool? think}) => RunRequest(noteId: 'n', kind: kind, model: model, system: 's', prompt: 'p', maxTokens: 100, think: think);

Output answered(String text) => Output(text: text, promptTokens: 100, outputTokens: 20, ms: 42000, cachedTokens: 0, prefillMs: 100, loadMs: 100, tokensPerSecond: 12, truncated: false);

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    useStored(MemoryStored());
    forgetAllRuns();
    fakes.clear();
    simulateRuns((options) {
      final fake = Model(options);
      fakes.add(fake);
      return fake.run;
    });
  });

  // Taken down before the runs are forgotten, so no strip is left on the page to hear of it.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    forgetAllRuns();
    simulateRuns(null);
  }

  group('the strip', () {
    testWidgets('draws nothing for a note with no run', (tester) async {
      await show(tester, const AiStrip(noteId: 'quiet'));
      expect(words(tester), '');
      expect(tester.getSize(find.byType(AiStrip)).height, 0);
      await end(tester);
    });

    testWidgets('says what the model is doing, with Stop, and then how it ended, with a way to put it away', (tester) async {
      final heights = <double>[];
      await show(tester, AiStrip(noteId: 'n', onHeight: heights.add));
      final handle = startRun(ask(RunKind.format));
      await tick(tester);
      expect(words(tester), contains('Loading Qwen3.5 4B.'));
      expect(keyed('ai-strip-stop'), findsOneWidget);
      expect(heights.last, tester.getSize(keyed('ai-strip-loading')).height);
      fakes[0].options.onProgress(const Progress(id: 'x', phase: Phase.generating, promptTokens: 100, promptTokensDone: 100, outputTokens: 25, tokensPerSecond: 20, elapsedMs: 3000, partial: '# Trip\n'));
      await tick(tester);
      expect(words(tester), contains('Formatting with Qwen3.5 4B, 20 tokens a second, 0:03, 1 line.'));
      expect(filled(tester), 0.25);
      fakes[0].complete(answered('# Trip\n'));
      await handle.done;
      await tick(tester);
      expect(words(tester), contains('Formatted by Qwen3.5 4B in 0:42.'));
      expect(keyed('ai-strip-stop'), findsNothing);
      // Nothing changed the note, so there is nothing to undo from the line.
      expect(keyed('ai-strip-undo'), findsNothing);
      await tester.tap(keyed('ai-strip-dismiss'));
      await tick(tester);
      expect(words(tester), '');
      expect(heights.last, 0);
      await end(tester);
    });

    testWidgets('opens the log under the line, with Undo for a run that changed the note', (tester) async {
      final undone = <String>[];
      await show(
        tester,
        AiStrip(
          noteId: 'n',
          onUndo: (record) {
            undone.add(record.id);
            return true;
          },
        ),
      );
      final handle = startRun(ask(RunKind.summarize, model: 'qwen3.5-2b'));
      await tick(tester);
      fakes[0].complete(answered('short\n'));
      await handle.done;
      recordChange('n', handle.id, 'before', 'after');
      await tick(tester);
      expect(keyed('ai-strip-undo'), findsOneWidget);
      await tester.tap(keyed('ai-strip-words'));
      await tick(tester);
      expect(words(tester), contains('Summarize by Qwen3.5 2B in 0:42.'));
      expect(words(tester), contains('Just now'));
      await tester.tap(find.descendant(of: keyed('ai-strip-log'), matching: find.text('Undo')));
      expect(undone, [handle.id]);
      await end(tester);
    });

    testWidgets('says the review’s own stage while no run is on, with its percent along the foot', (tester) async {
      await show(tester, const AiStrip(noteId: 'quiet', stage: ReviewStage(what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent: 40)));
      await tick(tester);
      expect(words(tester), contains('Listening again, 40%. The slower speech model is listening to the recording again.'));
      expect(filled(tester), 0.4);
      await end(tester);
    });

    testWidgets('says how many of the AI’s changes are still marked, with Keep all, when no run is left to speak of', (tester) async {
      var kept = 0;
      await show(tester, AiStrip(noteId: 'quiet', marks: StripMarks(count: 3, keepAll: () => kept += 1)));
      expect(words(tester), contains('3 changes from the AI are marked in the note.'));
      await tester.tap(keyed('ai-strip-keep-all'));
      expect(kept, 1);
      await show(tester, AiStrip(noteId: 'also-quiet', marks: StripMarks(count: 1, keepAll: () {})));
      expect(words(tester), contains('One change from the AI is marked in the note.'));
      // With none left, the strip is gone.
      await show(tester, AiStrip(noteId: 'quiet', marks: StripMarks(count: 0, keepAll: () {})));
      expect(words(tester), '');
      await end(tester);
    });

    testWidgets('offers Keep all beside an ended run that left marks, and not while it runs', (tester) async {
      var kept = 0;
      await show(tester, AiStrip(noteId: 'n', marks: StripMarks(count: 2, keepAll: () => kept += 1)));
      final handle = startRun(ask(RunKind.fix));
      await tick(tester);
      expect(keyed('ai-strip-keep-all'), findsNothing);
      fakes[0].complete(answered('fixed\n'));
      await handle.done;
      await tick(tester);
      await tester.tap(keyed('ai-strip-keep-all'));
      expect(kept, 1);
      await end(tester);
    });

    testWidgets('shows a thinking model’s thought in the card', (tester) async {
      await show(tester, const AiStrip(noteId: 'n'));
      startRun(ask(RunKind.review, think: true));
      await tick(tester);
      fakes[0].options.onProgress(const Progress(id: 'x', phase: Phase.generating, promptTokens: 10, promptTokensDone: 10, outputTokens: 5, tokensPerSecond: 9, elapsedMs: 2000, partial: '<think>Is seat right?', thinking: true));
      await tick(tester);
      expect(words(tester), contains('Qwen3.5 4B is thinking it through, 9.0 tokens a second, 0:02.'));
      await tester.tap(keyed('ai-strip-words'));
      await tick(tester);
      expect(tester.widget<Text>(find.descendant(of: keyed('ai-strip-thought'), matching: find.byType(Text))).data, 'Is seat right?');
      // The card under it, while the run is on.
      expect(find.byType(AiCard), findsOneWidget);
      fakes[0].cancel();
      await tick(tester);
      await end(tester);
    });

    testWidgets('stops the run from the line', (tester) async {
      await show(tester, const AiStrip(noteId: 'n'));
      final handle = startRun(ask(RunKind.enhance));
      await tick(tester);
      await tester.tap(keyed('ai-strip-stop'));
      await handle.done;
      await tick(tester);
      expect(words(tester), contains('Stopped.'));
      await end(tester);
    });
  });

  group('how it is drawn', () {
    testWidgets('a line 2.25rem tall inside the gutters, a hairline round it, a 2px bar along its foot', (tester) async {
      await show(tester, const AiStrip(noteId: 'quiet', stage: ReviewStage(what: 'Comparing', detail: 'Both models heard the same words.', percent: null)));
      await tick(tester);
      final t = tester.element(keyed('ai-strip-stage')).tokens;
      final strip = tester.getRect(keyed('ai-strip-stage'));
      expect(strip.left, closeTo(t.len('app-gutter-start'), 0.01));
      expect(390 - strip.right, closeTo(t.len('app-gutter-end'), 0.01));
      // The row's least height, the bar, and the hairline above and below.
      expect(strip.height, closeTo(36 + 2 + 2 * t.len('glacier-hairline'), 0.6));
      final bar = tester.getRect(keyed('ai-strip-bar'));
      expect(bar.height, 2);
      expect(bar.bottom, closeTo(strip.bottom - t.len('glacier-hairline'), 0.6));
      // The icon 16 across, the words a gap after it, a space-3 in from the edge.
      final icon = tester.getRect(find.descendant(of: find.byType(AiStrip), matching: find.byType(AppIcon)).first);
      expect(icon.size, const Size(16, 16));
      expect(icon.left - strip.left, closeTo(t.space(3) + t.len('glacier-hairline'), 0.6));
      expect(tester.getRect(keyed('ai-strip-words')).left - icon.right, closeTo(t.space(2), 0.1));
      final said = tester.widget<Text>(keyed('ai-strip-words'));
      expect((said.style!.fontSize, said.style!.color), (t.fontSize('sm'), t.color('app-ink-2')));
      await end(tester);
    });
  });

  // Pictures, to lay beside the page's (AiStrip.module.css): `flutter test --update-goldens`, then open shots/.
  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('a run writing, the card open, $theme', (tester) async {
        await show(tester, AiStrip(noteId: 'n', deviceFacts: ValueNotifier(const DeviceFacts(cores: 8, memoryGb: 12, battery: BatteryReading(level: 0.81, charging: false)))), theme: theme);
        startRun(ask(RunKind.review, think: true));
        await tick(tester);
        fakes[0].options.onProgress(const Progress(
          id: 'x',
          phase: Phase.generating,
          promptTokens: 684,
          promptTokensDone: 684,
          outputTokens: 42,
          tokensPerSecond: 7.3,
          elapsedMs: 32000,
          partial: '<think>Thinking Process:\n\n1. Words. The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right.\n2. Structure. The heading names the note.',
          thinking: true,
          hardware: Hardware(rssBytes: 3100000000, freeBytes: 5000000000, totalBytes: 12000000000, cpuPercent: 640, threads: 6, cores: 8, tempC: 41),
        ));
        await tick(tester);
        await tester.tap(keyed('ai-strip-words'));
        await tick(tester);
        await shot(tester, 'ai-strip-open-$theme', settle: Duration.zero);
        fakes[0].cancel();
        await end(tester);
      });

      testWidgets('each line the strip can be, $theme', (tester) async {
        Future<void> one(String name, Future<void> Function() make) async {
          useStored(MemoryStored());
          forgetAllRuns();
          fakes.clear();
          await make();
          await tick(tester);
          await shot(tester, 'ai-strip-$name-$theme', settle: Duration.zero);
        }

        await one('stage', () => show(tester, const AiStrip(noteId: 'q', stage: ReviewStage(what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent: 40)), theme: theme));
        await one('marks', () => show(tester, AiStrip(noteId: 'q', marks: StripMarks(count: 3, keepAll: () {})), theme: theme));
        await one('loading', () async {
          await show(tester, const AiStrip(noteId: 'n'), theme: theme);
          startRun(ask(RunKind.format));
        });
        await one('done', () async {
          await show(tester, AiStrip(noteId: 'n', onUndo: (_) => true, marks: StripMarks(count: 2, keepAll: () {})), theme: theme);
          final handle = startRun(ask(RunKind.format));
          await tester.pump();
          fakes[0].complete(answered('# Trip\n'));
          await handle.done;
          recordChange('n', handle.id, 'before', 'after');
        });
        await one('failed', () async {
          await show(tester, const AiStrip(noteId: 'n'), theme: theme);
          final handle = startRun(ask(RunKind.summarize));
          await tester.pump();
          fakes[0].fail('out of memory');
          await handle.done;
        });
        await end(tester);
      });
    }
  });
}
