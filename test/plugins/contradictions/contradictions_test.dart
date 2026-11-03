// The contradiction finder as the person meets it (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "flags the stale one inline,
// 'superseded by …', so old notes stop misleading you or the AI", then "Yes, fold them" for its word and Note decay
// alerts' chip): the one "May be out of date" mark on the older line (lib/plugins/out_of_date/), its sheet's
// Mark superseded and Not a conflict, the page in Settings in Simple and Advanced, and the home page's line. Pictures in
// build/feature-shots/contradictions/ under --update-goldens.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/contradictions/findings.dart';
import 'package:ghost_md/ai/contradictions/runner.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/column.dart' show EditorColumn;
import 'package:ghost_md/editor/view/editor_view.dart' show EditorView;
import 'package:ghost_md/editor/items/note_plugins.dart';
import 'package:ghost_md/market/market_items.dart' show marketHues, pluginHue;
import 'package:ghost_md/plugins/brands.dart' show ownPlugins;
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/contradictions/contradictions.dart';
import 'package:ghost_md/plugins/out_of_date/out_of_date.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart' show Pick;

import '../../ai/contradictions/support.dart';
import '../../editor/media/support.dart' show pumpNote;
import '../../support/feature_shot.dart';
import '../github/support.dart' show away, loadAppFonts, pumpPane, settle;

const String shots = 'contradictions';
final DateTime now = DateTime.utc(2026, 11, 9, 10);

Future<ContradictionRunner> foundRunner({List<String>? answers}) async {
  final runner = ContradictionRunner(notes: () => [plan, standup], pickAi: () async => ScriptedAi(answers ?? [releaseMoved()]), store: MemoryStored(), clock: () => now, activity: Activity(clock: () => now));
  await runner.run(personStarted: true);
  return runner;
}

/// The open note's editing, made once the view is.
class _Editing implements NoteEditing {
  _Editing(this.noteId);
  @override
  final String noteId;
  EditorView? view;
  final List<String> said = [];
  late final NoteEditing _inner = noteEditing(noteId, view, () => '', said.add);

  @override
  String body() => _inner.body();
  @override
  bool replaceLine(bool Function(String text, int line) find, String Function(String text) next) => _inner.replaceLine(find, next);
  @override
  void say(String message) => _inner.say(message);
}

Future<(EditorView, _Editing)> pumpPlan(WidgetTester tester, ContradictionRunner runner, {String theme = 'light'}) async {
  contradictionRunner.value = runner;
  addTearDown(() => contradictionRunner.value = null);
  final editing = _Editing('plan');
  final source = OutOfDateSource(id: 'contradictions', on: () => true, marks: (noteId, body) => contradictionMarks(noteId, body, runner: runner));
  final view = await pumpNote(tester, plan.body, theme: theme, more: <Extension>[outOfDateMarks(OutOfDateHooks(noteId: () => 'plan', sources: () => [source], editing: () => editing))]);
  editing.view = view;
  runner.onFindings = () => view.dispatch(TransactionSpec(effects: outOfDateRedraw()));
  await tester.pump();
  return (view, editing);
}

