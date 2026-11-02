// The project tools' gates that are pure (docs/PM_PLUGINS.md §5): the + and the / rows of a ready-made database and a
// ticket board, the query switcher's and builder's ways, and which notes are tickets at all to My tickets, Triage, the
// digest and the palette.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/project_tools.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/editor/plus/add_rows.dart';
import 'package:ghost_md/root/library_reads.dart';

void main() {
  group('the + and the / palette', () {
    test('offer the ready-made databases and the ticket board only where their tools are on', () {
      expect(boardRows().map((row) => row.id), ['board', 'query:board'], reason: 'every one where nothing says otherwise');
      // Tickets off: the ticket board and the ticket queries are not offered; the to-dos' and the notes' are.
      bool noTickets(String lines) => !toolsOfQuery(lines).contains(ticketsTool);
      expect(boardRows(noTickets).map((row) => row.id), ['board']);
      expect(databaseRows(noTickets).map((row) => row.words), ['To-dos due this week', 'Overdue to-dos', 'To-dos by person', 'To-dos on a calendar', 'Notes changed this week', 'How many to-dos are open', 'Write your own']);
      // Tickets on and Gantt off: the ticket timeline alone goes.
      bool noGantt(String lines) => !toolsOfQuery(lines).contains(ganttTool);
      expect(databaseRows(noGantt).map((row) => row.id), isNot(contains('query:timeline')));
      expect(databaseRows(noGantt).map((row) => row.id), contains('query:board'));
    });

    test('a board, Make this a ticket and a Gantt chart are rows only where the gates say', () {
      final off = readGates(picture: false, video: false, place: false, note: false, canvas: false, board: false, ticket: false, gantt: false);
      final on = readGates(picture: false, video: false, place: false, note: false, canvas: false, board: true, ticket: true, gantt: true);
      List<String> ids(AddGates gates) => [for (final row in allRows(gates, DateTime(2026, 11, 1))) row.id];
      expect(ids(off), isNot(contains('board')));
      expect(ids(off), isNot(contains('ticket')));
      expect(ids(off), isNot(contains('gantt')));
      expect(ids(on), containsAll(['board', 'ticket', 'gantt']));
    });
  });

  group('the library’s tickets', () {
    test('are only the notes where Tickets is on: My tickets, Triage, the digest and the palette read no others', () {
      final notes = SampleLibrary.seeded().value;
      final all = LibraryReads(shown: () => notes, all: () => notes);
      expect(all.entries, isNotEmpty);
      final none = LibraryReads(shown: () => notes, all: () => notes, ticketsOn: (_) => false);
      expect(none.entries, isEmpty);
      final one = all.entries.first.note.id;
      final some = LibraryReads(shown: () => notes, all: () => notes, ticketsOn: (id) => id == one);
      expect([for (final entry in some.entries) entry.note.id], [one]);
      expect(some.ticket(all.entries.first.ticket.id!), isNotNull, reason: 'its [[KEY]] finds it');
      expect(none.ticket(all.entries.first.ticket.id!), isNull, reason: 'a [[KEY]] where Tickets is off is a plain link');
    });
  });
}
