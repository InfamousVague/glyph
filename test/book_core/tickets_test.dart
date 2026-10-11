import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_facts.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/properties.dart' show StatusCategory, defaultStatuses, isTicket, statusesOf, ticketOf;

import '../core/make_note.dart';

/// A notebook's tickets across the library (lib/book/tickets.dart; tauri/docs/DESIGN.md §157): the key a notebook
/// gives, the next number, the status a new ticket starts in, the notebook a ticket's workflow comes from, the people
/// already named, and what a ticket waits on. Case for case with the web's `book/tickets.test.ts`.
const String notebook = '---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\n---\n# Ghost.md\n\n- [[Fix the login loop]]\n- [[Fix the session cookie]]\n';
String ticket(String id, String title, String status, [String more = '']) => '---\ntype: ticket\nid: $id\nstatus: $status\n$more---\n# $title\n';

void main() {
  group('a notebook’s key', () {
    test('is set upper case, taken off for nothing, and left alone where it will not do', () {
      final plain = bookNoteBody('Ghost.md');
      expect(withNotebookKey(plain, ' gho '), '---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\n---\n# Ghost.md\n\n');
      expect(withNotebookKey(withNotebookKey(plain, 'GHO'), 'WEB2'), contains('key: WEB2'));
      expect(withNotebookKey(withNotebookKey(plain, 'GHO'), ''), plain);
      expect(withNotebookKey(plain, 'G'), plain);
      expect(withNotebookKey(plain, '12'), plain);
    });

    test('says what is wrong with a key as it is typed, and nothing for one that will do or for none', () {
      expect(keyProblem(''), isNull);
      expect(keyProblem('gho'), isNull);
      expect(keyProblem('WEB2'), isNull);
      expect(keyProblem('G'), 'Two letters at least, like GHO.');
      expect(keyProblem('2GO'), 'A key starts with a letter, like GHO.');
      expect(keyProblem('GH-O'), 'Only letters and digits, like GHO or WEB2.');
      expect(keyProblem('ABCDEFGHIJK'), 'Ten letters and digits at most.');
    });

    test('numbers the next ticket one past the highest any note names, the Trash’s too, and gives none without a key', () {
      final bodies = [ticket('GHO-3', 'One', 'Done'), 'see [[GHO-12]] for that', ticket('WEB-40', 'Elsewhere', 'To do')];
      expect(nextTicketId(notebook, bodies), 'GHO-13');
      expect(nextTicketId(notebook, []), 'GHO-1');
      expect(nextTicketId(bookNoteBody('Plain'), bodies), isNull);
    });
  });

  group('a new ticket', () {
    test('starts To do in the default workflow, after the backlog, and in a notebook’s own first open status', () {
      expect(firstOpenStatus(defaultStatuses), 'To do');
      expect(firstOpenStatus(['Ideas', 'Building', 'Live']), 'Ideas');
      expect(firstOpenStatus(['Backlog', 'Icebox', 'Doing', 'Done']), 'Backlog');
      expect(firstOpenStatus([]), 'To do');
    });

    test('is written type, id and status first, then its title as its heading', () {
      expect(newTicketBody('Fix the login loop', id: 'GHO-13', statuses: defaultStatuses), '---\ntype: ticket\nid: GHO-13\nstatus: To do\n---\n# Fix the login loop\n\n');
      expect(newTicketBody('No key', id: null, statuses: ['Ideas', 'Live']), '---\ntype: ticket\nstatus: Ideas\n---\n# No key\n\n');
    });

    test('keeps a template’s keys and status where the workflow has it, and moves the status into the workflow where not', () {
      const words = '---\ntype: ticket\nid: GHO-13\nstatus: To do\npriority: high\n---\n# Login\n\n## Steps to reproduce\n';
      expect(newTicketBody('Login', id: 'GHO-13', statuses: defaultStatuses, words: words), words);
      final moved = newTicketBody('Login', id: 'GHO-13', statuses: ['Ideas', 'Building', 'Live'], words: words);
      expect(moved, words.replaceFirst('status: To do', 'status: Ideas'));
      // A template with no id line (it was filled where there was no key) is given the id it is made with.
      expect(newTicketBody('Login', id: 'GHO-2', statuses: defaultStatuses, words: '---\ntype: ticket\nstatus: To do\n---\n# Login\n'), contains('id: GHO-2'));
    });
  });

  group('the library’s tickets', () {
    final notes = <Note>[
      makeNote('book', body: notebook),
      makeNote('loop', body: ticket('GHO-12', 'Fix the login loop', 'In progress', 'assignee: Sam\nblocked-by: "[[GHO-9]]"\n')),
      makeNote('cookie', body: ticket('GHO-9', 'Fix the session cookie', 'Building')),
      makeNote('stray', body: ticket('GHO-20', 'Made from the blank page', 'To do')),
      makeNote('other', body: ticket('WEB-1', 'Somewhere else', 'Done')),
      makeNote('words', body: '# Standup\n\n- [ ] Ask @sam about the cookie\n- [ ] Pair with @Priya-Shah\n- email sam@example.com'),
    ];

    test('reads each in its notebook’s workflow, a page of it by its index and any other by its key', () {
      final withWorkflow = [for (final note in notes) note.id == 'book' ? note.copyWith(body: notebook.replaceFirst('key: GHO', 'key: GHO\nstatuses: [Ideas, Building, Live]')) : note];
      final entries = ticketsIn(withWorkflow);
      expect([for (final entry in entries) (entry.ticket.id, entry.notebook?.id, entry.ticket.category)], [
        ('GHO-12', 'book', StatusCategory.doing),
        ('GHO-9', 'book', StatusCategory.doing),
        ('GHO-20', 'book', StatusCategory.todo),
        ('WEB-1', null, StatusCategory.done),
      ]);
      expect(entries[1].statuses, ['Ideas', 'Building', 'Live']);
      expect(entries[3].statuses, defaultStatuses);
      // A ticket's template page makes tickets and is not one.
      expect([for (final entry in ticketsIn(notes, (note) => note.id == 'stray')) entry.note.id], isNot(contains('stray')));
    });

    test('is what each note’s own words say, and asked again reads nothing of a note again', () {
      // Each entry against the note's words read afresh: the title, the ticket in its notebook's workflow.
      final withWorkflow = [for (final note in notes) note.id == 'book' ? note.copyWith(body: notebook.replaceFirst('key: GHO', 'key: GHO\nstatuses: [Ideas, Building, Live]')) : note];
      for (final library in [notes, withWorkflow]) {
        final entries = ticketsIn(library);
        expect([for (final entry in entries) entry.note.id], [for (final note in library) if (isTicket(note.body)) note.id]);
        for (final entry in entries) {
          final statuses = statusesOf(entry.notebook?.body);
          expect(entry.title, noteTitle(entry.note.body));
          expect(entry.statuses, statuses);
          expect(entry.ticket, ticketOf(entry.note.body, statuses), reason: entry.note.id);
        }
      }
      // The library read again (the same notes in another list, as leaving a note for the home page hands them
      // over): what is kept of each note answers, and nothing is worked out from a note's words.
      ticketsIn(notes);
      final worked = NoteFacts.debugWorkedOut;
      final again = ticketsIn(List<Note>.of(notes));
      expect(NoteFacts.debugWorkedOut, worked);
      expect([for (final entry in again) entry.ticket.id], ['GHO-12', 'GHO-9', 'GHO-20', 'WEB-1']);
    });

    test('finds a ticket by its key in any case, or by its title as a link matches it', () {
      final find = ticketFinder(ticketsIn(notes));
      expect(find('GHO-9')?.note.id, 'cookie');
      expect(find('gho-9')?.note.id, 'cookie');
      expect(find('fix the session cookie!')?.note.id, 'cookie');
      expect(find('GHO-99'), isNull);
    });

    test('waits only on what names a ticket that is not done', () {
      TicketChoice? Function(String) choices(List<Note> from) {
        final find = ticketFinder(ticketsIn(from));
        return (target) {
          final entry = find(target);
          return entry != null ? ticketChoice(entry) : null;
        };
      }

      final loop = ticketsIn(notes).firstWhere((entry) => entry.note.id == 'loop').ticket;
      expect(waitingOn(loop, choices(notes)), const [
        Wait(target: 'GHO-9', found: TicketChoice(key: 'GHO-9', title: 'Fix the session cookie', status: 'Building', category: StatusCategory.doing)),
      ]);
      final done = [for (final note in notes) note.id == 'cookie' ? note.copyWith(body: ticket('GHO-9', 'Fix the session cookie', 'Done')) : note];
      expect(waitingOn(loop, choices(done)), isEmpty);
      expect(waitingOn(ticketOf(ticket('GHO-1', 'A', 'To do', 'blocked-by: "[[GHO-404]]"\n'))!, choices(notes)), isEmpty);
    });

    test('names the people the library already names, each once, the most named first and as they were written', () {
      expect(peopleIn([for (final note in notes) note.body]), ['Sam', 'Priya-Shah']);
      expect(peopleIn(['---\ntype: ticket\nassignee: Sam Ortiz\n---\n# A', 'with @Sam-Ortiz and @sam-ortiz']), ['Sam Ortiz']);
      expect(peopleIn(['`@code` and sam@example.com']), isEmpty);
    });
  });
}
