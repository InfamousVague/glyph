import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart' show Output, Run;
import 'package:ghost_md/ai/kinds.dart' show RunKind;
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/reset.dart' show spared;
import 'package:ghost_md/core/stored.dart' show stored;
import 'package:ghost_md/core/wip.dart';
import 'package:ghost_md/guide/guide_state.dart' show guideSeenKey, guideSeenValue;
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/cheat_sheet.dart';
import 'package:ghost_md/settings/panes/developer_pane.dart';
import 'package:ghost_md/settings/panes/marks.g.dart';
import 'package:ghost_md/settings/panes/spec_pane.dart';
import 'package:ghost_md/settings/panes/specification.g.dart';
import 'package:ghost_md/settings/panes/test_results_pane.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// The pages of Settings that draw more than the settings kit (lib/settings/panes/): the cheat sheet, the
/// specification, Developer and Test results. What each draws and does, and each held to the rects the web page
/// measured (its dev server in Chromium, 390 x 844 and 1280 x 800, light, 2026-10-07).

Rect boxOf(WidgetTester tester, Finder text) => tester.getRect(find.ancestor(of: text, matching: find.byType(Container)).first);

/// A report with a failure, a skip and a suite that did not run.
Map<String, Object?> report({bool failing = true, bool missing = true, String? hash = 'abc123'}) => {
      'schemaVersion': 1,
      'generatedAt': '2026-10-07T10:00:00Z',
      'version': '0.1.0',
      'commit': 'e386321',
      'dirty': true,
      'sourceHash': hash,
      'host': {'os': 'darwin arm64', 'node': 'v25.9.0'},
      'tools': {'flutter': 'flutter 3.35', 'cargo': null},
      'suites': [
        {
          'id': 'app',
          'title': 'App (Flutter)',
          'runnerVersion': 'flutter 3.35',
          'command': 'flutter test',
          'status': failing ? 'failed' : 'passed',
          'durationMs': 65000,
          'counts': {'total': 4, 'passed': failing ? 2 : 3, 'failed': failing ? 1 : 0, 'skipped': 1, 'todo': 0},
          'tests': [
            {'file': 'test/a_test.dart', 'line': 3, 'name': 'adds a workspace', 'status': 'passed', 'ms': 12, 'failure': null},
            {'file': 'test/b_test.dart', 'line': 9, 'name': 'keeps the trash', 'status': failing ? 'failed' : 'passed', 'ms': 1400, 'failure': failing ? 'Expected: 2\n  Actual: 3' : null},
            {'file': 'test/b_test.dart', 'line': 4, 'name': 'empties the trash', 'status': 'passed', 'ms': 3, 'failure': null},
            {'file': 'test/a_test.dart', 'line': null, 'name': 'needs a model', 'status': 'skipped', 'ms': null, 'failure': null},
          ],
        },
        {
          'id': 'kit',
          'title': 'Kit',
          'command': null,
          'status': 'passed',
          'durationMs': 900,
          'counts': {'total': 1, 'passed': 1, 'failed': 0, 'skipped': 0, 'todo': 0},
          'tests': [
            {'file': 'test/tokens_test.dart', 'line': 1, 'name': 'reads the page’s tokens', 'status': 'passed', 'ms': 40, 'failure': null},
          ],
        },
        if (missing)
          {
            'id': 'core',
            'title': 'Core (Rust)',
            'status': 'error',
            'reason': 'cargo: command not found',
            'exitCode': 127,
            'counts': {'total': 0, 'passed': 0, 'failed': 0, 'skipped': 0, 'todo': 0},
            'tests': <Object?>[],
          },
      ],
    };

