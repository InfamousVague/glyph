import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/favorites.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/page_tree.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/space_pages.dart';
import 'package:ghost_md/team/presence_avatars.dart' show PresenceMarked;

import '../library/support.dart';
import '../support/render.dart';
import 'support.dart';

/// The sidebar as spaces and pages (docs/TEAMSPACES.md; Matt, 2026-10-31: "Space switcher + sections";
/// lib/notes/note_tree_spaces.dart): the switcher scoping the tree, the fixed rows and the sections, the favorites,
/// the nested page rows and their folds, the + making a page inside a plain note, a drag writing `order:` and a drag
/// into a page moving its file, a refused drag's words, simple mode's More, the presence marks, and the same widget
/// at a phone's width and a desktop's.
void main() {
  setUpAll(loadAppFonts);

  var clock = 0;
  Note at(String id, String path, [String? body]) => Note(id: id, body: body ?? '# ${path.split('/').last.replaceAll('.md', '')}\n', createdAt: 0, updatedAt: clock += 1, path: path);

  const work = Workspace(id: 'w-work', name: 'Work');
  const acme = Workspace(id: 'org-acme', name: 'Acme', hue: 'sea');

  final notes = [
    at('loose', 'Inbox/Loose.md'),
    at('plan', 'workspaces/Work/Plan/index.md', '# Plan\n\nThe plan.'),
    at('step1', 'workspaces/Work/Plan/Step one.md'),
    at('step2', 'workspaces/Work/Plan/Step two.md'),
    at('standup', 'workspaces/Work/Standup.md'),
    at('home', 'orgs/Acme/Home.md', '---\ntitle: Home\ntype: teamspace\n---\n# Acme\n'),
    at('roadmap', 'orgs/Acme/Roadmap.md', '---\nicon: 🚀\n---\n# Roadmap\n'),
    at('client', 'orgs/Acme/Clients/A.md'),
  ];

  WorkspaceStore store() => WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [work, acme], notes: {'plan': 'w-work', 'standup': 'w-work'})));

  Future<void> show(WidgetTester tester, Widget tree, {Size size = const Size(390, 844), double width = 320}) =>
      pumpPage(tester, BackScope(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: tree))), size: size);

  NoteTree tree({
    List<Note>? of,
    WorkspaceStore? spaces,
    Stored? kept,
    SidebarSpaces given = const SidebarSpaces(),
    bool simple = false,
    void Function(String id)? onOpen,
    List<Note> trashed = const [],
  }) =>
      NoteTree(
        notes: of ?? notes,
        activeId: null,
        onOpen: onOpen ?? (_) {},
        onNew: () {},
        onCommands: () {},
        onTickets: () {},
        workspaces: spaces ?? store(),
        stored: kept ?? MemoryStored(),
        simple: simple,
        trashed: trashed,
        onRestore: (_) {},
        onDestroy: (_) {},
        onEmptyTrash: () {},
        spaces: given,
      );

  Finder row(String id) => find.byKey(ValueKey('page-row-$id'));
  Finder label(String words) => find.bySemanticsLabel(words);

  Future<void> unfold(WidgetTester tester, String title) async {
    await tester.tap(label('Unfold $title'));
    await tester.pump();
  }

  group('the switcher', () {
    testWidgets('shows Personal first, and an organization chosen scopes the tree, kept on the device', (tester) async {
      final kept = MemoryStored();
      await show(tester, tree(kept: kept));
      expect(find.text('Private'), findsOneWidget);
      expect(row('folder:Inbox'), findsOneWidget);
      expect(row('folder:workspaces/Work'), findsOneWidget);
      expect(row('roadmap'), findsNothing, reason: "an organization's pages are not Personal's");

      await tester.tap(find.byKey(const ValueKey('space-switcher-head')));
      await tester.pump();
      expect(find.byKey(const ValueKey('space-choice-personal')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('space-choice-org-acme')));
      await tester.pump();
      expect(find.text('Teamspace'), findsOneWidget);
      expect(find.text('Private'), findsNothing);
      expect(row('roadmap'), findsOneWidget);
      expect(find.descendant(of: row('roadmap'), matching: find.text('🚀')), findsOneWidget, reason: "the page's icon: is its mark");
      expect(row('folder:orgs/Acme/Clients'), findsOneWidget);
      expect(row('home'), findsNothing, reason: "the space's home is its Home row, not a page under it");
      expect(row('folder:Inbox'), findsNothing);
      expect(kept.readText('glyph-sidebar-space'), 'org-acme');

      // Made again over the same device's memory: still the organization.
      await away(tester);
      await show(tester, tree(kept: kept));
      expect(find.text('Teamspace'), findsOneWidget);
      await away(tester);
    });
  });

  group('the fixed rows and the sections', () {
    testWidgets('Home, Search, My tickets, Triage and Updates, and Home is the shown space\'s', (tester) async {
      final homes = <Space>[];
      var updates = 0, triage = 0;
      await show(tester, tree(given: SidebarSpaces(onHome: homes.add, onTriage: () => triage += 1, onUpdates: () => updates += 1)));
      for (final key in ['space-home', 'space-search', 'tree-tickets', 'space-triage', 'space-updates', 'section-pages']) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '$key is drawn');
      }
      await tester.tap(find.byKey(const ValueKey('space-home')));
      await tester.tap(find.byKey(const ValueKey('space-triage')));
      await tester.tap(find.byKey(const ValueKey('space-updates')));
      await tester.pump();
      expect((homes.single.isPersonal, triage, updates), (true, 1, 1));
      expect(find.byKey(const ValueKey('section-favorites')), findsNothing, reason: 'no favorites, no section');
      expect(find.text('Shared with me'), findsNothing, reason: 'nothing marks a note as shared to this person yet');
      // The archive and the trash, after the pages in advanced mode.
      await away(tester);
      await show(tester, tree(trashed: [at('gone', 'Inbox/Gone.md')]));
      expect(find.byKey(const ValueKey('folder-trash')), findsOneWidget);
      await away(tester);
    });

    testWidgets('a section folds, and its fold is kept', (tester) async {
      final kept = MemoryStored();
      await show(tester, tree(kept: kept));
      await tester.tap(label('Private'));
      await tester.pump();
      expect(row('folder:Inbox'), findsNothing);
      await away(tester);
      await show(tester, tree(kept: kept));
      expect(row('folder:Inbox'), findsNothing);
      await away(tester);
    });
  });

  group('favorites', () {
    testWidgets("the space's favorites over its pages, and the … menu adds and takes one off", (tester) async {
      final said = <(String, bool)>[];
      await show(tester, tree(given: SidebarSpaces(favorites: const ['standup', 'roadmap'], onFavorite: (id, on) => said.add((id, on)))));
      expect(find.byKey(const ValueKey('section-favorites')), findsOneWidget);
      expect(find.byKey(const ValueKey('favorite-row-standup')), findsOneWidget);
      expect(find.byKey(const ValueKey('favorite-row-roadmap')), findsNothing, reason: "Acme's favorite is Acme's");

      await tester.tap(label('More for Standup').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Favorites'));
      await tester.pumpAndSettle();
      expect(said, [('standup', false)]);

      await unfold(tester, 'Inbox');
      await tester.tap(label('More for Loose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Favorites'));
      await tester.pumpAndSettle();
      expect(said.last, ('loose', true));
      await away(tester);
    });

    test('are kept in the preferences, each once, and off the store when none is left', () {
      var prefs = Preferences.defaults;
      prefs = withFavorite(withFavorite(withFavorite(prefs, 'a', true), 'b', true), 'a', true);
      expect(favoritesIn(prefs), ['a', 'b']);
      prefs = withFavorite(withFavorite(prefs, 'a', false), 'b', false);
      expect((favoritesIn(prefs), prefs.toJson().containsKey(favoritesKey)), (const <String>[], false));
      expect(favoritesIn(Preferences.fromJson({'favorites': ['x', 7, 'x', 'y']})), ['x', 'y']);
    });
  });

  group('the page rows', () {
    testWidgets('nest as folders and their pages do, shut until unfolded, the folds kept on the device', (tester) async {
      final kept = MemoryStored();
      final opened = <String>[];
      await show(tester, tree(kept: kept, onOpen: opened.add));
      expect(row('plan'), findsNothing, reason: 'shut until opened');
      await unfold(tester, 'Work');
      expect(row('plan'), findsOneWidget);
      expect(row('standup'), findsOneWidget);
      expect(tester.getTopLeft(row('plan')).dy, lessThan(tester.getTopLeft(row('standup')).dy));
      await unfold(tester, 'Plan');
      expect(row('step1'), findsOneWidget);
      expect(tester.getTopLeft(find.descendant(of: row('step1'), matching: find.text('Step one'))).dx, greaterThan(tester.getTopLeft(find.descendant(of: row('plan'), matching: find.text('Plan'))).dx), reason: 'a sub-page stands in from its page');
      await tester.tap(find.text('Step one'));
      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(opened, ['step1', 'plan'], reason: "a folder's page opens as a page");
      expect(readOpenPages(kept), {'folder:workspaces/Work', 'plan'});
      // The presence marks stand after each page's name.
      expect(find.descendant(of: row('step1'), matching: find.byType(PresenceMarked)), findsOneWidget);
      expect(find.descendant(of: row('plan'), matching: find.byType(PresenceMarked)), findsOneWidget);
      await away(tester);
    });

    testWidgets('Rename… in the … menu changes the name on the row itself', (tester) async {
      final renamed = <(String, String)>[];
      await show(tester, tree(given: SidebarSpaces(onRename: (id, title) => renamed.add((id, title)))));
      await unfold(tester, 'Work');
      await tester.tap(label('More for Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-rename')), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('page-rename')), matching: find.byType(EditableText)), '  Daily   standup ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(renamed, [('standup', 'Daily standup')]);
      expect(find.byKey(const ValueKey('page-rename')), findsNothing);
      await away(tester);
    });

    testWidgets('a note with no file yet is still listed, after Personal\'s pages', (tester) async {
      await show(tester, tree(of: [...notes, const Note(id: 'draft', body: '# Draft\n', createdAt: 0, updatedAt: 0)]));
      expect(row('draft'), findsOneWidget);
      await away(tester);
    });
  });

  group('writing', () {
    Future<({FakeCore core, ValueListenable<List<Note>> notes, PageMover mover, WorkspaceStore workspaces})> over(void Function(FakeCore core) seed) async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      seed(core);
      await library.load();
      late final WorkspaceStore workspaces;
      final folders = NoteFolders(library, workspaces: () => workspaces.value.list);
      workspaces = WorkspaceStore(onFiled: folders.fileNotesInFolder);
      return (core: core, notes: library, mover: PageMover(library: library, workspaces: workspaces), workspaces: workspaces);
    }

    Widget live(ValueListenable<List<Note>> notes, WorkspaceStore workspaces, SidebarSpaces given, {Stored? kept, void Function(String id)? onOpen}) => ValueListenableBuilder<List<Note>>(
          valueListenable: notes,
          builder: (context, list, _) => tree(of: list, spaces: workspaces, given: given, kept: kept ?? (MemoryStored()..write('glyph-tree-pages-open', ['folder:Inbox', 'plan'])), onOpen: onOpen),
        );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// A finger's drag: held, then carried to [to] in small steps, and let go.
    Future<void> carry(WidgetTester tester, Finder from, Offset to) async {
      final gesture = await tester.startGesture(tester.getCenter(from));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      final start = tester.getCenter(from);
      for (var i = 1; i <= 8; i += 1) {
        await gesture.moveTo(Offset.lerp(start, to, i / 8)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets("the + on a plain note makes it its folder's page and a new page inside it, and opens that", (tester) async {
      final o = (await tester.runAsync(() => over((core) => core.seed('plan', '# Plan\n', path: 'Inbox/Plan.md'))))!;
      final (:core, :notes, :mover, :workspaces) = o;
      final opened = <String>[];
      await show(tester, live(notes, workspaces, SidebarSpaces(mover: mover), onOpen: opened.add));
      expect(row('plan'), findsOneWidget);
      await tester.tap(label('Add a page inside Plan'));
      await settle(tester);
      expect(core.files, ['Inbox/Plan/Untitled.md', 'Inbox/Plan/index.md']);
      expect(opened, hasLength(1));
      final made = notes.value.firstWhere((note) => note.id == opened.single);
      expect(made.path, 'Inbox/Plan/Untitled.md');
      expect(row(made.id), findsOneWidget, reason: 'the page it was made in is unfolded to show it');
      await away(tester);
    });

    testWidgets("a row let go over another's top goes before it, written as the folder page's order:", (tester) async {
      final o = (await tester.runAsync(() => over((core) {
            core
              ..seed('plan', '# Plan\n', path: 'Inbox/Plan/index.md')
              ..seed('a', '# A\n', path: 'Inbox/Plan/A.md')
              ..seed('b', '# B\n', path: 'Inbox/Plan/B.md');
          })))!;
      final (:core, :notes, :mover, :workspaces) = o;
      await show(tester, live(notes, workspaces, SidebarSpaces(mover: mover)));
      final a = tester.getRect(row('a'));
      await carry(tester, row('b'), Offset(a.center.dx, a.top + 3));
      await settle(tester);
      final page = notes.value.firstWhere((note) => note.id == 'plan');
      expect(frontMatterList(page.body, 'order'), ['B', 'A']);
      expect(tester.getTopLeft(row('b')).dy, lessThan(tester.getTopLeft(row('a')).dy), reason: 'the tree reads the order back');
      expect(core.files, contains('Inbox/Plan/B.md'), reason: 'a reorder moves no file');
      await away(tester);
    });

    testWidgets("a row let go over another's middle moves into it through the mover", (tester) async {
      final o = (await tester.runAsync(() => over((core) {
            core
              ..seed('plan', '# Plan\n', path: 'Inbox/Plan.md')
              ..seed('spec', '# Spec\n', path: 'Inbox/Spec.md');
          })))!;
      final (:core, :notes, :mover, :workspaces) = o;
      final said = <String>[];
      await show(tester, live(notes, workspaces, SidebarSpaces(mover: mover, onSay: said.add)));
      await carry(tester, row('spec'), tester.getCenter(row('plan')));
      await settle(tester);
      expect(core.files, ['Inbox/Plan/Spec.md', 'Inbox/Plan/index.md']);
      expect(said, ['Moved Spec into Plan']);
      expect(row('spec'), findsOneWidget, reason: 'the page it went into is unfolded');
      await away(tester);
    });

    testWidgets('a move the plan refuses says why, and moves nothing', (tester) async {
      final o = (await tester.runAsync(() => over((core) {
            core
              ..seed('plan', '# Plan\n', path: 'Inbox/Plan/index.md')
              ..seed('a', '# A\n', path: 'Inbox/Plan/A.md')
              ..seed('spec', '# Spec\n', path: 'Inbox/Spec.md');
          })))!;
      final (:core, :notes, :mover, :workspaces) = o;
      final said = <String>[];
      await show(tester, live(notes, workspaces, SidebarSpaces(mover: mover, onSay: said.add)));
      final before = [...core.files];
      await carry(tester, row('plan'), tester.getCenter(row('spec')));
      await settle(tester);
      expect(said, [refusalWords(MoveRefusal.isFolder)]);
      expect(core.files, before);
      await away(tester);
    });
  });

  group('simple mode', () {
    testWidgets('keeps Triage, the archive and the trash behind More, which opens in place', (tester) async {
      final archived = Note(id: 'old', body: '# Old\n', createdAt: 0, updatedAt: 0, path: 'Inbox/Old.md', archivedAt: 5);
      await show(tester, tree(of: [...notes, archived], simple: true, trashed: [at('gone', 'Inbox/Gone.md')], given: SidebarSpaces(onTriage: () {}, onUpdates: () {}, onHome: (_) {})));
      expect(find.byKey(const ValueKey('space-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('space-updates')), findsOneWidget);
      expect(find.byKey(const ValueKey('space-triage')), findsNothing);
      expect(find.byKey(const ValueKey('folder-row-archive')), findsNothing);
      expect(find.byKey(const ValueKey('folder-trash')), findsNothing);
      expect(label('New workspace'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('space-more')));
      await tester.pump();
      expect(find.byKey(const ValueKey('space-triage')), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-row-archive')), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-trash')), findsOneWidget);
      await away(tester);
    });
  });

  group('one widget at every width', () {
    testWidgets("at a phone's width every row is a finger's 44 tall, and its + and … are there", (tester) async {
      await show(tester, tree(given: SidebarSpaces(mover: PageMover(library: libraryOver().library, workspaces: WorkspaceStore()), onHome: (_) {})), size: const Size(390, 844), width: 320);
      await unfold(tester, 'Work');
      for (final id in ['folder:Inbox', 'plan', 'standup']) {
        expect(tester.getSize(row(id)).height, greaterThanOrEqualTo(44), reason: '$id is a finger tall');
      }
      expect(tester.getSize(find.byKey(const ValueKey('space-home'))).height, greaterThanOrEqualTo(44));
      expect(label('Add a page inside Plan'), findsOneWidget);
      expect(label('More for Plan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets("at a desktop's width the rows are a mouse's, and the same tree", (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await show(tester, tree(given: SidebarSpaces(mover: PageMover(library: libraryOver().library, workspaces: WorkspaceStore()))), size: const Size(1280, 800), width: 280);
        await unfold(tester, 'Work');
        expect(row('plan'), findsOneWidget);
        expect(tester.getSize(row('plan')).height, lessThan(44));
        // The … waits for the pointer.
        final more = find.descendant(of: find.bySemanticsLabel('More for Plan'), matching: find.byType(Opacity)).first;
        expect(tester.widget<Opacity>(more).opacity, 0);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(row('plan')));
        await tester.pump();
        expect(tester.widget<Opacity>(more).opacity, 1);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
        await away(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test('withPageTitle retitles a heading, a front matter title, or puts a heading over the first line', () {
    expect(withPageTitle('# Plan\n\nWords.', 'Roadmap'), '# Roadmap\n\nWords.');
    expect(withPageTitle('---\ntitle: Plan\n---\nWords.', 'Roadmap'), '---\ntitle: Roadmap\n---\nWords.');
    expect(withPageTitle('---\nicon: x\n---\n## Plan\nWords.', 'Roadmap'), '---\nicon: x\n---\n## Roadmap\nWords.');
    expect(withPageTitle('Words first.', 'Roadmap'), '# Roadmap\nWords first.');
    expect(withPageTitle('# Plan', '  '), '# Plan');
  });

  test('the space and the folds are kept on the device', () {
    final kept = MemoryStored();
    expect(readSidebarSpace(kept), personalSpaceId);
    writeSidebarSpace('org-acme', kept);
    writeOpenPages({'plan'}, kept);
    expect(readSidebarSpace(kept), 'org-acme');
    expect(readOpenPages(kept), {'plan'});
  });
}
