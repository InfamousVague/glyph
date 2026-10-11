import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_nav.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/book/journal_view.dart';
import 'package:ghost_md/book/new_book_sheet.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/canvas_body.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/boards/boards.dart' show DrawnBoardBox;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/wiki_links.dart' show wikiOptions;
import 'package:ghost_md/editor/queries/queries.dart' show QueryView, queriesWatchMidnight;
import 'package:ghost_md/editor/tickets/tickets.dart' show TicketPanel;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/notes/template_cards.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Stages 5 and 6 in the app put together (lib/root): a note draws its boards, its queries and a ticket's panel; a
/// notebook, a journal and a canvas take the page in place of their words; the + opens the sheet of what it makes;
/// and a new note's blank page offers its names and templates.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    // A query's clock for midnight would outlive the test.
    queriesWatchMidnight = false;
  });

  Future<SampleLibrary> open(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
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
  NoteScreenState screenOf(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen));

  Note titled(SampleLibrary library, String title) => library.value.firstWhere((note) => noteTitle(note.body) == title);

  Future<void> openNote(WidgetTester tester, String id) async {
    shellOf(tester).openNote(id);
    await settle(tester);
  }

  /// Lets go of the app, and of the timers a note's screen leaves (its place, its save).
  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  group('a note of words', () {
    testWidgets('draws its board in place of the fence, and the band is told boards are drawn', (tester) async {
      final library = await open(tester);
      await openNote(tester, titled(library, 'Launch week').id);
      expect(find.byType(DrawnBoardBox), findsOneWidget);
      expect(tester.widget<ContextBand>(find.byType(ContextBand)).boards, isTrue);
      await close(tester);
    });

    testWidgets('draws a query as what it finds, and again when another note changes', (tester) async {
      final library = await open(tester);
      await openNote(tester, titled(library, 'This sprint').id);
      expect(find.byType(QueryView), findsOneWidget);
      final ticket = library.value.firstWhere((note) => note.body.contains('type: ticket') && !note.body.contains('status: Done'));
      final name = noteTitle(ticket.body);
      expect(find.descendant(of: find.byType(QueryView), matching: find.textContaining(name)), findsWidgets);
      // The ticket is closed somewhere else: the library says so, and the query is run again without it.
      await tester.runAsync(() => library.save(ticket.id, ticket.body.replaceFirst(RegExp(r'status: .*'), 'status: Done')));
      await settle(tester);
      expect(find.descendant(of: find.byType(QueryView), matching: find.textContaining(name)), findsNothing);
      await close(tester);
    });

    testWidgets('draws a ticket\'s front matter as its panel, and opens a ticket by its key', (tester) async {
      final library = await open(tester);
      final ticket = library.value.firstWhere((note) => note.body.contains('type: ticket'));
      await openNote(tester, ticket.id);
      expect(find.byType(TicketPanel), findsOneWidget);
      final key = RegExp(r'^id: (\S+)', multiLine: true).firstMatch(ticket.body)!.group(1)!;
      final other = library.value.firstWhere((note) => note.body.contains('type: ticket') && note.id != ticket.id);
      await openNote(tester, other.id);
      // What a `[[KEY]]` tapped asks of the app.
      final view = screenOf(tester).view!;
      expect(view.state.facet(wikiOptions)?.known(key), isTrue, reason: 'a ticket is found by its key');
      expect(view.state.facet(wikiOptions)?.known('NOPE-404'), isFalse);
      view.state.facet(wikiOptions)!.open(key);
      await settle(tester);
      expect(shellOf(tester).shown, ticket.id);
      await close(tester);
    });
  });

  group('a note that is not words', () {
    testWidgets('a notebook opens on its index, and a page of it wears the notebook\'s bar', (tester) async {
      final library = await open(tester);
      final book = titled(library, 'Portugal');
      await openNote(tester, book.id);
      expect(find.byType(BookView), findsOneWidget);
      expect(find.textContaining('says which stage'), findsNothing);
      // A page opened from the index takes the notebook's tab.
      tester.widget<BookView>(find.byType(BookView)).open('Packing');
      await settle(tester);
      expect(shellOf(tester).shown, titled(library, 'Packing').id);
      expect(find.byType(BookBar), findsOneWidget);
      expect(shellOf(tester).tabs.open.contains(book.id), isFalse, reason: 'the page took the notebook\'s tab');
      await close(tester);
    });

    testWidgets('a notebook opened from All notes goes back to the page it was left in, and its tab shows the index', (tester) async {
      final library = await open(tester);
      final book = titled(library, 'Portugal');
      await openNote(tester, book.id);
      tester.widget<BookView>(find.byType(BookView)).open('Packing');
      await settle(tester);
      final page = titled(library, 'Packing').id;
      expect(shellOf(tester).shown, page);
      // Left for All notes (App.tsx gives it `openNoteWhereLeft`): the notebook's card opens the page again.
      shellOf(tester).showAllNotes();
      await settle(tester);
      tester.widget<AllNotesScreen>(find.byType(AllNotesScreen)).onOpen(book.id);
      await settle(tester);
      expect(shellOf(tester).shown, page, reason: 'the notebook was left in Packing');
      // From the page itself the notebook is its index, or there would be no way back to it.
      shellOf(tester).openNote(book.id);
      await settle(tester);
      expect(shellOf(tester).shown, book.id);
      await close(tester);
    });

    testWidgets('a journal opens on its entries, and New entry makes one, puts its line in the index and opens it', (tester) async {
      final library = await open(tester);
      final made = library.create('---\ntitle: "Days"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n"\n---\n# Days\n\n');
      await tester.pump();
      await openNote(tester, made.id);
      expect(find.byType(JournalView), findsOneWidget);
      final before = library.value.length;
      await tester.runAsync(() async {
        tester.widget<JournalView>(find.byType(JournalView)).onNewEntry!('# {{date}}\n\n');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settle(tester);
      expect(library.value.length, before + 1);
      final entry = library.noteOf(shellOf(tester).shown!)!;
      expect(entry.id, isNot(made.id));
      expect(chaptersOf(screenOfJournal(library, made.id)).map((chapter) => chapter.title), contains(noteTitle(entry.body)));
      // Its caret is at the end of its words, and the entry wears the journal's bar.
      expect(find.byType(BookBar), findsOneWidget);
      await close(tester);
    });

    testWidgets('a canvas opens drawn, filling the page under the header', (tester) async {
      final library = await open(tester);
      final canvas = library.value.firstWhere((note) => isCanvasBody(note.body));
      await openNote(tester, canvas.id);
      expect(find.byType(CanvasView), findsOneWidget);
      final box = tester.getRect(find.byType(CanvasView));
      expect(box.width, 390);
      // `.body { padding-block-end: var(--app-safe-bottom) }`: it ends above the phone's own bar, the 20px
      // [pumpApp] gives the screen, as the page's canvas body does.
      expect(box.bottom, 844 - 20);
      expect(box.height, greaterThan(600));
      await close(tester);
    });
  });

  group('the +', () {
    testWidgets('opens the sheet of what it makes, and Note makes a note opened ready to type', (tester) async {
      final library = await open(tester);
      expect(tester.widget<NewSheet>(find.byType(NewSheet)).open, isFalse);
      tester.widget<AppShell>(find.byType(AppShell)).onNew!();
      await settle(tester);
      final sheet = tester.widget<NewSheet>(find.byType(NewSheet));
      expect(sheet.open, isTrue);
      expect(sheet.onCanvas, isNotNull);
      expect(sheet.onBook, isNotNull);
      final before = library.value.length;
      await tester.tap(find.byKey(const ValueKey('new-note')));
      await settle(tester);
      expect(tester.widget<NewSheet>(find.byType(NewSheet)).open, isFalse);
      expect(library.value.length, before + 1);
      final screen = screenOf(tester);
      expect(screen.body, '');
      expect(screen.offering, isTrue);
      expect(screen.view!.hasFocus, isTrue, reason: 'opened to be written in');
      await close(tester);
    });

    testWidgets('makes a canvas, and a notebook from the sheet that names it', (tester) async {
      final library = await open(tester);
      tester.widget<NewSheet>(find.byType(NewSheet)).onCanvas!();
      await settle(tester);
      expect(isCanvasBody(library.noteOf(shellOf(tester).shown!)!.body), isTrue);
      expect(find.byType(CanvasView), findsOneWidget);

      tester.widget<NewSheet>(find.byType(NewSheet)).onBook!();
      await settle(tester);
      final books = tester.widget<NewBookSheet>(find.byType(NewBookSheet));
      expect(books.open, isTrue);
      expect(books.titles, contains('Packing'));
      expect(books.titles, isNot(contains('Portugal')), reason: 'a notebook is not a page of another');
      books.onCreate('Field notes', const ['Packing']);
      await settle(tester);
      final made = library.noteOf(shellOf(tester).shown!)!;
      expect(isBookBody(made.body), isTrue);
      expect(noteTitle(made.body), 'Field notes');
      expect(find.byType(BookView), findsOneWidget);
      await close(tester);
    });
  });

  group('a new note\'s blank page', () {
    testWidgets('offers its names and the template cards once it is being written in, and a name names it', (tester) async {
      await open(tester);
      tester.widget<NewSheet>(find.byType(NewSheet)).onNote();
      await settle(tester);
      final screen = screenOf(tester);
      expect(screen.offersShown, isFalse, reason: 'a phone: not until the keyboard is up or the page is pressed');
      // The keyboard comes up.
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      await settle(tester, 2);
      expect(screen.offersShown, isTrue);
      expect(find.byType(TemplateCards), findsOneWidget);
      expect(find.byKey(const ValueKey('name-day')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('name-day')));
      await settle(tester, 3);
      expect(screen.body, startsWith('# '));
      expect(screen.offering, isFalse);
      expect(find.byType(TemplateCards), findsNothing);
      tester.view.resetViewInsets();
      await close(tester);
    });

    testWidgets('becomes the template whose card is pressed, as one change', (tester) async {
      await open(tester);
      tester.widget<NewSheet>(find.byType(NewSheet)).onNote();
      await settle(tester);
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      await settle(tester, 2);
      final cards = tester.widget<TemplateCards>(find.byType(TemplateCards));
      expect(cards.onYours, isNotNull);
      await tester.tap(find.byKey(const ValueKey('template-day')));
      await settle(tester, 3);
      final screen = screenOf(tester);
      expect(screen.body, startsWith('# '));
      expect(screen.body, contains('- [ ] '));
      expect(find.byType(TemplateCards), findsNothing);
      undo(screen.view!);
      await tester.pump();
      expect(screen.view!.state.doc.toString(), '');
      tester.view.resetViewInsets();
      await close(tester);
    });
  });
}

/// The journal's words as the library has them now.
String screenOfJournal(SampleLibrary library, String id) => library.noteOf(id)!.body;
