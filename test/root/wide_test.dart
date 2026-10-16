import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart' show GlacierContext;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/aside/aside.dart';
import 'package:ghost_md/aside/aside_history.dart';
import 'package:ghost_md/aside/aside_panel.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_file.dart' show Version;
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart' show ChangeSpec, TransactionSpec;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/note/version_history.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Stage 10's wide layouts in the app put together (lib/root), at the Fold's unfolded size (704 x 933 at 2.625):
/// the aside beside a notebook's page, as a card and docked; the docked sidebar; what is kept to the device; and a
/// phone folded shut and open again with a note on screen.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const unfolded = Size(704, 933);
  const cover = Size(475, 751);

  Future<SampleLibrary> open(WidgetTester tester, {Size size = unfolded, String sidebar = 'popover', Stored? stored}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      ratio: 2.625,
      prefs: Preferences(theme: 'dark', sidebarStyle: sidebar),
      home: GhostRoot(launch: false, library: library, stored: stored ?? MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  Note titled(SampleLibrary library, String title) => library.value.firstWhere((note) => noteTitle(note.body) == title);

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // What a note's screen asked of the library while it was up answers before the app goes.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2.625;
    await settle(tester, 4);
  }

  testWidgets('a notebook’s page has the side panel’s icon, and its card is the notebook’s index with the page marked', (tester) async {
    final local = MemoryStored();
    final library = await open(tester, stored: local);
    expect(find.bySemanticsLabel('Side panel'), findsNothing, reason: 'the home page has no use for an aside');
    shellOf(tester).openNote(titled(library, 'Lisbon, the first three days').id);
    await settle(tester);
    expect(find.byType(AsideCard), findsNothing, reason: 'hidden until it has been opened once');
    await tester.tap(find.bySemanticsLabel('Side panel'));
    await settle(tester);
    expect(find.byType(AsideCard), findsOneWidget);
    expect(readAsideShown(local), isTrue);
    expect(find.descendant(of: find.byType(AsidePanel), matching: find.text('Portugal')), findsOneWidget);
    // A chapter opened from it closes the card and opens the page in this tab's place.
    await tester.tap(find.descendant(of: find.byType(AsidePanel), matching: find.text('The coast')));
    await settle(tester);
    expect(find.byType(AsideCard), findsNothing);
    expect(shellOf(tester).shown, titled(library, 'The coast').id);
    expect(shellOf(tester).tabs.tabs.length, 1);
    // A note in no book has an aside since 2.1 all the same: its links and its outline (lib/links/note_links.dart),
    // and no index.
    shellOf(tester).openNote(titled(library, 'Groceries').id);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Side panel'));
    await settle(tester);
    expect(find.descendant(of: find.byType(AsidePanel), matching: find.text('Links')), findsWidgets);
    expect(find.descendant(of: find.byType(AsidePanel), matching: find.text('Index')), findsNothing);
    await close(tester);
  });

  // Unwired 25 (docs/PARITY.md), the aside's half: nothing gave the side panel its `history`, so on a desktop a note
  // in no notebook had no side panel at all and the bar's History opened More's page (App.tsx `asideHistory`,
  // `openHistoryAside`; aside/AsideHistory.tsx).
  testWidgets('on a desktop a note has its version history in the side panel, which the bar\'s History opens at it', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final local = MemoryStored();
      final library = await open(tester, size: const Size(1100, 800), stored: local);
      final note = titled(library, 'Groceries');
      shellOf(tester).openNote(note.id);
      await settle(tester);
      // A note in no notebook has a side panel all the same: its history. Hidden until it is asked for.
      expect(find.bySemanticsLabel('Side panel'), findsOneWidget);
      expect(find.byType(AsideHistory), findsNothing);
      final screen = tester.widget<NoteScreen>(find.byType(NoteScreen));
      expect(screen.onHistory, isNotNull, reason: 'the bar\'s History goes to the side panel');
      screen.onHistory!();
      await settle(tester);
      expect(find.byType(AsideHistory), findsOneWidget);
      expect(readAsideShown(local), isTrue);
      expect(readAsideTab(local), AsideTab.history);
      expect(find.descendant(of: find.byType(AsidePanel), matching: find.text('Version history')), findsOneWidget);
      // It keeps none yet, and says so, with the way to start one.
      expect(find.text('This note keeps no version history.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aside-history-on')));
      await settle(tester);
      expect(find.text('This note keeps no version history.'), findsNothing);
      final history = tester.widget<VersionHistory>(find.descendant(of: find.byType(AsideHistory), matching: find.byType(VersionHistory)));
      // The timeline compares with the editor's words as they are now, and puts a version back through the editor.
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '\nTyped beside the history.'), userEvent: 'input.type'));
      await tester.pump();
      expect(history.current(), endsWith('Typed beside the history.'));
      history.onRestore('# Groceries\n\nAs it was.', const Version(n: 1, at: 1, by: 'me', hash: 'h', text: '# Groceries\n\nAs it was.', added: 1, removed: 0));
      await settle(tester);
      expect(view.state.doc.toString(), '# Groceries\n\nAs it was.');
      // A canvas has no history worth reading, and the home page no side panel.
      shellOf(tester).backToList();
      await settle(tester);
      expect(find.bySemanticsLabel('Side panel'), findsNothing);
      await close(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a phone opened out keeps a note\'s history in its More sheet: its side panel has the note\'s links and outline, not its history', (tester) async {
    final library = await open(tester);
    shellOf(tester).openNote(titled(library, 'Groceries').id);
    await settle(tester);
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).onHistory, isNull);
    await tester.tap(find.bySemanticsLabel('Side panel'));
    await settle(tester);
    expect(find.descendant(of: find.byType(AsidePanel), matching: find.text('Outline')), findsWidgets);
    expect(find.byType(AsideHistory), findsNothing);
    // Folded shut, the cover screen has no room for one: no side panel, and no icon for it.
    await resize(tester, cover);
    expect(find.bySemanticsLabel('Side panel'), findsNothing);
    await close(tester);
  });

  testWidgets('docked, the sidebar and the aside are columns beside the note, shown as the device left them', (tester) async {
    final local = MemoryStored();
    writeSidebarShown(true, local);
    writeAsideShown(true, local);
    final library = await open(tester, sidebar: 'docked', stored: local);
    // `clamp(300px, 30vw, 380px)`: the tree, with the home page in the rest.
    expect(tester.getSize(find.bySemanticsLabel('All notes').first).width, 300);
    expect(find.byType(NoteTree), findsOneWidget);
    // A notebook's page, 164px wide between the two: its bar and its foot are cut by the pane, as the page's
    // are, and nothing gives up.
    final errors = <String>[];
    final was = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.toString().split('\n').take(8).join('\n'));
    shellOf(tester).openNote(titled(library, 'Packing').id);
    await settle(tester);
    FlutterError.onError = was;
    expect(errors, isEmpty);
    // `clamp(240px, 22vw, 320px)` at the right, and the note what is left between them.
    final aside = tester.getRect(find.byType(AsidePanel));
    expect(aside.width, closeTo(240, 1));
    expect(aside.right, 704);
    expect(find.byType(AsideCard), findsNothing);
    expect(tester.getRect(find.byType(NoteScreen)).width, closeTo(704 - 300 - 240, 1));
    // The bar's icon hides the column, and the device remembers.
    await tester.tap(find.bySemanticsLabel('All your notes'));
    await settle(tester);
    expect(find.byType(NoteTree), findsNothing);
    expect(readSidebarShown(local), isFalse);
    expect(tester.getRect(find.byType(NoteScreen)).width, closeTo(704 - 240, 1));
    await close(tester);
  });

  testWidgets('a phone folded shut and opened again keeps the note it had: the same screen, its scroll and its tab', (tester) async {
    final library = await open(tester, sidebar: 'docked');
    shellOf(tester).openNote(titled(library, 'Weekend trip').id);
    await settle(tester);
    final before = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final scroll = tester.widget<CustomScrollView>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(CustomScrollView)).first).controller!;
    scroll.jumpTo(120);
    await tester.pump();
    // Shut: the cover screen, one window. The sidebar is a card's again.
    await resize(tester, cover);
    expect(tester.takeException(), isNull);
    expect(tester.state<NoteScreenState>(find.byType(NoteScreen)), same(before));
    expect(scroll.offset, closeTo(120, 40));
    final shut = scroll.offset;
    expect(shellOf(tester).shown, titled(library, 'Weekend trip').id);
    // And open: two panes may be up again, and the note is still the one it was.
    await resize(tester, unfolded);
    expect(tester.state<NoteScreenState>(find.byType(NoteScreen)), same(before));
    expect(scroll.offset, closeTo(shut, 40));
    // Turned on its side, the unfolded display is still two panes' worth.
    await resize(tester, unfolded.flipped);
    expect(tester.takeException(), isNull);
    expect(tester.state<NoteScreenState>(find.byType(NoteScreen)), same(before));
    await close(tester);
  });

  testWidgets('a notebook’s words keep the split layout’s room under them, and the index starts that much lower', (tester) async {
    // On the page `.app-split .editor .cm-editor .cm-content { padding-block-end: var(--glacier-space-8) }` beats
    // `.preface .cm-editor .cm-content { padding-block: 0 }`: the Example project's three lines of preface were
    // 87.45px of lines in a box of 125.42 on the Fold opened (37.98 more), and 113.02 of lines in a box of 113.02
    // on the cover. Portugal's preface here is one line.
    final library = await open(tester);
    shellOf(tester).openNote(titled(library, 'Portugal').id);
    await settle(tester);
    final words = find.descendant(of: find.byType(BookWords), matching: find.byType(EditorColumn));
    final t = tester.element(find.byType(BookWords)).tokens;
    expect(t.space(8), closeTo(37.98, 0.02), reason: 'the page’s own at 704 wide');
    // One line of the note's type there, 29.15px (18.22 at 1.6), and the room.
    expect(tester.getSize(words).height, closeTo(29.15 + 37.98, 0.05));
    // `.preface { margin-block-end: space-4 }` over `.index { margin-block-start: space-3 }`, collapsed: 18.99.
    final row = tester.getRect(find.byKey(const ValueKey('book-row-0')));
    expect(row.top - tester.getRect(words).bottom, closeTo(18.99, 0.6));
    // Shut, the window is one pane and the words have no room under them, as on any phone.
    await resize(tester, cover);
    // Lines of 28.26px (17.66 at 1.6) and nothing else.
    final lines = tester.getSize(words).height / 28.258;
    expect(lines, closeTo(lines.roundToDouble(), 0.01));
    await close(tester);
  });

  testWidgets('the home page keeps its place through a fold too', (tester) async {
    await open(tester);
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(200);
    await tester.pump();
    await resize(tester, cover);
    expect(tester.takeException(), isNull);
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position, same(position));
    await resize(tester, unfolded);
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position, same(position));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
