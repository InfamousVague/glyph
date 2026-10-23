import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/pages/mode.dart' show experienceChoices;
import 'package:ghost_md/settings/accent_swatch.dart';
import 'package:ghost_md/settings/appearance_pane.dart';
import 'package:ghost_md/settings/choice_card.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/experience_pane.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// Settings › Simple or advanced (GHST-103; Matt, 2026-10-17: "allow selecting between simple and advanced mode
/// where simple mode has a much more approachable UI with fancy features hidden behind more"): the page that
/// chooses, and what Simple does to Settings itself, its list, its search, Appearance and About. Advanced's list
/// is settings_sheet_test.dart's.

const Preferences _simple = Preferences(theme: 'light', experience: 'simple', experienceChosen: true);
const Preferences _advanced = Preferences(theme: 'light', experience: 'advanced', experienceChosen: true);

/// An Android phone's facts over [prefs]: nothing of what the table gates on besides the mode.
SettingsFacts _facts(Preferences prefs, {bool developer = false}) => SettingsFacts(prefs: prefs, wide: false, haptics: true, android: true, ios: false, developer: developer);

/// The ids of the sections the sheet would make of the table for [facts], listed or not.
List<String> _among(SettingsFacts facts) => [
      for (final spec in settingsSections)
        if (spec.where?.call(facts) ?? true) spec.id,
    ];

Future<void> _open(WidgetTester tester, {Preferences prefs = _simple, Size size = const Size(390, 1200), SettingsTarget? toPage}) =>
    pumpSettings(tester, SettingsSheet(open: true, onClose: () {}, toPage: toPage), size: size, prefs: prefs);

