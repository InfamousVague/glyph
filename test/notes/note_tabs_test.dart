import 'dart:ui' show SemanticsRole, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/live_titles.dart';
import 'package:ghost_md/core/tabs.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/tabs/bar_parts.dart';
import 'package:ghost_md/notes/tabs/tab_parts.dart';
import 'package:ghost_md/notes/tabs/tab_row.dart';
import 'package:ghost_md/shell/app_tab_bar.dart';
import 'package:ghost_md/shell/top_bar.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/edges.dart';
import '../support/render.dart';
import 'bar_support.dart';

/// The top bar, as `notes/NoteTabs.test.tsx` holds it, and where it is drawn: every box asserted here was measured on
/// the web app's own page (Chromium over the dev server, the invented library of seed.mjs with Weekend trip,
/// Groceries and Monday standup open) at the same window, and is held to half a pixel.
///
/// Measured before the header was condensed (Matt, 2026-10-17: "make the header of the app more condensed by
/// default"), and moved since by what that changed in the tokens, at density 1.1: the step over the bar's row went
/// from space-2 to space-1 and its rings from space-10 * 0.74 to 0.68. At 390 wide that is 8.93 to 4.46 over the row
/// and rings of 33.02 to 30.35, so the controls stand 4.46 higher, the ones after the first 2.67 nearer it for each
/// ring before them (the far group as much nearer the end), and what is under the row 4.46 + 2.67 = 7.14 higher; a
/// capsule is its rings and their gaps. In two panes the same at 1280 (10.54 to 5.27, 38.98 to 35.83: 8.43) and 840
/// (9.74 to 4.87, 36.03 to 33.12: 7.79); the Islands' one line there is the tab capsule's height, centred, so it
/// goes up by 5.27 + 3.16 / 2, and the tabs' capsule stays centred between the two that shrank.
void main() {
  setUpAll(loadAppFonts);

  const three = ['weekend', 'groceries', 'standup'];
  const trip = TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea')], of: {'groceries': 'g', 'standup': 'g'});

  Rect tab(WidgetTester tester, int at) => tester.getRect(find.byType(NoteTab).at(at));
  Tokens tokens(WidgetTester tester) => tester.element(find.byType(NoteTabs)).tokens;

  group('the top bar', () {
    testWidgets('draws nothing when it has no controls and no tabs', (tester) async {
      await pumpApp(tester, home: NoteTabs(tabs: const [], activeId: '', onOpen: (_) {}, onClose: (_) {}));
      expect(find.descendant(of: find.byType(NoteTabs), matching: find.byType(ToolRow)), findsNothing);
      expect(find.descendant(of: find.byType(NoteTabs), matching: find.byType(GlacierPressable)), findsNothing);
      await away(tester);
    });

    testWidgets('has no tab row with nothing open, and its controls still, in the middle of a bar one line tall', (tester) async {
      await pumpBar(tester, atHome: true);
      expect(find.byType(TabRow), findsNothing);
      expect(AppTabBar.heightOf(tokens(tester)), closeTo(39.28, 0.05));
      expect(named(tester, 'Home'), boxAt(13.39, 6.7, 30.35, 30.35));
      expect(named(tester, 'All your notes'), boxAt(48.2, 6.7, 30.35, 30.35));
      expect(named(tester, 'Back to where you were'), boxAt(83.02, 6.7, 30.35, 30.35));
      expect(named(tester, 'Forward again'), boxAt(117.83, 6.7, 30.35, 30.35));
      expect(named(tester, 'Organizations'), boxAt(267.71, 6.7, 30.35, 30.35));
      expect(named(tester, 'Notifications'), boxAt(302.53, 6.7, 30.35, 30.35));
      expect(named(tester, 'Settings'), boxAt(337.34, 6.7, 30.35, 30.35));
      await away(tester);
    });

    testWidgets('answers each control with its own doing, and leaves a dead arrow dead', (tester) async {
      final log = await pumpBar(tester, open: const ['weekend'], canGoBack: true, aside: true, kept: true);
      for (final label in ['Home', 'All your notes', 'Back to where you were', 'Forward again', 'Organizations', 'Notifications', 'Settings', 'Side panel']) {
        await tester.tap(find.bySemanticsLabel(label), warnIfMissed: false);
        await tester.pump();
      }
      // A new note under the ••• after the sidebar's icon (Matt, 2026-10-29: "Put the all files folder icon under the
      // more menu as well as the + button in the header").
      await tester.tap(find.bySemanticsLabel('More: all notes by folder, a new note'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('New note'));
      await tester.pump();
      // Nowhere forward to go: still there, so the row never changes width, but plainly dead.
      expect(log.said, ['home', 'sidebar', 'back', 'organizations', 'notifications', 'settings', 'aside', 'new']);
      await away(tester);
    });

    testWidgets('opens a tab on a tap, closes it on its cross, and marks the one being read', (tester) async {
      final handle = tester.ensureSemantics();
      final log = await pumpBar(tester, open: three, active: 'groceries');
      await tester.tap(find.bySemanticsLabel('Weekend trip'));
      await tester.tap(find.bySemanticsLabel('Close Groceries'));
      expect(log.said, ['open weekend', 'close groceries']);
      final read = tester.getSemantics(find.bySemanticsLabel('Groceries, in Home')).getSemanticsData();
      final behind = tester.getSemantics(find.bySemanticsLabel('Weekend trip')).getSemanticsData();
      expect(read.role, SemanticsRole.tab);
      expect(read.flagsCollection.isSelected, Tristate.isTrue);
      expect(behind.flagsCollection.isSelected, Tristate.isFalse);
      // The row is a group with a name; the pill is a colour to the eye and the workspace's name to a reader.
      expect(find.bySemanticsLabel('Notes you have open'), findsOneWidget);
      expect(find.bySemanticsLabel('Monday standup, in Work'), findsOneWidget);
      handle.dispose();
      await away(tester);
    });

    testWidgets('rings a bell that says when something is new, with a gold dot at its shoulder', (tester) async {
      await pumpBar(tester, open: three, unread: true);
      expect(find.bySemanticsLabel('Notifications, something new'), findsOneWidget);
      final bell = named(tester, 'Notifications, something new');
      // `.bell[data-unread]::after`: 6px, six in from the top and the end.
      final dot = find.descendant(of: find.bySemanticsLabel('Notifications, something new'), matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 6));
      expect(tester.getRect(dot), Rect.fromLTWH(bell.right - 12, bell.top + 6, 6, 6));
      await away(tester);
      await pumpBar(tester, open: three);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications, something new'), findsNothing);
      await away(tester);
    });

    testWidgets('steps the people icon, the bell and the cog out when it is told to be quiet, a phone reading a note', (tester) async {
      await pumpBar(tester, open: three, active: 'weekend', quiet: true);
      for (final label in ['Organizations', 'Notifications', 'Settings']) {
        expect(find.bySemanticsLabel(label), findsNothing);
      }
      expect(find.bySemanticsLabel('Home'), findsOneWidget);
      await away(tester);
    });

    testWidgets('opens a picker of your organizations from the people icon, a pick going straight to its dashboard', (tester) async {
      const orgs = [OrgLike(id: 'o1', name: 'Attic Press', hue: 'moss'), OrgLike(id: 'o2', name: 'Field notes')];
      final log = await pumpBar(tester, open: three, organizations: orgs);
      await tester.tap(find.bySemanticsLabel('Organizations'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ORGANIZATIONS'), findsOneWidget);
      expect(find.bySemanticsLabel('Choose an organization'), findsOneWidget);
      await tester.tap(find.text('Attic Press'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said, ['organization o1']);
      expect(find.text('Field notes'), findsNothing);
      // The last row is the whole list in Settings.
      await tester.tap(find.bySemanticsLabel('Organizations'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('All organizations…'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said, ['organization o1', 'organizations']);
      await away(tester);
    });

    testWidgets('closes the organizations’ picker on the back gesture, a second press on the icon, and a press anywhere else', (tester) async {
      const orgs = [OrgLike(id: 'o1', name: 'Attic Press', hue: 'moss')];
      final log = await pumpBar(tester, open: three, organizations: orgs);
      Future<void> open() async {
        await tester.tap(find.bySemanticsLabel('Organizations').first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Attic Press'), findsOneWidget);
      }

      Future<void> gone() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Attic Press'), findsNothing);
      }

      await open();
      expect(backStack.goBack(), isTrue);
      await gone();
      // The gesture was the picker's alone: nothing else is on the stack.
      expect(backStack.depth, 0);
      await open();
      await tester.tap(find.bySemanticsLabel('Organizations').first);
      await gone();
      await open();
      await tester.tapAt(const Offset(60, 600));
      await gone();
      expect(log.said, isEmpty);
      await away(tester);
    });

    testWidgets('goes to Settings from the people icon when you belong to no organization yet', (tester) async {
      final log = await pumpBar(tester, open: three);
      await tester.tap(find.bySemanticsLabel('Organizations'));
      await tester.pump();
      expect(log.said, ['organizations']);
      await away(tester);
    });

    testWidgets('moves a tab by the arrow keys only with the platform’s modifier', (tester) async {
      final log = await pumpBar(tester, open: three);
      final pressable = find.descendant(of: find.byType(NoteTab).at(1), matching: find.byType(GlacierPressable)).first;
      Future<void> focus() async {
        Focus.of(tester.element(find.descendant(of: pressable, matching: find.byType(GestureDetector)).first)).requestFocus();
        await tester.pump();
      }

      await focus();
      // A bare arrow is the keyboard's own way about the page, and moves no tab.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(log.said, isEmpty);
      await focus();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(log.said, ['move groceries 2', 'move groceries 0']);
      // Enter opens it, as a press does.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log.said.last, 'open groceries');
      await away(tester);
    });

    testWidgets('holds the screen’s own controls in its slot, pushed to the far end, and its More after the cog', (tester) async {
      await pumpBar(
        tester,
        open: three,
        tools: const SizedBox(key: ValueKey('tools'), width: 65.16, height: 30.35),
        tail: const SizedBox(key: ValueKey('more'), width: 30.35, height: 30.35),
      );
      // Measured with a note's two tools in the slot and its More in the tail: the people icon, the bell and the cog
      // sit between them.
      expect(tester.getRect(find.byKey(const ValueKey('more'))), boxAt(337.34, 4.46, 30.35, 30.35));
      expect(named(tester, 'Settings').left, closeTo(302.53, 0.5));
      expect(tester.getRect(find.byKey(const ValueKey('tools'))).right, closeTo(named(tester, 'Organizations').left - tokens(tester).space(1), 0.01));
      await away(tester);
    });
  });

  group('a tab’s title', () {
    testWidgets('says what the open note’s editor has in line 1 as it is written, and the note’s own once that is newer', (tester) async {
      final live = LiveTitles();
      var note = makeNote('n', body: '', updatedAt: 1000);
      Future<void> draw() => pumpApp(
            tester,
            home: SizedBox(height: 92, child: NoteTabs(tabs: [note], activeId: 'n', onOpen: (_) {}, onClose: (_) {}, liveTitles: live)),
          );
      await draw();
      expect(find.bySemanticsLabel('Untitled'), findsOneWidget);
      live.set('n', 'Shopping', at: 2000);
      await tester.pump();
      expect(find.bySemanticsLabel('Shopping'), findsOneWidget);
      // A rename that arrives by sync afterwards wins.
      note = makeNote('n', body: '# Groceries', updatedAt: 3000);
      await draw();
      expect(find.bySemanticsLabel('Groceries'), findsOneWidget);
      await away(tester);
    });
  });

  group('the bar’s styles', () {
    testWidgets('is Classic unless told otherwise: the controls, then the tabs standing on the bar’s foot, every tab with its cross', (tester) async {
      await pumpBar(tester, open: three, atHome: true);
      expect(AppTabBar.heightOf(tokens(tester)), closeTo(84.67, 0.05));
      expect(named(tester, 'Home'), boxAt(13.39, 4.46, 30.35, 30.35));
      expect(named(tester, 'Organizations'), boxAt(267.71, 4.46, 30.35, 30.35));
      expect(named(tester, 'Settings'), boxAt(337.34, 4.46, 30.35, 30.35));
      expect(tester.getRect(find.byType(TabRow)), boxAt(0, 42.78, 390, 41.89));
      expect(tab(tester, 0), boxAt(13.39, 43.75, 151, 40.92));
      expect(tab(tester, 1), boxAt(166.39, 42.78, 194.23, 41.89));
      expect(tab(tester, 2), boxAt(362.63, 42.78, 243.08, 41.89));
      expect(named(tester, 'Weekend trip'), boxAt(14.39, 48.91, 117.78, 31.59));
      expect(named(tester, 'Groceries, in Home'), boxAt(167.39, 43.78, 161.02, 40.89));
      expect(tester.getRect(find.byType(SpacePill).first), boxAt(180.78, 49.58, 60.92, 29.3));
      expect(named(tester, 'Close Weekend trip'), boxAt(132.17, 51.33, 26.77, 26.77));
      // No + after the tabs: a new note is under the bar's ••• (Matt, 2026-10-29).
      expect(find.bySemanticsLabel('New note in a new tab'), findsNothing);
      expect(find.byTooltip('x'), findsNothing);
      for (final title in ['Weekend trip', 'Groceries', 'Monday standup']) {
        expect(find.bySemanticsLabel('Close $title'), findsOneWidget);
      }
      await away(tester);
    });

    testWidgets('as the Ledger puts the tabs first, with Home pinned in the row, and the row there with nothing open', (tester) async {
      await pumpBar(tester, style: TopBarStyle.ledger, open: three, atHome: true);
      expect(AppTabBar.heightOf(tokens(tester)), closeTo(84.67, 0.05));
      expect(tester.getRect(find.byType(HomeTab)), boxAt(13.39, 4.21, 40.92, 40.92));
      expect(tab(tester, 0), boxAt(56.31, 4.21, 119.78, 40.92));
      // A tab that wears a pill is a pixel taller than the row is made, and stands on the row's line.
      expect(tab(tester, 1), boxAt(178.09, 3.24, 163.02, 41.89));
      expect(named(tester, 'All your notes'), boxAt(13.39, 51.59, 30.35, 30.35));
      expect(named(tester, 'Back to where you were'), boxAt(48.2, 51.59, 30.35, 30.35));
      expect(named(tester, 'Organizations'), boxAt(267.71, 51.59, 30.35, 30.35));
      expect(named(tester, 'Settings'), boxAt(337.34, 51.59, 30.35, 30.35));
      // No + after the tabs: a new note is under the bar's ••• (Matt, 2026-10-29).
      expect(find.bySemanticsLabel('New note in a new tab'), findsNothing);
      // The cross is the open tab's alone.
      expect(find.bySemanticsLabel(RegExp('^Close ')), findsNothing);
      await away(tester);
      await pumpBar(tester, style: TopBarStyle.ledger, open: three, active: 'groceries');
      expect(named(tester, 'Close Groceries'), boxAt(340.11, 11.31, 26.77, 26.77));
      expect(find.bySemanticsLabel('Close Weekend trip'), findsNothing);
      await away(tester);
      // The row is always there, so Home always is.
      final log = await pumpBar(tester, style: TopBarStyle.ledger);
      expect(find.byType(TabRow), findsOneWidget);
      expect(AppTabBar.heightOf(tokens(tester)), closeTo(84.67, 0.05));
      await tester.tap(find.byType(HomeTab));
      expect(log.said, ['home']);
      await away(tester);
    });

    testWidgets('as the Masthead says Home, Notes and Back as words, and draws the tabs as an index line', (tester) async {
      await pumpBar(tester, style: TopBarStyle.masthead, open: three, atHome: true);
      expect(named(tester, 'Home'), boxAt(13.39, 4.46, 63.05, 30.35));
      expect(named(tester, 'All your notes'), boxAt(80.89, 4.46, 62.88, 30.35));
      expect(named(tester, 'Back to where you were'), boxAt(148.22, 4.46, 76.08, 30.35));
      expect(named(tester, 'Organizations'), boxAt(233.2, 4.46, 68.41, 30.35));
      // The words come to more than a narrow phone's line: the last rings run past its end rather than shrinking.
      expect(named(tester, 'Notifications'), boxAt(306.06, 4.46, 30.35, 30.35));
      expect(named(tester, 'Settings'), boxAt(340.87, 4.46, 30.35, 30.35));
      expect(find.text('Teams'), findsOneWidget);
      // Forward only when there is somewhere forward to go.
      expect(find.bySemanticsLabel('Forward again'), findsNothing);
      expect(tester.getRect(find.byType(TabRow)), boxAt(0, 43.75, 390, 40.92));
      expect(tab(tester, 0), boxAt(13.39, 43.75, 103.94, 40.92));
      expect(tab(tester, 1), boxAt(135.17, 43.75, 147.17, 40.92));
      expect(tab(tester, 2), boxAt(300.19, 43.75, 196.02, 40.92));
      // No + after the tabs: a new note is under the bar's ••• (Matt, 2026-10-29).
      expect(find.bySemanticsLabel('New note in a new tab'), findsNothing);
      await away(tester);
      final log = await pumpBar(tester, style: TopBarStyle.masthead, open: three, active: 'groceries', canGoOn: true, canGoBack: true);
      await tester.tap(find.bySemanticsLabel('Forward again'));
      expect(log.said, ['on']);
      expect(tab(tester, 1), boxAt(135.17, 43.75, 178.39, 40.92));
      await away(tester);
    });

    testWidgets('as the Islands floats three capsules: the way around, the tabs, and the screen’s own', (tester) async {
      await pumpBar(tester, style: TopBarStyle.islands, open: three, atHome: true);
      expect(AppTabBar.heightOf(tokens(tester)), closeTo(100.67, 0.05));
      final capsules = find.byType(BarCapsule);
      expect(tester.getRect(capsules.at(0)), boxAt(13.39, 6.48, 135.39, 38.35));
      expect(tester.getRect(capsules.at(1)), boxAt(262.65, 6.48, 105.04, 38.35));
      expect(named(tester, 'Home'), boxAt(17.39, 10.48, 30.35, 30.35));
      expect(named(tester, 'Forward again'), boxAt(114.43, 10.48, 30.35, 30.35));
      expect(named(tester, 'Organizations'), boxAt(268.65, 10.48, 30.35, 30.35));
      expect(named(tester, 'Settings'), boxAt(333.34, 10.48, 30.35, 30.35));
      // The tabs' capsule on a line of its own on a phone.
      expect(tester.getRect(find.byType(TabRow)), boxAt(13.39, 53.74, 354.3, 44.92));
      expect(tab(tester, 0), boxAt(23.31, 57.74, 117.78, 36.92));
      expect(tab(tester, 1), boxAt(145.55, 57.74, 161.02, 36.92));
      expect(tester.getRect(find.byType(SpacePill).first), boxAt(158.94, 61.55, 60.92, 29.3));
      // No + after the tabs: a new note is under the bar's ••• (Matt, 2026-10-29).
      expect(find.bySemanticsLabel('New note in a new tab'), findsNothing);
      await away(tester);
      // With nothing open the bar is one line.
      await pumpBar(tester, style: TopBarStyle.islands, atHome: true);
      expect(AppTabBar.heightOf(tokens(tester)), closeTo(47.27, 0.05));
      expect(tester.getRect(find.byType(BarCapsule).at(0)), boxAt(13.39, 6.7, 135.39, 38.35));
      expect(tester.getRect(find.byType(BarCapsule).at(1)), boxAt(262.65, 6.7, 105.04, 38.35));
      await away(tester);
    });
  });

  group('on a window in two panes', () {
    testWidgets('the Classic bar is glass from the window’s top edge, its rings a size up, the tabs its bottom edge', (tester) async {
      await pumpBar(tester, open: three, groups: trip, atHome: true, size: const Size(1280, 800), split: true, fine: true);
      final t = tokens(tester);
      expect(AppTabBar.heightOf(t) - notch, closeTo(96.24, 0.05));
      expect(tester.getTopLeft(find.byType(AppTabBar)).dy, 0);
      expect(named(tester, 'Home'), boxAt(15.8, 5.27, 35.83, 35.83));
      expect(named(tester, 'All your notes'), boxAt(62.16, 5.27, 35.83, 35.83));
      expect(named(tester, 'Organizations'), boxAt(1125.12, 5.27, 35.83, 35.83));
      expect(named(tester, 'Settings'), boxAt(1217.85, 5.27, 35.83, 35.83));
      expect(tab(tester, 0), boxAt(15.8, 50.63, 168.22, 44.61));
      expect(tester.getRect(find.byType(GroupChip)), boxAt(188.02, 59.7, 61.47, 25.5));
      expect(tab(tester, 1), boxAt(253.48, 49.66, 214.2, 45.58));
      expect(tab(tester, 2), boxAt(469.69, 49.66, 267.31, 45.58));
      // No + after the tabs: a new note is under the bar's ••• (Matt, 2026-10-29).
      expect(find.bySemanticsLabel('New note in a new tab'), findsNothing);
      // The row fits, so neither end fades.
      expect(find.byType(BlurSides), findsNothing);
      await away(tester);
      // With nothing open the bar keeps its hairline and the air over it.
      await pumpBar(tester, atHome: true, size: const Size(1280, 800), split: true, fine: true);
      expect(AppTabBar.heightOf(tokens(tester)) - notch, closeTo(56.9, 0.05));
      await away(tester);
    });

    testWidgets('the opened Fold’s bar is the same bar at its own size', (tester) async {
      await pumpBar(tester, open: three, active: 'groceries', quiet: true, canGoBack: true, size: const Size(840, 900), split: true);
      expect(AppTabBar.heightOf(tokens(tester)) - notch, closeTo(90.52, 0.05));
      expect(named(tester, 'Home'), boxAt(14.61, 4.86, 33.12, 33.12));
      expect(named(tester, 'All your notes'), boxAt(57.47, 4.86, 33.12, 33.12));
      expect(tab(tester, 0), boxAt(14.61, 46.74, 159.73, 42.78));
      expect(tab(tester, 1), boxAt(176.34, 45.76, 204.36, 43.77));
      // No + after the tabs: a new note is under the bar's ••• (Matt, 2026-10-29).
      expect(find.bySemanticsLabel('New note in a new tab'), findsNothing);
      await away(tester);
    });

    testWidgets('the Islands’ three capsules share one line, the tabs between the other two', (tester) async {
      await pumpBar(tester, style: TopBarStyle.islands, open: three, groups: trip, atHome: true, size: const Size(1280, 800), split: true, fine: true);
      expect(AppTabBar.heightOf(tokens(tester)) - notch, closeTo(64.9, 0.05));
      expect(tester.getRect(find.byType(BarCapsule).at(0)), boxAt(15.8, 5.01, 157.32, 43.82));
      expect(tester.getRect(find.byType(TabRow)), boxAt(300.65, 5.01, 704, 48.61));
      expect(tester.getRect(find.byType(BarCapsule).at(1)), boxAt(1132.18, 5.01, 121.49, 43.82));
      expect(tab(tester, 0), boxAt(312.19, 9.01, 129.34, 40.61));
      expect(tester.getRect(find.byType(GroupChip)), boxAt(448.8, 16.56, 61.47, 25.5));
      await away(tester);
      // More tabs than fit, on the opened Fold: still one line, the tabs' capsule taking the room there is. (The
      // page's own line broke here, its third capsule wrapping under the first.)
      await pumpBar(tester, style: TopBarStyle.islands, open: three, active: 'groceries', quiet: true, size: const Size(840, 900), split: true, tail: const SizedBox(width: 36, height: 36));
      final way = tester.getRect(find.byType(BarCapsule).at(0)), own = tester.getRect(find.byType(BarCapsule).at(1)), row = tester.getRect(find.byType(TabRow));
      expect(way.top, own.top);
      expect(row.top, way.top);
      expect(row.left, greaterThan(way.right));
      expect(row.right, lessThan(own.left));
      expect(own.right, closeTo(840 - 24.34, 0.5));
      await away(tester);
    });
  });

  group('a group’s chip', () {
    testWidgets('stands before its first tab in its colour, says how many tabs it holds, and folds them away on a tap', (tester) async {
      final log = await pumpBar(tester, open: three, groups: trip, atHome: true);
      expect(tester.getRect(find.byType(GroupChip)), boxAt(168.39, 51.7, 58.11, 24.03));
      expect(tab(tester, 1), boxAt(230.5, 42.78, 194.23, 41.89));
      expect(find.bySemanticsLabel('Trip, 2 tabs'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Trip, 2 tabs'));
      expect(log.said, ['groups Trip:sea:folded {groceries: g, standup: g}']);
      await away(tester);
      // A folded group draws only its chip, the size it was, in a row still a tab tall.
      await pumpBar(tester, open: three, groups: toggleGroup(trip, 'g'), atHome: true);
      expect(find.byType(NoteTab), findsOneWidget);
      expect(find.bySemanticsLabel('Trip, 2 tabs, folded'), findsOneWidget);
      expect(tester.getRect(find.byType(GroupChip)), boxAt(168.39, 52.19, 58.11, 24.03));
      expect(tester.getRect(find.byType(TabRow)), boxAt(0, 43.75, 390, 40.92));
      // No + after the tabs: a new note is under the bar's ••• (Matt, 2026-10-29).
      expect(find.bySemanticsLabel('New note in a new tab'), findsNothing);
      await away(tester);
    });

    testWidgets('offers its colours in place under their name, ungrouping, and closing every tab it holds', (tester) async {
      final log = await pumpBar(tester, open: three, groups: trip);
      await tester.longPress(find.bySemanticsLabel('Trip, 2 tabs'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('Trip group'), findsOneWidget);
      expect(find.text('COLOUR'), findsOneWidget);
      for (final hue in ['Ink', 'Ember', 'Amber', 'Moss', 'Sea', 'Violet', 'Rose']) {
        expect(find.bySemanticsLabel('Colour: $hue'), findsOneWidget);
      }
      await tester.tap(find.text('Violet'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said, ['groups Trip:violet {groceries: g, standup: g}']);
      expect(find.text('Violet'), findsNothing);
      await tester.longPress(find.bySemanticsLabel('Trip, 2 tabs'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Close group'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said.last, 'close tabs [groceries, standup]');
      await tester.longPress(find.bySemanticsLabel('Trip, 2 tabs'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ungroup'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said.last, 'groups  {}');
      await away(tester);
    });

    testWidgets('flies its colours out for a mouse on a wide window, from a right-click', (tester) async {
      await pumpBar(tester, open: three, groups: trip, size: const Size(1280, 800), split: true, fine: true);
      await tester.tap(find.bySemanticsLabel('Trip, 2 tabs'), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 300));
      // One row under the menu's own name, and no colours until it is opened.
      expect(find.text('Colour'), findsOneWidget);
      expect(find.text('Violet'), findsNothing);
      await tester.tap(find.text('Colour'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Violet'), findsOneWidget);
      // A mouse keeps the kit's rows.
      expect(tester.getSize(find.ancestor(of: find.text('Ungroup'), matching: find.byType(GlacierMenuItem))).height, closeTo(42.31, 0.5));
      await away(tester);
    });

    testWidgets('is renamed in place: Enter keeps the words, Escape the name it had', (tester) async {
      final log = await pumpBar(tester, open: three, groups: trip, size: const Size(1280, 800), split: true, fine: true);
      Future<void> rename() async {
        await tester.tap(find.bySemanticsLabel('Trip, 2 tabs'), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Rename'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
      }

      await rename();
      expect(find.bySemanticsLabel('Group name'), findsOneWidget);
      // `.groupName { inline-size: 8rem }`, a line of the chip's type inside its padding and ring.
      expect(tester.getRect(find.byType(GroupChip)), boxAt(188.02, 59.41, 128, 26.06));
      await tester.enterText(find.byType(EditableText), 'Weekend away');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log.said, ['groups Weekend away:sea {groceries: g, standup: g}']);
      expect(find.byType(EditableText), findsNothing);
      await rename();
      await tester.enterText(find.byType(EditableText), 'Nothing');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(log.said.last, 'groups Trip:sea {groceries: g, standup: g}');
      await away(tester);
    });
  });

  group('a tab’s menu', () {
    testWidgets('opens when a finger holds a tab and lets go where it was, and the tap that ends it opens nothing', (tester) async {
      final log = await pumpBar(tester, open: three, active: 'weekend', groups: const TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea'), TabGroup(id: 'h', name: 'Work things', hue: 'moss')], of: {'groceries': 'g', 'standup': 'h'}));
      await tester.longPress(find.bySemanticsLabel('Weekend trip'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said, isEmpty);
      expect(find.bySemanticsLabel('Weekend trip tab'), findsOneWidget);
      // Under a finger: a thumb's height, the + list's type, the groups listed in place under their name.
      final row = find.ancestor(of: find.text('Close tab'), matching: find.byType(GlacierMenuItem));
      expect(tester.getSize(row).height, closeTo(44, 0.01));
      expect(tester.getSize(row).width, closeTo(181.09, 0.5));
      expect(find.text('ADD TO GROUP'), findsOneWidget);
      expect(find.bySemanticsLabel('Add to Trip'), findsOneWidget);
      expect(find.bySemanticsLabel('Add to Work things'), findsOneWidget);
      // Not in a group, so nothing to be taken out of; a note, so nothing to rename.
      expect(find.text('Remove from group'), findsNothing);
      expect(find.text('Rename'), findsNothing);
      // Delete in the app's one red.
      final t = tokens(tester);
      expect(tester.widget<DefaultTextStyle>(find.ancestor(of: find.text('Delete note'), matching: find.byType(DefaultTextStyle)).first).style.color, t.color('glacier-red-11'));
      await tester.tap(find.bySemanticsLabel('Add to Trip'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said, ['groups Trip:sea,Work things:moss {groceries: g, standup: h, weekend: g}']);
      expect(find.text('Close tab'), findsNothing);
      await away(tester);
    });

    testWidgets('opens on a mouse’s right-click, and not for a mouse held and let go in place', (tester) async {
      final log = await pumpBar(tester, open: [...three, 'cabin-canvas'], active: 'groceries', groups: trip, size: const Size(1280, 800), split: true, fine: true);
      final gesture = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Weekend trip')), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('Weekend trip tab'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Groceries, in Home'), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('Groceries tab'), findsOneWidget);
      // In a group: it can be taken out, and there is no other group to add it to.
      expect(find.text('Remove from group'), findsOneWidget);
      expect(find.text('Add to group'), findsNothing);
      // The menu hangs from the foot of the tab, 8px under it: the page's panel stood at [254, 112], its first row
      // inside the panel's padding and hairline at [260.27, 118.27 179.47x42.31], before the bar was 8.43 shorter
      // here. The kit puts a panel on a whole pixel, and the tab's foot is half a pixel from two of them.
      await tester.pump(const Duration(milliseconds: 300));
      final first = tester.getRect(find.ancestor(of: find.text('Add to a new group'), matching: find.byType(GlacierMenuItem)));
      expect(first.left, closeTo(260.27, 1.1));
      expect(first.top, closeTo(118.27 - 8.43 + notch, 1.1));
      expect(first.size.width, closeTo(179.47, 0.5));
      expect(first.size.height, closeTo(42.31, 0.5));
      await tester.tap(find.text('Close tab'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Groceries, in Home'), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Delete note'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said, ['close groceries', 'delete groceries']);
      await away(tester);
    });

    testWidgets('renames a canvas: Enter and leaving the field keep the words, Escape and the same name keep nothing', (tester) async {
      const two = TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea'), TabGroup(id: 'h', name: 'Work things', hue: 'moss')], of: {'groceries': 'g', 'standup': 'h'});
      final log = await pumpBar(tester, open: [...three, 'cabin-canvas'], groups: two, size: const Size(1280, 800), split: true, fine: true);
      const was = 'Cabin weekend, laid out';
      Future<void> rename() async {
        await tester.tap(find.bySemanticsLabel(was), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Rename'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.bySemanticsLabel('Canvas name'), findsOneWidget);
        // `autoFocus`: the caret is in it and the keyboard asked for, though the menu that made it had the focus.
        expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      }

      await rename();
      // The field stands where the name stood, a browser's field of twenty characters wide: [863.22, 64.52 218.06x34.69].
      final field = tester.getRect(find.byType(EditableText));
      expect(field.left, closeTo(863.22 + 15.81, 0.6));
      expect(field.width, closeTo(218.06 - 15.81 - 5.27, 0.6));
      await tester.enterText(find.byType(EditableText), '  The cabin  ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log.said, ['rename cabin-canvas The cabin']);
      await rename();
      await tester.enterText(find.byType(EditableText), 'Somewhere else');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(log.said, hasLength(1));
      // The same name is no rename.
      await rename();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log.said, hasLength(1));
      // Leaving the field keeps the words.
      await rename();
      await tester.enterText(find.byType(EditableText), 'Left behind');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(log.said.last, 'rename cabin-canvas Left behind');
      await away(tester);
    });

    testWidgets('closes on the back gesture, and leaves the gesture to nothing else', (tester) async {
      final log = await pumpBar(tester, open: three);
      await tester.longPress(find.bySemanticsLabel('Weekend trip'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Close tab'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Close tab'), findsNothing);
      expect(log.said, isEmpty);
      await away(tester);
    });
  });

  group('dragging a tab', () {
    testWidgets('pans the row rather than moving a tab until the press has been held, and the pan opens nothing', (tester) async {
      final log = await pumpBar(tester, open: three);
      final before = tab(tester, 0).left;
      await tester.drag(find.bySemanticsLabel('Groceries, in Home'), const Offset(-120, 0));
      await tester.pump();
      expect(tab(tester, 0).left, lessThan(before - 60));
      expect(log.said, isEmpty);
      await away(tester);
    });

    testWidgets('carries a held tab to the place the pointer has passed, and into the group it is over', (tester) async {
      final log = await pumpBar(tester, open: three, groups: const TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea')], of: {'groceries': 'g'}));
      final from = tester.getCenter(find.bySemanticsLabel('Weekend trip'));
      final over = tester.getCenter(find.bySemanticsLabel('Groceries, in Home'));
      final gesture = await tester.startGesture(from);
      await tester.pump(holdTime + const Duration(milliseconds: 40));
      // Held, and not yet carried anywhere: nothing has moved.
      expect(log.said, isEmpty);
      await gesture.moveTo(over + const Offset(30, 0));
      await tester.pump();
      // Past Groceries' middle, and over a tab of the group: in it, and after it.
      expect(log.said, ['groups Trip:sea {groceries: g, weekend: g}', 'move weekend 1 grouped']);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      // A tab carried is not a tab held: no menu.
      expect(find.text('Close tab'), findsNothing);
      await away(tester);
    });

    testWidgets('takes a tab into a folded group only when it is let go, counting the chip as every tab it holds', (tester) async {
      final folded = TabGroups(list: [const TabGroup(id: 'g', name: 'Trip', hue: 'sea', collapsed: true)], of: const {'groceries': 'g', 'standup': 'g'});
      final log = await pumpBar(tester, open: three, groups: folded);
      final gesture = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Weekend trip')));
      await tester.pump(holdTime + const Duration(milliseconds: 40));
      await gesture.moveTo(tester.getCenter(find.byType(GroupChip)) + const Offset(10, 0));
      await tester.pump();
      expect(log.said, ['move weekend 2 grouped']);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said.last, 'groups Trip:sea:folded {groceries: g, standup: g, weekend: g}');
      await away(tester);
    });

    testWidgets('never picks a tab up by its cross', (tester) async {
      final log = await pumpBar(tester, open: three);
      final gesture = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Close Weekend trip')));
      await tester.pump(holdTime + const Duration(milliseconds: 40));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(log.said.where((line) => line.startsWith('move')), isEmpty);
      expect(find.text('Close tab'), findsNothing);
      await away(tester);
    });
  });

  group('the outline of the tab being read', () {
    // The ends go soft, where the page's go into smoke (art/wispSides.ts over NoteTabs.module.css's 12px fade): seen
    // beside Ghost.md on the owner's phone, 2026-10-11, the last tab's letters faded at the window's edge there
    // ("HelloTr") and cut plain here ("HelloTra"), the row having worn the fade alone. Since 2026-10-24 a gradient
    // blur, where it was the wisp's smoke (Matt: "replace the smoke effect with a gradient blur on all places that
    // use the wisp smoke").
    testWidgets('blurs whichever end of the row has tabs past it, and never the start at the start', (tester) async {
      List<EdgeBlurStrip> blurs() => edgeStripsUnder(tester, find.byType(BlurSides)).whereType<EdgeBlurStrip>().toList();
      await pumpBar(tester, open: three, active: 'groceries');
      // Three tabs are more than a phone's width: the end blurs over a fade of twelve pixels under a finger.
      expect(find.byType(BlurSides), findsOneWidget);
      final row = tester.widget<TabRow>(find.byType(TabRow));
      expect(row.fade, 12);
      expect(blurs(), hasLength(1));
      expect(blurs().single.side, EdgeSide.right, reason: 'nothing is out of sight at the start');
      // The twelve pixels are the fade the blur's strips and Android's bands are laid over; this engine blurs
      // nothing, and the end it draws fades over the blur's whole depth (2026-10-27, lib/art/blur_box.dart
      // fadedEnds), so a tab cut off by the row's end is not crisp up to the last twelve.
      expect(blurs().single.fade!.clearFrom - blurs().single.fade!.wholeUntil, blurSidesDepth);
      await tester.drag(find.bySemanticsLabel('Groceries, in Home'), const Offset(-2000, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(BlurSides), findsOneWidget);
      expect(blurs().single.side, EdgeSide.left, reason: 'scrolled to its end, the row goes on past its start');
      await away(tester);
      // A row that fits fades at neither end.
      await pumpBar(tester, open: const ['weekend']);
      expect(find.byType(BlurSides), findsNothing);
      await away(tester);
    });

    testWidgets('is the line the tabs stand on, mixed opaque from the page’s ink and paper, and the Masthead’s is the page’s rule', (tester) async {
      await pumpBar(tester, open: three, active: 'groceries');
      final t = tokens(tester);
      expect(tester.widget<TabRow>(find.byType(TabRow)).lineColor, t.colorOf('color-mix(in oklch, var(--app-ink) 22%, var(--app-paper))'));
      expect(tester.widget<TabRow>(find.byType(TabRow)).lineColor!.a, 1);
      await away(tester);
      await pumpBar(tester, style: TopBarStyle.masthead, open: three);
      expect(tester.widget<TabRow>(find.byType(TabRow)).lineColor, tokens(tester).color('app-rule'));
      await away(tester);
      await pumpBar(tester, style: TopBarStyle.islands, open: three);
      expect(tester.widget<TabRow>(find.byType(TabRow)).lineColor, isNull);
      await away(tester);
    });
  });
}
