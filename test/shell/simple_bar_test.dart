import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/tabs/tab_parts.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/shell/screen.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

/// Simple mode's bar (GHST-103; Matt, 2026-10-17: "simple mode has a much more approachable UI with fancy features
/// hidden behind more"): Home, the sidebar, Back, the screen's own tools and the cog, and no people icon, bell,
/// Forward or side panel; the tabs stay, with Close tab and Delete note and no groups.
void main() {
  setUpAll(loadAppFonts);

  Future<AppShellState> shell(WidgetTester tester, {required bool simple, List<String> open = const [], Screen initial = const Screen.list()}) async {
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        openNotes: open,
        simple: simple,
        mobile: true,
        finePointer: false,
        backStack: BackStack(),
        initialScreen: initial,
        // The stand-in note, with its tools in the bar's slot; and an aside for it, which simple mode leaves out.
        asideBuilder: (context, shell) => const SizedBox(key: ValueKey('an-aside')),
        onSettings: () {},
        onOrganizations: () {},
        onNew: () {},
        onDeleteNote: (_) {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return tester.state<AppShellState>(find.byType(AppShell));
  }

  Finder bar(String label) => find.descendant(of: find.byType(NoteTabs), matching: find.bySemanticsLabel(label));

  testWidgets('keeps Home, the sidebar, Back and the cog, and leaves out the people icon, the bell and Forward', (tester) async {
    await shell(tester, simple: true);
    for (final kept in ['Home', 'All your notes', 'Back to where you were', 'Settings']) {
      expect(bar(kept), findsOneWidget, reason: '$kept stays');
    }
    for (final gone in ['Organizations', 'Notifications', 'Forward again', 'Side panel']) {
      expect(bar(gone), findsNothing, reason: '$gone is advanced');
    }
    await away(tester);
  });

  testWidgets('has every control in advanced, from the same shell', (tester) async {
    await shell(tester, simple: false);
    for (final control in ['Home', 'All your notes', 'Back to where you were', 'Forward again', 'Organizations', 'Notifications', 'Settings']) {
      expect(bar(control), findsOneWidget, reason: '$control is drawn');
    }
    await away(tester);
  });

  testWidgets('keeps the tabs and a new tab, and gives a tab a menu with no groups in it', (tester) async {
    await shell(tester, simple: true, open: const ['weekend', 'groceries']);
    expect(find.byType(NoteTab), findsNWidgets(2));
    expect(bar('New note in a new tab'), findsOneWidget);
    expect(tester.widget<NoteTabs>(find.byType(NoteTabs)).grouping, isFalse);
    // A finger held on a tab: its menu, the tab's own rows and nothing to group it with.
    await tester.longPress(find.byType(NoteTab).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TabMenu), findsOneWidget);
    expect(find.text('Close tab'), findsOneWidget);
    expect(find.text('Delete note'), findsOneWidget);
    expect(find.text('Add to a new group'), findsNothing);
    expect(find.text('Add to group'), findsNothing);
    await away(tester);
  });

  testWidgets('offers the groups in advanced, from the same tab', (tester) async {
    await shell(tester, simple: false, open: const ['weekend', 'groceries']);
    expect(tester.widget<NoteTabs>(find.byType(NoteTabs)).grouping, isTrue);
    await tester.longPress(find.byType(NoteTab).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TabMenu), findsOneWidget);
    expect(find.text('Add to a new group'), findsOneWidget);
    expect(find.text('Close tab'), findsOneWidget);
    await away(tester);
  });

  testWidgets('draws no aside over a note, so there is nothing for a toggle to open', (tester) async {
    final it = await shell(tester, simple: true, open: const ['weekend'], initial: Screen.note(noteOf('weekend')));
    expect(it.screen, isA<ScreenNote>());
    expect(find.byType(NotePlaceholder), findsOneWidget);
    expect(find.byKey(const ValueKey('an-aside')), findsNothing);
    expect(bar('Side panel'), findsNothing);
    await away(tester);
  });
}
