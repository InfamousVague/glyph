import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/appearance_pane.dart';
import 'package:ghost_md/settings/kit/settings_icons.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/cheat_sheet.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/settings/words.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// Settings itself: the app's sections in the web app's order (src/app/settings/SettingsSheet.tsx), their live
/// readings, the links into it, and the list held to the rects the web page measured (2026-10-07, 390 x 844 and
/// 1280 x 800, light). The Flutter app is the phone app, so it lists what the web lists inside the Android app,
/// which is three rows more than a browser's page: Library folder, Backup, Recording and AI. Account's card heads
/// the list where the page measured it: Simple or advanced headed it on a card of its own from 2026-10-18 (GHST-103)
/// until Matt, 2026-10-24: "move the simple or advanced toggle under appearance and move appearnce up in the
/// settings to under account". Appearance is on a card of its own under Account's since, where the page's second
/// card began, so Library folder's card is one row and a gap further down than the page measured it
/// ([_appearancePhone]). Simple's own shorter list, and the choice on Appearance, are mode_cards_test.dart's.

/// What stands over Library folder's card now: Appearance's row (64.38 on a phone, as every row is), Sounds' under it
/// on the same card since 2026-10-27 (65.38 with its hairline), and the gap between two cards (17.85, as the page's
/// second card has under its first).
const double _appearancePhone = 64.38 + 65.38 + 17.85;

Future<void> _open(WidgetTester tester, {Preferences prefs = const Preferences(theme: 'light'), Size size = phone, int toCheatSheet = 0, int toModel = 0, SettingsTarget? toPage, VoidCallback? onClose}) =>
    pumpSettings(tester, SettingsSheet(open: true, onClose: onClose ?? () {}, toCheatSheet: toCheatSheet, toModel: toModel, toPage: toPage), size: size, prefs: prefs);

