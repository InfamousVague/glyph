import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/properties.dart' show StatusCategory, defaultStatuses, ticketOf;
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/tickets/triage.dart';

import 'support.dart';

/// Triage (lib/tickets/triage.dart): which new tickets wait to be looked at, what looking at one writes, a duplicate
/// closed, and what each key and swipe does.
void main() {
  final library = libraryOf(notes);

  group('the list', () {
    test('gathers tickets from a form, mail, the connector, marked or new, and with nobody on them, the newest first', () {
      final list = triageList(library, today, teamOf: teamOf);
      expect([for (final each in list) each.line.key], ['WAIT-4', 'PAY-3', 'GHO-9', 'GHO-10', 'GHO-11']);
      expect([for (final each in list) each.reason], ['From a form', 'From mail', 'From the connector', 'New', 'Marked for triage']);
      expect(list[1].line.place, 'HelloTrade · Payments');
    });

    test('leaves out what was looked at, what is done, and tickets with someone on them that came by hand', () {
      final keys = [for (final each in triageList(library, today)) each.line.key];
      expect(keys, isNot(contains('GHO-12')));
      expect(keys, isNot(contains('WAIT-3')));
      expect(keys, isNot(contains('WAIT-1')));
    });

    test('takes a ticket with nobody on it, and one told triage: false is out', () {
      final more = libraryOf([note('n', ticket('NB-1', 'Nobody')), note('f', ticket('NB-2', 'Told', more: 'triage: false\n'))]);
      expect([for (final each in triageList(more, today)) (each.line.key, each.reason)], [('NB-1', 'No one assigned')]);
    });

    test('is narrowed to one notebook, and names the notebooks it can be', () {
      expect([for (final each in triageList(library, today, notebook: 'waitlist')) each.line.key], ['WAIT-4']);
      expect(triageNotebooks(library), ['Waitlist', 'Payments']);
    });

    test('reads priority as plain front matter, written or not', () {
      expect(triageReason(const {'triage': 'yes', 'priority': 'urgent-ish'}, category: StatusCategory.todo, assignee: 'Sam'), 'Marked for triage');
      final line = triageList(libraryOf([note('p', ticket('PR-1', 'P', priority: 'high'))]), today).single.line;
      expect(line.priority, 'high');
    });
  });

  group('looked at', () {
    test('takes triage: off, writes the day, and moves a triage’s own status on', () {
      final body = ticket('GHO-10', 'Retry', status: 'New', more: 'triage: true\n');
      final out = triagedBody(body, today, defaultStatuses);
      expect(out, '---\ntype: ticket\nid: GHO-10\nstatus: To do\ntriaged: 2026-10-28\nstatus-since: 2026-10-28\n---\n# Retry\n');
      expect(triagedBody(ticket('A-1', 'A', status: 'In progress'), today, defaultStatuses), contains('status: In progress'));
      final again = libraryOf([note('x', out)]);
      expect(triageList(again, today), isEmpty);
    });

    test('as a duplicate links duplicate-of:, closes it in its workflow and takes it out', () {
      final out = duplicateBody(ticket('WAIT-4', 'Spam', more: 'via: form\n'), 'WAIT-1', today, defaultStatuses);
      expect(out, contains('duplicate-of: "[[WAIT-1]]"'));
      expect(ticketOf(out)!.category, StatusCategory.done);
      expect(out, contains('triaged: 2026-10-28'));
      expect(duplicateStatus(['Open', 'Doing', 'Duplicate', 'Done']), 'Duplicate');
      expect(duplicateStatus(['Ideas', 'Building', 'Live']), 'Live');
      expect(duplicateStatus(defaultStatuses), 'Done');
    });
  });

  group('the keys and swipes', () {
    test('are J K A P L S D E and T, in any case, and the arrows', () {
      expect([for (final key in ['j', 'K', 'a', 'p', 'L', 's', 'd', 'e', 't', 'Enter', 'Arrow Down', 'x']) triageKey(key)], [
        TriageAction.next,
        TriageAction.previous,
        TriageAction.assign,
        TriageAction.priority,
        TriageAction.labels,
        TriageAction.status,
        TriageAction.duplicate,
        TriageAction.open,
        TriageAction.done,
        TriageAction.done,
        TriageAction.next,
        null,
      ]);
    });

    test('move the cursor within the list, and a swipe right is done, left the actions', () {
      expect(triageMove(TriageAction.next, 0, 3), 1);
      expect(triageMove(TriageAction.next, 2, 3), 2);
      expect(triageMove(TriageAction.previous, 0, 3), 0);
      expect(triageMove(TriageAction.done, 3, 3), 2);
      expect(triageMove(TriageAction.next, 0, 0), 0);
      expect(triageSwipe(right: true), TriageAction.done);
      expect(triageSwipe(right: false), TriageAction.actions);
    });
  });
}
