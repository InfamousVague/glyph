import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/tabs.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/tabs/tab_parts.dart';
import 'package:ghost_md/notes/tabs/tab_row.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/app_tab_bar.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/shell/top_bar.dart';
import 'package:ghost_md/shell/top_bar_tools.dart';
import 'package:glacier/glacier.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

/// The frame of App.tsx: which screen is up, the bar where the web draws it, the tabs and the trail it holds, the
/// back gesture, and the window in two panes.
void main() {
  setUpAll(loadAppFonts);

  /// What the shell handed to whoever keeps the preferences, and what it asked of the app.
  final kept = <String>[];
  setUp(kept.clear);

  Future<AppShellState> shell(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    TopBarStyle topBar = TopBarStyle.classic,
    SidebarStyle sidebarStyle = SidebarStyle.popover,
    List<String> open = const [],
    TabGroups groups = TabGroups.none,
    bool? mobile,
    bool? fine,
    bool? sidebarShown,
    BackStack? stack,
    ShellNoteBuilder? noteBuilder,
    ShellAsideBuilder? asideBuilder,
    VoidCallback? onSettings,
    List<OrgLike> organizations = const [],
    Screen initial = const Screen.list(),
    String theme = 'light',
  }) async {
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme),
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        topBar: topBar,
        sidebarStyle: sidebarStyle,
        sidebarShown: sidebarShown,
        openNotes: open,
        tabGroups: groups,
        organizations: organizations,
        mobile: mobile,
        finePointer: fine,
        backStack: stack ?? BackStack(),
        initialScreen: initial,
        noteBuilder: noteBuilder,
        asideBuilder: asideBuilder,
        onSettings: onSettings,
        onNew: () => kept.add('new'),
        onDeleteNote: (id) => kept.add('delete $id'),
        onRenameNote: (id, title) => kept.add('rename $id $title'),
        onOpenNotesChanged: (ids) => kept.add('open $ids'),
        onTabGroupsChanged: (next) => kept.add('groups ${next.list.map((g) => g.name).join(',')} ${next.of}'),
        onSidebarShownChanged: (shown) => kept.add('sidebar $shown'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return tester.state<AppShellState>(find.byType(AppShell));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A control of the bar's, by its name: the home page's stand-in lists the same titles the tabs wear.
  Finder bar(String label) => find.descendant(of: find.byType(NoteTabs), matching: find.bySemanticsLabel(label)).first;

  Map<String, String> stamps(WidgetTester tester, [Finder? under]) => tester.element(under ?? find.byType(AppTabBar)).tokens.attrs;

  group('the screen that is up', () {
    testWidgets('is the home page as the app opens, under a bar one line tall, with the row as it was left', (tester) async {
      final app = await shell(tester, open: ['weekend', 'gone', 'groceries']);
      expect(app.screen, const Screen.list());
      expect(find.byType(HomePlaceholder), findsOneWidget);
      // The row is kept, never which tab was in front; a tab whose note is not there is not drawn.
      expect(find.byType(NoteTab), findsNWidgets(2));
      expect(app.tabs.open, ['weekend', 'gone', 'groceries']);
      expect(stamps(tester)['tabs'], 'rows');
      expect(stamps(tester).containsKey('split'), isFalse);
      expect(stamps(tester).containsKey('topbar'), isFalse);
      // On the home page a phone's bar has its people icon, its bell and its cog.
      for (final label in ['Organizations', 'Notifications', 'Settings']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      await away(tester);
      await shell(tester);
      expect(stamps(tester)['tabs'], 'on');
      expect(find.byType(TabRow), findsNothing);
      await away(tester);
    });

    testWidgets('becomes a note when one is opened, which takes a tab; a phone’s bar goes quiet while it is read', (tester) async {
      final app = await shell(tester);
      await tester.tap(find.bySemanticsLabel('Weekend trip'));
      await settle(tester);
      expect(app.screen.noteOnScreen, 'weekend');
      expect(find.byType(NotePlaceholder), findsOneWidget);
      expect(find.byType(NoteTab), findsOneWidget);
      expect(stamps(tester)['tabs'], 'rows');
      expect(kept, ['open [weekend]']);
      // The bar holds the note's own tools, so the people icon, the bell and the cog step out of it.
      for (final label in ['Organizations', 'Notifications', 'Settings']) {
        expect(find.bySemanticsLabel(label), findsNothing);
      }
      // Home is the way back, and they are there again.
      await tester.tap(find.bySemanticsLabel('Home'));
      await settle(tester);
      expect(app.screen, const Screen.list());
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(find.byType(NoteTab), findsOneWidget);
      await away(tester);
    });

    testWidgets('changes with a tab pressed, and a tab closed hands over to the one beside it, then home', (tester) async {
      final app = await shell(tester, open: ['weekend', 'groceries', 'standup']);
      await tester.tap(bar('Groceries, in Home'));
      await settle(tester);
      expect(app.shown, 'groceries');
      await tester.tap(find.bySemanticsLabel('Close Groceries'));
      await settle(tester);
      // The first tab after it that stays open.
      expect(app.shown, 'standup');
      expect(app.tabs.open, ['weekend', 'standup']);
      // A tab that is not being read closes without anything moving.
      await tester.tap(find.bySemanticsLabel('Close Weekend trip'));
      await settle(tester);
      expect(app.shown, 'standup');
      await tester.tap(find.bySemanticsLabel('Close Monday standup'));
      await settle(tester);
      expect(app.screen, const Screen.list());
      expect(app.tabs.open, isEmpty);
      expect(kept.last, 'open []');
      await away(tester);
    });

    testWidgets('is walked back and forward by the arrows, over the places and not the captures', (tester) async {
      final app = await shell(tester, mobile: false);
      app.openNote('weekend');
      await settle(tester);
      app.showAllNotes();
      await settle(tester);
      app.show(const Screen.academy());
      await settle(tester);
      // The Academy is the whole screen, with no bar, and is no place on the trail.
      expect(find.byType(AppTabBar), findsNothing);
      app.show(const Screen.list());
      await settle(tester);
      expect(app.trail.trail.places, ['list', 'note:weekend', 'notes', 'list']);
      await tester.tap(find.bySemanticsLabel('Back to where you were'));
      await settle(tester);
      expect(app.screen, const Screen.notes());
      expect(find.byType(AllNotesPlaceholder), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back to where you were'));
      await settle(tester);
      expect(app.shown, 'weekend');
      await tester.tap(find.bySemanticsLabel('Forward again'));
      await settle(tester);
      expect(app.screen, const Screen.notes());
      // A step is not somewhere new.
      expect(app.trail.trail.places, ['list', 'note:weekend', 'notes', 'list']);
      await away(tester);
    });

    testWidgets('is an organization’s dashboard from the people icon’s picker, a place with the bar and off the trail', (tester) async {
      final app = await shell(tester, organizations: const [OrgLike(id: 'o1', name: 'Attic Press', hue: 'moss')]);
      await tester.tap(find.bySemanticsLabel('Organizations'));
      await settle(tester);
      await tester.tap(find.text('Attic Press'));
      await settle(tester);
      expect(app.screen, const Screen.organization('o1'));
      expect(find.byType(OrganizationPlaceholder), findsOneWidget);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(app.trail.trail.places, ['list']);
      await tester.tap(find.bySemanticsLabel('Activity'));
      await settle(tester);
      expect(app.screen, const Screen.organization('o1', page: OrganizationPage.log));
      await away(tester);
    });

    testWidgets('is drawn by whoever is given to draw it, with the shell to ask things of', (tester) async {
      await shell(tester, noteBuilder: (context, shell, screen) => GestureDetector(onTap: shell.backToList, child: Center(child: Text('the editor for ${screen.note.id}'))));
      await tester.tap(find.bySemanticsLabel('Groceries'));
      await settle(tester);
      expect(find.byType(NotePlaceholder), findsNothing);
      await tester.tap(find.text('the editor for groceries'));
      await settle(tester);
      expect(find.byType(HomePlaceholder), findsOneWidget);
      await away(tester);
    });
  });

  group('the back gesture', () {
    testWidgets('closes what is over the screen first, then leaves the screen, and at the home page stays in the app', (tester) async {
      final stack = BackStack();
      final app = await shell(tester, stack: stack);
      app.openNote('weekend');
      await settle(tester);
      app.showNotifications();
      await settle(tester);
      expect(find.bySemanticsLabel('notifications'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await settle(tester);
      expect(app.notificationsOpen, isFalse);
      expect(app.shown, 'weekend');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await settle(tester);
      expect(app.screen, const Screen.list());
      // The root: the gesture is still used, and the app is not left.
      expect(stack.depth, 0);
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(app.screen, const Screen.list());
      await away(tester);
    });

    testWidgets('goes home from the grid and a dashboard, back to the dashboard from its log, and out of the Academy', (tester) async {
      final app = await shell(tester);
      for (final (from, to) in [
        (const Screen.notes(), const Screen.list()),
        (const Screen.organization('o'), const Screen.list()),
        (const Screen.organization('o', page: OrganizationPage.log), const Screen.organization('o')),
        (const Screen.academy(), const Screen.list()),
        (ScreenCapture.fresh(false, now: 1), const Screen.list()),
      ]) {
        app.show(from);
        await settle(tester);
        expect(await tester.binding.handlePopRoute(), isTrue);
        await settle(tester);
        expect(app.screen, to, reason: 'back from ${from.name}');
      }
      await away(tester);
    });

    testWidgets('closes a tab’s menu and nothing under it', (tester) async {
      final app = await shell(tester, open: ['weekend', 'groceries']);
      app.openNote('weekend');
      await settle(tester);
      await tester.longPress(bar('Groceries, in Home'));
      await settle(tester);
      expect(find.text('Close tab'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await settle(tester);
      expect(find.text('Close tab'), findsNothing);
      expect(app.shown, 'weekend');
      await away(tester);
    });
  });

  group('what the bar asks of the shell', () {
    testWidgets('opens the notes’ card and the notifications, lit while they are open, and one closes the other', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await shell(tester);
      await tester.tap(find.bySemanticsLabel('All your notes'));
      await settle(tester);
      expect(app.drawerOpen, isTrue);
      expect(find.bySemanticsLabel('all your notes'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('All your notes')).getSemanticsData().flagsCollection.isExpanded.name, 'isTrue');
      await tester.tap(find.bySemanticsLabel('Notifications'));
      await settle(tester);
      expect(app.drawerOpen, isFalse);
      expect(app.notificationsOpen, isTrue);
      // The bell again closes them.
      await tester.tap(find.bySemanticsLabel('Notifications'));
      await settle(tester);
      expect(app.notificationsOpen, isFalse);
      // A note opened from the notes' card closes the card.
      await tester.tap(find.bySemanticsLabel('All your notes'));
      await settle(tester);
      app.openNote('flat');
      await settle(tester);
      expect(app.drawerOpen, isFalse);
      handle.dispose();
      await away(tester);
    });

    testWidgets('asks for Settings and a new note, and stands in for Settings where nobody answers', (tester) async {
      var asked = 0;
      await shell(tester, open: ['weekend'], onSettings: () => asked += 1);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.tap(find.bySemanticsLabel('New note in a new tab'));
      expect(asked, 1);
      expect(kept, ['new']);
      await away(tester);
      await shell(tester);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await settle(tester);
      expect(find.bySemanticsLabel('Settings').evaluate().length, greaterThan(1));
      expect(find.textContaining('PLACEHOLDER · Settings'), findsOneWidget);
      await away(tester);
    });

    testWidgets('groups a tab from its menu and names the group at once, kept for whoever keeps the preferences', (tester) async {
      final app = await shell(tester, open: ['weekend', 'groceries']);
      await tester.longPress(bar('Weekend trip'));
      await settle(tester);
      await tester.tap(find.text('Add to a new group'));
      await settle(tester);
      // Named "Group" to begin with, and straight into its name to be called something better.
      expect(app.tabs.groups.list.single.name, 'Group');
      expect(find.bySemanticsLabel('Group name'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'Trip');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(app.tabs.groups.list.single.name, 'Trip');
      expect(find.bySemanticsLabel('Trip, 1 tab'), findsOneWidget);
      expect(kept.last, 'groups Trip {weekend: ${app.tabs.groups.list.single.id}}');
      // Folded, the group is its chip, and the tab is still open.
      await tester.tap(find.bySemanticsLabel('Trip, 1 tab'));
      await settle(tester);
      expect(find.bySemanticsLabel('Trip, 1 tab, folded'), findsOneWidget);
      expect(find.byType(NoteTab), findsOneWidget);
      expect(app.tabs.open, ['weekend', 'groceries']);
      await away(tester);
    });

    testWidgets('moves a tab a finger carries, the row reordering under it, and keeps the new row', (tester) async {
      final app = await shell(tester, open: ['weekend', 'flat', 'reading']);
      final gesture = await tester.startGesture(tester.getCenter(bar('Weekend trip')));
      await tester.pump(holdTime + const Duration(milliseconds: 40));
      await gesture.moveTo(tester.getCenter(bar('Flat, in Home')) + const Offset(40, 0));
      await tester.pump();
      expect(app.tabs.open, ['flat', 'weekend', 'reading']);
      // The tab is drawn where the finger is, not where it now stands.
      await gesture.up();
      await settle(tester);
      expect(app.tabs.open, ['flat', 'weekend', 'reading']);
      expect(kept.last, 'open [flat, weekend, reading]');
      expect(app.screen, const Screen.list());
      await away(tester);
    });

    testWidgets('deletes a tab’s note from its menu: its tab goes, and the note being read is left', (tester) async {
      final app = await shell(tester, open: ['weekend', 'groceries']);
      app.openNote('weekend');
      await settle(tester);
      await tester.longPress(bar('Weekend trip'));
      await settle(tester);
      await tester.tap(find.text('Delete note'));
      await settle(tester);
      expect(kept.last, 'delete weekend');
      expect(app.tabs.open, ['groceries']);
      expect(app.screen, const Screen.list());
      await away(tester);
    });

    testWidgets('draws a screen’s own controls in its slot while that screen is up', (tester) async {
      final app = await shell(
        tester,
        noteBuilder: (context, shell, screen) => const TopBarFill(tools: Text('Share'), tail: Text('More'), child: SizedBox.expand()),
      );
      app.openNote('weekend');
      await settle(tester);
      expect(find.descendant(of: find.byType(NoteTabs), matching: find.text('Share')), findsOneWidget);
      expect(find.descendant(of: find.byType(NoteTabs), matching: find.text('More')), findsOneWidget);
      // The More ends the row.
      expect(tester.getRect(find.text('More')).left, greaterThan(tester.getRect(find.text('Share')).right));
      app.backToList();
      await settle(tester);
      expect(find.text('Share'), findsNothing);
      await away(tester);
    });

    testWidgets('goes with a screen still up, and the screen’s controls are given back to nobody', (tester) async {
      final app = await shell(
        tester,
        noteBuilder: (context, shell, screen) => const TopBarFill(tools: Text('Share'), tail: Text('More'), child: SizedBox.expand()),
      );
      app.openNote('weekend');
      await settle(tester);
      expect(find.text('Share'), findsOneWidget);
      // The shell and the note's screen in one frame: the screen hands its controls back a frame later, to a bar
      // that is gone. It threw there ("A TopBarTools was used after being disposed"), in the next test's first frame.
      await away(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('a window wide enough for two panes', () {
    testWidgets('says so on the root, and keeps a phone’s quiet bar on the opened Fold', (tester) async {
      final app = await shell(tester, size: const Size(840, 900), open: ['weekend']);
      expect(stamps(tester)['split'], 'on');
      // The bar reaches the window's top, glass across it.
      expect(tester.getTopLeft(find.byType(AppTabBar)).dy, 0);
      app.openNote('weekend');
      await settle(tester);
      // `isMobile` is the device, not the window's width: a Fold opened wide does without.
      expect(find.bySemanticsLabel('Notifications'), findsNothing);
      // A capture takes the whole window, and the window is in two panes all the same.
      app.show(ScreenCapture.fresh(false, now: 1));
      await settle(tester);
      expect(find.byType(AppTabBar), findsNothing);
      expect(stamps(tester, find.byType(WholeScreenPlaceholder))['split'], 'on');
      expect(stamps(tester, find.byType(WholeScreenPlaceholder)).containsKey('tabs'), isFalse);
      await away(tester);
      // A desktop's narrow window keeps the bell.
      final desk = await shell(tester, size: const Size(600, 800), mobile: false, fine: true);
      desk.openNote('weekend');
      await settle(tester);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(stamps(tester).containsKey('split'), isFalse);
      await away(tester);
    });

    // Matt, 2026-10-24: "make the sidebar on advanced mode the same as simple but just hide it by default".
    for (final style in SidebarStyle.values) {
      testWidgets('docks the notes in simple mode\'s column beside the note with ${style.name} chosen, hidden under a finger and a mouse until asked for', (tester) async {
        final app = await shell(tester, size: const Size(840, 900), sidebarStyle: style);
        expect(find.byType(PanePlaceholder), findsNothing);
        expect(find.bySemanticsLabel('Your notes'), findsNothing);
        await tester.tap(find.bySemanticsLabel('All your notes'));
        await settle(tester);
        // The icon shows and hides the column; no card is drawn over it.
        expect(app.drawerOpen, isFalse);
        expect(kept, ['sidebar true']);
        // Simple mode's column (`simpleListColumn`), with its rule at the end; the note takes the rest.
        expect(tester.getRect(find.bySemanticsLabel('Your notes')), const Rect.fromLTWH(0, 0, 352.8, 900));
        expect(tester.getRect(find.byType(HomePlaceholder)), const Rect.fromLTWH(352.8, 0, 840 - 352.8, 900));
        // The bar is still the whole window's.
        expect(tester.getSize(find.byType(AppTabBar)).width, 840);
        await tester.tap(find.bySemanticsLabel('All your notes'));
        await settle(tester);
        expect(find.byType(PanePlaceholder), findsNothing);
        expect(tester.getSize(find.byType(HomePlaceholder)).width, 840);
        expect(kept, ['sidebar true', 'sidebar false']);
        await away(tester);
        // Under a mouse it starts hidden too, and opens at its widest.
        await shell(tester, size: const Size(1280, 800), sidebarStyle: style, mobile: false, fine: true);
        expect(find.bySemanticsLabel('Your notes'), findsNothing);
        expect(tester.getRect(find.byType(HomePlaceholder)), const Rect.fromLTWH(0, 0, 1280, 800));
        await away(tester);
        // As the device left it, once it has been toggled.
        await shell(tester, size: const Size(1280, 800), sidebarStyle: style, mobile: false, fine: true, sidebarShown: true);
        expect(tester.getRect(find.bySemanticsLabel('Your notes')), const Rect.fromLTWH(0, 0, 360, 800));
        expect(tester.getRect(find.byType(HomePlaceholder)), const Rect.fromLTWH(360, 0, 920, 800));
        await away(tester);
      });
    }

    testWidgets('opens the column without moving the bar, its controls, or the note, which is the same screen beside it', (tester) async {
      final app = await shell(tester, size: const Size(1280, 800), mobile: false, fine: true);
      app.openNote('weekend');
      await settle(tester);
      final note = tester.element(find.byType(NotePlaceholder));
      final barRect = tester.getRect(find.byType(AppTabBar));
      final controls = {for (final label in ['All your notes', 'Home', 'Settings']) label: tester.getRect(bar(label))};
      await tester.tap(bar('All your notes'));
      await settle(tester);
      expect(find.bySemanticsLabel('Your notes'), findsOneWidget);
      expect(tester.element(find.byType(NotePlaceholder)), same(note), reason: 'the note is not made again');
      expect(tester.getRect(find.byType(NotePlaceholder)).left, 360);
      expect(tester.getRect(find.byType(AppTabBar)), barRect);
      for (final MapEntry(:key, :value) in controls.entries) {
        expect(tester.getRect(bar(key)), value, reason: key);
      }
      await tester.tap(bar('All your notes'));
      await settle(tester);
      expect(tester.element(find.byType(NotePlaceholder)), same(note));
      expect(tester.getRect(find.byType(NotePlaceholder)).left, 0);
      await away(tester);
    });

    testWidgets('keeps a narrow window\'s card, whichever style is chosen', (tester) async {
      final app = await shell(tester, size: const Size(600, 800), sidebarStyle: SidebarStyle.docked, mobile: false, fine: true);
      await tester.tap(find.bySemanticsLabel('All your notes'));
      await settle(tester);
      expect(app.drawerOpen, isTrue);
      expect(find.bySemanticsLabel('Your notes'), findsNothing);
      expect(kept, isEmpty);
      await away(tester);
    });

    testWidgets('gives the aside a third column beside a docked sidebar, and a toggle only when it has something to hold', (tester) async {
      final app = await shell(tester, size: const Size(1280, 800), sidebarStyle: SidebarStyle.docked, mobile: false, fine: true, sidebarShown: true, asideBuilder: (context, shell) => shell.shown == null ? null : const Text('History'));
      expect(find.bySemanticsLabel('Side panel'), findsNothing);
      app.openNote('weekend');
      await settle(tester);
      expect(find.text('History'), findsNothing);
      await tester.tap(bar('Side panel'));
      await settle(tester);
      // `clamp(240px, 22vw, 320px)` at the far side.
      final aside = tester.getRect(find.bySemanticsLabel('Side panel').first);
      expect(aside.right, 1280);
      expect(aside.width, closeTo(281.6, 0.01));
      expect(tester.getRect(find.byType(NotePlaceholder)).width, closeTo(1280 - 360 - 281.6, 0.01));
      await away(tester);
      // Popover chosen, the sidebar is the same column and the aside a card over the note, as it was.
      final card = await shell(tester, size: const Size(1280, 800), mobile: false, fine: true, sidebarShown: true, asideBuilder: (context, shell) => shell.shown == null ? null : const Text('History'));
      card.openNote('weekend');
      await settle(tester);
      await tester.tap(bar('Side panel'));
      await settle(tester);
      expect(find.text('History'), findsOneWidget);
      expect(tester.getRect(find.byType(NotePlaceholder)).width, closeTo(1280 - 360, 0.01));
      await away(tester);
    });

    testWidgets('stamps the bar’s style, Classic stamping nothing', (tester) async {
      await shell(tester, topBar: TopBarStyle.islands, open: ['weekend']);
      expect(stamps(tester)['topbar'], 'islands');
      await away(tester);
      // The Ledger's row is always there, so the bar is two lines with nothing open.
      await shell(tester, topBar: TopBarStyle.ledger);
      expect(stamps(tester)['topbar'], 'ledger');
      expect(stamps(tester)['tabs'], 'rows');
      await away(tester);
      // On a mouse's right-click a tab's menu opens through the shell as well.
      await shell(tester, size: const Size(1280, 800), open: ['weekend'], mobile: false, fine: true);
      await tester.tap(bar('Weekend trip'), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await settle(tester);
      expect(find.bySemanticsLabel('Weekend trip tab'), findsOneWidget);
      await away(tester);
    });
  });
}
