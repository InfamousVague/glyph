import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/tickets/inbox.dart';

import 'support.dart';

/// My tickets (lib/tickets/inbox.dart): every ticket assigned to you across your notebooks and your teams', in
/// Overdue, Today, This week, Later and No date, by the query engine's own `where: assignee = me`.
void main() {
  setUp(() => queryMe = const ['matt']);
  tearDown(() => queryMe = const []);

  group('the buckets', () {
    test('are by the due day against today, the week ending on Sunday', () {
      expect(bucketOf('2026-10-27', today), InboxBucket.overdue);
      expect(bucketOf(today, today), InboxBucket.today);
      expect(bucketOf('2026-10-29', today), InboxBucket.thisWeek);
      expect(bucketOf('2026-11-01', today), InboxBucket.thisWeek);
      expect(bucketOf('2026-11-02', today), InboxBucket.later);
      expect(bucketOf(null, today), InboxBucket.noDate);
      expect(weekEnd('2026-11-01'), '2026-11-01');
      expect(weekEnd('2026-10-26'), '2026-11-01');
    });
  });

  group('the inbox', () {
    final library = libraryOf(notes);

    test('gathers your tickets across notebooks and teams, in their groups, by due then priority', () {
      final groups = myTickets(library, today, teamOf: teamOf);
      expect([for (final group in groups) group.label], ['Overdue', 'Today', 'This week', 'Later', 'No date']);
      expect([for (final group in groups) [for (final line in group.tickets) line.key]], [
        ['WAIT-1'],
        ['WAIT-2'],
        ['PAY-1', 'GHO-1'],
        ['GHO-2'],
        ['GHO-3'],
      ]);
    });

    test('leaves out what is done, other people’s tickets and notes that are not tickets', () {
      final keys = [for (final group in myTickets(library, today)) for (final line in group.tickets) line.key];
      expect(keys, isNot(contains('WAIT-3')));
      expect(keys, isNot(contains('PAY-2')));
      expect(keys, hasLength(6));
    });

    test('says where each one is: its team and its notebook, and what its row shows', () {
      final lines = {for (final group in myTickets(library, today, teamOf: teamOf)) for (final line in group.tickets) line.key: line};
      expect(lines['PAY-1']!.place, 'HelloTrade · Payments');
      expect(lines['WAIT-1']!.place, 'Waitlist');
      expect(lines['WAIT-1']!.overdue, isTrue);
      expect(lines['WAIT-1']!.labels, ['bug', 'email']);
      expect(lines['WAIT-1']!.component, 'Waitlist');
      expect(lines['GHO-1']!.status, 'Building');
      expect(lines['GHO-1']!.workflow, ['Ideas', 'Building', 'Live']);
    });

    test('sorts two due on one day by priority, the most urgent first', () {
      final more = libraryOf([
        ...notes,
        note('pay9', ticket('PAY-9', 'Same day, urgent', assignee: 'Matt', due: '2026-10-30', priority: 'highest')),
      ]);
      final week = myTickets(more, today).firstWhere((group) => group.bucket == InboxBucket.thisWeek);
      expect([for (final line in week.tickets) line.key], ['PAY-1', 'PAY-9', 'GHO-1']);
    });

    test('counts the tickets, and the overdue ones', () {
      expect(myTicketCount(myTickets(library, today)), (all: 6, overdue: 1));
    });

    test('with no account, `me` is only someone written as me', () {
      queryMe = const [];
      expect(myTickets(library, today), isEmpty);
      final mine = libraryOf([note('m', ticket('XY-1', 'Mine', assignee: 'me'))]);
      expect(myTickets(mine, today).single.tickets.single.key, 'XY-1');
    });
  });

  group('`me` in any query', () {
    test('is the account’s handle however a ticket writes it, in where: and in from:', () {
      final library = libraryOf(notes);
      List<String?> keys(String lines) => [for (final group in runQuery(readQuery(lines).query!, library, today).groups) for (final row in group.rows) row.id];
      expect(keys('from: tickets\nwhere: assignee = me\nsort: id'), ['GHO-1', 'GHO-2', 'GHO-3', 'PAY-1', 'WAIT-1', 'WAIT-2', 'WAIT-3']);
      expect(keys('from: tickets @me\nwhere: status != Done\nsort: id'), ['GHO-1', 'GHO-2', 'GHO-3', 'PAY-1', 'WAIT-1', 'WAIT-2']);
      expect(keys('from: tickets\nwhere: assignee != me and assignee is not empty\nsort: id'), ['GHO-9', 'GHO-10', 'GHO-11', 'PAY-2']);
      final tasks = runQuery(readQuery('from: tasks\nwhere: assignee = me').query!, library, today);
      expect([for (final row in tasks.groups.single.rows) row.name], ['Milk']);
    });
  });
}
