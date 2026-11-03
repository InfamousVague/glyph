// The one "May be out of date" mark (lib/plugins/out_of_date/; Matt, 2026-11-02: "Yes, fold them", of the Contradiction
// finder's "Out of date?" word and Note decay alerts' chip): a line both flag wears one chip that counts its reasons, and
// its sheet lists each reason with its own plugin's actions; one put away leaves the other. With neither plugin on, the
// page is never read for marks. Pictures in build/feature-shots/out-of-date/ with --update-goldens. The AI is a fake's.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/contradictions/runner.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/plugins/contradictions/contradictions.dart';
import 'package:ghost_md/plugins/note_decay/decay.dart';
import 'package:ghost_md/plugins/note_decay/source.dart';
import 'package:ghost_md/plugins/out_of_date/out_of_date.dart';

import '../../ai/contradictions/support.dart';
import '../../editor/media/support.dart' show pumpNote;
import '../../support/feature_shot.dart';
import '../github/support.dart' show away, loadAppFonts, settle;

/// The plan's release line, speaking of its day as ahead, a day after it.
final String planBody = plan.body.replaceFirst('Release is Thursday Nov 12.', 'Release is Thursday Nov 12, and it will ship then.');
final DateTime now = DateTime(2026, 11, 13, 10);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a line both plugins flag wears one chip, and its sheet lists both reasons with their own actions', (tester) async {
    final older = note('plan', planBody);
    final runner = (await tester.runAsync(() async {
      final runner = ContradictionRunner(notes: () => [older, standup], pickAi: () async => ScriptedAi([releaseMoved()]), store: MemoryStored(), clock: () => now, activity: Activity(clock: () => now));
      await runner.run(personStarted: true);
      return runner;
    }))!;
    final decay = NoteDecay(notes: () => [older, standup], clock: () => now);
    addTearDown(decay.dispose);
    var reads = 0;
    final sources = [
      OutOfDateSource(id: 'contradictions', on: () => true, marks: (noteId, body) => contradictionMarks(noteId, body, runner: runner)),
      decayOutOfDate(decay: () => decay),
    ];
    final view = await pumpNote(tester, planBody, more: <Extension>[
      outOfDateMarks(OutOfDateHooks(
        noteId: () => 'plan',
        sources: () {
          reads += 1;
          return sources;
        },
        changes: decay,
      )),
    ]);
    runner.onFindings = () => view.dispatch(TransactionSpec(effects: outOfDateRedraw()));
    await settle(tester);
    expect(reads, greaterThan(0));
    final chip = find.byKey(OutOfDateChip.chipKey);
    expect(chip, findsOneWidget);
    expect(find.text('May be out of date · 2'), findsOneWidget);
    await featureShot(tester, 'out-of-date', 'one-chip-two-reasons');

    await tester.tap(chip);
    await settle(tester);
    expect(find.byKey(OutOfDateSheet.sheetKey), findsOneWidget);
    // The newer note's words first, then the date's, each with its own plugin's rows.
    expect(find.text('Standup says “Release moved to Monday”'), findsOneWidget);
    expect(find.text('Nov 12 has passed; this still speaks of it as ahead'), findsOneWidget);
    for (final key in ['contradiction-superseded', 'contradiction-dismiss', 'decay-update', 'decay-still-right']) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    expect(tester.getTopLeft(find.byKey(const ValueKey('contradiction-dismiss'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('decay-update'))).dy));
    await featureShot(tester, 'out-of-date', 'sheet-both');

    // Not a conflict puts the finder's reason away; the date's stays, on the same chip.
    await tester.tap(find.byKey(const ValueKey('contradiction-dismiss')));
    await settle(tester);
    expect(runner.open, isEmpty);
    expect(chip, findsOneWidget);
    expect(find.text('May be out of date'), findsOneWidget);
    expect(find.bySemanticsLabel('May be out of date: Nov 12 has passed; this still speaks of it as ahead'), findsOneWidget);
    await away(tester);
  });

  testWidgets('with no source on, the page is never read for marks, typing or not', (tester) async {
    var read = 0;
    final source = OutOfDateSource(id: 'off', on: () => false, marks: (noteId, body) {
      read += 1;
      return const [];
    });
    final view = await pumpNote(tester, planBody, more: <Extension>[outOfDateMarks(OutOfDateHooks(noteId: () => 'plan', sources: () => [source]))]);
    view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'x')));
    await tester.pump(const Duration(seconds: 1));
    expect(read, 0);
    expect(find.byKey(OutOfDateChip.chipKey), findsNothing);
    await away(tester);
  });
}
