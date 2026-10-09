import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/capture/refine.dart' show RefineState;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/scene/at_work.dart';
import 'package:ghost_md/scene/feed.dart';
import 'package:ghost_md/scene/hot_phone.dart';
import 'package:ghost_md/scene/steps.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import 'scene_support.dart';

/// The scene over the note: it is there in the first frame a review key gives it, says what the review is doing,
/// follows the run through its phases and the phone's readings, leaves once the run ends, and never keeps a timer
/// after it is gone. The cases of `src/app/scene/AtWork.test.tsx`, by name.
///
/// Where the page's tests read the DOM, these read the widgets that draw it: a step's row ([AtWorkStepRow]), a tile
/// ([AtWorkTile]), a line of the pane ([AtWorkLine]), the phone ([HotPhone]), and what the scene's root element wore
/// ([AtWorkState.debugScene]). `vi.getTimerCount()` is [AtWorkState.debugTimers], and the test binding itself fails
/// a test that ends with a timer waiting.

Finder get sceneFinder => find.byKey(const ValueKey('at-work'));
bool there() => sceneFinder.evaluate().isNotEmpty;
AtWorkState state(WidgetTester tester) => tester.state<AtWorkState>(find.byType(AtWork));
String? title(WidgetTester tester) => there() ? tester.widget<Text>(find.byKey(const ValueKey('at-work-title'))).data : null;
String detail(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('at-work-detail'))).data!;
String live(WidgetTester tester) => tester.widget<Semantics>(find.byKey(const ValueKey('at-work-live'))).properties.label!;
List<AtWorkStepRow> rows(WidgetTester tester) => tester.widgetList<AtWorkStepRow>(find.byType(AtWorkStepRow)).toList();
String rowText(AtWorkStepRow row) => '${row.step.words}${row.step.detail != null && row.step.detail!.isNotEmpty ? ' ${row.step.detail}' : ''}';
String? working(WidgetTester tester) {
  final found = rows(tester).where((row) => row.step.state == StepState.working);
  return found.isEmpty ? null : rowText(found.first);
}

List<AtWorkStepRow> done(WidgetTester tester) => rows(tester).where((row) => row.step.state == StepState.done).toList();
String? tile(WidgetTester tester, String label) => tester.widgetList<AtWorkTile>(find.byType(AtWorkTile)).firstWhere((t) => t.label == label).value;
List<AtWorkLine> lines(WidgetTester tester) => tester.widgetList<AtWorkLine>(find.byType(AtWorkLine)).toList();
String paneText(WidgetTester tester) => [for (final line in lines(tester)) line.line.text].join('\n');
int? head(WidgetTester tester) {
  final found = lines(tester).where((line) => line.place == LinePlace.current);
  return found.isEmpty ? null : found.first.line.at;
}

HotPhone phone(WidgetTester tester) => tester.widget<HotPhone>(find.byType(HotPhone));
List<String> buttons(WidgetTester tester) => [for (final word in tester.widgetList<AppWord>(find.descendant(of: sceneFinder, matching: find.byType(AppWord)))) (word.child as Text).data!];

Future<void> hide(WidgetTester tester, bool hidden) async {
  tester.binding.handleAppLifecycleStateChanged(hidden ? AppLifecycleState.hidden : AppLifecycleState.resumed);
  await tester.pump();
}

