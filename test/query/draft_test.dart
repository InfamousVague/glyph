import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

/// What a lane's new ticket must say for its board to list it there (lib/core/query/draft.dart), case for case with
/// the web's `core/query/draft.test.ts`.
TicketDraft? draft(String lines, String? lane, [String? group = 'status']) {
  final query = readQuery(lines).query;
  if (query == null) fail('unreadable: $lines');
  return ticketDraft(query, query.group ?? group, lane);
}

void main() {
  group('a ticket drafted from a lane of a query’s board', () {
    test('takes the lane’s value for the field the board groups by', () {
      expect(draft('from: tickets\nshow: board', 'In review'), const TicketDraft(link: null, fields: [('status', 'In review')], labels: []));
      expect(draft('from: tickets\ngroup: assignee\nshow: board', 'sam'), const TicketDraft(link: null, fields: [('assignee', 'sam')], labels: []));
    });

    test('takes the notebook, the tags and the person every record must come from, never one of several', () {
      expect(
        draft('from: tickets [[GHST]] #bug @kebim\nshow: board', 'To do'),
        const TicketDraft(link: 'GHST', fields: [('assignee', 'kebim'), ('status', 'To do')], labels: ['bug']),
      );
      expect(draft('from: tickets [[GHST]] or [[Other]]\nshow: board', 'To do')?.link, isNull);
      expect(draft('from: tickets not #bug\nshow: board', 'To do')?.labels, isEmpty);
    });

    test('takes the equal tests every record must pass, and leaves the rest', () {
      final made = draft('from: tickets\nwhere: priority = high and estimate = 3 and due < today and (assignee = sam or assignee = kebim) and status = Done\nshow: board', 'To do');
      // The lane's status wins over the query's own; a test under `or`, or not an equal, is the person's to meet.
      expect(made?.fields, [('priority', 'high'), ('estimate', '3'), ('status', 'To do')]);
    });

    test('never copies a field the ticket’s maker sets', () {
      expect(draft('from: tickets\nwhere: type = ticket and id = GHO-4 and title = Plan\nshow: board', 'To do')?.fields, [('status', 'To do')]);
    });

    test('drafts nothing for a board of to-dos or of notes', () {
      expect(draft('from: tasks\nshow: board', null), isNull);
      expect(draft('from: notes\nshow: board', null), isNull);
    });
  });
}
