import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/workspace_sheet.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/about_pane.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';
import 'package:ghost_md/settings/panes/ai_pane.dart';
import 'package:ghost_md/settings/panes/examples_pane.dart';
import 'package:ghost_md/settings/panes/pane_parts.dart';
import 'package:ghost_md/settings/panes/recording_pane.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// The pages of Settings that are built from the settings kit alone (lib/settings/panes/): what each draws, what
/// each control writes and what each row runs, and each held to the rects the web page measured (its dev server in
/// Chromium, 390 x 844 and 1280 x 800, light, 2026-10-07; the pages a browser does not list were measured with the
/// page told it was inside the Android app).
///
/// The kit rounds a line of small text to a whole pixel (20 where the page has 20.09), so a rect far down a page is
/// held a little looser than the half pixel the first ones are held to.

/// The row's label and the line under it, as drawn.
String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(rowCalled(label)).hint;
  return hint is Text ? hint.data : null;
}

GlacierSwitch switchIn(WidgetTester tester, String label) => tester.widget(inRow(label, find.byType(GlacierSwitch, skipOffstage: false)));
bool rowOff(WidgetTester tester, String label) {
  final row = tester.widget<SettingRow>(rowCalled(label));
  return row.disabled || row.disabledReason != null;
}

/// The rows of the list of sections, each with the line under it.
String? listLine(WidgetTester tester, String section) {
  final row = find.ancestor(of: find.text(section, skipOffstage: false), matching: find.byType(GlacierPressable, skipOffstage: false)).first;
  final line = find.descendant(of: row, matching: find.byKey(const ValueKey('settings-row-summary'), skipOffstage: false), skipOffstage: false);
  return line.evaluate().isEmpty ? null : tester.widget<Text>(line).data;
}

