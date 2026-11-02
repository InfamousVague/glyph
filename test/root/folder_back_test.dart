import 'package:flutter/gestures.dart' show PointerDeviceKind, kBackMouseButton, kForwardMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../library/support.dart' show FakeCore, libraryOver;
import '../support/render.dart';

/// Back inside a folder of All notes by folder, in the app put together (Matt, 2026-11-02, on the Fold and the Mac:
/// "Going back from inside a folder doesn't take you back to the root folder view"). Every way back goes up one
/// level - Acme to Clients to Work to the top's folders - and only the top leaves, home: the page's own arrow, the
/// phone's back gesture (the system's pop), Escape, Cmd-[ and a mouse's back button. Each level is a step on the
/// shell's trail, so Forward (the bar's, Cmd-], a mouse's forward button) goes down again, and the line over the
/// tiles starts at the top, "All notes › Work › Clients › Acme".
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  /// Work › Clients › Acme and Home, and with [more] that many other workspaces at the top, so the top scrolls.
  WorkspaceSheet sheet({int more = 0}) => WorkspaceSheet(
        list: [
          for (var i = 0; i < more; i += 1) Workspace(id: 'more-$i', name: 'More $i'),
          const Workspace(id: 'work', name: 'Work'),
          const Workspace(id: 'clients', name: 'Clients', parent: 'work'),
          const Workspace(id: 'acme', name: 'Acme', parent: 'clients'),
          const Workspace(id: 'home', name: 'Home'),
        ],
        notes: const {'plan': 'work', 'brief': 'clients', 'quote': 'acme', 'seeds': 'home'},
      );

  late WorkspaceStore store;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  Finder key(String value) => find.byKey(ValueKey(value));

  /// The app on All notes by folder, at its top: the workspaces as its first tiles.
  Future<void> open(WidgetTester tester, {int more = 0}) async {
    final core = FakeCore()
      ..seed('plan', '# Plan\n\nThe year.', path: 'workspaces/Work/Plan.md')
      ..seed('brief', '# Brief\n\nWhat they want.', path: 'workspaces/Work/Clients/Brief.md')
      ..seed('quote', '# Quote\n\nTwelve days.', path: 'workspaces/Work/Clients/Acme/Quote.md')
      ..seed('seeds', '# Seeds\n\nTomatoes.', path: 'workspaces/Home/Seeds.md');
    final it = libraryOver(core);
    await tester.runAsync(it.library.load);
    store = WorkspaceStore(storage: MemoryWorkspaceStorage(sheet(more: more)));
    await pumpApp(
      tester,
      size: const Size(900, 1000),
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: it.library, workspaces: store, stored: MemoryStored()),
    );
    await settle(tester);
    shellOf(tester).showFolders();
    await settle(tester);
    expect(key('all-notes-icons'), findsOneWidget);
    expect(key('tile-folder-work'), findsOneWidget, reason: 'the workspaces at the top are its folders');
  }

  /// Down from the top into Work, Clients and Acme by their tiles.
  Future<void> down(WidgetTester tester) async {
    for (final id in ['work', 'clients', 'acme']) {
      await tester.tap(key('tile-folder-$id'));
      await settle(tester);
      expect(store.value.current?.id, id);
    }
    expect(find.bySemanticsLabel('In All notes › Work › Clients › Acme'), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    folderCarrying.value = null;
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  /// Where the page is: the level, on All notes, or home.
  String? at(WidgetTester tester) => shellOf(tester).screen is ScreenNotes ? (store.value.current?.id ?? 'top') : shellOf(tester).screen.name;

  testWidgets('the page’s arrow goes up a level at a time, Acme to Clients to Work to the top, and only the top leaves', (tester) async {
    await open(tester);
    await down(tester);
    final steps = <String?>[];
    for (var i = 0; i < 4; i += 1) {
      await tester.tap(key('all-notes-back'));
      await settle(tester);
      steps.add(at(tester));
    }
    expect(steps, ['clients', 'work', 'top', 'list']);
    await close(tester);
  });

  testWidgets('the arrow says where it goes, and the line over the tiles starts at the top, each part a way up', (tester) async {
    await open(tester);
    expect(find.bySemanticsLabel('Back to home'), findsOneWidget);
    expect(key('folder-crumbs'), findsNothing, reason: 'nothing above the top');
    await tester.tap(key('tile-folder-work'));
    await settle(tester);
    expect(find.bySemanticsLabel('Back to All notes'), findsOneWidget);
    expect(find.bySemanticsLabel('In All notes › Work'), findsOneWidget, reason: 'a workspace at the top has its way up too');
    await tester.tap(key('tile-folder-clients'));
    await settle(tester);
    await tester.tap(key('tile-folder-acme'));
    await settle(tester);
    expect(find.bySemanticsLabel('Back to Clients'), findsOneWidget);
    await tester.tap(key('crumb-work'));
    await settle(tester);
    expect(at(tester), 'work');
    await tester.tap(key('crumb-root'));
    await settle(tester);
    expect(at(tester), 'top');
    await close(tester);
  });

  testWidgets('the phone’s back gesture goes up a level at a time, and leaves only from the top', (tester) async {
    await open(tester);
    await down(tester);
    final steps = <String?>[];
    for (var i = 0; i < 4; i += 1) {
      await tester.binding.handlePopRoute();
      await settle(tester);
      steps.add(at(tester));
    }
    expect(steps, ['clients', 'work', 'top', 'list']);
    await close(tester);
  });

  testWidgets('Escape and Cmd-[ go up a level, and Cmd-] goes down again', (tester) async {
    await open(tester);
    await down(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(at(tester), 'clients');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
    expect(at(tester), 'work');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
    expect(at(tester), 'clients');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(at(tester), 'top');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(at(tester), 'list');
    await close(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Forward after Back goes down again, step by step, to where Back began', (tester) async {
    await open(tester);
    await down(tester);
    await tester.tap(key('all-notes-back'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    await tester.tap(key('all-notes-back'));
    await settle(tester);
    expect(at(tester), 'top');
    expect(shellOf(tester).trail.canOn, isTrue);
    final steps = <String?>[];
    for (var i = 0; i < 3; i += 1) {
      shellOf(tester).goOn();
      await settle(tester);
      steps.add(at(tester));
    }
    expect(steps, ['work', 'clients', 'acme']);
    expect(shellOf(tester).trail.canOn, isFalse);
    // And the bar's Back walks the same steps up.
    shellOf(tester).goBack();
    await settle(tester);
    expect(at(tester), 'clients');
    await close(tester);
  });

  testWidgets('a mouse’s back and forward buttons go up and down a level', (tester) async {
    await open(tester);
    await down(tester);
    final centre = tester.getCenter(key('all-notes-icons'));
    Future<void> press(int buttons) async {
      final mouse = await tester.startGesture(centre, kind: PointerDeviceKind.mouse, buttons: buttons);
      await mouse.up();
      await settle(tester);
    }

    await press(kBackMouseButton);
    expect(at(tester), 'clients');
    await press(kBackMouseButton);
    expect(at(tester), 'work');
    await press(kForwardMouseButton);
    expect(at(tester), 'clients');
    await close(tester);
  });

  testWidgets('a note opened from a folder comes back to that folder, in the icon view', (tester) async {
    await open(tester);
    await down(tester);
    await tester.tap(key('tile-note-quote'));
    await settle(tester);
    expect(shellOf(tester).screen, isA<ScreenNote>());
    shellOf(tester).goBack();
    await settle(tester);
    expect(at(tester), 'acme');
    expect(key('all-notes-icons'), findsOneWidget);
    await tester.tap(key('all-notes-back'));
    await settle(tester);
    expect(at(tester), 'clients');
    await close(tester);
  });

  testWidgets('the top gone back up to is where it was scrolled to, not at its top', (tester) async {
    await open(tester, more: 60);
    final page = find.descendant(of: key('all-notes-scroll'), matching: find.byType(Scrollable)).first;
    final scroller = tester.state<ScrollableState>(page).position;
    await tester.ensureVisible(key('tile-folder-work'));
    await settle(tester);
    final left = scroller.pixels;
    expect(left, greaterThan(200), reason: 'Work is well down the top');
    await tester.tap(key('tile-folder-work'));
    await settle(tester);
    await settle(tester);
    expect(scroller.pixels, lessThan(left), reason: 'a folder opens at its top');
    await tester.tap(key('all-notes-back'));
    await settle(tester);
    expect(at(tester), 'top');
    expect(scroller.pixels, moreOrLessEquals(left, epsilon: 1));
    await close(tester);
  });
}
