import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/properties.dart' show StatusCategory;
import 'package:ghost_md/core/query/query.dart';

import 'support.dart';

/// A query run over a library (lib/core/query/records.dart, run.dart; tauri/docs/QUERIES.md): what is read from
/// the notes, the defaults that make `from: #bug` alone useful, the tests, the order, the groups a board and a table
/// draw, the totals, and what the drawing is handed. Case for case with the web's `core/query/run.test.ts`. The
/// library is support.dart's; today is 5 October 2026.
QueryResult run(String body, [List<QueryNote>? over, String day = today]) {
  final reading = readQuery(body);
  if (reading.problem != null) fail(reading.problem!.message);
  return runQuery(reading.query!, libraryOf(over ?? notes), day);
}

List<QueryRow> rows(QueryResult result) => [for (final group in result.groups) ...group.rows];
List<String> names(QueryResult result) => [for (final row in rows(result)) row.name];
List<String?> ids(QueryResult result) => [for (final row in rows(result)) row.id];

void main() {
  group('the library', () {
    final library = libraryOf(notes);

    test('reads every note as a record, a ticket as one, and every to-do with words as one of its own', () {
      final kinds = [for (final record in library.records) '${record.kind.name}:${record.noteId}'];
      expect(kinds.where((k) => k.startsWith('ticket:')), ['ticket:gho1', 'ticket:gho2', 'ticket:gho3']);
      expect(kinds.where((k) => k.startsWith('note:')), ['note:launch', 'note:shop', 'note:ideas', 'note:standup']);
      // Five on the shopping list (the empty box is not one, nor the box in code) and one in a ticket.
      expect(
        [for (final record in library.records) if (record.kind == RecordKind.task) record.text],
        ['Write the failing test', 'Milk #dairy', 'Eggs', 'Bread', 'Coffee beans', 'Butter'],
      );
    });

    test('keeps a to-do’s line, its box, its fields, and its note’s tags', () {
      final milk = library.records.firstWhere((record) => record.text == 'Milk #dairy');
      expect((milk.noteId, milk.line, milk.done, milk.title, milk.source), ('shop', 5, false, 'Groceries', '- [ ] Milk 📅 2026-10-04 @sam #dairy'));
      expect(milk.fields?.due, '2026-10-04');
      expect(milk.fields?.assignees, ['sam']);
      expect(milk.tags, ['dairy', 'errands']);
      expect(library.records.firstWhere((record) => record.text == 'Eggs').done, isTrue);
    });

    test('knows the notebook a page is in, and the workflow it moves through', () {
      final ticket = library.records.firstWhere((record) => record.noteId == 'gho1' && record.kind == RecordKind.ticket);
      expect(ticket.notebook, 'Launch');
      expect(ticket.workflow, ['Backlog', 'To do', 'In progress', 'In review', 'Done']);
      expect((ticket.ticket?.id, ticket.ticket?.status, ticket.ticket?.category, ticket.ticket?.estimate), ('GHO-1', 'In progress', StatusCategory.doing, 3));
      expect(library.records.firstWhere((record) => record.noteId == 'shop').notebook, isNull);
    });

    test('finds the notes a note links to, by title and by a ticket’s key', () {
      final standup = library.records.firstWhere((record) => record.noteId == 'standup');
      expect(standup.linksTo.toList()..sort(), ['gho1', 'gho2']);
      expect(noteNamed(library, 'gho-1')?.id, 'gho1');
      expect(noteNamed(library, 'launch')?.book, isTrue);
      expect(noteNamed(library, 'Nothing like it'), isNull);
    });

    test('reads a note once while its words stay the same, and lets go of a note that is gone', () {
      final cache = recordCache();
      libraryOf(notes, cache);
      final kept = cache.read['shop']?.note;
      libraryOf(notes, cache);
      expect(cache.read['shop']?.note, same(kept));
      libraryOf([for (final n in notes) n.id == 'shop' ? n.withBody('${n.body}- [ ] Jam\n') : n], cache);
      expect(cache.read['shop']?.note, isNot(same(kept)));
      libraryOf([for (final n in notes) if (n.id != 'ideas') n], cache);
      expect(cache.read.containsKey('ideas'), isFalse);
    });
  });

  group('the defaults', () {
    test('lists notes, the last changed first, with their title and when they changed', () {
      final result = run('');
      expect(result.show, ShowAs.list);
      expect([for (final column in result.columns) column.field], ['title', 'updated']);
      expect(names(result), ['Groceries', 'Fix the login loop', 'Pricing page', 'Standup', 'Dark mode', 'Launch', 'Book ideas']);
    });

    test('shows tickets as a table, the most urgent first, then the soonest due', () {
      final result = run('from: tickets');
      expect(result.show, ShowAs.table);
      expect([for (final column in result.columns) column.label], ['ID', 'Title', 'Status', 'Assignee', 'Priority', 'Due']);
      expect(ids(result), ['GHO-2', 'GHO-1', 'GHO-3']);
      expect(result.opens, 1);
    });

    test('lists the open to-dos, the soonest due first, and those with no due date after', () {
      final result = run('from: tasks');
      expect(names(result), ['Milk #dairy', 'Bread', 'Write the failing test', 'Coffee beans', 'Butter']);
      expect([for (final column in result.columns) column.field], ['text', 'due', 'priority', 'assignee', 'note']);
    });

    test('lists ticked to-dos too where the query asks about being done', () {
      expect(names(run('from: tasks\nwhere: checked')), ['Eggs']);
      expect(names(run('from: tasks\nwhere: checked = no')), hasLength(5));
      expect(names(run('from: tasks\nwhere: status = Done')), ['Eggs']);
    });
  });

  group('from:', () {
    test('reads a tag, the tags inside it, and a note’s tags on its to-dos', () {
      expect(names(run('from: #writing')), ['Book ideas']);
      expect(names(run('from: tasks #dairy')), ['Milk #dairy']);
      expect(names(run('from: tasks #errands')), ['Milk #dairy', 'Bread', 'Coffee beans', 'Butter']);
      expect(names(run('from: tickets #bug')), ['Fix the login loop']);
    });

    test('reads a notebook as its pages, and any other note as the notes that link to it', () {
      expect(names(run('from: tickets [[Launch]]')), ['Pricing page', 'Fix the login loop', 'Dark mode']);
      expect(names(run('from: [[GHO-1]]')), containsAll(['Standup', 'Pricing page']));
    });

    test('warns of a note that is not there, and reads only what links to it by name', () {
      final result = run('from: [[Q4 plan]]');
      expect(result.warnings, ['No note is called “Q4 plan”.']);
      expect(rows(result), isEmpty);
    });

    test('reads a person on a ticket and on a to-do, however they are written', () {
      expect(names(run('from: tickets @sam')), ['Fix the login loop']);
      expect(names(run('from: tasks @Sam')), ['Milk #dairy']);
    });

    test('reads words, or, and not', () {
      expect(names(run('from: "ghost who writes"')), ['Book ideas']);
      expect(names(run('from: tickets @sam or @alex')), ['Pricing page', 'Fix the login loop']);
      expect(names(run('from: tickets [[Launch]] -#bug')), ['Pricing page', 'Dark mode']);
    });
  });

  group('where:', () {
    test('compares a status by its place in the workflow', () {
      expect(names(run('from: tickets\nwhere: status != Done')), ['Pricing page', 'Fix the login loop']);
      expect(names(run('from: tickets\nwhere: status < In review')), ['Pricing page', 'Fix the login loop']);
      expect(names(run('from: tickets\nwhere: status >= In progress')), ['Fix the login loop', 'Dark mode']);
      expect(names(run('from: tickets\nwhere: category = done')), ['Dark mode']);
    });

    test('compares a priority by its rank, the most urgent the greatest', () {
      expect(names(run('from: tickets\nwhere: priority >= high')), ['Pricing page', 'Fix the login loop']);
      expect(names(run('from: tasks\nwhere: priority = high')), ['Bread']);
      // None sits between medium and low, as Tasks has it.
      expect(names(run('from: tasks\nwhere: priority < medium')), ['Milk #dairy', 'Write the failing test', 'Coffee beans', 'Butter']);
    });

    test('compares days with today, counted on or back', () {
      expect(names(run('from: tasks\nwhere: due < today')), ['Milk #dairy']);
      expect(names(run('from: tasks\nwhere: due = today')), ['Bread']);
      expect(names(run('from: tasks\nwhere: due <= today+1')), ['Milk #dairy', 'Bread', 'Write the failing test']);
      expect(names(run('from: tickets\nwhere: due > 2026-10-04')), ['Pricing page']);
    });

    test('never lists what has no value for a comparison, but does for is empty and !=', () {
      expect(names(run('from: tickets\nwhere: due < 2027-01-01')), ['Pricing page', 'Fix the login loop']);
      expect(names(run('from: tickets\nwhere: due is empty')), ['Dark mode']);
      expect(names(run('from: tickets\nwhere: assignee != Sam')), ['Pricing page', 'Dark mode']);
    });

    test('compares numbers as a sum reads them, a currency and all', () {
      expect(names(run('from: tickets\nwhere: estimate >= 3')), ['Pricing page', 'Fix the login loop']);
      expect(names(run('from: tasks\nwhere: cost > 10')), ['Coffee beans']);
    });

    test('reads a list as equal to anything it holds', () {
      expect(names(run('from: tickets\nwhere: labels = auth')), ['Fix the login loop']);
      expect(names(run('from: tickets\nwhere: blocked-by contains GHO-1')), ['Pricing page']);
      expect(names(run('from: tickets\nwhere: blocked-by')), ['Pricing page']);
    });

    test('compares words whatever their case, and looks inside them with contains', () {
      expect(names(run('from: tickets\nwhere: title = "pricing PAGE"')), ['Pricing page']);
      expect(names(run('from: tickets\nwhere: title contains login')), ['Fix the login loop']);
      expect(names(run('from: tickets\nwhere: notebook = Launch')), hasLength(3));
    });
  });

  group('the order and the limit', () {
    test('sorts by the fields asked, either way, with nothing last whichever way', () {
      expect(ids(run('from: tickets\nsort: estimate desc')), ['GHO-2', 'GHO-1', 'GHO-3']);
      expect(ids(run('from: tickets\nsort: due desc')), ['GHO-2', 'GHO-1', 'GHO-3']);
      expect(ids(run('from: tickets\nsort: due')), ['GHO-1', 'GHO-2', 'GHO-3']);
      expect(ids(run('from: tickets\nsort: id')), ['GHO-1', 'GHO-2', 'GHO-3']);
    });

    test('shows as many as its limit, and counts how many passed', () {
      final result = run('from: tasks\nlimit: 2');
      expect(names(result), ['Milk #dairy', 'Bread']);
      expect(result.matched, 5);
      expect(result.shown, 2);
    });
  });

  group('the cells', () {
    test('says what kind of value each is, a due day overdue or today while it is still open', () {
      final result = run('from: tickets\ncolumns: id, status, assignee, priority, due, labels, estimate, blocked-by');
      final [pricing, login, dark] = rows(result);
      expect(login.cells, const [
        TextCell('GHO-1'),
        StatusCell('In progress', StatusCategory.doing),
        PeopleCell(['Sam']),
        PriorityCell('high'),
        DayCell('2026-10-03', tone: DayTone.overdue),
        ListCell(['bug', 'auth'], tags: false),
        NumberCell('3'),
        EmptyCell(),
      ]);
      expect(login.cells[4].toJson(), {'kind': 'day', 'day': '2026-10-03', 'tone': 'overdue'});
      expect(login.overdue, isTrue);
      expect(pricing.cells[7], const ListCell(['GHO-1'], tags: false));
      expect(dark.cells[3], const PriorityCell('low'));
      expect(dark.cells[4], const EmptyCell());
    });

    test('gives a to-do its line, its note and its box, and a ticket its key, to open and tick them', () {
      final milk = rows(run('from: tasks #dairy'))[0];
      expect(
        (milk.key, milk.kind, milk.noteId, milk.line, milk.done, milk.id, milk.due, milk.day, milk.overdue),
        ('shop:5', RecordKind.task, 'shop', 5, false, null, '2026-10-04', '2026-10-04', true),
      );
      final ticket = rows(run('from: tickets @alex'))[0];
      expect((ticket.key, ticket.kind, ticket.id, ticket.line, ticket.category), ('gho2', RecordKind.ticket, 'GHO-2', -1, StatusCategory.todo));
    });
  });

  group('groups, boards and totals', () {
    test('lays a ticket board out as the whole workflow, empty statuses and all', () {
      final result = run('from: tickets\nshow: board');
      expect(result.group, 'status');
      expect(
        [for (final group in result.groups) '${group.label}:${group.rows.map((row) => row.id).join(',')}'],
        ['Backlog:', 'To do:GHO-2', 'In progress:GHO-1', 'In review:', 'Done:GHO-3'],
      );
    });

    test('groups by any field, a record in each group its list holds, the group with nothing last', () {
      final result = run('from: tasks\ngroup: assignee');
      expect([for (final group in result.groups) '${group.label}:${group.rows.length}'], ['alex:1', 'sam:1', 'No assignee:3']);
      final labels = run('from: tickets\ngroup: labels');
      expect([for (final group in labels.groups) group.label], ['auth', 'bug', 'No labels']);
    });

    test('groups a board of to-dos by whether they are done, and lists the done ones too', () {
      final result = run('from: tasks\nshow: board');
      expect([for (final group in result.groups) '${group.label}:${group.rows.length}'], ['To do:5', 'Done:1']);
    });

    test('adds up totals as a sum would, over all and over each group', () {
      final result = run('from: tickets\ngroup: status\ntotal: estimate');
      expect(result.totals, const [Total(field: 'estimate', label: 'Estimate', text: '10')]);
      expect([for (final group in result.groups) group.totals[0].text], ['5', '3', '2']);
      expect(run('from: tasks\ntotal: cost').totals[0].text, r'$16.50');
      expect(run('from: tasks\ntotal: nothing-here').totals[0].text, '0');
    });

    test('counts', () {
      final result = run('from: tasks\nshow: count');
      expect(result.show, ShowAs.count);
      expect(result.matched, 5);
    });
  });

  group('a gantt', () {
    test('is Mermaid’s gantt text, a bar from start to due, done and overdue marked', () {
      final result = run('from: tickets\nshow: gantt');
      expect(result.gantt?.placed, 2);
      expect(result.gantt?.code.split('\n').sublist(1), [
        'gantt',
        '  dateFormat YYYY-MM-DD',
        '  axisFormat %e %b',
        '  tickInterval 1week',
        '  GHO-2 Pricing page :2026-10-10, 2026-10-11',
        '  GHO-1 Fix the login loop :active, crit, 2026-09-28, 2026-10-04',
      ]);
    });

    test('is nothing where no record has a day', () {
      expect(run('from: notes #writing\nshow: gantt').gantt, const Gantt(code: '', placed: 0));
      expect(run('from: tickets').gantt, isNull);
    });
  });
}
