// What moves, and when it stops: the frame loop the smoke and the effects share (`markMotion`), which the page has
// as `requestAnimationFrame` while any smoke is on screen and CSS animations otherwise; and the leaving half of the
// wisp drawn (`wispDepartures`): a ghost of what a person took out, gone and settled after its arc.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';

Future<EditorView> _pump(WidgetTester tester, String doc, {bool typing = false, bool still = false}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: doc, extensions: noteExtensions(formats: marks, more: <Extension>[markExtensions(marks, wispTyping: typing)])),
  );
  addTearDown(view.destroy);
  if (still) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await pumpApp(
    tester,
    prefs: const AppPreferences(theme: 'light'),
    home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view)))),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return view;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a spoiler keeps the frames coming, and stops when the caret lifts it', (tester) async {
    final view = await _pump(tester, 'A ||secret|| here');
    await tester.pump(const Duration(milliseconds: 40));
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0), reason: 'the smoke moves');
    final before = MarkClock.now;
    await tester.pump(const Duration(milliseconds: 100));
    expect(MarkClock.now, greaterThan(before));
    // The caret in the words: plain text, nothing moving, no frames asked for.
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(5)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(SchedulerBinding.instance.transientCallbackCount, 0, reason: 'nothing moves');
    debugDisableShadows = true;
  });

  testWidgets('with reduced motion the smoke and the effects are drawn and nothing ticks', (tester) async {
    await _pump(tester, 'A ||secret|| and 🌊🌊sea🌊🌊 and 👻👻gone👻👻', still: true);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    debugDisableShadows = true;
  });

  testWidgets('a word deleted by hand leaves a ghost that settles after its arc', (tester) async {
    final view = await _pump(tester, 'The quick brown fox', typing: true);
    view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 4, to: 10), userEvent: 'delete.selection'));
    expect(moving(view.state).length, 1);
    expect(moving(view.state).single.gone, 'quick ');
    await tester.pump();
    // Drawn where the word left, taking no room: the line reads as it now is.
    expect(view.state.doc.toString(), 'The brown fox');
    await tester.pump(const Duration(milliseconds: 60));
    expect(moving(view.state), isNotEmpty, reason: 'still leaving');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(moving(view.state), isEmpty, reason: 'settled');
    // A single letter backspaced leaves no trace.
    view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 12, to: 13), userEvent: 'delete.backward'));
    expect(moving(view.state), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
  });
}
