import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/show_in_files.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/folder_menu.dart';
import 'package:ghost_md/notes/folder_strip.dart' show folderTiles;
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/notes/note_menu.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/space_pages.dart' show SidebarSpaces;
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart' show away;
import '../support/render.dart';
import 'support.dart';

/// Show in Finder in the note and folder menus (Matt, 2026-11-01: "also add an 'open in finder' option";
/// lib/core/show_in_files.dart): the row's words and what it runs on a Mac, Windows and Linux, none on a phone or an
/// iPhone or in a browser, none for a note with no file or a folder with no directory, and the row where it stands
/// in a note's menu, a folder's tile and a page's … in the sidebar. Nothing is ever opened: the launcher is a fake.
void main() {
  setUpAll(loadAppFonts);

  const root = '/Users/someone/Ghost.md';

  /// A [ShowInFiles] over a library at [at], with [onDisk] the paths there and every command written down.
  ({ShowInFiles show, List<ShowCommand> ran}) showIn(TargetPlatform platform, {String? at = root, Set<String> onDisk = const {}, bool web = false}) {
    final ran = <ShowCommand>[];
    final show = ShowInFiles(
      root: () async => at,
      platform: platform,
      web: web,
      exists: (path, {required directory}) => onDisk.contains(directory ? '$path/' : path),
      launch: (executable, arguments) async => ran.add(ShowCommand(executable, arguments)),
    );
    return (show: show, ran: ran);
  }

  group('the command', () {
    test('a Mac selects it in Finder, Windows in Explorer, Linux opens its folder; a phone has none', () {
      expect(showCommandFor(TargetPlatform.macOS, '$root/Inbox/Plan.md'), const ShowCommand('open', ['-R', '$root/Inbox/Plan.md']));
      expect(showCommandFor(TargetPlatform.windows, r'C:\Users\someone\Ghost.md/Inbox/Plan.md'), const ShowCommand('explorer', ['/select,', r'C:\Users\someone\Ghost.md\Inbox\Plan.md']));
      expect(showCommandFor(TargetPlatform.linux, '$root/workspaces/Work'), const ShowCommand('xdg-open', ['$root/workspaces']));
      for (final phone in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.fuchsia]) {
        expect(showCommandFor(phone, '$root/Inbox/Plan.md'), isNull, reason: '$phone');
        expect(showInFilesLabel(phone), isNull, reason: '$phone');
      }
      expect([for (final p in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) showInFilesLabel(p)], ['Show in Finder', 'Show in Explorer', 'Show in Files']);
    });

    test('a library path is put under the root in the device’s own way', () {
      expect(libraryPathOf('$root/', 'workspaces/Work/Plan.md', platform: TargetPlatform.macOS), '$root/workspaces/Work/Plan.md');
      expect(libraryPathOf(r'D:\Vault', 'orgs/Ghost.md/Plan.md', platform: TargetPlatform.windows), r'D:\Vault\orgs\Ghost.md\Plan.md');
    });

    test('offered for a file on the disk, on a desktop only, and the press runs it there', () async {
      final mac = showIn(TargetPlatform.macOS, onDisk: {'$root/Inbox/Plan.md', '$root/workspaces/Work/'});
      await mac.show.refresh();
      expect(mac.show.offer('Inbox/Plan.md'), 'Show in Finder');
      expect(mac.show.offer('workspaces/Work', directory: true), 'Show in Finder');
      expect(mac.show.offer('Inbox/Gone.md'), isNull, reason: 'no file on the disk');
      expect(mac.show.offer(null), isNull, reason: 'a note with no file yet');
      expect(mac.show.offer('workspaces/Home', directory: true), isNull, reason: 'a folder with no directory');
      await mac.show.show('Inbox/Plan.md');
      await mac.show.show('Inbox/Gone.md');
      expect(mac.ran, [const ShowCommand('open', ['-R', '$root/Inbox/Plan.md'])]);

      final linux = showIn(TargetPlatform.linux, onDisk: {'$root/workspaces/Work/'});
      await linux.show.show('workspaces/Work', directory: true);
      expect(linux.ran, [const ShowCommand('xdg-open', ['$root/workspaces'])]);

      for (final none in [showIn(TargetPlatform.android, onDisk: {'$root/Inbox/Plan.md'}), showIn(TargetPlatform.iOS, onDisk: {'$root/Inbox/Plan.md'}), showIn(TargetPlatform.macOS, onDisk: {'$root/Inbox/Plan.md'}, web: true)]) {
        await none.show.refresh();
        expect(none.show.offer('Inbox/Plan.md'), isNull);
        await none.show.show('Inbox/Plan.md');
        expect(none.ran, isEmpty);
      }
      final nowhere = showIn(TargetPlatform.macOS, at: null, onDisk: {'$root/Inbox/Plan.md'});
      await nowhere.show.refresh();
      expect(nowhere.show.offer('Inbox/Plan.md'), isNull, reason: 'a library Dart cannot reach');
    });

    test('the library moved meanwhile: the press asks where it is again', () async {
      var at = root;
      final ran = <ShowCommand>[];
      final show = ShowInFiles(root: () async => at, platform: TargetPlatform.macOS, web: false, exists: (_, {required directory}) => true, launch: (e, a) async => ran.add(ShowCommand(e, a)));
      await show.refresh();
      at = '/Volumes/Vault';
      await show.show('Inbox/Plan.md');
      expect(ran.single.arguments, ['-R', '/Volumes/Vault/Inbox/Plan.md']);
    });
  });

  group('a note’s menu', () {
    final plan = Note(id: 'plan', body: '# Plan\n', createdAt: 0, updatedAt: 0, path: 'workspaces/Work/Plan.md');
    const draft = Note(id: 'draft', body: '# Draft\n', createdAt: 0, updatedAt: 0);

    Future<NoteMenuController> host(WidgetTester tester, ShowInFiles show) async {
      final menu = NoteMenuController();
      await pumpApp(
        tester,
        size: const Size(1000, 800),
        home: BackScope(
          child: Stack(children: [
            const Positioned.fill(child: SizedBox.expand()),
            NoteMenuHost(controller: menu, notes: [plan, draft], coarse: false, onOpen: (_) {}, onPin: (_) {}, onArchive: (_, _) {}, onDelete: (_) {}, show: show),
          ]),
        ),
      );
      return menu;
    }

    List<String> rows(WidgetTester tester) => [for (final item in tester.widgetList<GlacierMenuItem>(find.byType(GlacierMenuItem))) ((item.child as Text).data!)];

    testWidgets('on a Mac: Show in Finder before the rule over Delete, selecting the file in Finder', (tester) async {
      final it = showIn(TargetPlatform.macOS, onDisk: {'$root/workspaces/Work/Plan.md'});
      await tester.runAsync(it.show.refresh);
      final menu = await host(tester, it.show);
      menu.open('plan', const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-menu-show')), findsOneWidget);
      expect(rows(tester), ['Open', 'Pin', 'Archive', 'Show in Finder', 'Delete']);
      final menuRows = tester.widget<GlacierMenu>(find.byType(GlacierMenu)).children;
      expect(menuRows[menuRows.length - 2], isA<GlacierMenuSeparator>(), reason: 'a rule between it and Delete');
      await tester.tap(find.byKey(const ValueKey('note-menu-show')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(it.ran, [const ShowCommand('open', ['-R', '$root/workspaces/Work/Plan.md'])]);
      // A note with no file yet has no row.
      menu.open('draft', const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-menu-show')), findsNothing);
      await away(tester);
    });

    testWidgets('on Windows, Show in Explorer; the device’s own platform where none is said', (tester) async {
      final it = showIn(TargetPlatform.windows, at: r'C:\Ghost.md', onDisk: {r'C:\Ghost.md\workspaces\Work\Plan.md'});
      await tester.runAsync(it.show.refresh);
      final menu = await host(tester, it.show);
      menu.open('plan', const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Show in Explorer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-menu-show')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(it.ran, [const ShowCommand('explorer', ['/select,', r'C:\Ghost.md\workspaces\Work\Plan.md'])]);
      await away(tester);

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final ran = <ShowCommand>[];
      final linux = ShowInFiles(root: () async => root, web: false, exists: (_, {required directory}) => true, launch: (e, a) async => ran.add(ShowCommand(e, a)));
      expect(linux.label, 'Show in Files');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on Android: no row, whatever is on the disk', (tester) async {
      final it = showIn(TargetPlatform.android, onDisk: {'$root/workspaces/Work/Plan.md'});
      await tester.runAsync(it.show.refresh);
      final menu = await host(tester, it.show);
      menu.open('plan', const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-menu-show')), findsNothing);
      expect(rows(tester), ['Open', 'Pin', 'Archive', 'Delete']);
      await away(tester);
    });
  });

  group('a folder’s menu and a page’s', () {
    WorkspaceStore storeOf() => WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));

    Future<void> pump(WidgetTester tester, WorkspaceStore store, ShowInFiles show, Widget child, {Size size = const Size(390, 844)}) async {
      await pumpApp(
        tester,
        size: size,
        prefs: const AppPreferences(theme: 'light'),
        home: BackScope(child: FolderMenuScope(store: store, onRename: (_) {}, onDelete: (_) {}, onDeleteAll: (_) {}, show: show, child: child)),
      );
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
      await tester.pump();
    }

    Future<void> rightClick(WidgetTester tester, Finder on) async {
      final mouse = await tester.startGesture(tester.getCenter(on), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Widget icons(WorkspaceStore store) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: IconBrowser(folders: folderTiles(store.value.list, store.value.of, organizeNotes(), null), notes: organizeNotes().take(3).toList(), onFolder: (_) {}, onOpen: (_) {}, now: organizeNow, store: store),
          ),
        );

    testWidgets('a folder’s tile on a Mac: Show in Finder after Move to, before the deletes, for a nested folder too', (tester) async {
      final store = storeOf();
      final it = showIn(TargetPlatform.macOS, onDisk: {'$root/workspaces/Work/', '$root/workspaces/Work/Clients/'});
      await tester.runAsync(it.show.refresh);
      await pump(tester, store, it.show, icons(store));
      await rightClick(tester, find.byKey(const ValueKey('tile-folder-work')));
      expect(find.byKey(const ValueKey('folder-menu-show')), findsOneWidget);
      final children = tester.widget<GlacierMenu>(find.byType(GlacierMenu)).children;
      final at = children.indexWhere((row) => row.key == const ValueKey('folder-menu-show'));
      expect(children[at + 1], isA<GlacierMenuSeparator>());
      expect(find.byKey(const ValueKey('move-to-home')), findsOneWidget, reason: 'Move to, above it');
      expect(children.indexWhere((row) => row.key == const ValueKey('folder-menu-rename')), lessThan(at));
      expect(children.indexWhere((row) => row.key == const ValueKey('folder-menu-remove')), greaterThan(at));
      await tester.tap(find.byKey(const ValueKey('folder-menu-show')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 300));
      expect(it.ran, [const ShowCommand('open', ['-R', '$root/workspaces/Work'])]);
      expect(it.show.offer('workspaces/Work/Clients', directory: true), 'Show in Finder');
      // Home has never had a file filed in it: no directory, no row.
      await rightClick(tester, find.byKey(const ValueKey('tile-folder-home')));
      expect(find.text('Rename…'), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-menu-show')), findsNothing);
      await away(tester);
    });

    testWidgets('a folder’s tile on Android: no row', (tester) async {
      final store = storeOf();
      final it = showIn(TargetPlatform.android, onDisk: {'$root/workspaces/Work/'});
      await pump(tester, store, it.show, icons(store));
      await rightClick(tester, find.byKey(const ValueKey('tile-folder-work')));
      expect(find.text('Rename…'), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-menu-show')), findsNothing);
      await away(tester);
    });

    testWidgets('a page’s … in the sidebar on Linux: Show in Files opens the folder it is in', (tester) async {
      const work = Workspace(id: 'w-work', name: 'Work');
      final store = WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [work], notes: {'standup': 'w-work'})));
      final standup = Note(id: 'standup', body: '# Standup\n', createdAt: 0, updatedAt: 1, path: 'workspaces/Work/Standup.md');
      final it = showIn(TargetPlatform.linux, onDisk: {'$root/workspaces/Work/Standup.md'});
      await tester.runAsync(it.show.refresh);
      final tree = NoteTree(
        notes: [standup],
        activeId: null,
        onOpen: (_) {},
        onNew: () {},
        onCommands: () {},
        onTickets: () {},
        workspaces: store,
        stored: MemoryStored(),
        trashed: const [],
        onRestore: (_) {},
        onDestroy: (_) {},
        onEmptyTrash: () {},
        spaces: const SidebarSpaces(),
      );
      await pump(tester, store, it.show, Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: tree)));
      await tester.tap(find.bySemanticsLabel('Unfold Work'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('More for Standup').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-menu-show')), findsOneWidget);
      expect(find.text('Show in Files'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-menu-show')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(it.ran, [const ShowCommand('xdg-open', ['$root/workspaces/Work'])]);
      await away(tester);
    });
  });
}
