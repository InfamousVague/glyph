import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/tabs/tab_parts.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/app_tab_bar.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/shell/wide_screen.dart' show simpleListColumn;
import 'package:ghost_md/simple/simple_pane.dart';
import 'package:glacier/glacier.dart';

import '../notes/bar_support.dart';
import '../support/header_bar.dart';
import '../support/render.dart';

/// Simple mode's plain shell (GHST-105; Matt, 2026-10-18: "The simple mode in the app is not quite right, it still
/// is a bit complex with the tabs and such"): no bar and no tabs over a place, no drawer, no aside; a note opened
/// takes the one tab there is and leaves it on the way home, so the row never holds more than the note showing; the
/// phone's back gesture still leaves a note; and a wide window is the list beside the note. Advanced is as it was
/// (test/shell/app_shell_test.dart), with every control from the same shell.
///
/// Until GHST-105 this file (as simple_bar_test.dart) held simple mode to a trimmed bar: Home, the sidebar, Back
/// and the cog kept, the tabs with no groups. There is no bar in simple mode now, so those cases are gone.
void main() {
  setUpAll(loadAppFonts);

  final kept = <String>[];
  setUp(kept.clear);

  Future<AppShellState> shell(
    WidgetTester tester, {
    required bool simple,
    List<String> open = const [],
    Screen initial = const Screen.list(),
    Size size = const Size(390, 844),
    bool mobile = true,
    bool fine = false,
    BackStack? stack,
    ShellBuilder? emptyPaneBuilder,
  }) async {
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      size: size,
      prefs: const Preferences(theme: 'light'),
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        openNotes: open,
        simple: simple,
        mobile: mobile,
        finePointer: fine,
        backStack: stack ?? BackStack(),
        initialScreen: initial,
        // An aside for the stand-in note, which simple mode leaves out.
        asideBuilder: (context, shell) => const SizedBox(key: ValueKey('an-aside')),
        emptyPaneBuilder: emptyPaneBuilder,
        onSettings: () {},
        onOrganizations: () {},
        onNew: () {},
        onDeleteNote: (_) {},
        onOpenNotesChanged: (ids) => kept.add('open $ids'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return tester.state<AppShellState>(find.byType(AppShell));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Map<String, String> stamps(WidgetTester tester, Finder under) => tester.element(under).tokens.attrs;

  testWidgets('draws no bar, no tabs and no drawer over a place, so the page starts under the notch alone', (tester) async {
    final it = await shell(tester, simple: true, open: const ['weekend', 'groceries']);
    expect(find.byType(HomePlaceholder), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);
    expect(find.byType(NoteTabs), findsNothing);
    expect(find.byType(NoteTab), findsNothing);
    for (final control in ['Home', 'All your notes', 'Back to where you were', 'Settings', 'Organizations', 'Notifications', 'New note in a new tab']) {
      expect(find.bySemanticsLabel(control), findsNothing, reason: '$control is the bar\'s');
    }
    // No bar: `--app-tabs` is nothing, so `--app-safe-top` is the notch alone.
    expect(stamps(tester, find.byType(HomePlaceholder)).containsKey('tabs'), isFalse);
    expect(it.drawerOpen, isFalse);
    // A row kept from advanced is cut to the note showing, which on the home page is none.
    expect(it.tabs.open, isEmpty);
    expect(kept, ['open []']);
    await away(tester);
  });

  testWidgets('opens each note in the one tab there is, and leaves it on the way home', (tester) async {
    final it = await shell(tester, simple: true);
    it.openNote('weekend');
    await settle(tester);
    expect(find.byType(NotePlaceholder), findsOneWidget);
    expect(find.byType(NoteTabs), findsNothing);
    expect(find.byKey(const ValueKey('an-aside')), findsNothing);
    expect(it.tabs.open, ['weekend']);
    it.openNote('groceries');
    await settle(tester);
    expect(it.tabs.open, ['groceries'], reason: 'the note shown gives its tab to the next');
    it.backToList();
    await settle(tester);
    expect(find.byType(HomePlaceholder), findsOneWidget);
    expect(it.tabs.open, isEmpty);
    expect(kept, ['open [weekend]', 'open [groceries]', 'open []']);
    await away(tester);
  });

  testWidgets('still leaves a note on the phone\'s back gesture', (tester) async {
    final stack = BackStack();
    final it = await shell(tester, simple: true, stack: stack);
    it.openNote('weekend');
    await settle(tester);
    expect(it.screen.noteOnScreen, 'weekend');
    expect(stack.goBack(), isTrue);
    await settle(tester);
    expect(it.screen, const Screen.list());
    expect(find.byType(HomePlaceholder), findsOneWidget);
    await away(tester);
  });

  testWidgets('has every control in advanced, from the same shell, with the tabs and their groups', (tester) async {
    // Today's bar's rings, by what they say, every one in the row; Grouped command keeps some behind its round
    // button and •••.
    pinTodaysBar();
    final it = await shell(tester, simple: false, open: const ['weekend', 'groceries']);
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(find.byType(NoteTab), findsNWidgets(2));
    for (final control in ['Home', 'All your notes', 'Back to where you were', 'Forward again', 'Organizations', 'Notifications', 'Settings']) {
      expect(find.descendant(of: find.byType(NoteTabs), matching: find.bySemanticsLabel(control)), findsOneWidget, reason: '$control is drawn');
    }
    expect(tester.widget<NoteTabs>(find.byType(NoteTabs)).grouping, isTrue);
    expect(it.tabs.open, ['weekend', 'groceries']);
    expect(kept, isEmpty, reason: 'nothing trimmed in advanced');
    it.openNote('standup');
    await settle(tester);
    expect(it.tabs.open, ['weekend', 'groceries', 'standup']);
    await away(tester);
  });

  testWidgets('on a wide window is the list beside the place: the quiet pane with no note open, the note once one is', (tester) async {
    const size = Size(1100, 800);
    final it = await shell(tester, simple: true, size: size, mobile: false, fine: true, emptyPaneBuilder: (context, shell) => const SimpleEmptyPane(ghost: SizedBox(key: ValueKey('a-ghost'))));
    final list = find.bySemanticsLabel('Your notes');
    expect(list, findsOneWidget);
    expect(tester.getSize(list).width, simpleListColumn(size.width));
    expect(find.descendant(of: list, matching: find.byType(HomePlaceholder)), findsOneWidget);
    expect(find.byType(SimpleEmptyPane), findsOneWidget);
    expect(find.byKey(const ValueKey('a-ghost')), findsOneWidget);
    expect(find.text('Pick a note, or make one.'), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);
    expect(stamps(tester, find.byType(HomePlaceholder))['split'], 'on');
    // A note opened from the list shows on the right, and the list stays.
    it.openNote('weekend');
    await settle(tester);
    expect(find.byType(SimpleEmptyPane), findsNothing);
    expect(find.byType(NotePlaceholder), findsOneWidget);
    expect(find.descendant(of: list, matching: find.byType(HomePlaceholder)), findsOneWidget);
    expect(tester.getTopLeft(find.byType(NotePlaceholder)).dx, greaterThanOrEqualTo(simpleListColumn(size.width)));
    expect(find.byKey(const ValueKey('an-aside')), findsNothing);
    // Home again is the quiet pane again.
    it.backToList();
    await settle(tester);
    expect(find.byType(SimpleEmptyPane), findsOneWidget);
    await away(tester);
  });

  testWidgets('says to pick a note in the quiet pane without a builder, and draws the advanced window as before', (tester) async {
    await shell(tester, simple: true, size: const Size(1100, 800), mobile: false, fine: true);
    expect(find.text('Pick a note, or make one.'), findsOneWidget);
    await away(tester);
    await shell(tester, simple: false, size: const Size(1100, 800), mobile: false, fine: true);
    expect(find.bySemanticsLabel('Your notes'), findsNothing);
    expect(find.byType(SimpleEmptyPane), findsNothing);
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(find.byType(HomePlaceholder), findsOneWidget);
    await away(tester);
  });
}