List<String?> _labels(WidgetTester tester) => [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-label'), skipOffstage: false))) text.data];
String? _display(WidgetTester tester) {
  final found = find.byKey(const ValueKey('settings-display'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

/// The line under a row of the list, by the row's label.
String? _line(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label, skipOffstage: false), matching: find.byType(GlacierPressable, skipOffstage: false)).first;
  final summary = find.descendant(of: row, matching: find.byKey(const ValueKey('settings-row-summary'), skipOffstage: false), skipOffstage: false);
  return summary.evaluate().isEmpty ? null : tester.widget<Text>(summary).data;
}

Finder _rowFor(String label) => find.ancestor(of: find.text(label), matching: find.byType(GlacierPressable)).first;
Finder _card(String name) => find.descendant(of: find.byType(ChoiceCards<String>), matching: find.text(name));
List<String?> _titles(WidgetTester tester) => [for (final card in tester.widgetList<PaneSection>(find.byType(PaneSection))) card.title];

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await settleSettings(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('the table', () {
    test('in Simple is the choice, Account, Notifications, Appearance and About with its cheat sheet, and in Advanced everything', () {
      expect(_among(_facts(_simple)), ['experience', 'account', 'notifications', 'theme', 'about', 'cheatsheet']);
      // The hidden pages answer to their own switch, in either mode.
      expect(_among(_facts(_simple, developer: true)), ['experience', 'account', 'notifications', 'theme', 'about', 'cheatsheet', 'developer', 'test-results']);
      // Meetings is kept in Simple too, but listed only for an account whose service has Ghost in meetings, and
      // these facts have no account (test/meet/meet_card_test.dart lists it).
      expect(_among(_facts(_simple, developer: true)).toSet(), simpleSections.difference({'meetings'}));
      const everything = ['experience', 'account', 'organizations', 'workspaces', 'daily', 'notifications', 'library', 'backup', 'export', 'import', 'theme', 'recording', 'ai', 'plugins', 'about', 'cheatsheet', 'spec', 'examples'];
      expect(_among(_facts(_advanced)), everything);
      // Until the choice is made the app is advanced, and so is Settings.
      expect(_among(_facts(const Preferences(theme: 'light'))), everything);
      expect(const Preferences(theme: 'light').simple, isFalse);
    });

    test('says the mode on the row, and finds the page by it', () {
      expect(experienceSummary(_simple), 'Simple');
      expect(experienceSummary(_advanced), 'Advanced');
      expect(experienceSummary(const Preferences()), 'Advanced');
      expect(experienceFindable.map((f) => f.name), ['Mode']);
      // The page's words are the walkthrough's, so the two say the same thing.
      expect(experienceChoices.map((c) => c.label), ['Simple', 'Advanced']);
    });
  });

  group('the sheet', () {
    testWidgets('lists the short list in Simple, with the mode on its first row, and the rest comes back with Advanced', (tester) async {
      await _open(tester);
      expect(_labels(tester), ['Simple or advanced', 'Account', 'Notifications', 'Appearance', 'About']);
      expect(_line(tester, 'Simple or advanced'), 'Simple');
      // Another device, or the walkthrough, choosing Advanced: the list is read from the preferences, live.
      preferences.update((now) => now.choosing('advanced'));
      await tester.pump();
      expect(_labels(tester), ['Simple or advanced', 'Account', 'Organizations', 'Workspaces', 'Notifications', 'Library folder', 'Backup', 'Export', 'Appearance', 'Recording', 'AI', 'Plugins', 'About']);
      expect(_line(tester, 'Simple or advanced'), 'Advanced');
      await endSettings(tester);
    });

    testWidgets('the page is two cards with the walkthrough’s words, lit as the app is, and a tap writes the choice the one way', (tester) async {
      // Before any choice: advanced, and Advanced is what is lit.
      await _open(tester, prefs: const Preferences(theme: 'light'), toPage: const SettingsTarget('experience', nonce: 1));
      expect(_display(tester), 'Simple or advanced');
      expect(find.byType(ExperiencePane), findsOneWidget);
      final cards = tester.widget<ChoiceCards<String>>(find.byWidgetPredicate((w) => w is ChoiceCards<String> && w.label == 'Mode'));
      expect(cards.values, ['simple', 'advanced']);
      expect(cards.values.map(cards.nameOf), ['Simple', 'Advanced']);
      expect(cards.value, 'advanced');
      for (final choice in experienceChoices) {
        expect(_card(choice.hint), findsOneWidget, reason: choice.value);
      }
      expect(find.text('Boards, databases, canvases, AI, teams and most settings wait behind Advanced. Nothing is lost: switch back any time.'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Advanced')), isSemantics(label: 'Advanced', hasCheckedState: true, isChecked: true, isInMutuallyExclusiveGroup: true, hasTapAction: true, isFocusable: true, hasFocusAction: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Simple')), isSemantics(label: 'Simple', hasCheckedState: true, isChecked: false, isInMutuallyExclusiveGroup: true, hasTapAction: true, isFocusable: true, hasFocusAction: true));

      // Simple: chosen, and the notes opened formatted with it, as Preferences.choosing has it everywhere.
      await _tap(tester, _card('Simple'));
      expect((preferences.value.experience, preferences.value.experienceChosen, preferences.value.noteView), ('simple', true, 'formatted'));
      expect(tester.widget<ChoiceCards<String>>(find.byWidgetPredicate((w) => w is ChoiceCards<String> && w.label == 'Mode')).value, 'simple');
      // Back on the list, Settings is already the short list, and the row says so.
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(_display(tester), isNull);
      expect(_labels(tester), ['Simple or advanced', 'Account', 'Notifications', 'Appearance', 'About']);
      expect(_line(tester, 'Simple or advanced'), 'Simple');

      // And back again.
      await _tap(tester, _rowFor('Simple or advanced'));
      await _tap(tester, _card('Advanced'));
      expect((preferences.value.experience, preferences.value.experienceChosen), ('advanced', true));
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(_labels(tester), hasLength(13));
      await endSettings(tester);
    });

    testWidgets('finds nothing of what Simple put away, on the list or inside a page', (tester) async {
      await _open(tester);
      final field = find.byType(EditableText);
      // Not "backup": Account's own Export everything answers to it, in either mode.
      for (final word in ['accent', 'usb', 'smoke', 'plugins', 'workspace', 'examples', 'model']) {
        await tester.enterText(field, word);
        await tester.pump();
        expect(find.text('Nothing in Settings matches “$word”.'), findsOneWidget, reason: word);
      }
      // What stays is found as before: by its name, its words, and a setting inside it.
      for (final (word, hit) in [('mode', 'Simple or advanced'), ('theme', 'Appearance'), ('text size', 'Text size'), ('cheat', 'Cheat sheet'), ('sign', 'Account')]) {
        await tester.enterText(field, word);
        await tester.pump();
        expect(_labels(tester), contains(hit), reason: word);
      }
      await endSettings(tester);
    });

    testWidgets('Appearance in Simple is the theme cards and the text size, and one line to where the rest is', (tester) async {
      await _open(tester, size: const Size(390, 1600), toPage: const SettingsTarget('theme', nonce: 1));
      expect(_titles(tester), ['Page', 'Type']);
      expect([for (final row in tester.widgetList<SettingRow>(find.byType(SettingRow))) row.label], ['Text size']);
      expect(find.byType(AccentSwatch), findsNothing);
      expect(find.text('Accent'), findsNothing);
      expect(find.text('ACCENT'), findsNothing);
      expect(find.text('Home page'), findsNothing);
      expect(find.byKey(const ValueKey('settings-sample')), findsOneWidget);
      // The two that are there still write.
      await _tap(tester, find.text('Largest'));
      expect(preferences.value.textSize, 'largest');
      await _tap(tester, find.descendant(of: find.byWidgetPredicate((w) => w is ChoiceCards<String> && w.label == 'Theme'), matching: find.text('Dark')));
      expect(preferences.value.theme, 'dark');
      // The search's list of the page is the page's.
      expect(appearanceFindable(wide: true, haptics: true, simple: true).map((f) => f.name), ['Page', 'Type', 'Text size']);
      expect(appearanceFindable(wide: true, haptics: true).map((f) => f.name), containsAll(['Accent', 'Sidebar', 'Haptics']));
      // The footnote's word lands on Simple or advanced.
      expect(find.byKey(const ValueKey('appearance-more-looks')), findsOneWidget);
      await _tap(tester, find.descendant(of: find.byType(GoWord), matching: find.text('Advanced')));
      expect(_display(tester), 'Simple or advanced');
      expect(find.byType(ExperiencePane), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('About’s Help in Simple keeps the cheat sheet and leaves out the Specification and the Examples', (tester) async {
      await _open(tester, toPage: const SettingsTarget('about', nonce: 1));
      expect(_display(tester), 'About');
      expect(find.text('Cheat sheet'), findsOneWidget);
      expect(find.text('Specification'), findsNothing);
      expect(find.text('Examples'), findsNothing);
      await _tap(tester, _rowFor('Cheat sheet'));
      expect(_display(tester), 'Cheat sheet');
      await endSettings(tester);
    });
  });
}