List<String?> _labels(WidgetTester tester) => [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-label'), skipOffstage: false))) text.data];
String? _display(WidgetTester tester) {
  final found = find.byKey(const ValueKey('settings-display'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

/// Each row's label with the line under it, or null where it has none.
Map<String, String?> _rows(WidgetTester tester) {
  final out = <String, String?>{};
  for (final row in find.ancestor(of: find.byKey(const ValueKey('settings-row-label'), skipOffstage: false), matching: find.byType(GlacierPressable), matchRoot: false).evaluate()) {
    final label = find.descendant(of: find.byWidget(row.widget, skipOffstage: false), matching: find.byKey(const ValueKey('settings-row-label'), skipOffstage: false), skipOffstage: false);
    final summary = find.descendant(of: find.byWidget(row.widget, skipOffstage: false), matching: find.byKey(const ValueKey('settings-row-summary'), skipOffstage: false), skipOffstage: false);
    out[tester.widget<Text>(label).data!] = summary.evaluate().isEmpty ? null : tester.widget<Text>(summary).data;
  }
  return out;
}

Finder _rowFor(String label) => find.ancestor(of: find.text(label), matching: find.byType(GlacierPressable)).first;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await settleSettings(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('the sections', () {
    testWidgets('are the web app’s, in its order, each with its reading', (tester) async {
      await _open(tester, size: const Size(390, 1200));
      expect(_rows(tester), {
        'Account': 'Not signed in',
        'Organizations': 'Signed out',
        'Workspaces': 'None yet',
        'Notifications': '4 of 4 on',
        // Under Account's card since 2026-10-24, and first on its line the mode the app is in (GHST-103), advanced
        // until it is chosen: the choice is the page's first card.
        'Appearance': 'Advanced · Light · Maple Mono',
        // Under Appearance on its card since 2026-10-27: the pack, and how many sounds are on.
        'Sounds': 'Ghostly · 3 of 11 on',
        'Library folder': 'Where your notes are kept',
        'Backup': 'To a USB drive or SD card',
        'Export': 'Everything as one zip',
        'Recording': 'Better words',
        'AI': 'Qwen3.5 4B, 2.7 GB to get',
        // The app's registry is empty until the built-in plugins are put in place (lib/plugins/built_in.dart).
        'Market': '0 of 0 plugins added',
        'About': '0.1.0',
      });
      expect(_rows(tester).keys, ['Account', 'Organizations', 'Workspaces', 'Notifications', 'Appearance', 'Sounds', 'Library folder', 'Backup', 'Export', 'Recording', 'AI', 'Market', 'About']);
      await endSettings(tester);
    });

    test('are one table: every section of the web’s sheet, each with its icon, its card and the web file its page is', () {
      expect([for (final spec in settingsSections) (spec.id, spec.group, spec.glyph)], [
        ('account', 0, SettingsGlyph.circleUser),
        ('organizations', 0, SettingsGlyph.userGroup),
        ('workspaces', 0, SettingsGlyph.folder),
        // The port's own (2026-10-16): today's note's choices, a page behind Workspaces.
        ('daily', 0, SettingsGlyph.calendarDays),
        ('notifications', 0, SettingsGlyph.bell),
        // Meetings, the port's own from 2026-10-23 (GHST-110), is the Google Meet and Zoom plugins' pages since
        // 2026-10-26 (test/plugins/meetings_test.dart).
        // On a card of its own under Account's since 2026-10-24, with how much of the app there is as its first card
        // (GHST-103), which had a page heading the list, on a card over Account's, from 2026-10-18.
        ('theme', 6, SettingsGlyph.sunMoon),
        // The port's own (Matt, 2026-10-27: "build ... the sounds settings"), under Appearance on its card.
        ('sounds', 6, SettingsGlyph.volume),
        ('library', 1, SettingsGlyph.folderOpen),
        ('backup', 1, SettingsGlyph.hardDriveUpload),
        ('export', 1, SettingsGlyph.hardDriveDownload),
        ('import', 1, SettingsGlyph.folderInput),
        ('recording', 2, SettingsGlyph.mic),
        ('ai', 2, SettingsGlyph.sparkles),
        // Ask Claude, Calendar and Contacts were the port's own sections until they were plugins (2026-10-17): their
        // pages are the Claude, Calendar and Contacts plugins' now. Plugins, the catalogue, headed a card of its own
        // from 2026-10-18; the Market's row does since 2026-10-26, the plugins' own pages as rows after it once they
        // are added (test/plugins/plugins_pane_test.dart).
        ('market', 5, SettingsGlyph.puzzle),
        ('about', 3, SettingsGlyph.info),
        ('cheatsheet', 3, SettingsGlyph.bookOpen),
        ('spec', 3, SettingsGlyph.fileCode),
        ('examples', 3, SettingsGlyph.shapes),
        ('developer', 4, SettingsGlyph.terminal),
        ('test-results', 4, SettingsGlyph.flaskConical),
      ]);
      // The sub-pages are off the list: Daily notes, the port's own, behind Workspaces; Import behind Export; the rest
      // behind About.
      expect([for (final spec in settingsSections) if (!spec.listed) (spec.id, spec.parent)], [('daily', 'workspaces'), ('import', 'export'), ('cheatsheet', 'about'), ('spec', 'about'), ('examples', 'about')]);
      // Every one is a page (lib/settings/panes/, and Appearance): none waits on a feature that is not ported.
      expect([for (final spec in settingsSections) if (spec.pane == null) spec.id], isEmpty);
      final web = Directory('tauri/src/app');
      for (final spec in settingsSections) {
        expect(spec.webFile, matches(RegExp(r'^(settings|plugins|guide)/\w+\.tsx$')), reason: spec.id);
        // Beside the web app's checkout, the file is there.
        if (web.existsSync()) expect(File('${web.path}/${spec.webFile}').existsSync(), isTrue, reason: spec.webFile);
      }
    });

    testWidgets('wear a colour each: Account and Organizations blue, Workspaces indigo, Notifications coral, Appearance purple, Sounds amber, Library cyan, Backup lime, Export rose, Recording red, AI magenta, the Market green, About yellow; none grey', (tester) async {
      await _open(tester, size: const Size(390, 1200));
      final chips = tester.widgetList<Container>(find.byKey(const ValueKey('settings-row-icon'))).toList();
      // Appearance's purple under Account's card since 2026-10-24; no row grey since the same day (Matt: "make sure all
      // settings sections icons have a color").
      final want = ['#0a6fe0', '#0a6fe0', '#4f5bd5', '#c8643f', '#9a45c9', '#c27c00', '#0a86a8', '#5a8a00', '#d6336c', '#dd3a30', '#b5279f', '#2a9d4b', '#b58400'];
      expect(chips.length, want.length);
      for (var i = 0; i < want.length; i++) {
        expect((chips[i].decoration! as BoxDecoration).color, sameColor(cssColor(tester, want[i]).withValues(alpha: 0.16)), reason: 'row $i');
      }
      await endSettings(tester);
    });

    testWidgets('read their lines live from what the pages write', (tester) async {
      await _open(tester, size: const Size(390, 1200));
      preferences.update((now) => now.copyWith(
            theme: 'dark',
            textSize: 'largest',
            typeface: 'plex',
            accent: 'teal',
            density: 'compact',
            rounding: 'square',
            refine: false,
            localOnly: true,
            notifications: now.notifications.copyWith(claude: false),
            workspaces: const KeptWorkspaces(list: [KeptWorkspace(id: 'w1', name: 'Work'), KeptWorkspace(id: 'w2', name: 'Home')]),
          ));
      await tester.pump();
      final rows = _rows(tester);
      expect(rows['Appearance'], 'Advanced · Dark · Maple Mono · Largest · Plex · Teal · Tight · Square');
      expect(rows['Recording'], 'Words as heard');
      expect(rows['Account'], 'Not signed in · Local only');
      expect(rows['Notifications'], '3 of 4 on');
      expect(rows['Workspaces'], '2 workspaces');
      // A size or a spacing with no word, from a newer build, is said as it is kept.
      expect(appearanceSummary(const Preferences(textSize: 'huge', density: 'airy', noteFace: 'fira')), 'Dark · Fira Code · huge · airy');
      await endSettings(tester);
    });

    testWidgets('leave out what an iPhone has no use for, and add the hidden pages once they are unlocked', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await _open(tester, size: const Size(390, 1200));
      expect(_labels(tester), ['Account', 'Organizations', 'Workspaces', 'Notifications', 'Appearance', 'Sounds', 'Export', 'Market', 'About']);
      debugDefaultTargetPlatformOverride = null;
      await endSettings(tester);

      await _open(tester, size: const Size(390, 1400));
      expect(_labels(tester), isNot(contains('Developer')));
      developerMode.set(true);
      await tester.pump();
      expect(_labels(tester).sublist(13), ['Developer', 'Test results']);
      expect(_rows(tester)['Developer'], 'Benches, reset');
      await endSettings(tester);
    });

    testWidgets('open Backup and Library folder on their pages, each saying what it cannot do until it is handed its feature', (tester) async {
      await _open(tester);
      await _tap(tester, _rowFor('Backup'));
      expect(_display(tester), 'Backup');
      expect(find.text('Not ported yet'), findsNothing);
      expect(find.text('Backups need the app'), findsOneWidget);
      // In the section's colour, Backup's lime.
      final tile = find.descendant(of: find.byType(SettingsEmpty), matching: find.byType(Container)).at(1);
      expect((tester.widget<Container>(tile).decoration! as BoxDecoration).color, sameColor(cssColor(tester, '#5a8a00').withValues(alpha: 0.16)));
      await _tap(tester, find.byKey(const ValueKey('settings-head-word')));
      await _tap(tester, _rowFor('Library folder'));
      expect(find.text('Needs the app’s next update'), findsOneWidget);
      // Back to the list, and Appearance is the page itself.
      await _tap(tester, find.byKey(const ValueKey('settings-head-word')));
      await _tap(tester, _rowFor('Appearance'));
      expect(find.byType(AppearancePane), findsOneWidget);
      expect(find.text('Not ported yet'), findsNothing);
      await endSettings(tester);
    });
  });

  group('the links into Settings', () {
    testWidgets('open at the cheat sheet when asked, behind About, each time it is asked', (tester) async {
      final ask = ValueNotifier(0);
      var closed = 0;
      await pumpSettings(tester, ValueListenableBuilder<int>(valueListenable: ask, builder: (context, at, _) => SettingsSheet(open: true, onClose: () => closed++, toCheatSheet: at)));
      expect(_display(tester), isNull);
      ask.value = 1759000000001;
      await tester.pump();
      await settleSettings(tester);
      expect(_display(tester), 'Cheat sheet');
      expect(find.byType(CheatSheet), findsOneWidget);
      testBack.goBack();
      await tester.pump();
      await settleSettings(tester);
      expect(_display(tester), 'About');
      ask.value = 1759000000002;
      await tester.pump();
      await settleSettings(tester);
      expect(_display(tester), 'Cheat sheet');
      expect(closed, 0);
      await endSettings(tester);
    });

    testWidgets('open at the AI section for a model, and at a page by its id', (tester) async {
      await _open(tester, toModel: 7);
      expect(_display(tester), 'AI');
      await endSettings(tester);
      await _open(tester, toPage: const SettingsTarget('organizations', nonce: 3));
      expect(_display(tester), 'Organizations');
      await endSettings(tester);
    });

    testWidgets('open a page at one of its settings, brought into view and lit', (tester) async {
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}, toPage: const SettingsTarget('theme', setting: 'Haptics', nonce: 9)), settle: false);
      await tester.pump(const Duration(milliseconds: 16));
      final row = find.widgetWithText(SettingRow, 'Haptics', skipOffstage: false);
      bool lit() => SettingsFindableMark.isLit(tester.widget(find.descendant(of: row, matching: find.byKey(SettingsFindableMark.lightKey, skipOffstage: false), skipOffstage: false)));
      expect(lit(), isTrue);
      // Far down the page, it is scrolled to: on the screen once the scroll has settled, and let go after a moment.
      await tester.pump(const Duration(milliseconds: 900));
      final at = tester.getRect(find.text('Haptics'));
      expect(at.top, greaterThan(62));
      expect(at.bottom, lessThan(844));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();
      expect(lit(), isFalse);
      await endSettings(tester);
    });

    testWidgets('find a setting from the search, on its own page', (tester) async {
      await _open(tester);
      await tester.enterText(find.byType(EditableText), 'smoke');
      await tester.pump();
      expect(_rows(tester), {'Blur at the edges': 'Appearance'});
      await tester.enterText(find.byType(EditableText), 'sign');
      await tester.pump();
      // Account is found by its own words, so what on its page answers to them is listed after it.
      expect(_rows(tester), {'Account': 'Not signed in', 'I have an account': 'Account', 'Create an account': 'Account', 'Organizations': 'Signed out'});
      await tester.enterText(find.byType(EditableText), 'privacy');
      await tester.pump();
      expect(_rows(tester).keys, ['Privacy', 'Local only', 'Privacy policy']);
      // A sub-page is found by its own name, though it is not on the list.
      await tester.enterText(find.byType(EditableText), 'cheat');
      await tester.pump();
      expect(_rows(tester), {'Cheat sheet': 'Every mark you can type'});
      await tester.enterText(find.byType(EditableText), 'corners');
      await tester.pump();
      await _tap(tester, _rowFor('Corners'));
      expect(_display(tester), 'Appearance');
      await endSettings(tester);
    });
  });

  group('the list as the web page measured it', () {
    testWidgets('on a phone: the head, the search and the first card, rect for rect', (tester) async {
      await _open(tester);
      final head = find.byKey(const ValueKey('settings-head-word'));
      expect(tester.getRect(head), rectNear(22.31, 4.45, 117.3, 53.55, 0.1));
      final arrow = find.descendant(of: head, matching: find.byType(SettingsIcon));
      expect(tester.getRect(arrow), rectNear(22.31, 19.19, 23.33, 23.33, 0.3));
      final word = DefaultTextStyle.of(tester.element(find.descendant(of: head, matching: find.byType(Text)))).style;
      expect(word.fontSize, closeTo(23.3334, 0.001));
      expect(word.fontWeight, FontWeight.w500);
      expect(word.color, sameColor(cssColor(tester, 'oklch(0.16 0 0)')));

      // The search: a pill 345.38 x 38.39 at 66.91, the magnifier 13.39 in, the words 8.93 after it.
      final field = find.byType(EditableText);
      final pill = find.ancestor(of: field, matching: find.byType(Container)).first;
      expect(tester.getRect(pill), rectNear(22.31, 66.91, 345.38, 38.39, 0.1));
      final look = tester.widget<Container>(pill).decoration! as ShapeDecoration;
      expect(look.color, sameColor(cssColor(tester, 'oklch(0.955 0 0)')));
      expect(look.shape, isA<StadiumBorder>());
      expect(tester.getRect(find.descendant(of: pill, matching: find.byType(SettingsIcon)).first), rectNear(35.7, 78.09, 16, 16, 0.1));
      expect(tester.getRect(field), rectNear(60.63, 76.09, 293.67, 20, 0.1));
      expect(tester.widget<EditableText>(field).style.fontSize, closeTo(16.1152, 0.001));
      expect(find.text('Search settings'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Search settings')).style!.color, sameColor(cssColor(tester, 'oklch(0.8 0 0)')));

      // The rows: 64.38 the first, 65.38 each after it with its hairline; the chip, the label over its line, the
      // chevron. Account's card is first, where the page's was; Appearance's card begins 17.85 under it, where the
      // page's second card does, and Library folder's that row and gap further down.
      Rect row(String label) => tester.getRect(_rowFor(label));
      expect(row('Account'), rectNear(22.31, 118.69, 345.38, 64.38, 0.1));
      expect(row('Organizations'), rectNear(22.31, 183.06 + 1, 345.38, 64.38, 0.1));
      expect(row('Workspaces').top, closeTo(248.44 + 1, 0.1));
      expect(row('Notifications').top, closeTo(313.81 + 1, 0.1));
      expect(row('Appearance'), rectNear(22.31, 397.03, 345.38, 64.38, 0.1));
      expect(row('Library folder').top, closeTo(397.03 + _appearancePhone, 0.1));
      expect(tester.getRect(find.byKey(const ValueKey('settings-row-icon')).first), rectNear(35.7, 136.08, 29.59, 29.59, 0.1));
      final chip = tester.widget<Container>(find.byKey(const ValueKey('settings-row-icon')).first).decoration! as BoxDecoration;
      expect(chip.borderRadius, BorderRadius.circular(8.8));
      expect(tester.getRect(find.descendant(of: find.byKey(const ValueKey('settings-row-icon')).first, matching: find.byType(SettingsIcon))), rectNear(42.5, 142.88, 16, 16, 0.1));
      final label = find.byKey(const ValueKey('settings-row-label')).first, summary = find.byKey(const ValueKey('settings-row-summary')).first;
      expect(tester.getRect(label).topLeft, within(distance: 0.1, from: const Offset(78.69, 132.08)));
      expect(tester.getRect(label).height, 20);
      expect(tester.getRect(summary).topLeft, within(distance: 0.1, from: const Offset(78.69, 153.67)));
      expect(tester.getRect(summary).height, 16);
      expect(tester.widget<Text>(label).style!.fontSize, closeTo(16.1152, 0.001));
      expect(tester.widget<Text>(label).style!.fontWeight, FontWeight.w500);
      expect(tester.widget<Text>(summary).style!.fontSize, closeTo(13.3948, 0.001));
      expect(tester.widget<Text>(summary).style!.color, sameColor(cssColor(tester, 'oklch(0.56 0 0)')));
      final chevron = find.descendant(of: _rowFor('Account'), matching: find.byType(SettingsIcon)).last;
      expect(tester.getRect(chevron), rectNear(336.3, 141.88, 18, 18, 0.1));
      expect(tester.widget<SettingsIcon>(chevron).color, sameColor(cssColor(tester, 'oklch(0.8 0 0)')));
      // The card: paper-2 with the kit's large corner.
      final card = tester.widget<ClipRRect>(find.ancestor(of: _rowFor('Account'), matching: find.byType(ClipRRect)).first);
      expect(card.borderRadius, BorderRadius.circular(16));
      await endSettings(tester);
    });

    testWidgets('under a notch, the head clears it and nothing else moves against it', (tester) async {
      await pumpApp(tester, home: SettingsSheet(open: true, onClose: () {}));
      await settleSettings(tester);
      // `padding-block-start: calc(var(--app-inset-top) + var(--glacier-space-1))`: 36 of notch here.
      expect(tester.getRect(find.byKey(const ValueKey('settings-head-word'))).top, closeTo(36 + 4.45, 0.1));
      expect(tester.getRect(_rowFor('Account')).top, closeTo(36 + 118.69, 0.1));
      await endSettings(tester);
    });

    testWidgets('ends where the keyboard begins, so what the search finds can be reached', (tester) async {
      await _open(tester);
      final list = find.byKey(const ValueKey('settings-list'));
      expect(tester.getRect(list).bottom, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.getRect(list).bottom, 544);
      await endSettings(tester);
    });

    testWidgets('on a wide window: the column and the page beside it, rect for rect', (tester) async {
      await _open(tester, size: wideWindow);
      expect(settingsSplitFits(tester.element(find.byType(SettingsSheet))), isTrue);
      final head = find.byKey(const ValueKey('settings-head-word'));
      expect(tester.getRect(head), rectNear(26.33, 5.27, 134.27, 63.22, 0.15));
      // The first section's page shows until one is chosen, and its row is the current one, a shade deeper: Account's,
      // as the page's was (Simple or advanced's from 2026-10-18 to 2026-10-24).
      final display = find.byKey(const ValueKey('settings-display'));
      expect(tester.widget<Text>(display).data, 'Account');
      expect(tester.getRect(display), rectNear(346.33, 73.75, 907.34, 34.75, 0.3));
      expect(tester.widget<Text>(display).style!.fontSize, closeTo(30.2184, 0.001));
      expect(tester.getSemantics(_rowFor('Account')), isSemantics(isSelected: true, isButton: true));
      final ground = tester.widget<ColoredBox>(find.descendant(of: _rowFor('Account'), matching: find.byType(ColoredBox)).first).color;
      expect(ground, sameColor(cssColor(tester, 'oklch(0.16 0 0)').withValues(alpha: 0.07)));
      // The column: 20rem with its hairline, the field over the sections in the header's glass, no chevrons.
      final field = find.byType(EditableText);
      final pill = find.ancestor(of: field, matching: find.byType(Container)).first;
      expect(tester.getRect(pill), rectNear(21.06, 79.02, 276.88, 38.39, 0.15));
      final glass = tester.widget<ColoredBox>(find.ancestor(of: pill, matching: find.byType(ColoredBox)).first);
      expect(glass.color, sameColor(cssColor(tester, 'oklch(0.995 0 0)').withValues(alpha: 0.66)));
      expect(tester.getRect(find.ancestor(of: pill, matching: find.byType(ColoredBox)).first), rectNear(0, 73.75, 319, 59.45, 0.15));
      expect(tester.getRect(_rowFor('Account')), rectNear(21.06, 133.22, 276.88, 71.19, 0.15));
      expect(tester.getRect(_rowFor('Organizations')).top, closeTo(204.41 + 1, 0.15));
      expect(tester.getRect(find.byKey(const ValueKey('settings-row-label')).first).topLeft, within(distance: 0.15, from: const Offset(82.25, 149.02)));
      expect(tester.getRect(find.byKey(const ValueKey('settings-row-label')).first).height, 21);
      expect(tester.getRect(find.byKey(const ValueKey('settings-row-summary')).first).top, closeTo(171.61, 0.15));
      expect(find.descendant(of: _rowFor('Account'), matching: find.byWidgetPredicate((w) => w is SettingsIcon && w.glyph == SettingsGlyph.chevronRight)), findsNothing);
      // Choosing another section changes the page beside the column, which stays. Tapped where it stands, in view
      // under Account's card: brought to the column's top first, it would be under the search's glass.
      await tester.tap(_rowFor('Appearance'));
      await tester.pump();
      await settleSettings(tester);
      expect(tester.widget<Text>(display).data, 'Appearance');
      expect(_labels(tester), contains('Account'));
      // The sidebar's choice is on Appearance here, and the search lists it.
      expect(find.text('SIDEBAR', skipOffstage: false), findsOneWidget);
      await tester.enterText(field, 'dock');
      await tester.pump();
      expect(_labels(tester), ['Sidebar']);
      await endSettings(tester);
    });
  });

  group('what a screen reader is told', () {
    testWidgets('a dialog called Settings, its way out, its search, and each section as a button with its state', (tester) async {
      await _open(tester);
      // `role="dialog" aria-modal aria-label="Settings"`: a route of its own, named.
      expect(tester.getSemantics(find.bySemanticsLabel('Settings').first), isSemantics(label: 'Settings', scopesRoute: true, namesRoute: true));
      // The head's word leaves for the notes, which is what it is told to say aloud.
      expect(tester.getSemantics(find.bySemanticsLabel('Back to your notes')), isSemantics(label: 'Back to your notes', isButton: true, hasTapAction: true, hasEnabledState: true, isEnabled: true, isFocusable: true, hasFocusAction: true));
      expect(tester.getSemantics(find.byType(EditableText)), isSemantics(label: 'Search settings', isTextField: true, hasTapAction: true, isFocusable: true));
      expect(find.bySemanticsLabel('Settings sections'), findsOneWidget);
      expect(tester.getSemantics(_rowFor('Account')), isSemantics(label: 'Account\nNot signed in', isButton: true, hasTapAction: true, hasEnabledState: true, isEnabled: true, isFocusable: true, hasFocusAction: true));
      // What the field found is named as such, and nothing found is said once, as a status.
      await tester.enterText(find.byType(EditableText), 'smoke');
      await tester.pump();
      expect(find.bySemanticsLabel('Settings found'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Clear the search')), isSemantics(label: 'Clear the search', isButton: true, hasTapAction: true, hasEnabledState: true, isEnabled: true));
      await tester.enterText(find.byType(EditableText), 'nothing like it');
      await tester.pump();
      expect(tester.getSemantics(find.text('Nothing in Settings matches “nothing like it”.')), isSemantics(label: 'Nothing in Settings matches “nothing like it”.', isLiveRegion: true));
      await tester.tap(find.bySemanticsLabel('Clear the search'));
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '');
      // Over a page: its name as a heading, and the head's word steps back and says only where.
      await _tap(tester, _rowFor('Appearance'));
      expect(tester.getSemantics(find.byKey(const ValueKey('settings-display'))), isSemantics(label: 'Appearance', isHeader: true));
      expect(find.bySemanticsLabel('Back to your notes'), findsNothing);
      await endSettings(tester);
    });
  });

  test('every value a preference can take has its word', () {
    expect(themeWords.keys, themes);
    expect(accentWords.keys, accents);
    expect(densityWords.keys, densities);
    expect(roundingWords.keys, roundings);
    expect(sizeWords.keys, textSizes);
    expect(faceWords.keys, typefaces);
    expect(speedWords.keys, motionScales.keys);
    expect(scaleWords.keys, uiScales);
    expect(codeLightWords.keys, codeThemesLight);
    expect(codeDarkWords.keys, codeThemesDark);
    expect(sidebarWords.keys, sidebarStyles);
    // The kit's density stops are the preference's.
    expect([for (final mode in GlacierDensityMode.values) mode.token], densities);
  });
}
