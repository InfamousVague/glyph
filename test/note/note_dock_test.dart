// A note's dock (docs/DOCK.md, lib/note/note_screen.dart `NoteScreen.dock`): Claude about the note first, the note's
// own actions for what is up, its ⋯ last; each press the screen's own; and the dock stepping aside while the
// keyboard is up in the note, and back when it goes.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/book/journal.dart' show journalNoteBody;
import 'package:ghost_md/book/journal_view.dart';
import 'package:ghost_md/canvas/add_sheet.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/minimap.dart';
import 'package:ghost_md/canvas/sample_canvas.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/shell/page_dock.dart';

import '../shell/dock_support.dart';
import '../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'dock${made += 1}', body)))!;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a note’s words: Claude, Find in note, Speak, Add and its ⋯, each the screen’s own', (tester) async {
    final world = NoteWorld();
    final asked = <String>[];
    final seams = NoteSeams(onFind: (view, initial) => asked.add('find "$initial"'), onAdd: (view) => asked.add('add at ${view.state.selection.main.head}'));
    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), seams: seams, speak: true, dock: PageDockSeam(claude: fakeClaude(asked)));
    await settle(tester);
    expect(dockOrder(tester), ['claude', 'note-find', 'note-speak', 'note-add', 'note-options']);
    expect(find.bySemanticsLabel('Find in note'), findsOneWidget);
    expect(find.bySemanticsLabel('Add to this line'), findsOneWidget);
    expect(find.bySemanticsLabel('Note options'), findsOneWidget);
    expect(find.bySemanticsLabel('Note actions'), findsOneWidget);
    expectInCorner(tester);

    await tester.tap(find.byKey(const ValueKey('dock-claude')));
    await tester.tap(find.byKey(const ValueKey('dock-note-find')));
    await tester.tap(find.byKey(const ValueKey('dock-note-add')));
    await tester.tap(find.byKey(const ValueKey('dock-note-speak')));
    await tester.pump();
    expect(asked, ['claude Plan', 'find ""', 'add at 0']);
    expect(world.asked, contains('speak ${world.library.value.last.id}'));
    // The ⋯ is the More sheet, the header's own.
    await tester.tap(find.byKey(const ValueKey('dock-note-options')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NoteSettings), findsOneWidget);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('steps aside while the keyboard is up in the note, so it never stands over the caret, and comes back', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), seams: NoteSeams(onFind: (view, initial) {}), dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(dockShown(tester), isTrue);
    expect(find.bySemanticsLabel('Find in note'), findsOneWidget);

    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await settle(tester);
    expect(dockShown(tester), isFalse);
    expect(tester.widget<IgnorePointer>(find.descendant(of: find.byKey(const ValueKey('page-dock')), matching: find.byType(IgnorePointer)).first).ignoring, isTrue);
    expect(tester.widget<ExcludeSemantics>(find.descendant(of: find.byKey(const ValueKey('page-dock')), matching: find.byType(ExcludeSemantics)).first).excluding, isTrue, reason: 'nothing of it is read while it is aside');

    tester.view.resetViewInsets();
    await settle(tester);
    expect(dockShown(tester), isTrue);
    expect(find.bySemanticsLabel('Find in note'), findsOneWidget);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('a note read only, or a spoken one, has no Add and no Speak; the ⋯ stays', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), seams: NoteSeams(onFind: (view, initial) {}, onAdd: (view) {}), speak: true, readOnly: true, dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(dockOrder(tester), ['claude', 'note-find', 'note-options']);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('a canvas: Claude, its own Add a card and Fit, and its ⋯; the map stands clear of the dock', (tester) async {
    final world = NoteWorld();
    final asked = <String>[];
    await pumpNote(tester, world, await seeded(tester, world, sampleCanvasBody()), seams: NoteSeams(canvas: canvasSeam()), dock: PageDockSeam(claude: fakeClaude(asked)));
    await settle(tester);
    expect(dockOrder(tester), ['claude', 'canvas-add', 'canvas-fit', 'note-options']);
    expect(find.bySemanticsLabel('Canvas options'), findsOneWidget);
    expect(find.bySemanticsLabel('Canvas actions'), findsOneWidget);
    // The canvas's map is at the dock's start, not under it.
    expect(tester.getRect(find.byType(Minimap)).right, lessThan(tester.getRect(find.byType(PageDock)).left));

    await tester.tap(find.byKey(const ValueKey('dock-claude')));
    expect(asked, ['claude $canvasTitle']);
    expect(find.byType(AddSheet), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dock-canvas-add')));
    await settle(tester);
    expect(find.byType(AddSheet), findsOneWidget, reason: 'the toolbar’s own Add: its sheet of kinds');
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('a notebook’s index: Claude, Add a page, Read straight through and its ⋯; reading, the way back', (tester) async {
    final world = NoteWorld();
    final seams = NoteSeams(
      book: (context, body, onChange) => BookView(body: body, known: (_) => true, open: (_) {}, titles: () => const [], title: 'Trip', onChange: onChange),
    );
    await pumpNote(tester, world, await seeded(tester, world, bookNoteBody('Trip', ['Day one', 'Day two'])), seams: seams, dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(dockOrder(tester), ['claude', 'book-add-page', 'book-read', 'note-options']);
    expect(find.bySemanticsLabel('Notebook options'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dock-book-read')));
    await settle(tester);
    expect(tester.state<BookViewState>(find.byType(BookView)).reading, isTrue);
    expect(dockOrder(tester), ['claude', 'book-add-page', 'book-index', 'note-options']);
    await tester.tap(find.byKey(const ValueKey('dock-book-index')));
    await settle(tester);
    expect(tester.state<BookViewState>(find.byType(BookView)).reading, isFalse);

    // Add a page: the index's own form, its field there to be written in.
    await tester.tap(find.byKey(const ValueKey('dock-book-add-page')));
    await settle(tester);
    expect(find.byKey(const ValueKey('book-page-title')), findsOneWidget);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('a journal: Claude, New entry and its ⋯; New entry opens the templates', (tester) async {
    final world = NoteWorld();
    final seams = NoteSeams(
      journal: (context, body, onChange) => JournalView(body: body, noteOf: (_) => null, known: (_) => false, open: (_) {}, onChange: onChange, onNewEntry: (_) {}),
    );
    await pumpNote(tester, world, await seeded(tester, world, journalNoteBody('Days', '', false)), seams: seams, dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(dockOrder(tester), ['claude', 'journal-new-entry', 'note-options']);
    expect(find.bySemanticsLabel('Journal options'), findsOneWidget);
    expect(find.bySemanticsLabel('Start the entry with'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dock-journal-new-entry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('journal-choose')), findsOneWidget);
    await closeNote(tester);
    await done(tester);
  });
  testWidgets('one microphone (GHST-104): with Talk to Claude on the dock the note’s own Speak is left off, and is back without it', (tester) async {
    final world = NoteWorld();
    final asked = <String>[];
    final seams = NoteSeams(onFind: (view, initial) => asked.add('find "$initial"'), onAdd: (view) => asked.add('add at ${view.state.selection.main.head}'));
    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), seams: seams, speak: true, dock: PageDockSeam(claude: fakeClaude(asked), talk: fakeClaude(asked)));
    await settle(tester);
    expect(dockOrder(tester), isNot(contains('note-speak')));
    expect(dockOrder(tester), containsAll(['note-find', 'note-add', 'note-options']));
    await closeNote(tester);
    await done(tester);

    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), seams: seams, speak: true, dock: PageDockSeam(claude: fakeClaude(asked)));
    await settle(tester);
    expect(dockOrder(tester), contains('note-speak'));
    await closeNote(tester);
    await done(tester);
  });
}
