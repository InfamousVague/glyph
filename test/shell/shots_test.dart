import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/tabs.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/top_bar.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

/// Pictures of the shell, drawn with the real faces, for looking at without a phone and beside the web app's own:
/// `flutter test --update-goldens test/shell/shots_test.dart`, then open `test/shell/shots/`. Each of the bar's four
/// styles on a phone reading a note and on the opened Fold, in light and in dark; the home page with a group and
/// something unread; and the two menus.
void main() {
  setUpAll(loadAppFonts);

  const three = ['weekend', 'groceries', 'standup'];
  const trip = TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea')], of: {'groceries': 'g', 'standup': 'g'});

  Future<AppShellState> shell(WidgetTester tester, {required TopBarStyle style, required String theme, Size size = const Size(390, 844), TabGroups groups = TabGroups.none, bool unread = false, bool? mobile, bool? fine}) async {
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme),
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        topBar: style,
        openNotes: three,
        tabGroups: groups,
        unread: unread,
        mobile: mobile,
        finePointer: fine,
        organizations: const [OrgLike(id: 'o1', name: 'Attic Press', hue: 'moss')],
        onNew: () {},
        onDeleteNote: (_) {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return tester.state<AppShellState>(find.byType(AppShell));
  }

  for (final theme in ['light', 'dark']) {
    for (final style in TopBarStyle.values) {
      testWidgets('the ${style.label} bar on a phone reading a note, $theme', (tester) async {
        final app = await shell(tester, style: style, theme: theme);
        app.openNote('groceries');
        await tester.pump(const Duration(milliseconds: 400));
        await shot(tester, 'bar-${style.id}-phone-$theme');
      });

      testWidgets('the ${style.label} bar on the opened Fold, $theme', (tester) async {
        final app = await shell(tester, style: style, theme: theme, size: const Size(840, 900));
        app.openNote('groceries');
        await tester.pump(const Duration(milliseconds: 400));
        await shot(tester, 'bar-${style.id}-fold-$theme');
      });
    }

    testWidgets('the home page with a group and something unread, $theme', (tester) async {
      await shell(tester, style: TopBarStyle.classic, theme: theme, groups: trip, unread: true);
      await shot(tester, 'bar-classic-home-$theme');
    });

    testWidgets('a tab’s menu under a finger, $theme', (tester) async {
      final app = await shell(tester, style: TopBarStyle.classic, theme: theme, groups: const TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea'), TabGroup(id: 'h', name: 'Work things', hue: 'moss')], of: {'groceries': 'g', 'standup': 'h'}));
      app.openNote('weekend');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.longPress(find.descendant(of: find.byType(NoteTabs), matching: find.bySemanticsLabel('Weekend trip')).first);
      await tester.pump(const Duration(milliseconds: 600));
      await shot(tester, 'menu-tab-phone-$theme');
    });
  }

  testWidgets('the Classic bar on a desktop window at home, with a group', (tester) async {
    await shell(tester, style: TopBarStyle.classic, theme: 'light', size: const Size(1280, 800), groups: trip, mobile: false, fine: true);
    await shot(tester, 'bar-classic-desk-light');
  });

  testWidgets('the Islands on a desktop window at home, with a group', (tester) async {
    await shell(tester, style: TopBarStyle.islands, theme: 'light', size: const Size(1280, 800), groups: trip, mobile: false, fine: true);
    await shot(tester, 'bar-islands-desk-light');
  });
}