void main() {
  setUpAll(loadAppFonts);

  test('it ships off, on the AI shelf, in a hue of its own, with its own mark', () {
    final plugin = builtIn.singleWhere((p) => p.manifest.id == 'contradictions');
    expect(plugin.manifest.standard, isFalse);
    expect(plugin.manifest.category, PluginCategory.ai);
    expect(plugin.manifest.declares(Permission.network), isFalse, reason: 'Local only must not hold it off: it asks no host itself');
    expect(ownPlugins, contains('contradictions'));
    expect(pluginHue(plugin), 'slate');
    expect(marketHues.containsKey('slate'), isTrue);
    expect([for (final p in builtIn) if (p.manifest.id != 'contradictions') pluginHue(p)], isNot(contains('slate')));
  });

  test('the marks are one a line, on the line that holds the older words, and none without a runner', () async {
    final runner = await foundRunner();
    final marks = contradictionMarks('plan', plan.body, runner: runner);
    // The third line, counted from 0, with what the newer note says as its reason.
    expect(marks.single.line, 2);
    expect(marks.single.reason, 'Standup says “Release moved to Monday”');
    expect([for (final a in marks.single.actions) a.key], ['contradiction-superseded', 'contradiction-dismiss']);
    expect(contradictionMarks('standup', standup.body, runner: runner), isEmpty);
    expect(contradictionMarks('plan', withSuperseded(plan.body, runner.open.single, now), runner: runner), isEmpty);
    expect(contradictionMarks('plan', plan.body), isEmpty);
  });

  testWidgets('the mark on the older line opens its sheet; Mark superseded writes the line through the editor', (tester) async {
    final runner = (await tester.runAsync(foundRunner))!;
    final opened = <String>[];
    contradictionOpenNote = opened.add;
    addTearDown(() => contradictionOpenNote = null);
    final (view, _) = await pumpPlan(tester, runner);
    final pill = find.byKey(OutOfDateChip.chipKey);
    expect(pill, findsOneWidget);
    // On the third line: below the title's.
    final top = tester.getTopLeft(find.byType(EditorColumn)).dy;
    final line3 = view.coordsAtPos(view.state.doc.line(3).from)!, line5 = view.coordsAtPos(view.state.doc.line(5).from)!;
    final at = tester.getCenter(pill).dy - top;
    expect(at, greaterThan(line3.top - 4));
    expect(at, lessThan(line5.top));
    await featureShot(tester, shots, 'mark-light');

    await tester.tap(pill);
    await settle(tester);
    expect(find.byKey(OutOfDateSheet.sheetKey), findsOneWidget);
    expect(find.textContaining('Standup says “Release moved to Monday”', findRichText: true), findsOneWidget);
    expect(find.text('Open Standup'), findsOneWidget);
    await featureShot(tester, shots, 'sheet-light');

    await tester.tap(find.byKey(const ValueKey('contradiction-superseded')));
    await settle(tester);
    final lines = view.state.doc.toString().split('\n');
    expect(lines[2], 'Release is Thursday Nov 12.');
    expect(lines[3], startsWith('> Superseded by [[Standup]] ('));
    expect(lines[3], endsWith('): “Release moved to Monday”'));
    expect(runner.open, isEmpty);
    expect(find.byKey(OutOfDateChip.chipKey), findsNothing);
    await featureShot(tester, shots, 'superseded-light');
    await away(tester);
  });

  testWidgets('Not a conflict takes the mark away and it stays away', (tester) async {
    final runner = (await tester.runAsync(foundRunner))!;
    await pumpPlan(tester, runner, theme: 'dark');
    await featureShot(tester, shots, 'mark-dark');
    await tester.tap(find.byKey(OutOfDateChip.chipKey));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('contradiction-dismiss')));
    await settle(tester);
    expect(find.byKey(OutOfDateChip.chipKey), findsNothing);
    expect(runner.open, isEmpty);
    await away(tester);
  });

  testWidgets('the page: Check, when it checks, what may be out of date, and More in Simple', (tester) async {
    final runner = (await tester.runAsync(foundRunner))!;
    await pumpPane(tester, ContradictionsPane(runner: runner, aiName: () => 'Claude'));
    expect(find.text('Check now'), findsOneWidget);
    expect(find.textContaining('Checked by Claude', findRichText: true), findsOneWidget);
    expect(find.text('Nightly'), findsOneWidget);
    expect(find.text('Release plan'), findsOneWidget);
    expect(find.text('Organization notes'), findsOneWidget, reason: 'Advanced shows every setting');
    await featureShot(tester, shots, 'page-advanced');

    preferences.value = preferences.value.copyWith(experience: 'simple');
    await settle(tester);
    expect(find.text('Organization notes'), findsNothing);
    expect(find.byKey(const ValueKey('contradictions-more')), findsOneWidget);
    await featureShot(tester, shots, 'page-simple');
    await tester.ensureVisible(find.text('Show'));
    await settle(tester);
    await tester.tap(find.text('Show'));
    await settle(tester);
    expect(find.text('Organization notes'), findsOneWidget, reason: 'More opens in place');

    await tester.ensureVisible(find.byKey(const ValueKey('contradictions-when-saved')));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('contradictions-when-saved')), matching: find.byType(Pick)));
    await settle(tester);
    expect(runner.settings.schedule, ContradictionSchedule.saved);

    await tester.ensureVisible(find.byKey(const ValueKey('finding-dismiss')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('finding-dismiss')));
    await settle(tester);
    expect(find.text('Nothing out of date'), findsOneWidget);
    await away(tester);
  });

  testWidgets('the home page’s line while anything may be out of date', (tester) async {
    final runner = (await tester.runAsync(foundRunner))!;
    var opened = 0;
    await pumpPane(tester, ContradictionsNotice(runner: runner, on: () => true, onOpen: () => opened += 1));
    expect(find.textContaining('1 note may be out of date', findRichText: true), findsOneWidget);
    await featureShot(tester, shots, 'home-line');
    await tester.tap(find.text('Review'));
    expect(opened, 1);
    await tester.runAsync(() => runner.dismiss(runner.open.single));
    await settle(tester);
    expect(find.byKey(const ValueKey('contradictions-notice')), findsNothing);
    await away(tester);
  });
}