Future<void> setWispEdge(WidgetTester tester, bool on) async {
  preferences.value = preferences.value.copyWith(wispEdge: on);
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(setUpScene);

  /// Each case ends as the page's `afterEach` did: the scene off the screen, the fakes ended, the app seen again.
  Future<void> end(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tearDownScene(tester);
  }

  group('opening', () {
    testWidgets('renders nothing with no review', (tester) async {
      await show(tester, atWork(tester, opening: null));
      expect(there(), isFalse);
      await end(tester);
    });

    testWidgets('has the scene in the first render a key gives it, with the opening words', (tester) async {
      await show(tester, atWork(tester));
      expect(there(), isTrue);
      expect(title(tester), 'Checking what was heard.');
      expect(detail(tester), 'The recording is saved.');
      expect(working(tester), 'Listening again');
      expect(phone(tester).step, StepId.listen);
      // The transcript, through the phone.
      expect(paneText(tester), contains('Groceries for the week.'));
      expect(tile(tester, 'Since Done'), '0:00');
      expect(tile(tester, 'CPU'), '');
      await end(tester);
    });

    testWidgets('says the stage’s words and percent, and the download’s words while the better model comes down', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(40)));
      expect(title(tester), 'Listening again, 40%.');
      // The heading a screen reader hears has no number in it.
      expect(tester.widget<Semantics>(find.byKey(const ValueKey('at-work-heading'))).properties.label, 'Listening again.');
      expect(live(tester), 'Listening again.');
      refining.value = const RefineState(pending: <String>{}, download: (received: 12000000, total: 190000000));
      await rerender(tester, atWork(tester, stage: listeningAt(0)));
      expect(title(tester), 'Getting the better voice model, 12 of 190 MB.');
      expect(working(tester), contains('Getting the better voice model, 12 of 190 MB.'));
      expect(detail(tester), 'Once, then it stays on the phone.');
      await end(tester);
    });

    testWidgets('ignores an ended run the note already had, and follows a live one', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final first = await start(tester);
      first.fake.finish('[]\n');
      await tester.pump();
      await first.handle.done;
      await show(tester, atWork(tester, opening: 1));
      expect(title(tester), 'Checking what was heard.');
      await unmount(tester);
      await start(tester);
      await rerender(tester, atWork(tester, opening: 2));
      expect(title(tester), 'Loading Qwen3.5 4B.');
      await end(tester);
    });
  });

  group('following the run', () {
    testWidgets('goes through loading, reading, thinking and writing to done, with the phone’s readings, then leaves', (tester) async {
      await show(tester, atWork(tester, stage: comparingStage));
      expect(rowText(done(tester).first), contains('3 places where the two models heard different words.'));
      await rerender(tester, atWork(tester));
      final run = await start(tester);
      final fake = run.fake;
      expect(title(tester), 'Loading Qwen3.5 4B.');
      expect(detail(tester), '2.7 GB on this phone.');
      expect(working(tester), 'Loading the model');
      expect(rows(tester).any((row) => row.turning), isTrue);
      expect(tile(tester, 'CPU'), '');
      expect(tile(tester, 'Heat'), '');
      expect(tile(tester, 'Pace'), '');
      expect(state(tester).debugScene?.warmth, Warmth.warm);
      // The listen step keeps what Comparing said after the stage has cleared.
      expect(rowText(done(tester).first), contains('3 places where the two models heard different words.'));

      fake.report(phase: Phase.prefill, promptTokens: 1040, promptTokensDone: 312, tokensPerSecond: 430);
      await tester.pump();
      expect(title(tester), 'Reading the note, 312 of 1040.');
      expect(working(tester), 'Reading the note');
      expect(state(tester).debugScene?.warmth, Warmth.hot);
      // A report past loading without hardware: the phone gives no reading.
      expect(tile(tester, 'CPU'), 'No reading');
      expect(tile(tester, 'Heat'), 'No reading');
      expect(tile(tester, 'Pace'), '430');
      expect(phone(tester).litPins, 0);

      fake.report(partial: '<think>Is seat right?', thinking: true, tokensPerSecond: 9.4, hardware: busy);
      await tester.pump();
      expect(title(tester), 'Qwen3.5 4B is thinking it through.');
      expect(working(tester), 'Thinking it through');
      expect(phone(tester).step, StepId.think);
      expect(tile(tester, 'Heat'), '41 °C');
      expect(tile(tester, 'CPU'), '640%');
      expect(tile(tester, 'Pace'), '9.4');
      expect(paneText(tester), contains('Is seat right?'));
      expect(phone(tester).pins, 8);
      expect(phone(tester).litPins, 6);
      // Busy 640 of 600 is full; heat 41 is a little over half: the glow reaches the fourth ring.
      expect(phone(tester).glowStep, 4);

      fake.report(partial: '<think>Is seat right?</think>\n[{"what": "“seek”, not “seat”", "why": "x"}, {"what": "The garden li', thinking: true, hardware: busy);
      await tester.pump();
      expect(title(tester), 'Qwen3.5 4B is writing what it found.');
      expect(working(tester), 'Writing what it found');
      expect(paneText(tester), contains('“seek”, not “seat”'));
      expect(paneText(tester), contains('The garden li'));
      expect(paneText(tester), isNot(contains('"what"')));

      fake.finish('<think>Is seat right?</think>\n[]\n', thinking: true);
      await tester.pump();
      await run.handle.done;
      await tester.pump();
      expect(title(tester), 'Reviewed by Qwen3.5 4B in 1:12.');
      expect(working(tester), isNull);
      expect(done(tester).length, 6);
      expect(state(tester).debugScene?.warmth, Warmth.cold);
      // The settle: the words go to the quiet ink with the die.
      expect(state(tester).debugScene?.ended, isTrue);
      expect(lines(tester).every((line) => line.ended), isTrue);
      expect(phone(tester).litPins, 0);
      expect(state(tester).debugScene?.leaving, isFalse);
      expect(live(tester), 'Reviewed by Qwen3.5 4B in 1:12.');
      await later(tester, holdMs);
      expect(state(tester).debugScene?.leaving, isTrue);
      await later(tester, leaveMs);
      expect(there(), isFalse);
      expect(state(tester).debugTimers, 0);
      await end(tester);
    });

    testWidgets('does not leave while a stage is up, whatever an earlier ask’s run did', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final run = await start(tester, RunKind.ask);
      run.fake.cancel();
      await tester.pump();
      await run.handle.done;
      expect(runFor('n')?.phase, RunPhase.stopped);
      await show(tester, atWork(tester, opening: 2, stage: listeningAt(20)));
      expect(title(tester), 'Listening again, 20%.');
      // In steps, so a frame is drawn between the timers: a leave chain a missing guard started would be seen.
      await later(tester, graceMs);
      await later(tester, holdMs);
      await later(tester, leaveMs + 1000);
      expect(there(), isTrue);
      expect(title(tester), 'Listening again, 20%.');
      await end(tester);
    });

    testWidgets('waits while the document is hidden, and settles and leaves once it is seen again', (tester) async {
      await show(tester, atWork(tester, stage: comparingStage));
      await rerender(tester, atWork(tester));
      final run = await start(tester);
      await hide(tester, true);
      run.fake.finish('[]\n');
      await tester.pump();
      await run.handle.done;
      await later(tester, holdMs);
      await later(tester, leaveMs + 1000);
      expect(there(), isTrue);
      expect(state(tester).debugScene?.leaving, isFalse);
      await hide(tester, false);
      expect(title(tester), 'Reviewed by Qwen3.5 4B in 1:12.');
      await later(tester, holdMs);
      expect(state(tester).debugScene?.leaving, isTrue);
      await later(tester, leaveMs);
      expect(there(), isFalse);
      expect(state(tester).debugTimers, 0);
      await end(tester);
    });

    testWidgets('cancels a pending leave when a new run appears', (tester) async {
      await show(tester, atWork(tester, stage: comparingStage));
      await rerender(tester, atWork(tester));
      final first = await start(tester);
      first.fake.finish('[]\n');
      await tester.pump();
      await first.handle.done;
      await later(tester, holdMs - 50);
      await start(tester);
      await later(tester, 5000);
      expect(there(), isTrue);
      expect(title(tester), 'Loading Qwen3.5 4B.');
      await end(tester);
    });

    testWidgets('waits the grace for a summary run after the review’s while the queue holds one for the note, and follows it', (tester) async {
      summaryDue.value = true;
      await show(tester, atWork(tester, stage: comparingStage));
      await rerender(tester, atWork(tester));
      final first = await start(tester);
      first.fake.finish('[]\n');
      await tester.pump();
      await first.handle.done;
      // Past the settle the scene is still there: a summary may follow.
      await later(tester, holdMs + leaveMs);
      expect(there(), isTrue);
      expect(state(tester).debugScene?.leaving, isFalse);
      final second = await start(tester, RunKind.summarize);
      second.fake.report(phase: Phase.prefill, promptTokens: 400, promptTokensDone: 100);
      await tester.pump();
      expect(working(tester), 'Reading the recording');
      expect([for (final row in rows(tester)) rowText(row)], contains('Writing the summary'));
      second.fake.finish('## Summary\nA line.\n');
      await tester.pump();
      await second.handle.done;
      summaryDue.value = false;
      await rerender(tester, atWork(tester));
      await later(tester, holdMs + leaveMs);
      expect(there(), isFalse);
      expect(state(tester).debugTimers, 0);
      await end(tester);
    });

    testWidgets('leaves after the grace when no summary run comes, and after the settle alone when none is queued', (tester) async {
      summaryDue.value = true;
      await show(tester, atWork(tester, stage: comparingStage));
      await rerender(tester, atWork(tester));
      final run = await start(tester);
      run.fake.finish('[]\n');
      await tester.pump();
      await run.handle.done;
      await tester.pump();
      await later(tester, graceMs - 1);
      expect(state(tester).debugScene?.leaving, isFalse);
      await later(tester, 1);
      expect(state(tester).debugScene?.leaving, isTrue);
      await later(tester, leaveMs);
      expect(there(), isFalse);
      expect(state(tester).debugTimers, 0);
      await end(tester);
    });

    testWidgets('takes the review as over when no run comes after the stage clears, says so, and leaves', (tester) async {
      await show(tester, atWork(tester, stage: comparingStage));
      await rerender(tester, atWork(tester));
      await later(tester, graceMs);
      expect(title(tester), 'Done.');
      expect(done(tester).length, 6);
      await later(tester, holdMs + leaveMs);
      expect(there(), isFalse);
      expect(state(tester).debugTimers, 0);
      await end(tester);
    });

    testWidgets('leaves quietly when it has seen nothing at all', (tester) async {
      await show(tester, atWork(tester));
      await later(tester, openGraceMs - 1);
      expect(there(), isTrue);
      expect(title(tester), 'Checking what was heard.');
      await later(tester, 1 + leaveMs);
      expect(there(), isFalse);
      expect(state(tester).debugTimers, 0);
      await end(tester);
    });
  });

  group('the words', () {
    testWidgets('stops the run from the scene', (tester) async {
      await show(tester, atWork(tester));
      final run = await start(tester);
      await tester.tap(find.text('Stop'));
      await tester.pump();
      await run.handle.done;
      await tester.pump();
      expect(haptics, contains(HapticKind.warning));
      expect(title(tester), 'Stopped.');
      expect(working(tester), isNull);
      expect(buttons(tester), ['Back to the note']);
      await end(tester);
    });

    testWidgets('shows Stop only while a run is live, never for a stage, even with an earlier ask’s run live under it', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(10)));
      expect(buttons(tester), ['Back to the note']);
      // The recorder hands the review and an ask together; the ask's run is live while the stage is up, and has no Stop here.
      await start(tester, RunKind.ask);
      await rerender(tester, atWork(tester, stage: listeningAt(20)));
      expect(runFor('n')?.phase, RunPhase.loading);
      expect(buttons(tester), ['Back to the note']);
      await end(tester);
    });

    testWidgets('goes behind the note at once on Back to the note, and holds no timer after', (tester) async {
      await show(tester, atWork(tester));
      await tester.tap(find.text('Back to the note'));
      await tester.pump();
      expect(there(), isFalse);
      expect(haptics, contains(HapticKind.selection));
      expect(state(tester).debugTimers, 0);
      await unmount(tester);
      await end(tester);
    });

    testWidgets('takes the first back gesture, and leaves the second to the note', (tester) async {
      var backs = 0;
      await show(tester, OnBack(onBack: () => backs += 1, child: atWork(tester)));
      testBack.goBack();
      await tester.pump();
      expect(there(), isFalse);
      expect(backs, 0);
      testBack.goBack();
      await tester.pump();
      expect(backs, 1);
      await end(tester);
    });
  });

  group('motion and the haze', () {
    testWidgets('keeps still under reduced motion: no filter on the pane at all', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(10)), still: true);
      expect(state(tester).debugScene?.still, isTrue);
      // The phone is told too: no fade on its mark, no transitions.
      expect(phone(tester).still, isTrue);
      expect(state(tester).debugBend, isNull);
      expect(state(tester).debugHazeOn, isFalse);
      await end(tester);
    });

    testWidgets('bends the words by the warmth: half while a model listens or loads, whole while it reads and writes, none after', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(10)));
      expect(state(tester).debugBend, '0.72');
      await rerender(tester, atWork(tester));
      final run = await start(tester);
      run.fake.report(phase: Phase.prefill, promptTokens: 1040, promptTokensDone: 312);
      await tester.pump();
      expect(state(tester).debugBend, '1.44');
      run.fake.finish('[]\n');
      await tester.pump();
      await run.handle.done;
      await tester.pump();
      expect(state(tester).debugBend, '0.00');
      await end(tester);
    });

    testWidgets('wears the haze only with the smoke at the edges on', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(10)), prefs: const Preferences(theme: 'light', wispEdge: false));
      expect(state(tester).debugBend, isNotNull);
      expect(state(tester).debugHazeOn, isFalse);
      await setWispEdge(tester, true);
      expect(state(tester).debugHazeOn, isTrue);
      // And never while the die is cold.
      await rerender(tester, atWork(tester));
      expect(state(tester).debugHazeOn, isFalse);
      await end(tester);
    });

    testWidgets('steps the noise once a report, no faster than eight a second, and not while hidden', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(10)));
      expect(state(tester).debugFrequency, matches(RegExp(r'^0\.0\d{3} 0\.\d{4}$')));
      final were = state(tester).debugHazeWrites;
      int writes() => state(tester).debugHazeWrites - were;
      // A report a moment later: one write.
      await tester.pump(const Duration(milliseconds: 200));
      await rerender(tester, atWork(tester, stage: listeningAt(20)));
      expect(writes(), 1);
      // The same report drawn again: nothing.
      await rerender(tester, atWork(tester, stage: listeningAt(20)));
      expect(writes(), 1);
      // Two reports inside an eighth of a second: the second is skipped.
      await tester.pump(const Duration(milliseconds: 200));
      await rerender(tester, atWork(tester, stage: listeningAt(30)));
      await tester.pump(const Duration(milliseconds: 20));
      await rerender(tester, atWork(tester, stage: listeningAt(40)));
      expect(writes(), 2);
      // Hidden: nothing, and the filter comes off.
      await hide(tester, true);
      await tester.pump(const Duration(milliseconds: 500));
      await rerender(tester, atWork(tester, stage: listeningAt(50)));
      expect(writes(), 2);
      expect(state(tester).debugHazeOn, isFalse);
      await hide(tester, false);
      await end(tester);
    });

    testWidgets('holds the feed and the picture while hidden, and reads them again on return', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(10)));
      expect(head(tester), 0);
      expect(state(tester).debugScene?.warmth, Warmth.warm);
      await hide(tester, true);
      // The stage clears off screen: the head would move to the last phrase and the die would cool, but nothing is redrawn.
      await rerender(tester, atWork(tester));
      expect(head(tester), 0);
      expect(state(tester).debugScene?.warmth, Warmth.warm);
      await hide(tester, false);
      expect(head(tester), 2);
      expect(state(tester).debugScene?.warmth, Warmth.cold);
      await end(tester);
    });

    testWidgets('pauses the clock while hidden and jumps to the truth on return', (tester) async {
      await show(tester, atWork(tester, stage: listeningAt(10)));
      expect(tile(tester, 'Since Done'), '0:00');
      await later(tester, 3000);
      expect(tile(tester, 'Since Done'), '0:03');
      await hide(tester, true);
      await later(tester, 5000);
      expect(tile(tester, 'Since Done'), '0:03');
      await hide(tester, false);
      expect(tile(tester, 'Since Done'), '0:08');
      await end(tester);
    });
  });

  group('the pane', () {
    testWidgets('keeps the line being read at the anchor, gliding to it while it reads and snapping while it streams', (tester) async {
      final many = [for (var i = 0; i < 30; i += 1) 'Sentence number ${i + 1} is said here.'].join(' ');
      await show(tester, atWork(tester, heard: many, stage: listeningAt(0)));
      expect(state(tester).debugScrollTop, 0);
      expect(state(tester).debugScene?.mode, FeedMode.transcript);
      await rerender(tester, atWork(tester, heard: many, stage: listeningAt(50)));
      // On its way: `scroll-behavior: smooth`.
      await tester.pump(const Duration(milliseconds: 100));
      final part = state(tester).debugScrollTop;
      expect(part, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 300));
      final whole = state(tester).debugScrollTop;
      expect(whole, greaterThan(part));
      // The head line's top is 72% down the pane.
      final pane = tester.getRect(find.byKey(const ValueKey('at-work-pane')));
      final current = tester.getRect(find.byWidgetPredicate((w) => w is AtWorkLine && w.place == LinePlace.current));
      expect(current.top - pane.top, closeTo(pane.height * 0.72, 0.5));
      await end(tester);
    });
  });
}