void main() {
  setUpAll(loadAppFonts);

  group('the cheat sheet', () {
    test('lists every mark for Settings’ search, by its name and its characters', () {
      final found = cheatSheetFindable();
      expect(found.length, markGroups.fold<int>(0, (sum, group) => sum + group.rows.length));
      expect(found.firstWhere((f) => f.name == 'Bold').words, '**');
      expect(markGroups.map((g) => g.title), ['Words', 'Lines', 'Pointing somewhere', 'Raised and lowered', 'Blocks', 'Ghost.md’s own']);
      // Every row's icon is one the app can draw.
      for (final group in markGroups) {
        for (final row in group.rows) {
          expect(Lucide.all[row.icon], isNotNull, reason: '${row.name}: ${row.icon}');
        }
      }
    });

    testWidgets('is a field, the groups as chips, and a card for each mark: its icon, its name, its characters and what to type', (tester) async {
      await openPane(tester, 'cheatsheet');
      expect(display(tester), 'Cheat sheet');
      // Every mark's card, and the basics' own cards over them (GHST-103).
      expect(tester.widgetList(find.byType(MarkCard, skipOffstage: false)).length, cheatSheetFindable().length + basicsGroup().rows.length);
      // The field: a pill over the page, the chips under it, and the strip they make. The basics' chip is first,
      // and the page's chips follow it, each where the page had it, one chip along.
      final field = find.ancestor(of: find.text('Find a mark'), matching: find.byType(DecoratedBox)).first;
      expect(tester.getRect(field), rectNear(22.31, 122.73, 345.38, 39.84));
      expect(tester.getRect(find.byKey(const ValueKey('chip The basics'))), rectNear(22.31, 184.89, 93.8, 27.38));
      expect(tester.getRect(find.byKey(const ValueKey('chip Words'))), rectNear(125.04, 184.89, 65.39, 27.38));
      expect(tester.getRect(find.byKey(const ValueKey('chip Lines'))), rectNear(199.36, 184.89, 58.36, 27.38));
      expect(tester.getRect(find.byKey(const ValueKey('chip Pointing somewhere'))), rectNear(266.65, 184.89, 153.63, 27.38));
      // The first group, The basics, where the page's first group stood, and its first card, which carries its
      // plain line where the page's card went straight to TYPE: the card is that line and its gap taller.
      expect(tester.getRect(find.text('THE BASICS')).topLeft, offsetMoreOrLessEquals(const Offset(22.31, 221.19), epsilon: 0.5));
      expect(tester.getRect(find.text(basicsLead)).top, closeTo(241.64, 0.5));
      final title = find.byKey(const ValueKey('basic Title'));
      expect(tester.getRect(title).topLeft, offsetMoreOrLessEquals(const Offset(22.31, 275.11), epsilon: 0.5));
      expect(tester.getRect(title).width, closeTo(345.38, 0.5));
      expect(tester.getRect(find.descendant(of: title, matching: find.text('The note’s name, on its first line.'))).topLeft, offsetMoreOrLessEquals(const Offset(36.7, 326.41), epsilon: 0.5));
      expect(tester.getRect(find.descendant(of: title, matching: find.text('TYPE'))).topLeft, offsetMoreOrLessEquals(const Offset(36.7, 355.41), epsilon: 0.5));
      expect(tester.getRect(title).height, closeTo(159.9, 0.75));
      // A mark's own card, Bold in Words, further down now: the page's card, measured from its own corner.
      final bold = find.byKey(const ValueKey('Bold'), skipOffstage: false);
      final at = tester.getRect(bold).topLeft;
      expect(tester.getRect(bold).width, closeTo(345.38, 0.5));
      expect(tester.getRect(find.descendant(of: bold, matching: find.byType(AppIcon), skipOffstage: false)), rectNear(at.dx + 20.39, at.dy + 20.39, 16, 16));
      expect(tester.getRect(find.descendant(of: bold, matching: find.text('Bold', skipOffstage: false), skipOffstage: false)).topLeft, offsetMoreOrLessEquals(at + const Offset(51.32, 18.39), epsilon: 0.5));
      expect(boxOf(tester, find.descendant(of: bold, matching: find.text('**', skipOffstage: false), skipOffstage: false)), rectNear(at.dx + 300.88, at.dy + 16.39, 30.11, 24));
      expect(tester.getRect(find.descendant(of: bold, matching: find.text('TYPE', skipOffstage: false), skipOffstage: false)).topLeft, offsetMoreOrLessEquals(at + const Offset(14.39, 51.3), epsilon: 0.5));
      // What to type: the page's block, with its margin under it (the rect here counts it, the page's does not).
      final typed = tester.getRect(find.descendant(of: bold, matching: find.byKey(const ValueKey('mark-typed'), skipOffstage: false), skipOffstage: false));
      expect(Rect.fromLTWH(typed.left, typed.top, typed.width, typed.height - tokensAt(tester, bold).space(2)), rectNear(at.dx + 14.39, at.dy + 69.75, 316.59, 37.92));
      // "Reads", the line as the note draws it, waits for the editor: a card ends at what to type.
      expect(find.text('READS', skipOffstage: false), findsNothing);
      expect(tester.getRect(bold).height, closeTo(131.0, 0.75));
      // Advanced: the whole sheet open, nothing behind a disclosure.
      expect(find.byKey(const ValueKey('everything-else'), skipOffstage: false), findsNothing);
      await endSettings(tester);
    });

    testWidgets('in simple mode keeps everything past the basics behind one disclosure, opened by it or its chip, and a search looks past it (GHST-103)', (tester) async {
      await openPane(tester, 'cheatsheet', prefs: const Preferences(theme: 'light', experience: 'simple', experienceChosen: true));
      List<String> cards() => [for (final card in tester.widgetList<MarkCard>(find.byType(MarkCard, skipOffstage: false))) card.row.name];
      expect(find.text('THE BASICS'), findsOneWidget);
      expect(cards().length, basicsGroup().rows.length);
      expect(find.text('WORDS', skipOffstage: false), findsNothing);
      // The chips: the basics, and one for all the rest.
      expect(find.byKey(const ValueKey('chip The basics')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip Everything else')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip Words')), findsNothing);
      final rest = find.byKey(const ValueKey('everything-else'), skipOffstage: false);
      expect(rest, findsOneWidget);
      expect(find.descendant(of: rest, matching: find.text('${cheatSheetFindable().length} more marks, in ${markGroups.length} groups.', skipOffstage: false), skipOffstage: false), findsOneWidget);
      // A search finds a mark behind it.
      await tester.enterText(find.byType(EditableText), 'spoiler');
      await tester.pump();
      expect(cards(), ['Spoiler']);
      expect(rest, findsNothing);
      await tester.tap(find.bySemanticsLabel('Clear'));
      await tester.pump();
      expect(rest, findsOneWidget);
      // Opened, the rest is the sheet as advanced has it, from its first group.
      await tester.ensureVisible(rest);
      await tester.pump();
      await tester.tap(rest);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(rest, findsNothing);
      expect(find.text('WORDS', skipOffstage: false), findsOneWidget);
      expect(cards().length, cheatSheetFindable().length + basicsGroup().rows.length);
      expect(find.byKey(const ValueKey('chip Words')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip Everything else')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('finds a mark by its name, its characters or its example, and says when there is none', (tester) async {
      await openPane(tester, 'cheatsheet');
      List<String> cards() => [for (final card in tester.widgetList<MarkCard>(find.byType(MarkCard, skipOffstage: false))) card.row.name];
      await tester.enterText(find.byType(EditableText), 'spoiler');
      await tester.pump();
      expect(cards(), ['Spoiler']);
      // Looking, the chips are away.
      expect(find.byKey(const ValueKey('chip Words')), findsNothing);
      await tester.enterText(find.byType(EditableText), '||');
      await tester.pump();
      expect(cards(), ['Spoiler']);
      await tester.enterText(find.byType(EditableText), 'FRIDAY at');
      await tester.pump();
      expect(cards(), ['Bold']);
      await tester.enterText(find.byType(EditableText), 'zzz');
      await tester.pump();
      expect(cards(), isEmpty);
      expect(find.text('No mark by that name. Try “bold”, “||” or “board”.'), findsOneWidget);
      // The cross empties it.
      await tester.tap(find.bySemanticsLabel('Clear'));
      await tester.pump();
      expect(cards().length, cheatSheetFindable().length + basicsGroup().rows.length);
      expect(find.byKey(const ValueKey('chip Words')), findsOneWidget);
      expect(marksFound('  ').length, markGroups.length);
      await endSettings(tester);
    });

    testWidgets('keeps the field and the chips at the top as the page scrolls, and a chip goes to its group', (tester) async {
      await openPane(tester, 'cheatsheet');
      final field = find.ancestor(of: find.text('Find a mark'), matching: find.byType(DecoratedBox)).first;
      final top = tester.getRect(find.byKey(const ValueKey('settings-display'))).top;
      await tester.tap(find.byKey(const ValueKey('chip Lines')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The group's heading is at the top of what scrolls, a `--glacier-space-2` short of it; the strip is over it.
      expect(tester.getRect(find.text('LINES', skipOffstage: false)).top, closeTo(top + 8.93, 1));
      expect(tester.getRect(field).top, closeTo(top, 0.5));
      expect(tester.getRect(find.byKey(const ValueKey('chip Words'))).top, closeTo(top + 62.16, 0.75));
      // And it can still be typed in from there.
      await tester.tap(field);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await endSettings(tester);
    });

    testWidgets('lays its cards three across on a wide window, a board on a row of its own', (tester) async {
      await openPane(tester, 'cheatsheet', size: wideWindow);
      Rect card(String name) => tester.getRect(find.byKey(ValueKey(name), skipOffstage: false));
      expect(card('Bold').left, closeTo(346.33, 0.75));
      expect(card('Bold').width, closeTo(291.91, 0.75));
      expect(card('Italic').left, closeTo(654.03, 0.75));
      expect(card('Both').left, closeTo(961.75, 0.75));
      expect(card('Struck through').left, closeTo(346.33, 0.75));
      // The cards of a row are one height.
      expect(card('Italic').height, card('Bold').height);
      // The basics' row first, three across the same way, and Words' rows under it (GHST-103).
      expect(card('basic Title').top, closeTo(314.5, 0.75));
      expect(card('basic Title').left, closeTo(346.33, 0.75));
      expect(card('basic Heading').left, closeTo(654.03, 0.75));
      expect(card('basic Bold').left, closeTo(961.75, 0.75));
      expect(card('basic Heading').height, card('basic Title').height);
      expect(card('Bold').top, greaterThan(card('basic A dividing line').bottom));
      expect(card('A board').left, closeTo(346.33, 0.75));
      expect(card('A board').width, closeTo(907.33, 0.75));
      await endSettings(tester);
    });
  });

  group('the specification', () {
    test('defines every mark the cheat sheet teaches, and lists every definition for the search under its part', () {
      final covered = {for (final section in specification) for (final entry in section.entries) ...entry.covers};
      expect([for (final group in markGroups) for (final row in group.rows) if (!covered.contains(row.name)) row.name], isEmpty);
      final found = specFindable();
      expect(found.take(2).map((f) => (f.name, f.words)), [('CommonMark', 'markdown standard'), ('GitHub Flavored Markdown', 'markdown standard')]);
      expect(found.firstWhere((f) => f.name == 'Front matter').words, 'Standard Markdown');
      expect(found.length, 2 + specification.fold<int>(0, (sum, section) => sum + section.entries.length));
      expect(specification.map((s) => s.id), ['base', 'shared', 'own', 'lines', 'fills', 'keys', 'templates']);
    });

    testWidgets('links the base, then defines each part: a name, the characters, the rule, how other apps show it', (tester) async {
      final opened = <String>[];
      await openPane(tester, 'spec', onOpenLink: opened.add);
      expect(rowLabels(tester), ['CommonMark', 'GitHub Flavored Markdown']);
      expect(tester.widgetList(find.byType(SpecEntryCard, skipOffstage: false)).length, specification.fold<int>(0, (sum, section) => sum + section.entries.length));

      // Rect for rect: a part's heading over the page's gap and its own margin, its line, then its first card.
      expect(tester.getRect(surfaceOf(cardCalled('The base'))), rectNear(22.31, 194.73, 345.38, 179.66));
      expect(tester.getRect(find.text('STANDARD MARKDOWN')).topLeft, offsetMoreOrLessEquals(const Offset(22.31, 419), epsilon: 0.5));
      expect(tester.getRect(find.textContaining('Every note is CommonMark with GitHub’s extensions')), rectNear(22.31, 437.45, 345.38, 112, 0.75));
      final first = find.byType(SpecEntryCard).first;
      expect(tester.getRect(first), rectNear(22.31, 562.84, 345.38, 165.47, 0.75));
      expect(tester.getRect(find.descendant(of: first, matching: find.text('Emphasis and code'))).topLeft, offsetMoreOrLessEquals(const Offset(36.7, 577.23), epsilon: 0.5));
      expect(boxOf(tester, find.descendant(of: first, matching: find.textContaining('**bold**'))), rectNear(36.7, 606.16, 316.59, 53.84, 0.75));
      expect(tester.getRect(find.descendant(of: first, matching: find.text('As CommonMark and GFM define them.'))).topLeft, offsetMoreOrLessEquals(const Offset(36.7, 668.92), epsilon: 0.75));
      expect(tester.getRect(find.descendant(of: first, matching: find.textContaining('The same everywhere.'))).topLeft, offsetMoreOrLessEquals(const Offset(36.7, 697.92), epsilon: 0.75));
      // A card on the page's ground with 4% of the ink in it, inside a line of 10%.
      final box = tester.widget<Container>(find.descendant(of: first, matching: find.byType(Container)).first).decoration! as BoxDecoration;
      expect(box.color, sameColor(cssColor(tester, 'oklch(0.9616 0 0)')));
      expect((box.border! as Border).top.color, sameColor(cssColor(tester, 'oklch(0.16 0 0 / 0.1)')));
      // A base specification's row opens it.
      await tapOn(tester, rowCalled('GitHub Flavored Markdown'));
      expect(opened, ['https://github.github.com/gfm/']);
      await endSettings(tester);
    });

    testWidgets('folds a definition’s pattern away until it is asked for', (tester) async {
      await openPane(tester, 'spec');
      final tags = find.byWidgetPredicate((w) => w is SpecEntryCard && w.entry.name == 'Tags', skipOffstage: false);
      final pattern = tester.widget<SpecEntryCard>(tags).entry.pattern!;
      expect(find.text(pattern, skipOffstage: false), findsNothing);
      final was = tester.getSize(tags).height;
      await tapOn(tester, find.descendant(of: tags, matching: find.text('THE PATTERN', skipOffstage: false), skipOffstage: false));
      expect(find.text(pattern), findsOneWidget);
      expect(tester.getSize(tags).height, greaterThan(was + 20));
      await tapOn(tester, find.descendant(of: tags, matching: find.text('THE PATTERN')));
      expect(find.text(pattern, skipOffstage: false), findsNothing);
      // A definition with no one pattern has nothing to unfold.
      expect(find.descendant(of: find.byType(SpecEntryCard).first, matching: find.text('THE PATTERN')), findsNothing);
      await endSettings(tester);
    });
  });

  group('Developer', () {
    testWidgets('says what the window is, marks the bench that waits, and hides itself by its switch', (tester) async {
      await openPane(tester, 'developer', developer: true, size: const Size(390, 1800));
      // No Smoke card: the smoke went, and its bench with it (2026-10-24).
      expect(cardTitles(tester), ['Window', 'The phone at work', 'Developer mode', 'Reset', 'Onboarding', 'Work in progress']);
      expect(rowLabels(tester, 'Window'), ['Top inset', 'Page', 'Screen', 'Engine']);
      final facts = windowFacts(tester.element(find.byType(DeveloperPane)));
      expect((facts.inset, facts.page, facts.engine), ('0px', '390 × 1800 @2', 'Flutter on android'));
      expect(find.text('390 × 1800 @2'), findsOneWidget);
      // The bench is not given here: its row is there and cannot be pressed.
      expect(rowCalled('Smoke bench'), findsNothing);
      expect(tester.widget<SettingRow>(rowCalled('Play the scene')).disabled, isTrue);
      // The two resets with nothing to run, and the onboarding's Run with no walkthrough to open here.
      expect([for (final word in tester.widgetList<RowAction>(find.byType(RowAction))) word.disabled], [true, true, true]);

      await tapOn(tester, find.descendant(of: rowCalled('Developer settings'), matching: find.byType(GlacierSwitch)));
      expect(developerMode.value, isFalse);
      // The section is gone from the list, and so is its page.
      expect(find.byType(DeveloperPane), findsNothing);
      await endSettings(tester);
    });

    // Matt, 2026-10-28: "Add a developer setting to re run the onboarding".
    testWidgets('Run the onboarding again marks the walkthrough unseen and opens it on its first page', (tester) async {
      var opened = 0;
      stored.writeText(guideSeenKey, guideSeenValue);
      await openPane(tester, 'developer', developer: true, size: const Size(390, 1800), onGuide: () => opened += 1);
      expect(rowLabels(tester, 'Onboarding'), ['Run the onboarding again']);
      await tapOn(tester, find.byKey(const ValueKey('developer-run-onboarding-go')));
      expect(opened, 1);
      expect(stored.readText(guideSeenKey), isNull, reason: 'unseen, so it behaves as on a first launch until finished');
      await endSettings(tester);
    });

    // The phone assistant, the side key and Record note are off until a developer switches them on for this phone
    // (lib/core/wip.dart; Ghost.md's branch voice/assistant-flag, DESIGN §146): the page's last card.
    testWidgets('the voice assistant is off, and its switch tells the phone and keeps this device\'s flag', (tester) async {
      final asked = <Object?>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('ghost_md/meeting'), (call) async {
        asked.add([call.method, (call.arguments as Map?)?['on']]);
        return (call.arguments as Map?)?['on'] == true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel('ghost_md/meeting'), null));
      addTearDown(() => wipAssistant.set(false));
      await openPane(tester, 'developer', developer: true, size: const Size(390, 1800));
      expect(rowLabels(tester, 'Work in progress'), ['Voice assistant']);
      expect(wipAssistant.value, isFalse);
      final control = find.descendant(of: rowCalled('Voice assistant'), matching: find.byType(GlacierSwitch));
      expect(tester.widget<GlacierSwitch>(control).checked, isFalse);
      await tapOn(tester, control);
      expect(asked, [
        ['setAssistantSwitch', true],
      ]);
      expect(wipAssistant.value, isTrue);
      expect(tester.widget<GlacierSwitch>(control).checked, isTrue);
      await tapOn(tester, control);
      expect(asked.last, ['setAssistantSwitch', false]);
      expect(wipAssistant.value, isFalse);
      // A reset leaves it as the developer set it, as it leaves the page.
      expect(spared, contains(wipAssistantKey));
      // The phone's half answers by these names, and the build's own switch is off unless asked for.
      final kotlin = File('android/app/src/main/kotlin/com/mattssoftware/ghost_md/MeetingBridge.kt').readAsStringSync();
      expect(kotlin, contains('"setAssistantSwitch" ->'));
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('val ghostAssistant = System.getenv("GHOST_ASSISTANT") == "1"'));
      await endSettings(tester);
    });

    testWidgets('plays the scene with the readings chosen, and resets on the second tap; no smoke bench is left', (tester) async {
      final ran = <String>[];
      Object? fail;
      await openPane(
        tester,
        'developer',
        developer: true,
        size: const Size(390, 1800),
        features: SettingsFeatures(
          onPlayScene: (readings) => ran.add('scene $readings'),
          onReset: ({required bool models}) async {
            final failure = fail;
            if (failure != null) throw failure;
            ran.add('reset models=$models');
          },
        ),
      );
      expect(find.text('Smoke bench'), findsNothing, reason: 'the smoke went, and its bench with it');
      await tapOn(tester, rowCalled('Play the scene'));
      await tapOn(tester, find.text('No heat'));
      await tapOn(tester, rowCalled('Play the scene'));
      expect(ran, ['scene heat', 'scene cold']);

      final local = find.descendant(of: rowCalled('Reset local data'), matching: find.byType(RowAction));
      await tapOn(tester, local);
      expect(find.descendant(of: local, matching: find.text('Tap again')), findsOneWidget);
      expect(ran, hasLength(2));
      await tapOn(tester, local);
      expect(ran.last, 'reset models=false');
      await tapOn(tester, find.descendant(of: rowCalled('Reset everything'), matching: find.byType(RowAction)));
      await tapOn(tester, find.descendant(of: rowCalled('Reset everything'), matching: find.byType(RowAction)));
      expect(ran.last, 'reset models=true');
      // A reset that fails says why where its hint was.
      fail = 'The library is in use.';
      await tapOn(tester, local);
      await tapOn(tester, local);
      expect(find.descendant(of: rowCalled('Reset local data'), matching: find.text('The library is in use.')), findsOneWidget);
      expect(find.descendant(of: local, matching: find.text('Reset')), findsOneWidget);
      await endSettings(tester);
    });

    // Differs 32 (docs/PARITY.md): `disabled={busy}` with `disabledReason` (DeveloperPane.tsx `useAnyRunning`). The
    // row was pressable whatever the model was doing, and `useAnyRunning` had no caller.
    testWidgets('holds the scene off, and says why, while the model is on a note', (tester) async {
      final ran = <String>[];
      final answer = Completer<Output>();
      simulateRuns((options) => Run(done: answer.future, cancel: () {}));
      addTearDown(() {
        forgetAllRuns();
        simulateRuns(null);
      });
      await openPane(tester, 'developer', developer: true, size: const Size(390, 1800), features: SettingsFeatures(onPlayScene: (readings) => ran.add('scene $readings')));
      const reason = 'The model is on a note. Try again when it is done.';
      expect(tester.widget<SettingRow>(rowCalled('Play the scene')).disabled, isFalse);
      expect(find.text(reason), findsNothing);

      final run = startRun(const RunRequest(noteId: 'n', kind: RunKind.format, model: 'qwen3.5-4b', system: 'Format.', prompt: 'hello', maxTokens: 200));
      await tester.pump();
      await tester.pump();
      expect(anyRunning(), isTrue);
      expect(tester.widget<SettingRow>(rowCalled('Play the scene')).disabled, isTrue);
      expect(find.descendant(of: rowCalled('Play the scene'), matching: find.text(reason)), findsOneWidget);
      await tapOn(tester, rowCalled('Play the scene'));
      expect(ran, isEmpty);

      // The run ends: the row is the scene's again.
      answer.complete(const Output(text: 'x\n'));
      await tester.runAsync(() => run.done);
      await tester.pump();
      await tester.pump();
      expect(anyRunning(), isFalse);
      expect(tester.widget<SettingRow>(rowCalled('Play the scene')).disabled, isFalse);
      expect(find.text(reason), findsNothing);
      await tapOn(tester, rowCalled('Play the scene'));
      expect(ran, ['scene heat']);
      await endSettings(tester);
    });

    testWidgets('is the page’s, rect for rect', (tester) async {
      await openPane(tester, 'developer', developer: true);
      expect(tester.getRect(find.text('WINDOW')).topLeft, offsetMoreOrLessEquals(const Offset(31.24, 122.73), epsilon: 0.5));
      expect(tester.getRect(surfaceOf(cardCalled('Window'))), rectNear(22.31, 194.73, 345.38, 255.14, 0.75));
      expect(tester.getRect(find.text('Top inset')).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 208.13), epsilon: 0.5));
      // A row's value, small and quiet at its end.
      final value = tester.getRect(find.text('0px'));
      expect(value.right, closeTo(354.3, 0.5));
      expect(value.top, closeTo(231.39, 0.75));
      expect(value.height, closeTo(16, 0.5));
      expect(tester.getRect(find.text('Page')).top, closeTo(298.45, 0.75));
      // The page's Smoke card stood at 467.72 and was 199.25 to the next; with the smoke gone it is not drawn, and
      // every card after it stands that much higher.
      expect(find.text('SMOKE', skipOffstage: false), findsNothing);
      for (final (title, top) in [('THE PHONE AT WORK', 666.97 - 199.25), ('DEVELOPER MODE', 1028.02 - 199.25), ('RESET', 1178.19 - 199.25)]) {
        expect(tester.getRect(find.text(title, skipOffstage: false)).top, closeTo(top, 2), reason: title);
      }
      await endSettings(tester);
    });
  });

  group('Test results', () {
    test('adds the report up from its suites, and says it in a line', () {
      final failing = TestReport.fromJson(report());
      expect((verdict(failing), tally(failing).failed, tally(failing).notRun, tally(failing).passed), ('failed', 1, 1, 3));
      expect(verdict(TestReport.fromJson(report(failing: false))), 'incomplete');
      expect(verdict(TestReport.fromJson(report(failing: false, missing: false))), 'passed');
      expect(verdict(const TestReport()), 'empty');
      expect(reportSummary(null), 'No report yet');
      expect(reportSummary(failing, buildSource: 'abc123'), '1 failed');
      expect(reportSummary(failing, buildSource: 'other'), 'From other code');
      expect(reportSummary(TestReport.fromJson(report(failing: false))), '1 suite missing');
      expect(reportSummary(TestReport.fromJson(report(failing: false, missing: false))), '4 passed');
      expect((buildMatch(failing, 'abc123'), buildMatch(failing, 'x'), buildMatch(failing, null)), ('same', 'different', 'unknown'));
      // Failures first in a file, and the files with failures first.
      final files = byFile(failing.suites.first.tests);
      expect([for (final group in files) (group.file, group.failed, group.tests.first.name)], [('test/b_test.dart', 1, 'keeps the trash'), ('test/a_test.dart', 0, 'adds a workspace')]);
      expect(testMatches(failing.suites.first.tests[1], 'TRASH b_test'), isTrue);
      expect(testMatches(failing.suites.first.tests[1], 'trash a_test'), isFalse);
      final now = DateTime.utc(2026, 10, 7, 18);
      expect([ago('2026-10-07T17:59:45Z', now), ago('2026-10-07T17:20:00Z', now), ago('2026-10-07T10:00:00Z', now), ago('2026-10-01T10:00:00Z', now)], ['just now', '40 min ago', '8 hr ago', '6 days ago']);
      expect([testSeconds(null), testSeconds(640), testSeconds(1400), testSeconds(32000)], ['', '640 ms', '1.4 s', '32 s']);
    });

    testWidgets('with no report in the build, says so and how one is made', (tester) async {
      await openPane(tester, 'test-results', developer: true);
      expect(find.text('No test report in this build.'), findsOneWidget);
      expect(find.textContaining('node scripts/test-report.mjs'), findsOneWidget);
      await back(tester);
      expect(find.text('No report yet'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('draws the verdict, what makes it less than it seems, where it came from, and a card a suite', (tester) async {
      await openPane(tester, 'test-results', developer: true, size: const Size(390, 2600), features: SettingsFeatures(testReport: report()));
      expect(find.text('1 test failed'), findsOneWidget);
      final box = tester.widget<Container>(find.byKey(const ValueKey('test-verdict'))).decoration! as BoxDecoration;
      expect((box.border! as Border).top.color, sameColor(cssColor(tester, 'oklch(0.62 0.21 25)')));
      // A development build has no fingerprint, and one suite did not run.
      expect(find.text('This build has no source fingerprint to check the report against (a development build).'), findsOneWidget);
      expect(find.text('Core (Rust) did not run for this report.'), findsOneWidget);
      expect(cardTitles(tester), ['Where these come from', 'Find', 'App (Flutter)', 'Kit', 'Core (Rust)']);
      expect(rowLabels(tester, 'Where these come from'), ['Version', 'Code', 'Commit', 'Ran', 'On', 'Tools']);
      expect(find.text('e386321 + changes'), findsOneWidget);
      expect(rowLabels(tester, 'App (Flutter)'), ['2/4 passed · 1 skipped']);
      expect(find.descendant(of: cardCalled('App (Flutter)'), matching: find.text('Failed')), findsOneWidget);
      expect(find.descendant(of: cardCalled('Core (Rust)'), matching: find.text('Did not run')), findsOneWidget);
      expect(find.text('cargo: command not found'), findsOneWidget);
      expect(find.text('exit code 127'), findsOneWidget);
      // A suite that failed is open, its failing file first and open with the failure under the test; a file with
      // none is folded, and a suite that passed is shut.
      expect(find.text('Expected: 2\n  Actual: 3'), findsOneWidget);
      expect(find.text('keeps the trash'), findsOneWidget);
      expect(find.text('adds a workspace'), findsNothing);
      expect(find.text('test/tokens_test.dart'), findsNothing);
      await tapOn(tester, find.text('test/a_test.dart'));
      expect(find.text('adds a workspace'), findsOneWidget);
      expect(find.bySemanticsLabel('Skipped'), findsOneWidget);
      await tapOn(tester, rowCalled('1/1 passed'));
      expect(find.text('test/tokens_test.dart'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('finds tests by words, and shows only the failures when asked', (tester) async {
      await openPane(tester, 'test-results', developer: true, size: const Size(390, 2600), features: SettingsFeatures(testReport: report(), testBuildSource: 'abc123'));
      expect(find.text('The same code this build was made from.'), findsOneWidget);
      await tapOn(tester, find.descendant(of: rowCalled('Only failures'), matching: find.byType(GlacierSwitch)));
      // A suite that passed has nothing left and is not drawn.
      expect(cardTitles(tester), ['Where these come from', 'Find', 'App (Flutter)', 'Core (Rust)']);
      expect(find.text('empties the trash'), findsNothing);
      expect(find.text('keeps the trash'), findsOneWidget);
      await tapOn(tester, find.descendant(of: rowCalled('Only failures'), matching: find.byType(GlacierSwitch)));
      await tester.enterText(find.byType(EditableText), 'tokens');
      await tester.pump();
      expect(find.text('reads the page’s tokens'), findsOneWidget);
      expect(find.text('keeps the trash'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('is the page’s over the web app’s own report, rect for rect', (tester) async {
      final json = webTestReport();
      await openPane(tester, 'test-results', developer: true, features: SettingsFeatures(testReport: json, testBuildSource: json['sourceHash'] as String?));
      // The card's edge is `--app-line`, 1.5px. The page was measured in a desktop browser told to draw at 2, which
      // snaps a border to whole CSS pixels and drew it 1px; a phone snaps it to device pixels, three of them at 2,
      // as it is drawn here. So everything inside the card is half a pixel in from the page's, and what follows it a
      // pixel down.
      expect(tester.getRect(find.byKey(const ValueKey('test-verdict'))), rectNear(22.31, 122.73, 345.38, 120.08 + 1, 0.75));
      final word = find.descendant(of: find.byKey(const ValueKey('test-verdict')), matching: find.byType(AppIcon));
      expect(tester.getRect(word), rectNear(41.16 + 0.5, 142.58 + 0.5, 22, 22, 0.75));
      for (final (name, x) in [('PASSED', 41.16), ('FAILED', 120.3), ('SKIPPED', 199.45), ('NOT RUN', 278.61)]) {
        // Four columns of what is left inside the edge, so each a quarter of a pixel narrower than the page's.
        expect(tester.getRect(find.text(name)).topLeft, offsetMoreOrLessEquals(Offset(x + 0.5, 178.97 + 0.5), epsilon: 1), reason: name);
      }
      expect(tester.getRect(find.text('WHERE THESE COME FROM')).topLeft, offsetMoreOrLessEquals(const Offset(31.24, 260.66 + 1), epsilon: 0.75));
      expect(tester.getRect(find.text('Version')).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 296.97 + 1), epsilon: 0.75));
      expect(tester.getRect(find.text('FIND', skipOffstage: false)).top, closeTo(762.89 + 1, 1.5));
      await endSettings(tester);
    });
  });
}

Future<void> back(WidgetTester tester) async {
  testBack.goBack();
  await tester.pump();
  await settleSettings(tester);
}
