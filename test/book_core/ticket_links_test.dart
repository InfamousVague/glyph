import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_links.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/core/properties.dart';

import '../core/make_note.dart';

/// Sub-tickets and what a ticket waits on, across the library (lib/book/ticket_links.dart; Matt, 2026-10-30, of a
/// list of plain-Markdown features: "add all 12"): a parent's children and how many are done, the lock that clears
/// itself once its blockers are done, a move to done that asks while it has not, and the rings both fields refuse.
const String notebook = '---\ntitle: "Kiln"\nbook: true\nkey: KLN\n---\n# Kiln\n\n- [[Ship the beta]]\n- [[Fix login]]\n- [[Write docs]]\n';

String ticket(String id, String title, String status, [String more = '']) => '---\ntype: ticket\nid: $id\nstatus: $status\n$more---\n# $title\n';

List<TicketEntry> library(Map<String, String> bodies) => ticketsIn([makeNote('kiln', body: notebook), for (final MapEntry(:key, :value) in bodies.entries) makeNote(key, body: value)]);

TicketEntry entry(List<TicketEntry> entries, String id) => entries.firstWhere((each) => each.note.id == id);

void main() {
  group('sub-tickets', () {
    final entries = library({
      'beta': ticket('KLN-1', 'Ship the beta', 'In progress'),
      'login': ticket('KLN-2', 'Fix login', 'Done', 'parent: "[[KLN-1]]"\n'),
      'docs': ticket('KLN-3', 'Write docs', 'To do', 'parent: "[[Ship the beta]]"\n'),
      'other': ticket('KLN-4', 'Something else', 'To do'),
    });

    test('are the tickets whose parent names it, by its key or its title', () {
      expect([for (final child in subTicketsOf(entry(entries, 'beta'), entries)) child.note.id], ['login', 'docs']);
      expect(subTicketsOf(entry(entries, 'other'), entries), isEmpty);
    });

    test('count how many are done, for the bar', () {
      final progress = progressOf(subTicketsOf(entry(entries, 'beta'), entries));
      expect(progress, const TicketProgress(done: 1, total: 2));
      expect(progress.fraction, 0.5);
      expect(progress.words, '1 of 2 done');
      expect(progressOf(const []).isEmpty, isTrue);
    });

    test('are counted for every parent at once, for a board', () {
      expect(progressByParent(entries), {'beta': const TicketProgress(done: 1, total: 2)});
    });

    test('a new one names its parent by key, in its notebook’s workflow', () {
      final body = subTicketBody('Add a changelog', entry(entries, 'beta'), id: 'KLN-5', statuses: defaultStatuses);
      final made = ticketOf(body)!;
      expect(made.parent, 'KLN-1');
      expect(made.id, 'KLN-5');
      expect(made.status, 'To do');
      expect(body, contains('parent: "[[KLN-1]]"'));
      expect(body, contains('# Add a changelog'));
    });
  });

  group('blocked by', () {
    test('locks a ticket while a blocker is not done, and clears itself once every one is', () {
      var entries = library({
        'a': ticket('KLN-1', 'Ship the beta', 'To do', 'blocked-by: ["[[KLN-2]]", "[[KLN-3]]"]\n'),
        'b': ticket('KLN-2', 'Fix login', 'In progress'),
        'c': ticket('KLN-3', 'Write docs', 'Done'),
      });
      final find = ticketFinder(entries);
      expect([for (final blocker in openBlockers(entry(entries, 'a'), find)) blocker.note.id], ['b']);
      expect(doneWhileBlocked(entry(entries, 'a'), 'Done', find), isTrue);
      expect(doneWhileBlocked(entry(entries, 'a'), 'In progress', find), isFalse, reason: 'only a move to done asks');
      expect(doneWhileBlockedWords(openBlockers(entry(entries, 'a'), find)), 'It still waits on KLN-2, which isn’t done.');
      // KLN-2 is done: the lock is gone without anything written to KLN-1.
      entries = library({
        'a': ticket('KLN-1', 'Ship the beta', 'To do', 'blocked-by: ["[[KLN-2]]", "[[KLN-3]]"]\n'),
        'b': ticket('KLN-2', 'Fix login', 'Done'),
        'c': ticket('KLN-3', 'Write docs', 'Done'),
      });
      expect(openBlockers(entry(entries, 'a'), ticketFinder(entries)), isEmpty);
      expect(doneWhileBlocked(entry(entries, 'a'), 'Done', ticketFinder(entries)), isFalse);
    });

    test('a ring is refused with what it would go round, however far round it goes', () {
      final entries = library({
        'a': ticket('KLN-1', 'Ship the beta', 'To do'),
        'b': ticket('KLN-2', 'Fix login', 'To do', 'blocked-by: "[[KLN-3]]"\n'),
        'c': ticket('KLN-3', 'Write docs', 'To do', 'blocked-by: "[[KLN-1]]"\n'),
      });
      expect(blockedByProblem(entry(entries, 'a'), ['KLN-1'], entries), 'A ticket can’t wait on itself.');
      expect(blockedByProblem(entry(entries, 'a'), ['KLN-3'], entries), 'KLN-3 already waits on KLN-1, so this would go round in a circle: KLN-1 → KLN-3 → KLN-1.');
      expect(blockedByProblem(entry(entries, 'a'), ['KLN-2'], entries), 'KLN-2 already waits on KLN-1, so this would go round in a circle: KLN-1 → KLN-2 → KLN-3 → KLN-1.');
      expect(blockedByProblem(entry(entries, 'c'), ['KLN-1'], entries), isNull, reason: 'what it already says is no new ring');
      expect(blockedByProblem(entry(entries, 'b'), ['KLN-1', 'Nobody'], entries), isNull, reason: 'a name no ticket has is never a ring');
    });

    test('a ring written by hand ends the walk instead of looping it', () {
      final entries = library({
        'a': ticket('KLN-1', 'Ship the beta', 'To do', 'blocked-by: "[[KLN-2]]"\n'),
        'b': ticket('KLN-2', 'Fix login', 'To do', 'blocked-by: "[[KLN-1]]"\n'),
        'c': ticket('KLN-3', 'Write docs', 'To do'),
      });
      expect(blockedByProblem(entry(entries, 'c'), ['KLN-1'], entries), isNull);
    });
  });

  group('parent', () {
    test('can be neither the ticket itself nor anything under it', () {
      final entries = library({
        'a': ticket('KLN-1', 'Ship the beta', 'To do'),
        'b': ticket('KLN-2', 'Fix login', 'To do', 'parent: "[[KLN-1]]"\n'),
        'c': ticket('KLN-3', 'Write docs', 'To do', 'parent: "[[KLN-2]]"\n'),
      });
      expect(parentProblem(entry(entries, 'a'), 'KLN-1', entries), 'A ticket can’t be its own parent.');
      expect(parentProblem(entry(entries, 'a'), 'KLN-3', entries), 'KLN-3 is already under KLN-1, so it can’t be its parent too.');
      expect(parentProblem(entry(entries, 'c'), 'KLN-1', entries), isNull);
      expect(parentProblem(entry(entries, 'a'), null, entries), isNull);
    });
  });
}
