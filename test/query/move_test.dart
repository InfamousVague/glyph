import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

/// A card dragged into another lane, and a field picked for a to-do (lib/core/query/move.dart), case for case with
/// the web's `core/query/move.test.ts`.
void main() {
  group('a card dragged into another lane', () {
    const ticket = '---\ntype: ticket\nid: GHO-1\nstatus: In progress\npriority: high\n---\n# Fix the login loop\n';

    test('sets a ticket’s front-matter status to the lane it lands in', () {
      expect(movedBody(ticket, 0, '', RecordKind.ticket, 'status', 'In review'), contains('status: In review'));
      expect(movedBody(ticket, 0, '', RecordKind.ticket, 'status', 'In review'), isNot(contains('In progress')));
      // And the day it moved, for the planning (lib/core/properties.dart `withStatus`).
      expect(movedBody(ticket, 0, '', RecordKind.ticket, 'status', 'In review'), contains('status-since: '));
      expect(movedBody(ticket, 0, '', RecordKind.ticket, 'status', 'Done'), contains('done: '));
    });

    test('clears the field when dropped in the "No …" lane', () {
      final cleared = movedBody(ticket, 0, '', RecordKind.ticket, 'status', null)!;
      expect(cleared, isNot(contains('status:')));
      expect(cleared, contains('priority: high'));
    });

    test('leaves the body alone when the lane is the one it is already in', () {
      expect(movedBody(ticket, 0, '', RecordKind.ticket, 'status', 'In progress'), ticket);
    });

    test('writes a to-do’s inline field on its own line, found by its words', () {
      const body = '# Board\n\n- [ ] Milk [stage:: Todo]\n- [ ] Eggs [stage:: Todo]\n';
      const source = '- [ ] Eggs [stage:: Todo]';
      final next = movedBody(body, 3, source, RecordKind.task, 'stage', 'Doing')!;
      expect(next, contains('- [ ] Eggs [stage:: Doing]'));
      // The other line is untouched.
      expect(next, contains('- [ ] Milk [stage:: Todo]'));
    });

    test('leaves a to-do alone when its line is gone', () {
      expect(movedBody('# Board\n\n- [ ] Milk\n', 2, '- [ ] Bread', RecordKind.task, 'stage', 'Doing'), isNull);
    });
  });

  group('a field picked for a to-do', () {
    test('replaces its person with the one picked, as a person is written on a line', () {
      expect(withTaskField('- [ ] Milk @sam 📅 2026-10-04', 'assignee', 'Alex'), '- [ ] Milk @Alex 📅 2026-10-04');
      expect(withTaskField('- [ ] Milk', 'assignee', 'Sam'), '- [ ] Milk @Sam');
    });

    test('takes every person off with null, and leaves the rest of the line', () {
      expect(withTaskField('- [ ] Milk @sam @alex ⏫', 'assignee', null), '- [ ] Milk ⏫');
    });

    test('writes any other field through the line’s own writer', () {
      expect(withTaskField('- [ ] Milk', 'priority', 'high'), '- [ ] Milk ⏫');
      expect(withTaskField('- [ ] Milk 📅 2026-10-04', 'due', null), '- [ ] Milk');
    });

    test('is what a query writes into another note', () {
      const body = '# Shop\n\n- [ ] Milk @sam\n';
      expect(movedBody(body, 2, '- [ ] Milk @sam', RecordKind.task, 'assignee', 'Priya'), '# Shop\n\n- [ ] Milk @Priya\n');
    });
  });
}