Future<void> back(WidgetTester tester) async {
  testBack.goBack();
  await tester.pump();
  await settleSettings(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('Workspaces', () {
    testWidgets('lists every workspace with how many notes are in it, and the row counts the same store', (tester) async {
      final store = seededSpaces();
      await openPane(tester, 'workspaces', workspaces: store);
      expect(cardTitles(tester), ['Your workspaces']);
      expect(rowLabels(tester), ['Work', 'Home', 'New workspace']);
      expect((hintOf(tester, 'Work'), hintOf(tester, 'Home')), ('10 notes', '3 notes'));
      await back(tester);
      expect(listLine(tester, 'Workspaces'), '2 workspaces');
      // The count is the store's, the moment it changes: not the preferences', which this app's store does not write.
      store.addWorkspace('Garden', 'rose');
      await tester.pump();
      expect(listLine(tester, 'Workspaces'), '3 workspaces');
      expect(preferences.value.workspaces.list, isEmpty);
      await endSettings(tester);
    });

    testWidgets('with none, says so and offers one; with no store handed in, keeps them in the preferences', (tester) async {
      await openPane(tester, 'workspaces');
      expect(rowLabels(tester), ['None yet', 'New workspace']);
      expect(hintOf(tester, 'None yet'), 'Make one below.');
      await tapOn(tester, rowCalled('New workspace'));
      expect(find.byType(WorkspaceManageSheet), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(WorkspaceManageSheet), matching: find.byType(EditableText)), 'Reading');
      await tester.pump();
      await tapOn(tester, find.text('Add'));
      expect(find.byType(WorkspaceManageSheet), findsNothing);
      expect(rowLabels(tester), ['Reading', 'New workspace']);
      expect(hintOf(tester, 'Reading'), '0 notes');
      expect([for (final w in preferences.value.workspaces.list) w.name], ['Reading']);
      await back(tester);
      expect(listLine(tester, 'Workspaces'), '1 workspace');
      // Workspaces that arrive from elsewhere (another device's settings) are read again.
      preferences.update((now) => now.copyWith(workspaces: const KeptWorkspaces(list: [KeptWorkspace(id: 'a', name: 'A'), KeptWorkspace(id: 'b', name: 'B'), KeptWorkspace(id: 'c', name: 'C')])));
      await tester.pump();
      expect(listLine(tester, 'Workspaces'), '3 workspaces');
      await endSettings(tester);
    });

    testWidgets('opens a workspace’s sheet from its row, which renames it and deletes it, asking about its notes', (tester) async {
      final store = seededSpaces();
      final trashed = <String>[];
      await openPane(tester, 'workspaces', workspaces: store, notesInWorkspace: (id) => id == 'home' ? ['h0', 'h1'] : [], onTrashNotes: trashed.addAll);
      // The count is what the caller says is not already in the trash.
      expect((hintOf(tester, 'Work'), hintOf(tester, 'Home')), ('0 notes', '2 notes'));
      await tapOn(tester, rowCalled('Home'));
      expect(tester.widget<WorkspaceManageSheet>(find.byType(WorkspaceManageSheet)).editing?.id, 'home');
      await tapOn(tester, find.text('Delete workspace'));
      expect(find.text('What happens to its 2 notes?'), findsOneWidget);
      await tapOn(tester, find.text('Delete, and move the notes to Trash'));
      expect(trashed, ['h0', 'h1']);
      expect([for (final w in store.value.list) w.id], ['work']);
      expect(rowLabels(tester), ['Work', 'New workspace']);
      expect(find.byType(WorkspaceManageSheet), findsNothing);
      await endSettings(tester);
    });

    testWidgets('lists an organization’s workspace apart, and its row opens the organization', (tester) async {
      final store = seededSpaces()..ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Attic', hue: 'violet'));
      final opened = <String>[];
      await openPane(tester, 'workspaces', workspaces: store, onOrganization: opened.add);
      expect(cardTitles(tester), ['Your workspaces', 'Organizations’ workspaces']);
      expect(rowLabels(tester, 'Organizations’ workspaces'), ['Attic']);
      await tapOn(tester, rowCalled('Attic'));
      expect(opened, ['o1']);
      expect(find.byType(WorkspaceManageSheet), findsNothing);
      await endSettings(tester);
    });

    testWidgets('is the page’s, rect for rect, on a phone and on a wide window', (tester) async {
      await openPane(tester, 'workspaces', workspaces: seededSpaces());
      final card = cardCalled('Your workspaces');
      expect(tester.getRect(surfaceOf(card)), rectNear(22.31, 194.73, 345.38, 196.88));
      expect(tester.getRect(rowCalled('Work')), rectNear(22.31, 194.73, 345.38, 69.25));
      // A row after a row has the hairline over it: the page's rect counts the line, this one starts under it.
      expect(tester.getRect(rowCalled('Home')), rectNear(22.31, 264.98, 345.38, 69.25));
      expect(tester.getRect(rowCalled('New workspace')), rectNear(22.31, 335.23, 345.38, 56.38));
      expect(tester.getRect(inRow('Work', find.text('Work'))).topLeft, offsetMoreOrLessEquals(const Offset(78.69, 208.13), epsilon: 0.5));
      expect(tester.getRect(inRow('Work', find.text('10 notes'))).topLeft, offsetMoreOrLessEquals(const Offset(78.69, 230.52), epsilon: 0.5));
      // The round of its hue, in the chip every row's icon wears.
      final rounds = find.byKey(HueMark.roundKey);
      expect(tester.getRect(rounds.at(0)), rectNear(44.09, 222.95, 12.8, 12.8));
      expect(tester.getRect(rounds.at(1)), rectNear(44.09, 293.2, 12.8, 12.8));
      expect((tester.widget<Container>(rounds.at(0)).decoration! as BoxDecoration).color, sameColor(cssColor(tester, 'oklch(0.55 0.14 150)')));
      expect((tester.widget<Container>(rounds.at(1)).decoration! as BoxDecoration).color, sameColor(cssColor(tester, 'oklch(0.55 0.14 230)')));
      expect(tester.getRect(find.textContaining('Deleting a workspace asks first')).top, closeTo(409.45, 1));
      await endSettings(tester);

      await openPane(tester, 'workspaces', workspaces: seededSpaces(), size: wideWindow);
      expect(tester.getRect(surfaceOf(cardCalled('Your workspaces'))), rectNear(346.33, 201.67, 907.34, 215.66, 1));
      expect(tester.getRect(find.byKey(HueMark.roundKey).first), rectNear(370.52, 233.38, 12.8, 12.8, 0.75));
      expect(tester.getRect(inRow('Work', find.text('Work'))).topLeft, offsetMoreOrLessEquals(const Offset(407.52, 217.47), epsilon: 0.75));
      await endSettings(tester);
    });
  });

  group('Notifications', () {
    testWidgets('has a switch for each category, each a synced preference the row in the list counts', (tester) async {
      await openPane(tester, 'notifications');
      expect(cardTitles(tester), ['What reaches you']);
      expect(rowLabels(tester), ['Team', 'Claude', 'Summaries', 'Conflicts']);
      for (final (row, read) in <(String, bool Function(NotificationPrefs))>[('Team', (n) => n.team), ('Claude', (n) => n.claude), ('Summaries', (n) => n.summaries), ('Conflicts', (n) => n.conflicts)]) {
        expect(read(preferences.value.notifications), isTrue);
        await tapOn(tester, inRow(row, find.byType(GlacierSwitch)));
        expect(read(preferences.value.notifications), isFalse, reason: row);
        expect(switchIn(tester, row).checked, isFalse);
      }
      await tapOn(tester, inRow('Claude', find.byType(GlacierSwitch)));
      await back(tester);
      expect(listLine(tester, 'Notifications'), '1 of 4 on');
      await endSettings(tester);
    });

    testWidgets('signed out, sends the person to Account by a word; signed in, says nothing of it', (tester) async {
      await openPane(tester, 'notifications');
      expect(find.textContaining('Notifications come with an account. Sign in under'), findsOneWidget);
      await tapOn(tester, find.descendant(of: find.byType(GoWord), matching: find.text('Account')));
      expect(display(tester), 'Account');
      await endSettings(tester);

      await openPane(tester, 'notifications', features: const SettingsFeatures(signedIn: true));
      expect(find.byType(SettingsCallout), findsNothing);
      await endSettings(tester);
    });

    testWidgets('lists the organizations to mute once the account is in one, and keeps the muted ones by id', (tester) async {
      await openPane(tester, 'notifications', features: const SettingsFeatures(signedIn: true, orgs: [SettingsOrg(id: 'o1', name: 'Attic', members: 1), SettingsOrg(id: 'o2', name: 'Cellar', members: 4)]));
      expect(cardTitles(tester), ['What reaches you', 'Mute an organization']);
      expect((hintOf(tester, 'Attic'), hintOf(tester, 'Cellar')), ('1 member', '4 members'));
      await tapOn(tester, inRow('Cellar', find.byType(GlacierSwitch, skipOffstage: false)));
      await tapOn(tester, inRow('Attic', find.byType(GlacierSwitch, skipOffstage: false)));
      expect(preferences.value.notifications.mutedOrgs, ['o2', 'o1']);
      await tapOn(tester, inRow('Cellar', find.byType(GlacierSwitch, skipOffstage: false)));
      expect(preferences.value.notifications.mutedOrgs, ['o1']);
      await endSettings(tester);
    });

    testWidgets('is the page’s, rect for rect', (tester) async {
      await openPane(tester, 'notifications');
      expect(tester.getRect(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null).first), rectNear(22.31, 122.73, 345.38, 68.94, 0.75));
      expect(tester.getRect(find.descendant(of: find.byType(GoWord), matching: find.text('Account'))).topLeft, offsetMoreOrLessEquals(const Offset(36.7, 157.2), epsilon: 1));
      expect(tester.getRect(find.text('WHAT REACHES YOU')).topLeft, offsetMoreOrLessEquals(const Offset(31.24, 209.52), epsilon: 0.75));
      expect(tester.getRect(inRow('Team', find.byType(GlacierSwitch))).size, const Size(44, 26));
      await endSettings(tester);
    });
  });

  group('About', () {
    test('says the version pubspec.yaml has', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('\nversion: $ghostVersion+'));
    });

    testWidgets('with no updater, is the version and Help; its rows open the pages behind them and run what they are given', (tester) async {
      final ran = <String>[];
      await openPane(tester, 'about', onAcademy: () => ran.add('academy'), onGuideBook: () => ran.add('book'));
      expect(cardTitles(tester), [null, 'Help']);
      expect(tester.widget<PaneHero>(find.byType(PaneHero)).title, ghostVersion);
      expect(rowLabels(tester), ['Ghost.md Academy', 'The welcome walkthrough', 'Cheat sheet', 'Specification', 'Ghost.md: The Guide', 'Examples']);
      expect(hintOf(tester, 'Ghost.md: The Guide'), 'The whole app in 44 short chapters. Added to your notes the first time, and opened after that.');
      await tapOn(tester, rowCalled('Ghost.md Academy'));
      await tapOn(tester, rowCalled('Ghost.md: The Guide'));
      expect(ran, ['academy', 'book']);
      // The walkthrough has nothing to run yet: its row is there and cannot be pressed.
      expect(rowOff(tester, 'The welcome walkthrough'), isTrue);
      expect(rowOff(tester, 'Cheat sheet'), isFalse);
      for (final (row, page) in [('Cheat sheet', 'Cheat sheet'), ('Specification', 'Specification'), ('Examples', 'Examples')]) {
        await tapOn(tester, rowCalled(row));
        expect(display(tester), page);
        await back(tester);
        expect(display(tester), 'About');
      }
      await back(tester);
      expect(listLine(tester, 'About'), ghostVersion);
      await endSettings(tester);
    });

    testWidgets('unlocks the developer pages at the seventh press on the version, counting down from the third', (tester) async {
      await openPane(tester, 'about');
      addTearDown(() => developerMode.set(false));
      final hero = find.byType(PaneHero);
      for (var press = 1; press <= 6; press++) {
        await tester.tap(hero);
        await tester.pump(const Duration(milliseconds: 100));
        final left = 7 - press;
        expect(find.text('$left more ${left == 1 ? 'tap' : 'taps'} for developer settings.'), press >= 3 ? findsOneWidget : findsNothing, reason: 'press $press');
        expect(developerMode.value, isFalse);
      }
      await tester.tap(hero);
      await tester.pump();
      expect(developerMode.value, isTrue);
      expect(find.text('Developer settings are on.'), findsOneWidget);
      await settleSettings(tester);
      expect(display(tester), 'Developer');
      // The toast leaves on its own.
      await tester.pump(const Duration(seconds: 3));
      await endSettings(tester);
    });

    test('a run of presses starts again after a pause', () {
      for (var i = 0; i < 9; i++) {
        countKnock(1000000 + i * 5000);
      }
      expect([for (var i = 0; i < 6; i++) countKnock(2000000 + i * 100)], [6, 5, 4, 3, 2, 1]);
      expect(countKnock(2000000 + 600 + 901), 6);
    });

    testWidgets('with an updater, says where the build stands and moves it on', (tester) async {
      var checked = 0, reloaded = 0, installed = 0;
      bool? alerts;
      final updates = SettingsUpdates(
        version: '1.15.0',
        built: 'Oct 8, 02:55 AM',
        nativeVersion: '1.15.0',
        sourceHost: 'ghostmarkdown.com',
        overTheAir: true,
        ready: true,
        installable: '1.16.0',
        checked: true,
        onCheck: () => checked++,
        onReload: () => reloaded++,
        onInstall: () => installed++,
        alerts: SettingsUpdateAlerts(on: true, onChange: (on) => alerts = on),
        runningBuild: '20261007180703',
        releases: const [
          SettingsRelease(build: '20261007180703', version: '1.15.0', when: 'Oct 7, 6:07 PM', notes: 'Backup shows what the drive holds.', apk: '1.15.0'),
          SettingsRelease(build: '20261001120000', version: '1.14.2', when: 'Oct 1, 12:00 PM'),
        ],
      );
      await openPane(tester, 'about', updates: updates, size: const Size(390, 1800));
      expect(cardTitles(tester), [null, 'Updates', 'Alerts', 'Help', "What's new"]);
      expect(tester.widget<PaneHero>(find.byType(PaneHero)).title, '1.15.0');
      expect(find.text('Updated over the air · Oct 8, 02:55 AM · app 1.15.0 · updates from ghostmarkdown.com'), findsOneWidget);
      expect(rowLabels(tester, 'Updates'), ['Ghost.md 1.16.0 is ready to install.']);
      await tapOn(tester, find.text('Reload'));
      await tapOn(tester, find.text('Install 1.16.0'));
      await tapOn(tester, find.text('Check for updates'));
      expect((reloaded, installed, checked), (1, 1, 1));
      await tapOn(tester, inRow('Update alerts', find.byType(GlacierSwitch)));
      expect(alerts, isFalse);
      expect(rowLabels(tester, "What's new"), ["1.15.0 · you're on this one", '1.14.2']);
      expect(hintOf(tester, "1.15.0 · you're on this one"), 'Backup shows what the drive holds. Installed as Ghost.md 1.15.0.');
      await back(tester);
      expect(listLine(tester, 'About'), '1.15.0 · 1.16.0 ready to install');
      await endSettings(tester);
    });

    test('says each rung of the two ladders, the page’s and the list’s', () {
      SettingsUpdates u({bool checking = false, bool ready = false, String? lastError, bool checked = false, String? downloading, String? installable}) =>
          SettingsUpdates(version: '1', checking: checking, ready: ready, lastError: lastError, checked: checked, downloading: downloading, installable: installable);
      expect(updatesStatus(u(checking: true, ready: true)), 'Checking for updates.');
      expect(updatesStatus(u(downloading: '2', installable: '2')), 'Downloading Ghost.md 2.');
      expect(updatesStatus(u(installable: '2', ready: true)), 'Ghost.md 2 is ready to install.');
      expect(updatesStatus(u(ready: true, lastError: 'x')), 'A new version is downloaded.');
      expect(updatesStatus(u(lastError: 'no signal', checked: true)), "Couldn't check for updates: no signal");
      expect(updatesStatus(u(checked: true)), 'Up to date.');
      expect(updatesStatus(u()), 'Not checked yet.');
      // The list's is shorter and has no rung for an app downloading.
      expect([updatesSummary(u(checking: true)), updatesSummary(u(downloading: '2')), updatesSummary(u(installable: '2')), updatesSummary(u(ready: true)), updatesSummary(u(lastError: 'x')), updatesSummary(u(checked: true))],
          ['Checking', 'Not checked yet', '2 ready to install', 'New version downloaded', "Couldn't check", 'Up to date']);
      expect(buildLine(const SettingsUpdates(version: '1')), 'Built into the app · unknown build');
      expect(buildLine(const SettingsUpdates(version: '1', built: 'Oct 8', nativeVersion: '1.9.0', staging: true, sourceHost: 'x')), 'Built into the app · Oct 8 · app 1.9.0 · staging build, updates off');
      // From the App Store there is nothing to check here, and no What's new to list.
      expect(aboutFindable(updates: true, alerts: false, whatsNew: false).map((f) => f.name), ['Updates', 'Ghost.md Academy', 'The welcome walkthrough', 'Ghost.md: The Guide']);
      expect(aboutFindable(updates: false, alerts: false, whatsNew: true).map((f) => f.name), ['Ghost.md Academy', 'The welcome walkthrough', 'Ghost.md: The Guide']);
    });

    testWidgets('is the page’s inside the app, rect for rect', (tester) async {
      await openPane(tester, 'about', updates: measuredUpdates(), onAcademy: () {}, onGuide: () {}, onGuideBook: () {});
      expect(tester.getRect(surfaceOf(find.byType(PaneSection).first)), rectNear(22.31, 122.73, 345.38, 80.13));
      expect(tester.getRect(find.text('1.15.0')).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 136.13), epsilon: 0.5));
      expect(tester.getRect(find.text('Built into the app · Oct 8, 02:55 AM')).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 169.39), epsilon: 0.5));
      expect(tester.getRect(find.text('Not checked yet.')).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 257.02), epsilon: 0.5));
      // The words under the card: a thumb high, in from the card's edge as its title is.
      expect(tester.getRect(find.byType(RowAction)), rectNear(31.23, 308.25, 150.11, 44.63, 0.75));
      expect(tester.getRect(find.text('HELP')).topLeft, offsetMoreOrLessEquals(const Offset(31.24, 370.72), epsilon: 0.75));
      expect(tester.getRect(inRow('Ghost.md Academy', find.text('Ghost.md Academy'))).topLeft, offsetMoreOrLessEquals(const Offset(78.69, 407.03), epsilon: 0.75));
      expect(tester.getRect(inRow('Examples', find.text('Examples', skipOffstage: false))).topLeft, offsetMoreOrLessEquals(const Offset(78.69, 938.98), epsilon: 1.5));
      expect(tester.getRect(find.text("WHAT'S NEW", skipOffstage: false)).top, closeTo(1032.77, 1.5));
      await endSettings(tester);
    });
  });

  group('Examples', () {
    testWidgets('are four rows that each make a note, and a row with nothing to run cannot be pressed', (tester) async {
      final made = <String>[];
      await openPane(tester, 'examples', onSample: () => made.add('sample'), onHowCanvas: () => made.add('how'));
      expect(rowLabels(tester), examplesFindable.map((f) => f.name));
      await tapOn(tester, rowCalled('Add the sample note'));
      await tapOn(tester, rowCalled('Add the “How Ghost.md works” canvas'));
      expect(made, ['sample', 'how']);
      expect([for (final row in rowLabels(tester)) rowOff(tester, row)], [false, true, true, false]);
      await tester.tap(rowCalled('Add the example board'), warnIfMissed: false);
      expect(made, hasLength(2));
      // Rect for rect: one card of four rows, each with its icon's chip.
      expect(tester.getRect(surfaceOf(find.byType(PaneSection))), rectNear(22.31, 122.73, 345.38, 420.47, 1.5));
      expect(tester.getRect(inRow('Add the sample note', find.byType(AppIcon)).first), rectNear(42.09, 169.03, 16.8, 16.8, 0.75));
      await endSettings(tester);
    });
  });

  group('Recording', () {
    testWidgets('keeps each switch and the summaries’ pick as a preference, live at once', (tester) async {
      await openPane(tester, 'recording', size: const Size(390, 1400));
      expect(cardTitles(tester), ['While recording', 'After recording', 'Summaries', 'Tapes']);
      for (final (row, read) in <(String, bool Function(Preferences))>[('Stop when I go quiet', (p) => p.quietStop), ('Review after recording', (p) => p.review), ('Better words', (p) => p.refine)]) {
        final was = read(preferences.value);
        expect(switchIn(tester, row).checked, was);
        await tapOn(tester, inRow(row, find.byType(GlacierSwitch)));
        expect(read(preferences.value), !was, reason: row);
        expect(switchIn(tester, row).checked, !was);
      }
      expect(rowLabels(tester, 'Summaries'), ['Meetings', 'Meetings and long voice notes', 'Off']);
      expect(preferences.value.summaries, 'meetings');
      await tapOn(tester, inRow('Off', find.byType(Pick)));
      expect(preferences.value.summaries, 'off');
      expect([for (final pick in tester.widgetList<Pick>(find.byType(Pick))) pick.checked], [false, false, true]);
      await tapOn(tester, inRow('Meetings and long voice notes', find.byType(Pick)));
      expect(preferences.value.summaries, 'long');
      // On the phone the words say so.
      expect(hintOf(tester, 'Better words'), 'A larger model goes over the recording and fixes the words. A few seconds of the phone per minute of speech.');
      expect(hintOf(tester, 'Stop when I go quiet'), contains('The side key and Done still work.'));
      await back(tester);
      expect(listLine(tester, 'Recording'), recordingSummary(preferences.value));
      await endSettings(tester);
    });

    testWidgets('marks what waits for a recorder: no Meetings without the service, no tapes, and nothing to remove', (tester) async {
      await openPane(tester, 'recording', size: const Size(390, 1400));
      expect(cardTitles(tester), isNot(contains('Meetings')));
      expect(find.text('No tapes on this device.'), findsOneWidget);
      expect(tester.widget<SettingRow>(rowCalled('Remove audio older than a month')).control, isNull);
      await endSettings(tester);
    });

    testWidgets('with the meeting service, draws Meetings: the sound, the notification, and when it is written up', (tester) async {
      var asked = 0;
      await openPane(tester, 'recording', size: const Size(390, 1800), features: SettingsFeatures(meetings: true, meetingSoundWhy: 'Update Ghost.md to include sound from other apps.', onAllowMeetingNotices: () => ++asked > 0 && false));
      expect(rowLabels(tester, 'Meetings'), ['Include sound from other apps', 'Tell me when a meeting is written up', 'Write up straight away']);
      // The sound has no switch where the device cannot, and says why.
      expect(tester.widget<SettingRow>(rowCalled('Include sound from other apps')).control, isNull);
      expect(find.text('Update Ghost.md to include sound from other apps.'), findsOneWidget);
      await tapOn(tester, find.text('Allow'));
      expect(asked, 1);
      expect(hintOf(tester, 'Tell me when a meeting is written up'), 'Notifications are off for Ghost.md in the phone’s settings.');
      expect(preferences.value.writeUp, 'charging');
      await tapOn(tester, inRow('Write up straight away', find.byType(GlacierSwitch)));
      expect(preferences.value.writeUp, 'now');
      await endSettings(tester);

      await openPane(tester, 'recording', size: const Size(390, 1800), features: const SettingsFeatures(meetings: true, meetingSound: true, canNotifyMeetings: true));
      expect(find.text('Allow'), findsNothing);
      expect(find.descendant(of: rowCalled('Tell me when a meeting is written up'), matching: find.text('On')), findsOneWidget);
      await tapOn(tester, inRow('Include sound from other apps', find.byType(GlacierSwitch)));
      expect(preferences.value.meetingSound, isTrue);
      await endSettings(tester);
    });

    testWidgets('says the room the tapes take, and removes the old ones’ audio on the second tap', (tester) async {
      var removed = 0;
      await openPane(tester, 'recording', size: const Size(390, 1400), features: SettingsFeatures(tapes: 2300000000, oldTapes: 2, onRemoveOldAudio: () async => ++removed + 1));
      expect(find.text('Your tapes take about 2.3 GB on this device.'), findsOneWidget);
      await tapOn(tester, find.text('Remove'));
      expect(removed, 0);
      expect(find.text('Tap again'), findsOneWidget);
      await tapOn(tester, find.text('Tap again'));
      expect(removed, 1);
      expect(find.text('Removed the audio of 2 tapes. The words stay.'), findsOneWidget);
      // Armed, it lets go after five seconds.
      await tapOn(tester, find.text('Remove'));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Tap again'), findsNothing);
      expect((tapeSize(410000000), tapeSize(200), tapeSize(1500000000)), ('410 MB', '1 MB', '1.5 GB'));
      await endSettings(tester);
    });

    testWidgets('is the page’s inside the Android app, rect for rect', (tester) async {
      await openPane(tester, 'recording');
      expect(tester.getRect(find.text('WHILE RECORDING')).topLeft, offsetMoreOrLessEquals(const Offset(31.24, 122.73), epsilon: 0.5));
      expect(tester.getRect(inRow('Stop when I go quiet', find.text('Stop when I go quiet'))).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 159.05), epsilon: 0.5));
      expect(tester.getRect(inRow('Review after recording', find.text('Review after recording'))).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 269.45), epsilon: 0.75));
      expect(tester.getRect(find.text('AFTER RECORDING')).top, closeTo(403.39, 1));
      expect(tester.getRect(find.text('SUMMARIES')).top, closeTo(553.56, 1));
      expect(tester.getRect(inRow('Off', find.text('Off', skipOffstage: false))).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 823), epsilon: 1.5));
      expect(tester.getRect(find.text('TAPES', skipOffstage: false)).top, closeTo(877.63, 1.5));
      await endSettings(tester);
    });
  });

  group('AI', () {
    testWidgets('lists the catalogue, with Get waiting for a downloader, and keeps Fill blanks on their own', (tester) async {
      await openPane(tester, 'ai', size: const Size(390, 1200));
      expect(cardTitles(tester), ['Model']);
      expect(rowLabels(tester), ['Qwen3.5 2B', 'Qwen3.5 4B', 'Qwen3.5 9B', 'Gemma 4 E4B', 'Fill blanks on their own']);
      expect(hintOf(tester, 'Qwen3.5 4B'), 'The balance. Fits most phones; check a fact it answers from memory. 2.7 GB.');
      expect(find.text('Get'), findsNWidgets(4));
      expect([for (final get in tester.widgetList<RowAction>(find.byType(RowAction))) get.disabled], everyElement(isTrue));
      expect(find.text('Nothing downloaded yet. Get one above, or tap the robot on a note and it will offer to.'), findsOneWidget);
      final was = preferences.value.autoFill;
      await tapOn(tester, inRow('Fill blanks on their own', find.byType(GlacierSwitch)));
      expect(preferences.value.autoFill, !was);
      await back(tester);
      expect(listLine(tester, 'AI'), 'Qwen3.5 4B, 2.7 GB to get');
      await endSettings(tester);
    });

    testWidgets('with a model store: fetches, chooses, says which is in use, and removes on the second tap', (tester) async {
      final got = <String>[], gone = <String>[];
      await openPane(
        tester,
        'ai',
        size: const Size(390, 1200),
        features: SettingsFeatures(models: const SettingsModelsState(present: {'qwen3.5-2b', 'qwen3.5-4b'}), onGetModel: got.add, onRemoveModel: gone.add),
      );
      expect(find.text('7.0 GB on the phone.').evaluate().isEmpty && find.text('4.0 GB on the phone.').evaluate().length == 1, isTrue);
      expect(find.descendant(of: rowCalled('Qwen3.5 4B'), matching: find.text('In use')), findsOneWidget);
      expect([for (final pick in tester.widgetList<Pick>(find.byType(Pick))) (pick.label, pick.checked)], [('Use Qwen3.5 2B', false), ('Use Qwen3.5 4B', true)]);
      await tapOn(tester, find.text('Get').first);
      expect(got, ['qwen3.5-9b']);
      // The one not in use has Remove, asked twice.
      await tapOn(tester, find.text('Remove'));
      expect(gone, isEmpty);
      await tapOn(tester, find.text('Tap again'));
      expect(gone, ['qwen3.5-2b']);
      await tapOn(tester, inRow('Qwen3.5 2B', find.byType(Pick)));
      expect(preferences.value.formatModel, 'qwen3.5-2b');
      await back(tester);
      expect(listLine(tester, 'AI'), 'Qwen3.5 2B');
      await endSettings(tester);
      expect(aiSummary(const Preferences(formatModel: 'other'), null), 'other, 0.0 GB to get');
    });

    testWidgets('shows a download in the open, and what went wrong', (tester) async {
      await openPane(tester, 'ai', size: const Size(390, 1400), features: const SettingsFeatures(models: SettingsModelsState(downloading: 'qwen3.5-9b', received: 1200000000, total: 5680522464, problem: 'No room left on the phone.')));
      expect(find.text('Getting Qwen3.5 9B, 1.2 GB of 5.7 GB. Keep Ghost.md open.'), findsOneWidget);
      expect(find.byType(GlacierProgressBar), findsOneWidget);
      expect(find.text('No room left on the phone.'), findsOneWidget);
      expect(find.descendant(of: rowCalled('Qwen3.5 9B'), matching: find.text('Downloading')), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('is the page’s inside the Android app, rect for rect', (tester) async {
      await openPane(tester, 'ai');
      expect(tester.getRect(find.text('MODEL')).topLeft, offsetMoreOrLessEquals(const Offset(31.24, 122.73), epsilon: 0.5));
      expect(tester.getRect(inRow('Qwen3.5 2B', find.text('Qwen3.5 2B'))).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 288.44), epsilon: 0.75));
      expect(tester.getRect(find.byType(RowAction).first), rectNear(318.39, 297.39, 35.91, 44.63, 1));
      expect(tester.getRect(inRow('Fill blanks on their own', find.text('Fill blanks on their own'))).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 649.75), epsilon: 1.5));
      await endSettings(tester);
    });
  });

  group('Account, signed out', () {
    testWidgets('is the ghost, the way in, what a lost password means, then Privacy and Location', (tester) async {
      await openPane(tester, 'account', size: const Size(390, 2400));
      expect(find.byType(Ghost), findsOneWidget);
      expect(cardTitles(tester), ['Sign in', null, 'Privacy', 'Location']);
      expect(rowLabels(tester).take(2), ['Create an account', 'Lost the password']);
      expect(rowLabels(tester, 'Privacy'), ['Local only', 'Link previews', 'Look up blanks online', 'Privacy policy']);
      expect(rowLabels(tester, 'Location'), ['Map on a tagged note', 'Place names', 'Tag new notes with my location']);
      // With no account service the button cannot be pressed, whatever is typed.
      await tester.enterText(find.byType(EditableText).at(0), 'sam');
      await tester.enterText(find.byType(EditableText).at(1), 'correct horse');
      await tester.pump();
      expect(tester.widget<SettingsWord>(find.byKey(const ValueKey('account-submit'))).onPressed, isNull);
      await endSettings(tester);
    });

    testWidgets('signs in, makes an account and recovers one through what it is given, and shows new codes once', (tester) async {
      final asked = <String>[];
      Object? fail;
      Future<List<String>?> wayIn({required String mode, required String handle, required String password, String? code}) async {
        asked.add('$mode $handle $password ${code ?? '-'}');
        final failure = fail;
        if (failure != null) throw failure;
        return mode == 'in' ? null : ['AAAA-1111', 'BBBB-2222', 'CCCC-3333'];
      }

      await openPane(tester, 'account', size: const Size(390, 2400), features: SettingsFeatures(onWayIn: wayIn));
      Finder submit() => find.byKey(const ValueKey('account-submit'));
      expect(tester.widget<SettingsWord>(submit()).onPressed, isNull);
      await tester.enterText(find.byType(EditableText).at(0), 'sam');
      await tester.enterText(find.byType(EditableText).at(1), 'correct horse');
      await tester.pump();
      fail = 'That handle and password don’t match.';
      await tapOn(tester, submit());
      expect(asked, ['in sam correct horse -']);
      expect(find.text('That handle and password don’t match.'), findsOneWidget);
      fail = null;

      // The three rows change which way in the form is, and each leaves the other two.
      await tapOn(tester, rowCalled('Create an account'));
      expect(cardTitles(tester).first, 'New account');
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('That handle and password don’t match.'), findsNothing);
      expect(rowLabels(tester).take(2), ['I have an account', 'Lost the password']);
      await tapOn(tester, rowCalled('Lost the password'));
      expect(cardTitles(tester).first, 'Recover');
      expect(find.byType(EditableText), findsNWidgets(3));
      // A recovery wants its code too.
      expect(tester.widget<SettingsWord>(submit()).onPressed, isNull);
      await tester.enterText(find.byType(EditableText).at(1), 'CODE-9');
      await tester.pump();
      await tapOn(tester, submit());
      expect(asked.last, 'recover sam correct horse CODE-9');
      expect(cardTitles(tester), ['Recovery codes']);
      expect(find.text('BBBB-2222'), findsOneWidget);
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String?);
        return null;
      });
      await tapOn(tester, rowCalled('Copy all'));
      expect(copied, ['AAAA-1111\nBBBB-2222\nCCCC-3333']);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      await tapOn(tester, find.text("I've kept them"));
      expect(cardTitles(tester).first, 'Recover');
      await endSettings(tester);
    });

    testWidgets('keeps what leaves the phone as preferences, and Local only holds the rest off and says so', (tester) async {
      final opened = <String>[];
      var located = 0;
      await openPane(tester, 'account', size: const Size(390, 2600), onOpenLink: opened.add, features: SettingsFeatures(onLocate: () => located++));
      for (final (row, read) in <(String, bool Function(Preferences))>[
        ('Link previews', (p) => p.linkPreviews),
        ('Look up blanks online', (p) => p.lookUpBlanks),
        ('Map on a tagged note', (p) => p.mapTiles),
        ('Place names', (p) => p.placeNames),
      ]) {
        final was = read(preferences.value);
        await tapOn(tester, inRow(row, find.byType(GlacierSwitch)));
        expect(read(preferences.value), !was, reason: row);
        await tapOn(tester, inRow(row, find.byType(GlacierSwitch)));
        expect(read(preferences.value), was, reason: row);
      }
      // Tagging asks for a fix once, here, as it is switched on.
      preferences.update((now) => now.copyWith(tagNewNotes: false));
      await tester.pump();
      await tapOn(tester, inRow('Tag new notes with my location', find.byType(GlacierSwitch)));
      expect((preferences.value.tagNewNotes, located), (true, 1));
      await tapOn(tester, inRow('Tag new notes with my location', find.byType(GlacierSwitch)));
      expect((preferences.value.tagNewNotes, located), (false, 1));
      await tapOn(tester, rowCalled('Privacy policy'));
      expect(opened, [privacyUrl]);

      expect(find.byType(SettingsCallout), findsNothing);
      await tapOn(tester, inRow('Local only', find.byType(GlacierSwitch)));
      expect(preferences.value.localOnly, isTrue);
      expect(find.textContaining(' is on, so nothing syncs until it is off.'), findsOneWidget);
      expect(tester.widget<SettingRow>(rowCalled('Look up blanks online')).disabledReason, 'Local only is on, so such blanks wait.');
      expect(switchIn(tester, 'Look up blanks online').checked, isFalse);
      expect([for (final row in rowLabels(tester, 'Location')) tester.widget<SettingRow>(rowCalled(row)).disabledReason], everyElement('Local only is on.'));
      expect(find.textContaining('A tagged note shows where it was written and a pin while Local only is on'), findsOneWidget);
      // Link previews stays live under it.
      expect(rowOff(tester, 'Link previews'), isFalse);
      await back(tester);
      expect(listLine(tester, 'Account'), 'Not signed in · Local only');
      await endSettings(tester);
    });

    testWidgets('brings the Privacy card into view from the callout’s word', (tester) async {
      await openPane(tester, 'account', prefs: const Preferences(theme: 'light', localOnly: true));
      expect(tester.getRect(find.text('PRIVACY', skipOffstage: false)).top, greaterThan(844));
      await tester.tap(find.descendant(of: find.byType(GoWord), matching: find.text('Local only')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.getRect(find.text('PRIVACY')).top, inInclusiveRange(62, 800));
      await tester.pump(const Duration(seconds: 2));
      await endSettings(tester);
    });

    testWidgets('signed in, says the account’s own page is not ported, and still has Privacy and Location', (tester) async {
      await openPane(tester, 'account', size: const Size(390, 2400), features: const SettingsFeatures(signedIn: true));
      expect(find.text('Not ported yet'), findsOneWidget);
      expect(cardTitles(tester), ['Privacy', 'Location']);
      expect(accountFindable(signedIn: true), isEmpty);
      await endSettings(tester);
    });

    testWidgets('is the page’s inside the app, rect for rect', (tester) async {
      await openPane(tester, 'account', features: const SettingsFeatures(cannotLocate: 'Update Ghost.md to tag notes.'));
      expect(tester.getRect(find.byType(Ghost)), rectNear(22.31, 122.73, 345.38, 306.25, 0.75));
      expect(tester.getRect(find.text('SIGN IN')).topLeft, offsetMoreOrLessEquals(const Offset(31.24, 446.83), epsilon: 0.75));
      expect(tester.getRect(surfaceOf(cardCalled('Sign in'))), rectNear(22.31, 558.98, 345.38, 186.17, 1));
      final fields = find.byType(GlacierInput);
      expect(tester.getRect(fields.at(0)), rectNear(35.7, 572.38, 318.59, 44, 1));
      expect(tester.getRect(fields.at(1)), rectNear(35.7, 625.3, 318.59, 44, 1));
      expect(tester.getRect(find.byKey(const ValueKey('account-submit'))), rectNear(35.7, 678.22, 51.39, 53.55, 1));
      expect(tester.getRect(inRow('Create an account', find.text('Create an account'))).topLeft, offsetMoreOrLessEquals(const Offset(35.7, 776.39), epsilon: 1));
      expect(tester.getRect(find.text('PRIVACY', skipOffstage: false)).top, closeTo(996.03, 1.5));
      expect(tester.getRect(find.text('LOCATION', skipOffstage: false)).top, closeTo(1626.89, 3));
      expect(tester.getRect(find.text('Update Ghost.md to tag notes.', skipOffstage: false)).top, closeTo(2138.58, 4));
      await endSettings(tester);
    });
  });

  group('Organizations and Export', () {
    testWidgets('Organizations, signed out, is one sentence that sends the person to Account', (tester) async {
      await openPane(tester, 'organizations');
      expect(find.textContaining('Organizations come with an account. Sign in under'), findsOneWidget);
      expect(tester.getRect(find.descendant(of: find.byType(GoWord), matching: find.text('Account'))).topLeft, offsetMoreOrLessEquals(const Offset(77.36, 157.2), epsilon: 1));
      await tapOn(tester, find.descendant(of: find.byType(GoWord), matching: find.text('Account')));
      expect(display(tester), 'Account');
      await endSettings(tester);

      await openPane(tester, 'organizations', features: const SettingsFeatures(signedIn: true));
      expect(find.text('Not ported yet'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('Export is one row, which waits for the export', (tester) async {
      // With nothing handed to it: the row in the device's words, and not to be pressed. What it does once it is
      // handed the export is export_pane_test.dart's.
      await openPane(tester, 'export');
      expect(rowLabels(tester), ['Export everything']);
      expect(hintOf(tester, 'Export everything'), 'Every note, picture, film and recording, as one zip. Plug in a USB drive and choose it, or any folder.');
      expect(rowOff(tester, 'Export everything'), isTrue);
      expect(tester.getRect(inRow('Export everything', find.text('Export everything'))).topLeft, offsetMoreOrLessEquals(const Offset(78.69, 136.13), epsilon: 0.5));
      await endSettings(tester);
    });
  });

  group('the search', () {
    testWidgets('finds only names its page draws: every setting listed for a page is on that page', (tester) async {
      // The web's own rule (SettingsSheet.test.tsx): a name the search offers and the page does not draw opens the
      // page and lights nothing.
      //
      // Left out, as the web lists them all the same: the rows Recording lists on any Android phone and draws only with the
      // meeting service; and the cheat sheet's marks, which its cards draw themselves, not through the kit.
      const notDrawn = {
        // The way in the form already is has no row: "I have an account" is drawn once another way is chosen.
        'account': {'I have an account'},
        'recording': {'Include sound from other apps', 'Tell me when a meeting is written up', 'Write up straight away'},
        // Library folder draws its cards once it is handed the folder's calls (library_folder_pane_test.dart holds
        // both names to the page there); with none, as here, it is the page of a build that cannot choose.
        'library': {'Where your notes are', 'Good to know'},
      };
      for (final spec in settingsSections) {
        if (spec.pane == null || spec.id == 'cheatsheet' || spec.id == 'theme') continue;
        final developer = spec.id == 'developer' || spec.id == 'test-results';
        await openPane(tester, spec.id, size: const Size(390, 3000), developer: developer);
        expect(display(tester), spec.label);
        final screen = tester.state<SettingsScreenState>(find.byType(SettingsScreen));
        final section = screen.widget.sections.firstWhere((s) => s.id == spec.id);
        for (final setting in section.settings) {
          if (notDrawn[spec.id]?.contains(setting.name) ?? false) continue;
          final named = find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name != null && w.name!.toLowerCase().replaceAll('’', "'") == setting.name.toLowerCase().replaceAll('’', "'"), skipOffstage: false);
          expect(named, findsWidgets, reason: '${spec.label} lists "${setting.name}" for the search and does not draw it');
        }
        await endSettings(tester);
      }
    });

    testWidgets('opens a page at the setting it found, lit', (tester) async {
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}, toPage: const SettingsTarget('spec', setting: 'Front matter', nonce: 4)), settle: false);
      await tester.pump(const Duration(milliseconds: 16));
      final mark = find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name == 'Front matter', skipOffstage: false);
      expect(SettingsFindableMark.isLit(tester.widget(find.descendant(of: mark, matching: find.byKey(SettingsFindableMark.lightKey, skipOffstage: false), skipOffstage: false).first)), isTrue);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.getRect(find.text('Front matter')).top, inInclusiveRange(62, 844));
      await tester.pump(const Duration(seconds: 2));
      await endSettings(tester);
    });
  });
}
