import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

/// Where a note's query fences are (lib/core/query/fence.dart), case for case with the web's
/// `core/query/fence.test.ts`.
void main() {
  group('query fences', () {
    test('finds each closed fence, its lines and its body', () {
      const doc = '# Plan\n\n```query\nfrom: tickets\nshow: board\n```\n\nWords.\n\n~~~~QUERY\nfrom: tasks\n~~~~\n';
      expect(queryFencesIn(doc), const [
        QueryFence(from: 3, to: 6, body: 'from: tickets\nshow: board', height: null),
        QueryFence(from: 10, to: 12, body: 'from: tasks', height: null),
      ]);
    });

    test('is closed only by the same character, at least as long', () {
      expect(queryFencesIn('````query\nfrom: tasks\n```\nstill in it\n````'), const [QueryFence(from: 1, to: 5, body: 'from: tasks\n```\nstill in it', height: null)]);
      expect(queryFencesIn('~~~query\nfrom: tasks\n```\n~~~'), const [QueryFence(from: 1, to: 4, body: 'from: tasks\n```', height: null)]);
    });

    test('is not a fence with other words on its line, or another kind', () {
      expect(queryFencesIn('```query notes\nfrom: tasks\n```'), isEmpty);
      expect(queryFencesIn('```board\nTo do: a\n```'), isEmpty);
      expect(queryFencesIn('```js\nquery\n```'), isEmpty);
    });

    test('draws nothing for a fence still being typed', () {
      expect(queryFencesIn('```query\nfrom: tasks\n'), isEmpty);
    });

    test('finds an empty query', () {
      expect(queryFencesIn('```query\n```'), const [QueryFence(from: 1, to: 2, body: '', height: null)]);
    });

    test('writes one as the + does', () {
      expect(queryFence('from: tasks\nshow: list\n'), '```query\nfrom: tasks\nshow: list\n```');
      expect(queryFencesIn(queryFence('from: tasks'))[0].body, 'from: tasks');
    });

    test('reads a board\'s height from the fence, kept within what a board can be', () {
      expect(queryFencesIn('```query height=18\nshow: board\n```')[0].height, 18);
      expect(queryFencesIn('```query height=900\nshow: board\n```')[0].height, 60);
      expect(queryFencesIn('```query height=12.3em\n```')[0].height, 12.5);
    });

    test('sets and takes off the height on the opening line, leaving the rest', () {
      expect(withQueryHeight('```query', 20), '```query height=20');
      expect(withQueryHeight('```query height=20', 31.5), '```query height=31.5');
      expect(withQueryHeight('~~~query height=20 wide=yes', null), '~~~query wide=yes');
      expect(withQueryHeight('```board', 20), '```board');
    });

    test('switches the show line in the body, keeping from and where, and adds one where there is none', () {
      expect(withShow('from: tickets\nwhere: status != Done\nshow: list', ShowAs.board), 'from: tickets\nwhere: status != Done\nshow: board');
      // Its spacing is left as it was; a line with none gets the default space.
      expect(withShow('from: tasks\nshow:list', ShowAs.table), 'from: tasks\nshow:table');
      expect(withShow('from: tasks\nSHOW:   calendar', ShowAs.count), 'from: tasks\nshow:   count');
      // No show line (which reads as a table): one is added at the end.
      expect(withShow('from: notes\nwhere: updated >= today-7', ShowAs.list), 'from: notes\nwhere: updated >= today-7\nshow: list');
      // Only the first show line is touched.
      expect(withShow('show: list\nshow: table', ShowAs.board), 'show: board\nshow: table');
    });

    test('reads and sets any clause for the builder, keeping the lines it does not touch', () {
      const body = 'from: tasks\nwhere: due <= today+7\nsort: due, priority\nshow: list';
      expect(clauseValue(body, 'from'), 'tasks');
      expect(clauseValue(body, 'where'), 'due <= today+7');
      expect(clauseValue(body, 'group'), isNull);
      // Set from, keeping where/sort/show.
      expect(withClause(body, 'from', 'tickets'), 'from: tickets\nwhere: due <= today+7\nsort: due, priority\nshow: list');
      // Add a group line where there is none.
      expect(withClause(body, 'group', 'status'), 'from: tasks\nwhere: due <= today+7\nsort: due, priority\nshow: list\ngroup: status');
      // Take the where line off (Everything), leaving the rest.
      expect(withClause(body, 'where', null), 'from: tasks\nsort: due, priority\nshow: list');
    });
  });
}
