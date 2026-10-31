/// The library as the app reads it for the note on screen: what `src/app/App.tsx` keeps in `useMemo`s and the two
/// hooks beside it, `shell/useTickets.ts` and `shell/useQueries.ts`. Every note by its title as a link finds it
/// (`byTitle`), the tickets and the notebook each is in, the notes a ```query reads, your own templates, the notes
/// that are a journal's entries or a template's pages (`entryIds`), the journals, and a note's place in its notebook
/// (`placeInBook`).
///
/// Each is read once per change to the notes and not once a draw: a notebook's index asks after every page on every
/// draw, and a ticket's panel after every other ticket. And each note's title and kind are read through the
/// reading kept for it (lib/core/note_facts.dart), not from its words again.
///
/// What differs: the page's memos are keyed by the lists themselves; here whoever holds the library says when it
/// changed ([changed]), and everything is read again the next time it is asked for.
library;

import '../book/journal_months.dart' show inTimeOrder;
import '../book/ticket_links.dart';
import '../book/tickets.dart';
import '../core/aliases.dart';
import '../core/book.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart';
import '../core/properties.dart';
import '../core/query/records.dart' show QueryNote;
import '../editor/tickets/ticket_work.dart' show TicketWorkOptions;
import '../editor/tickets/tickets.dart' show TicketOptions;
import '../notes/note_templates.dart';
import '../notes/own_templates.dart';
import '../perf/frame_log.dart';

class LibraryReads {
  LibraryReads({required this.shown, required this.all});

  /// The notes every screen shows: none in the Trash, none a pending delete is holding back.
  final List<Note> Function() shown;

  /// Every note the store has, the Trash's too.
  final List<Note> Function() all;

  List<Note>? _shown;
  List<TicketEntry>? _entries;
  TicketEntry? Function(String target)? _find;
  Note? Function(Note note)? _notebookOf;
  List<String>? _people;
  Map<String, Note>? _byTitle;
  List<QueryNote>? _queryNotes;
  ({List<NoteTemplate>? own})? _templates;
  Set<String>? _entryIds;
  List<Note>? _journals;

  /// The notes less the Templates notebooks, whose lines are templates' pages and no note's place.
  List<Note>? _plain;

  /// A note's place in its notebook, by the note it was asked of: the same object asked again is not looked up again.
  final Map<Note, BookPlace?> _places = Map<Note, BookPlace?>.identity();

  /// The notes changed: everything is read again when next asked for.
  void changed() {
    _plain = null;
    _places.clear();
    _shown = null;
    _entries = null;
    _progress = null;
    _find = null;
    _notebookOf = null;
    _people = null;
    _byTitle = null;
    _queryNotes = null;
    _templates = null;
    _entryIds = null;
    _journals = null;
  }

  List<Note> get notes => _shown ??= shown();

  /// Every ticket in the library, each in its notebook's workflow. A ticket's template page makes tickets and is
  /// not one.
  List<TicketEntry> get entries => _entries ??= ticketsIn(notes, (note) => NoteFacts.of(note).isTemplatePage);

  /// The ticket a key or a title names.
  TicketEntry? ticket(String target) => (_find ??= ticketFinder(entries))(target);

  /// The notebook a note is in.
  Note? notebookOf(Note note) => (_notebookOf ??= notebookFinder(notes))(note);

  /// The people the library names, the most named first; read the first time a picker asks.
  List<String> people() => _people ??= peopleIn([for (final note in notes) note.body]);

  /// The note by that title, as a `[[link]]` names it (`titled`): the first of any two that share one; a template's
  /// page only where no note of the person's has its name; and a ticket by its key where no note is called that.
  Note? titled(String title) {
    final key = titleKey(title);
    return key.isEmpty ? null : _titles[key];
  }

  Map<String, Note> get _titles {
    final had = _byTitle;
    if (had != null) return had;
    final map = <String, Note>{};
    for (final pages in const [false, true]) {
      for (final note in notes) {
        final facts = NoteFacts.of(note);
        if (facts.isTemplatePage != pages) continue;
        final key = facts.key;
        if (key.isNotEmpty) map.putIfAbsent(key, () => note);
      }
    }
    for (final entry in entries) {
      final id = entry.ticket.id;
      final key = id == null ? '' : titleKey(id);
      if (key.isNotEmpty) map.putIfAbsent(key, () => entry.note);
    }
    // A note's `aliases:` last (lib/core/aliases.dart): a title or a ticket's key in the same words is what a link
    // means first. Read once for each note's body and kept.
    for (final note in notes) {
      for (final alias in aliasesOfNote(note)) {
        map.putIfAbsent(titleKey(alias), () => note);
      }
    }
    return _byTitle = map;
  }

  /// The library a ```query reads (`useQueries`): what a screen shows, less the archive, which is put away, and the
  /// templates' pages, which are patterns and not things to do.
  List<QueryNote> get queryNotes => _queryNotes ??= [
        for (final note in notes)
          if ((note.archivedAt ?? 0) == 0 && !NoteFacts.of(note).isTemplatePage) QueryNote.of(note),
      ];

  /// Your own templates, a Templates notebook's pages in its order, or null where there is none.
  List<NoteTemplate>? get ownTemplates => (_templates ??= (own: templatesOf(notes))).own;

