import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/book/journal_view.dart';
import 'package:ghost_md/book/new_book_sheet.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/canvas/json_canvas.dart' show isCanvasBody;
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/notes/note_templates.dart';

/// What a notebook's presses do to the library (lib/book `BookPages`, `JournalPages`, `NewBooks`): each write goes
/// through the [NoteLibrary], and the note it leaves is the Markdown `src/app/App.tsx` writes for the same press.
/// These are App.tsx's own paths, which the web tests only through the whole app; here over the library in memory.
void main() {
  final at = DateTime(2026, 10, 8, 15, 30);
  late SampleLibrary library;
  late List<Note> shown;
  late BookPages pages;

  setUp(() {
    useStored(MemoryStored());
    library = SampleLibrary([], clock: () => at.millisecondsSinceEpoch);
    shown = [];
    pages = BookPages(library, show: shown.add, clock: () => at);
  });

  test('a new notebook and a new journal are one note each, as the page writes them', () async {
    final books = NewBooks(library);
    final book = await books.createBook('Cabin trip', ['Packing', 'Days']);
    expect(book.body, '---\ntitle: "Cabin trip"\nbook: true\n---\n# Cabin trip\n\n- [[Packing]]\n- [[Days]]\n');
    final journal = await books.createJournal('Diary', defaultTemplate, true);
    expect(journal.body, journalNoteBody('Diary', defaultTemplate, true));
    expect(isJournalBody(library.noteOf(journal.id)!.body), isTrue);
    await pages.open('Packing');
    // What can be a page of the next notebook: no notebook, no journal.
    expect(books.pageTitles(), ['Packing']);
  });

  test('a page opened from the index is made once, as its heading, and found the second time', () async {
    await pages.open('Rivers');
    expect(shown.single.body, '# Rivers\n\n');
    await pages.open('rivers');
    expect(shown.map((n) => n.id).toSet(), hasLength(1));
    expect(library.value, hasLength(1));
    expect(pages.known('Rivers'), isTrue);
    expect(pages.bodyOf('Rivers'), '# Rivers\n\n');
  });

  test('a page from a template keeps its title as its heading over the template filled for the minute', () async {
    await pages.openNew('Monday', entryPresets[2].text, 'Field guide');
    expect(shown.single.body, startsWith('# Monday\n\n## '));
    expect(shown.single.body, contains('> What is on your mind this morning?'));
    await pages.openCanvas('Trail map');
    expect(isCanvasBody(shown.last.body), isTrue);
    expect(noteTitle(shown.last.body), 'Trail map');
  });

  test('a ticket takes the notebook’s next key and its first open status, and its status is written to its page', () async {
    final notebook = withNotebookKey(bookNoteBody('Ghost.md', ['Fix the login loop']), 'GHO');
    await library.createNote('---\ntype: ticket\nid: GHO-12\nstatus: Done\n---\n# Fix the login loop\n');
    await pages.openTicket('Session cookie expires', notebook, null);
    expect(shown.single.body, newTicketBody('Session cookie expires', id: 'GHO-13', statuses: const ['To do', 'In progress', 'In review', 'Done']));
    expect(shown.single.body, contains('id: GHO-13'));
    final bug = builtIns.firstWhere((one) => one.kind == TemplateId.bug);
    await pages.openTicket('Crash on launch', notebook, bug);
    expect(shown.last.body, contains('GHO-14'));
    expect(noteTitle(shown.last.body), 'Crash on launch');
    await pages.setStatus('Session cookie expires', 'In review');
    expect(pages.bodyOf('Session cookie expires'), contains('status: In review'));
    await pages.setStatus('Session cookie expires', null);
    expect(pages.bodyOf('Session cookie expires'), isNot(contains('status:')));
  });

  test('a new entry is named for the minute, listed in its journal and made from the template chosen, once a press', () async {
    final journal = await NewBooks(library).createJournal('Diary', defaultTemplate, false);
    // The records' clock is the entry's: one read by the real one would be more than a week old from 2026-10-15.
    final untouched = UntouchedNotes(kept: MemoryStored(), clock: () => at.millisecondsSinceEpoch);
    final entries = JournalPages(library, untouched: untouched, clock: () => at);
    final both = await Future.wait([entries.newEntry(journal.id), entries.newEntry(journal.id)]);
    // A second press before the first is open is the same press.
    expect(both.where((note) => note != null), hasLength(1));
    final first = both.firstWhere((note) => note != null)!;
    expect(first.body, '---\ntitle: "2026-10-08 15.30"\ndate: 2026-10-08T15:30\n---\n# Thursday 8 October\n\n**15:30** ');
    expect([for (final c in chaptersOf((await library.get(journal.id))!.body)) c.title], ['2026-10-08 15.30']);
    expect(untouched.recordOf(first.id)?.journalId, journal.id);
    // A second entry in one minute is " (2)", from the template picked for it.
    final second = await entries.newEntry(journal.id, template: entryPresets[1].text);
    expect(noteTitle(second!.body), '2026-10-08 15.30 (2)');
    expect(second.body, endsWith('---\n**15:30** '));
    expect((await library.get(journal.id))!.body, endsWith('- [[2026-10-08 15.30]]\n- [[2026-10-08 15.30 (2)]]\n'));
    // Not a journal: nothing is made.
    final plain = await library.createNote('# Plain\n');
    expect(await entries.newEntry(plain.id), isNull);
  });
}
