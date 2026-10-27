// Settings › Snippets (lib/settings/panes/snippets_pane.dart; Matt, 2026-10-27: "build ... snippets"): the list with
// what each writes now, a new one added, one edited and deleted, moved up and down, what is wrong said and Save held
// back for it; and the section itself, Advanced's, in amber, found by the search.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/account_forms.dart' show FormProblem;
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/snippets_pane.dart';
import 'package:ghost_md/settings/settings_sections.dart';

import '../support.dart';

final DateTime now = DateTime(2026, 10, 27, 16, 5);

List<String> labels(WidgetTester tester) => [
      for (final row in tester.widgetList<SettingRow>(find.byWidgetPredicate((w) => w is SettingRow && (w.key is ValueKey<String>) && (w.key! as ValueKey<String>).value.startsWith('snippet-s'), skipOffstage: false))) row.label,
    ];

List<String> triggers() => [for (final each in preferences.value.snippets) each.trigger];

Future<void> open(WidgetTester tester, {List<Snippet> snippets = defaultSnippets}) async {
  await pumpSettings(
    tester,
    SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: SnippetsPane(clock: () => now))),
    prefs: Preferences(theme: 'light', snippets: snippets),
    size: const Size(390, 1600),
  );
}

Future<void> typeIn(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(key), matching: find.byType(EditableText)), text);
  await tester.pump();
}

Future<void> tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await settleSettings(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('lists the snippets by trigger, each with what it writes now; ;date and ;time on a new device', (tester) async {
    await open(tester);
    expect(find.text(';date'), findsOneWidget);
    expect(find.text('27 October 2026'), findsOneWidget);
    expect(find.text(';time'), findsOneWidget);
    expect(find.text('16:05'), findsOneWidget);
    expect(find.text('New snippet'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('a new one: what is wrong is said as it is typed, Add waits for it, then it is kept at the end', (tester) async {
    await open(tester);
    await tap(tester, const ValueKey('snippet-new'));
    final add = find.byKey(const ValueKey('snippet-save'));
    // A fresh form is not yet wrong, and cannot be added.
    expect(find.byType(FormProblem), findsNothing);
    await typeIn(tester, const ValueKey('snippet-trigger'), ';DATE');
    expect(find.text(';DATE is already a snippet.'), findsOneWidget);
    await typeIn(tester, const ValueKey('snippet-trigger'), ';s g');
    expect(find.text('After the semicolon, letters and digits only, at most 24.'), findsOneWidget);
    await typeIn(tester, const ValueKey('snippet-trigger'), ';sig');
    expect(find.text('Write what ;sig becomes.'), findsOneWidget);
    await tester.tap(add);
    await tester.pump();
    expect(triggers(), [';date', ';time']);
    await typeIn(tester, const ValueKey('snippet-words'), 'Matt\n{cursor}{date}');
    // The preview is what typing it would write now, a bar where the caret lands.
    expect(find.text('Matt\n▏27 October 2026'), findsOneWidget);
    expect(find.text('Write what ;sig becomes.'), findsNothing);
    await tap(tester, const ValueKey('snippet-save'));
    expect(triggers(), [';date', ';time', ';sig']);
    expect(preferences.value.snippets.last.text, 'Matt\n{cursor}{date}');
    expect(find.byKey(const ValueKey('snippet-trigger')), findsNothing);
    expect(find.text('Matt · 27 October 2026'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('one edited, moved, and deleted', (tester) async {
    await open(tester, snippets: const [Snippet(id: 'sa', trigger: ';a', text: 'A'), Snippet(id: 'sb', trigger: ';b', text: 'B')]);
    expect(labels(tester), [';a', ';b']);
    // Edit ;b to ;bee, its words too.
    await tap(tester, const ValueKey('snippet-edit-sb'));
    expect([for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) section.title], ['Your snippets', 'Edit ;b']);
    await typeIn(tester, const ValueKey('snippet-trigger'), ';bee');
    await typeIn(tester, const ValueKey('snippet-words'), 'Bee');
    await tap(tester, const ValueKey('snippet-save'));
    expect(preferences.value.snippets, const [Snippet(id: 'sa', trigger: ';a', text: 'A'), Snippet(id: 'sb', trigger: ';bee', text: 'Bee')]);
    // Up: ;bee first. The first cannot go up, nor the last down.
    await tester.tap(find.bySemanticsLabel('Move ;bee up'));
    await settleSettings(tester);
    expect(triggers(), [';bee', ';a']);
    await tester.tap(find.bySemanticsLabel('Move ;bee up'));
    await settleSettings(tester);
    expect(triggers(), [';bee', ';a']);
    // Deleted from its form.
    await tap(tester, const ValueKey('snippet-edit-sa'));
    await tap(tester, const ValueKey('snippet-delete'));
    expect(triggers(), [';bee']);
    expect(find.byKey(const ValueKey('snippet-trigger')), findsNothing);
    // Cancel keeps what was there.
    await tap(tester, const ValueKey('snippet-edit-sb'));
    await typeIn(tester, const ValueKey('snippet-trigger'), ';changed');
    await tap(tester, const ValueKey('snippet-cancel'));
    expect(triggers(), [';bee']);
    await endSettings(tester);
  });

  testWidgets('with none, says so', (tester) async {
    await open(tester, snippets: const []);
    expect(find.text('None yet'), findsOneWidget);
    await endSettings(tester);
  });

  test('the section: Advanced\'s, on a card of its own under Appearance, read by its triggers, found by the search', () {
    final spec = settingsSections.firstWhere((each) => each.id == 'snippets');
    expect(spec.label, 'Snippets');
    expect(spec.group, snippetsGroup);
    final ids = [for (final each in settingsSections) each.id];
    expect(ids.indexOf('snippets'), ids.indexOf('theme') + 1);
    expect(spec.pane, isNotNull);
    expect(spec.settings!(_facts(const Preferences())).map((each) => each.name), ['Your snippets', 'New snippet']);
    expect(spec.where!(_facts(const Preferences())), isTrue);
    expect(spec.where!(_facts(const Preferences(experience: 'simple', experienceChosen: true))), isFalse);
    expect(snippetsSummary(const Preferences()), ';date, ;time');
    expect(snippetsSummary(const Preferences(snippets: [])), 'None yet');
    const four = [Snippet(id: '1', trigger: ';a', text: 'a'), Snippet(id: '2', trigger: ';b', text: 'b'), Snippet(id: '3', trigger: ';c', text: 'c'), Snippet(id: '4', trigger: ';d', text: 'd')];
    expect(snippetsSummary(const Preferences(snippets: four)), ';a, ;b, ;c and 1 more');
    expect(spec.words, contains('expansion'));
  });
}

SettingsFacts _facts(Preferences prefs) => SettingsFacts(prefs: prefs, wide: false, haptics: false, android: true, ios: false, developer: false);