  /// What New ticket can start from: the templates that make a ticket, your own where you keep them, else the ones
  /// built in (`ticketTemplatesOf`).
  List<NoteTemplate> get ticketTemplates => [
        for (final template in ownTemplates ?? builtIns)
          if (isTicket(template.words)) template,
      ];

  /// The notes some journal's index names, and the pages of a Templates notebook: left out of a notebook's pickers.
  Set<String> get entryIds => _entryIds ??= {...entryPages(notes), ...ownTemplatePages(notes)};

  /// The journals, the one written in last first; not one put away in the archive.
  List<Note> get journals => _journals ??= ([
        for (final note in notes)
          if ((note.archivedAt ?? 0) == 0 && NoteFacts.of(note).isJournal) note,
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  /// The notebook a note is a page of, and its place there, for the bar and the foot it wears (`placeInBook`): a
  /// journal's entries in the order they were written. A Templates notebook's lines are its marked pages, never a
  /// note of the person's that shares a name with one.
  ///
  /// Asked at every build of a note's screen, it read every note's front matter and every notebook's chapters each
  /// time (`bookOf`): a note opened was a walk of the library for each build of its desk. The places are now every
  /// notebook's at once, made once for the notes as they are (`bookIndex`, which reads each note through its kept
  /// facts: the first notebook in the library whose index names the title, and no notebook a page of itself, as
  /// `bookOf` answers), and a note asked after twice is answered what it was answered.
  BookPlace? placeInBook(Note note) {
    final began = ghostPerf ? Perf.now() : 0;
    final placed = _placeInBook(note);
    // How many times a note's place was asked for in a stretch, and how long the answers took in all.
    if (ghostPerf) Perf.add('reads.place', began);
    return placed;
  }

  BookPlace? _placeInBook(Note note) {
    if (_places.containsKey(note)) return _places[note];
    // The note asked of may be an open screen's, whose words are the ones it was opened with: read, and not kept
    // in place of the reading of its words as they now are.
    final facts = NoteFacts.read(note.body);
    final books = facts.isTemplatePage
        ? notes
        : _plain ??= [
            for (final each in notes)
              if (!NoteFacts.of(each).isTemplatesBook) each,
          ];
    final place = bookIndex(books)[facts.key];
    return _places[note] = place == null ? null : inTimeOrder(place, titled);
  }

  /// What the open note's panel and its `[[GHO-12]]`s are drawn with (`useTickets`): the workflow of the notebook it
  /// is in, the people the library names, the other tickets, the ticket a key or a title names, and the key a ticket
  /// with none would get from its notebook, read across every note, the Trash's too, so no number is given twice.
  ///
  /// And its sub-tickets, Add sub-ticket ([addSub], the root's), and the rings a Blocked by or a Parent would make,
  /// refused (lib/book/ticket_links.dart).
  TicketOptions ticketOptions(String noteId, {required void Function(String target) open, void Function(String parentId, String title)? addSub, TicketWorkOptions? work}) {
    TicketEntry? self() => entries.where((entry) => entry.note.id == noteId).firstOrNull;
    Note? notebook() {
      for (final note in notes) {
        if (note.id == noteId) return notebookOf(note);
      }
      return null;
    }

    return TicketOptions(
      statuses: () => statusesOf(notebook()?.body),
      nextId: () {
        final book = notebook();
        return book == null ? null : nextTicketId(book.body, [for (final note in all()) note.body]);
      },
      people: people,
      choices: () => [
        for (final entry in entries)
          if (entry.note.id != noteId) ticketChoice(entry),
      ],
      find: (target) {
        final entry = ticket(target);
        return entry == null ? null : ticketChoice(entry);
      },
      open: open,
      subTickets: () {
        final entry = self();
        return entry == null ? const <TicketChoice>[] : [for (final child in subTicketsOf(entry, entries)) ticketChoice(child)];
      },
      addSubTicket: addSub == null ? null : (title) => addSub(noteId, title),
      // Its time and its pull requests (lib/editor/tickets/ticket_work.dart).
      work: work,
      problem: (key, value) {
        final entry = self();
        if (entry == null) return null;
        final targets = linkTargets(value is List ? value.join(', ') : value?.toString());
        return switch (key) {
          'blocked-by' => blockedByProblem(entry, targets, entries),
          'parent' => parentProblem(entry, targets.firstOrNull, entries),
          _ => null,
        };
      },
    );
  }

  /// A ticket's lock and its sub-tickets' progress, by note id, for a board or a query that lists it: what blocks it
  /// that is not done, and how many of its sub-tickets are (lib/book/ticket_links.dart). Null for a note that is no
  /// ticket, or a ticket with neither.
  ({List<String> blockers, TicketProgress? progress})? ticketMarks(String noteId) {
    final progress = (_progress ??= progressByParent(entries))[noteId];
    final entry = entries.where((each) => each.note.id == noteId).firstOrNull;
    if (entry == null) return null;
    final blockers = entry.ticket.blockedBy.isEmpty ? const <TicketEntry>[] : openBlockers(entry, ticket);
    if (blockers.isEmpty && progress == null) return null;
    return (blockers: [for (final blocker in blockers) ticketWords(blocker)], progress: progress);
  }

  Map<String, TicketProgress>? _progress;
}
