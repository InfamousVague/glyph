import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/tickets/bulk.dart';
import 'package:ghost_md/tickets/labels.dart' show labelsOf;

import 'support.dart' show ticket;

/// A store of notes in memory, whose writes can be refused for one note: a team's note another member changed, a
/// note gone.
class _Store implements BulkStore {
  _Store(Map<String, String> bodies) : notes = {for (final MapEntry(:key, :value) in bodies.entries) key: (body: value, revision: 1)};

  final Map<String, ({String body, int revision})> notes;
  final Set<String> refuse = {};
  final List<String> writes = [];

  @override
  Future<BulkNote?> read(String id) async {
    final note = notes[id];
    return note == null ? null : BulkNote(note.body, note.revision);
  }

  @override
  Future<int> write(String id, String body, int revision) async {
    final note = notes[id];
    if (note == null) throw StateError('No such note.');
    if (refuse.contains(id) || note.revision != revision) throw StateError('Revision conflict.');
    writes.add(id);
    notes[id] = (body: body, revision: revision + 1);
    return revision + 1;
  }

  String body(String id) => notes[id]!.body;
}

/// Bulk edit (lib/tickets/bulk.dart): one batch for many tickets, all or nothing, one undo for all, and what failed
/// said.
void main() {
  Map<String, String> three() => {
        'a': ticket('GHO-1', 'One', more: 'labels: [ui]\n'),
        'b': ticket('GHO-2', 'Two', status: 'In progress'),
        'c': ticket('GHO-3', 'Three', status: 'Done'),
      };
  Map<String, BodyChange> plan(Iterable<String> ids, BulkEdit edit) => {for (final id in ids) id: (body) => bulkBody(body, edit)};

  test('each edit writes the front matter, plain', () {
    final body = ticket('GHO-1', 'One', more: 'labels: [ui]\n');
    expect(bulkBody(body, const SetField('status', 'Done')), contains('status: Done'));
    expect(bulkBody(body, const SetField('assignee', 'Sam')), contains('assignee: Sam'));
    expect(bulkBody(body, const SetField('due', '2026-11-02')), contains('due: 2026-11-02'));
    expect(bulkBody(body, const SetField('priority', 'high')), contains('priority: high'));
    expect(bulkBody(bulkBody(body, const SetField('priority', 'high')), const SetField('priority', null)), isNot(contains('priority')));
    expect(labelsOf(bulkBody(body, const ChangeLabels(add: ['bug'], remove: ['ui']))), ['bug']);
    expect(const SetField('status', 'Done').said, 'Status set to Done');
    expect(const ChangeLabels(add: ['bug']).said, 'Labelled bug');
  });

  test('a batch writes every ticket, and one undo puts every one back', () async {
    final store = _Store(three());
    final before = Map.of({for (final id in ['a', 'b', 'c']) id: store.body(id)});
    final outcome = await runBulk(plan(['a', 'b', 'c'], const SetField('status', 'Done')), store);
    expect(outcome.whole, isTrue);
    expect([for (final each in outcome.wrote) each.id], ['a', 'b']);
    expect(outcome.unchanged, ['c']);
    expect(store.body('a'), contains('status: Done'));
    expect(bulkReport(outcome, const SetField('status', 'Done').said, nameOf: (id) => id), 'Status set to Done on 3 tickets.');

    final undone = await undoBulk(outcome, store);
    expect(undone.whole, isTrue);
    for (final id in ['a', 'b', 'c']) {
      expect(store.body(id), before[id]);
    }
  });

  test('a write refused puts back what was written, and says which failed and why', () async {
    final store = _Store(three())..refuse.add('b');
    final before = store.body('a');
    final outcome = await runBulk(plan(['a', 'b', 'c'], const SetField('assignee', 'Sam')), store);
    expect(outcome.whole, isFalse);
    expect(outcome.wrote, isEmpty);
    expect(outcome.failed, {'b': 'It was changed somewhere else.'});
    // a was written and put back: nothing is left half done.
    expect(store.writes, ['a', 'a']);
    expect(store.body('a'), before);
    expect(bulkReport(outcome, 'Assignee set to Sam', nameOf: (id) => 'GHO-${id == 'b' ? 2 : 0}'), 'Nothing was changed. GHO-2: It was changed somewhere else.');
  });

  test('a note gone is reported before anything is written', () async {
    final store = _Store(three());
    final outcome = await runBulk(plan(['a', 'gone'], const SetField('status', 'Done')), store);
    expect(outcome.failed, {'gone': 'It is gone.'});
    expect(store.writes, isEmpty);
  });

  test('undo leaves a ticket changed since as it is, and says so', () async {
    final store = _Store(three());
    final outcome = await runBulk(plan(['a', 'b'], const SetField('priority', 'high')), store);
    await store.write('b', '${store.body('b')}\nMore words.\n', store.notes['b']!.revision);
    final undone = await undoBulk(outcome, store);
    expect(undone.failed, {'b': 'It was changed since, so it is left as it is.'});
    expect(store.body('a'), isNot(contains('priority')));
    expect(store.body('b'), contains('priority: high'));
  });

  test('moving to a notebook takes each line out of its own and writes each notebook once', () async {
    final store = _Store({
      'old': '---\nbook: true\n---\n# Old\n\n- [[One]]\n- [[Two]]\n- [[Stays]]\n',
      'new': '---\nbook: true\n---\n# New\n\n- [[Here]]\n',
    });
    final moves = movePlan(to: 'new', from: {'a': 'old', 'b': 'old', 'c': null, 'd': 'new'}, titles: {'a': 'One', 'b': 'Two', 'c': 'Loose', 'd': 'Here'});
    expect(moves.keys, ['old', 'new']);
    final outcome = await runBulk(moves, store);
    expect(outcome.whole, isTrue);
    expect(store.body('old'), '---\nbook: true\n---\n# Old\n\n- [[Stays]]\n');
    expect(store.body('new'), '---\nbook: true\n---\n# New\n\n- [[Here]]\n- [[One]]\n- [[Two]]\n- [[Loose]]\n');
    expect(store.writes, ['old', 'new']);
    await undoBulk(outcome, store);
    expect(store.body('old'), contains('[[One]]'));
    expect(store.body('new'), isNot(contains('[[One]]')));
  });
}
