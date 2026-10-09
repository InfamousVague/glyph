import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/review_stage.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/capture/refine.dart' show RefineState;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/scene/at_work.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import '../support/render.dart';

export '../support/render.dart';

/// A model that answers when the test says so: the web tests' fake `generate`, handed to the engine through
/// ai/runs.dart `simulateRuns`, which is that seam here.
class FakeModel {
  FakeModel(this.options);

  final RunOptions options;
  final Completer<Output> _done = Completer<Output>();

  Run get run => Run(done: _done.future, cancel: cancel);

  void report({Phase phase = Phase.generating, int promptTokens = 100, int promptTokensDone = 100, int outputTokens = 10, double tokensPerSecond = 12, int elapsedMs = 1000, String partial = '', bool? thinking, Hardware? hardware}) =>
      options.onProgress(Progress(id: 'x', phase: phase, promptTokens: promptTokens, promptTokensDone: promptTokensDone, outputTokens: outputTokens, tokensPerSecond: tokensPerSecond, elapsedMs: elapsedMs, partial: partial, thinking: thinking, hardware: hardware));

  void finish(String text, {bool? thinking}) {
    if (!_done.isCompleted) _done.complete(Output(text: text, promptTokens: 100, outputTokens: 20, ms: 72000, cachedTokens: 0, prefillMs: 100, loadMs: 100, tokensPerSecond: 12, truncated: false, thinking: thinking));
  }

  void fail(String message) {
    if (!_done.isCompleted) _done.completeError(AiFailure(message));
  }

  void cancel() => fail('cancelled');
}

/// Every fake the engine has been handed in this test, oldest first.
final List<FakeModel> fakes = <FakeModel>[];

/// What the scene asked of the motor.
final List<HapticKind> haptics = <HapticKind>[];

/// The better-words queue as the scene follows it: a test sets its download.
final ValueNotifier<RefineState> refining = ValueNotifier<RefineState>(const RefineState(pending: <String>{}, download: null));

/// Whether the summary queue holds a job for note `n`.
final ValueNotifier<bool> summaryDue = ValueNotifier<bool>(false);

/// The back stack the scene is under: `testBack.goBack()` is the phone's back gesture.
late BackStack testBack;

/// Before each test: the engine takes fakes, and what the last test left is gone.
void setUpScene() {
  fakes.clear();
  haptics.clear();
  refining.value = const RefineState(pending: <String>{}, download: null);
  summaryDue.value = false;
  simulateRuns((options) {
    final fake = FakeModel(options);
    fakes.add(fake);
    return fake.run;
  });
}

/// After each test: whatever the fake engine still holds ends now, on the clock that set it.
Future<void> tearDownScene(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  for (final fake in fakes) {
    fake.cancel();
  }
  await tester.pump();
  forgetAllRuns();
  await tester.pump();
  simulateRuns(null);
  await tester.pump(const Duration(seconds: 1));
}

const String heard = 'Groceries for the week. Milk, eggs and coffee. Then the garden.';
const String body = '# Groceries\n- Milk, eggs and coffee\nThen the garden.';
ReviewStage listeningAt(int percent) => ReviewStage(what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent: percent);
const ReviewStage comparingStage = ReviewStage(what: 'Comparing', detail: '3 places where the two models heard different words.', percent: null);
const Hardware busy = Hardware(rssBytes: 3000000000, freeBytes: 4000000000, totalBytes: 12000000000, cpuPercent: 640, threads: 6, cores: 8, tempC: 41);

/// The scene as the web's tests make it (`atWork(over)`): note `n`, opening 1, with a job and no stage, on the
/// test's clock.
Widget atWork(WidgetTester tester, {int? opening = 1, String heard = heard, String body = body, bool hasJob = true, ReviewStage? stage, bool inline = false}) => AtWork(
      noteId: 'n',
      opening: opening,
      heard: heard,
      body: body,
      hasJob: hasJob,
      stage: stage,
      inline: inline,
      refining: refining,
      summaryDue: summaryDue,
      haptic: haptics.add,
      now: () => tester.binding.clock.now().millisecondsSinceEpoch,
    );

/// What is on the screen: [show] puts it there and [rerender] changes it, the app round it left as it was.
final ValueNotifier<Widget> _shown = ValueNotifier<Widget>(const SizedBox.shrink());

/// Puts [child] under the app's theme and a back scope of the test's own (`show`). [still] is the phone asking for
/// reduced motion.
Future<void> show(WidgetTester tester, Widget child, {Size size = const Size(390, 844), Preferences prefs = const Preferences(theme: 'light'), bool still = false}) async {
  testBack = BackStack();
  if (still) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  _shown.value = child;
  await pumpApp(tester, size: size, prefs: prefs, home: BackScope(stack: testBack, child: ValueListenableBuilder<Widget>(valueListenable: _shown, builder: (context, shown, _) => shown)));
  await tester.pump();
}

/// The same tree with the scene given something new (`rerender`).
Future<void> rerender(WidgetTester tester, Widget child) async {
  _shown.value = child;
  await tester.pump();
  await tester.pump();
}

/// Takes what is shown off the screen (`unmount`).
Future<void> unmount(WidgetTester tester) => rerender(tester, const SizedBox.shrink());

/// A run started for note `n` on a fake that has not been told what to do yet (`start`).
Future<({RunHandle handle, FakeModel fake})> start(WidgetTester tester, [RunKind kind = RunKind.review]) async {
  final handle = startRun(RunRequest(noteId: 'n', kind: kind, model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 1900, think: true));
  await tester.pump();
  return (handle: handle, fake: fakes.last);
}

/// In steps, as frames, so every timer that falls due fires and is drawn before the next (`later`).
Future<void> later(WidgetTester tester, int ms) async {
  for (var left = ms; left > 0; left -= 50) {
    await tester.pump(Duration(milliseconds: left < 50 ? left : 50));
  }
  await tester.pump();
}

/// Ends a test that drew with real shadows ([pumpApp] turns them on, and the binding checks the switch as it ends).
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
