import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/read.dart';

/// A query's lines, read (lib/core/query/read.dart, tauri/docs/QUERIES.md): every clause, its defaults, the words
/// a test compares with, and the one sentence a query that cannot be read is answered with, at its line and column.
/// Case for case with the web's `core/query/read.test.ts`.
Query read(String body) {
  final reading = readQuery(body);
  final problem = reading.problem;
  if (problem != null) fail('${problem.line}:${problem.column} ${problem.message}');
  return reading.query!;
}

QueryProblem problem(String body) {
  final reading = readQuery(body);
  if (reading.problem == null) fail('read, when a problem was expected');
  return reading.problem!;
}

const _done = WordsLiteral('Done', quoted: false);

void main() {
  group('a query with nothing in it', () {
    test('reads every note, each clause left for its default', () {
      expect(read('').toJson(), {'kind': 'notes', 'from': null, 'where': null, 'sort': <Object>[], 'group': null, 'show': null, 'columns': <Object>[], 'total': <Object>[], 'limit': null});
      expect(read('\n  \n'), read(''));
    });

    test('leaves a clause with nothing after its colon for its default', () {
      expect(read('from:\nwhere:\nshow:'), read(''));
    });
  });

  group('from:', () {
    test('reads the kind of record first, in any of the ways it is said', () {
      expect(read('from: tickets').kind, QueryKind.tickets);
      expect(read('from: Issues').kind, QueryKind.tickets);
      expect(read('from: tasks').kind, QueryKind.tasks);
      expect(read('from: to-dos').kind, QueryKind.tasks);
      expect(read('from: notes').kind, QueryKind.notes);
      expect(read('from: tasks').from, isNull);
    });

    test('reads a tag, a notebook, a person and words', () {
      expect(read('from: #bug').from, const TagSource('bug'));
      expect(read('from: #Work/Clients').from, const TagSource('work/clients'));
      expect(read('from: [[Launch plan]]').from, const LinkSource('Launch plan'));
      expect(read('from: [[Launch plan#Goals|the plan]]').from, const LinkSource('Launch plan'));
      expect(read('from: @sam').from, const PersonSource('sam'));
      expect(read('from: "release notes"').from, const WordsSource('release notes'));
      expect(read('from: “curly quotes”').from, const WordsSource('curly quotes'));
    });

    test('reads filters side by side, or a comma, as all of them', () {
      const all = AndSource([TagSource('bug'), PersonSource('sam')]);
      expect(read('from: tasks #bug @sam').from, all);
      expect(read('from: tasks #bug, @sam').from, all);
      expect(read('from: tasks #bug and @sam').from, all);
    });

    test('reads or, not, a dash and brackets', () {
      expect(read('from: #bug or #ui').from, const OrSource([TagSource('bug'), TagSource('ui')]));
      expect(read('from: #bug -#wontfix').from, const AndSource([TagSource('bug'), NotSource(TagSource('wontfix'))]));
      expect(read('from: not [[Archive]]').from, const NotSource(LinkSource('Archive')));
      expect(
        read('from: (#bug or #ui) @sam').from,
        const AndSource([
          OrSource([TagSource('bug'), TagSource('ui')]),
          PersonSource('sam'),
        ]),
      );
    });

    test('says what is wrong with what it cannot read', () {
      expect(problem('from: #bug tickets').message, '“tickets” goes first in from:, before the #tags, [[notebooks]], @people and "words".');
      expect(problem('from: bugs').message, contains('“bugs” isn’t something a query reads from'));
      expect(problem('from: [[Launch plan').message, 'A [[ opened here is never closed with ]].');
      expect(problem('from: "open').message, 'A quote opened here is never closed.');
      expect(problem('from: (#bug or #ui').message, 'A bracket opened here is never closed.');
      expect(problem('from: #bug)').message, 'A bracket closes here that was never opened.');
      expect(problem('from: #bug or').message, 'Something to read from is missing after “or”.');
    });

    test('puts a problem at its line and column, counting from 1', () {
      final second = problem('show: table\nfrom: #bug bugs');
      expect([second.line, second.column], [2, 12]);
      final first = problem('  from:   bugs');
      expect([first.line, first.column], [1, 11]);
    });
  });

  group('where:', () {
    test('reads a comparison, its field in Dataview’s form and its value read for what it is', () {
      expect(read('where: status != Done').where, const Compare('status', Op.ne, _done));
      expect(read('where: estimate >= 3').where, const Compare('estimate', Op.ge, NumberLiteral(3, '3')));
      expect(read('where: estimate >= 3').where!.toJson(), {
        'kind': 'compare',
        'field': 'estimate',
        'op': '>=',
        'value': {'kind': 'number', 'value': 3, 'text': '3'},
      });
      expect(read('where: due < 2026-10-03').where, const Compare('due', Op.lt, DateLiteral('2026-10-03')));
      expect(read('where: Due-Date = today').where, const Compare('due-date', Op.eq, TodayLiteral(0, 'today')));
    });

    test('reads a status of more than one word without quotes, and one with and in it with them', () {
      expect(read('where: status = In progress').where, const Compare('status', Op.eq, WordsLiteral('In progress', quoted: false)));
      expect(read('where: status = "Won\'t do and done"').where, const Compare('status', Op.eq, WordsLiteral("Won't do and done", quoted: true)));
    });

    test('reads today counted on or back, in days or weeks, and tomorrow and yesterday', () {
      int? offset(String body) => switch (read(body).where) {
            Compare(value: TodayLiteral(:final offset)) => offset,
            _ => null,
          };
      expect(offset('where: due < today+7'), 7);
      expect(offset('where: due < today + 7 days'), 7);
      expect(offset('where: due > today-2w'), -14);
      expect(offset('where: due = tomorrow'), 1);
      expect(offset('where: due = yesterday'), -1);
    });

    test('reads the other ways to write an operator', () {
      String? op(String body) => switch (read(body).where) {
            Compare(:final op) => op.sign,
            _ => null,
          };
      expect(op('where: status == Done'), '=');
      expect(op('where: status ≠ Done'), '!=');
      expect(op('where: due ≤ today'), '<=');
      expect(op('where: due ≥ today'), '>=');
      expect(op('where: status is Done'), '=');
      expect(op('where: status is not Done'), '!=');
      expect(op('where: labels contains ui'), 'contains');
      expect(op('where: labels has ui'), 'contains');
      expect(op('where: labels not contains ui'), '!contains');
    });

    test('reads is empty, is not empty, and a field alone', () {
      expect(read('where: due is empty').where, const EmptyTest('due', empty: true));
      expect(read('where: assignee is not empty').where, const EmptyTest('assignee', empty: false));
      expect(read('where: due = empty').where, const Compare('due', Op.eq, EmptyLiteral()));
      expect(read('where: blocked-by').where, const Has('blocked-by'));
    });

    test('reads and before or, not, and brackets', () {
      expect(
        read('where: status != Done and (priority >= high or due < today+7)').where,
        const AndCondition([
          Compare('status', Op.ne, _done),
          OrCondition([
            Compare('priority', Op.ge, WordsLiteral('high', quoted: false)),
            Compare('due', Op.lt, TodayLiteral(7, 'today+7')),
          ]),
        ]),
      );
      expect(read('where: a = 1 or b = 2 and c = 3').where, isA<OrCondition>());
      expect(read('where: not checked').where, const NotCondition(Has('checked')));
    });

    test('reads the names a field is also called as the one the app keeps', () {
      expect(fieldName('Assignees'), 'assignee');
      expect(fieldName('completed'), 'checked');
      expect(fieldName('completion'), 'done');
      expect(fieldName('Blocked By'), 'blocked-by');
      expect((read('where: people = Sam').where! as Compare).field, 'assignee');
    });

    test('joins two where: lines with and', () {
      final where = read('where: status != Done\nwhere: assignee = Sam').where;
      expect(where, isA<AndCondition>());
      expect([for (final each in (where! as AndCondition).all) (each as Compare).field], ['status', 'assignee']);
    });

    test('says what is wrong with a test it cannot read', () {
      expect(problem('where: = Done').message, 'A field is missing here, like status or due, before “=”.');
      expect(problem('where: status !=').message, 'After “status !=”, something to compare it with: a word, a number, a date or empty.');
      expect(problem('where: status Done').message, 'After “status”, a comparison: =, !=, <, >, contains, or is empty.');
      expect(problem('where: due < 2026-02-30').message, '“2026-02-30” isn’t a day on the calendar.');
      expect(problem('where: (status = Done').message, 'A bracket opened here is never closed.');
      expect(problem('where: status = Done)').message, 'A bracket closes here that was never opened.');
    });
  });

  group('the other lines', () {
    test('reads sort, each field asc or desc, with or without by', () {
      expect(read('sort: priority desc, due').sort, const [SortKey('priority', desc: true), SortKey('due')]);
      expect(read('sort by: Due Date descending').sort, const [SortKey('due-date', desc: true)]);
      expect(read('sort: by updated').sort, const [SortKey('updated')]);
    });

    test('reads group by one field', () {
      expect(read('group: status').group, 'status');
      expect(read('group by: assignee').group, 'assignee');
      expect(read('group: by priority').group, 'priority');
      expect(problem('group: status, assignee').message, 'A query groups by one field, like status.');
    });

    test('reads show as any of its ways, and the other words for them', () {
      for (final way in ['table', 'list', 'board', 'calendar', 'gantt', 'count']) {
        expect(read('show: $way').show?.name, way);
      }
      expect(ShowAs.values.map((way) => way.name), ['table', 'list', 'board', 'calendar', 'gantt', 'count']);
      expect(read('show: Kanban').show, ShowAs.board);
      expect(read('show: timeline').show, ShowAs.gantt);
      expect(problem('show: pie').message, '“pie” isn’t a way to show a query: table, list, board, calendar, gantt or count.');
    });

    test('reads columns and totals as lists of fields', () {
      expect(read('columns: id, Title, Blocked By').columns, ['id', 'title', 'blocked-by']);
      expect(read('total: estimate, cost').total, ['estimate', 'cost']);
      expect(problem('columns: id, ti@tle').message, '“ti@tle” isn’t a field’s name: a name is letters, numbers and dashes, like blocked-by.');
    });

    test('reads a limit, and says when it is not a whole number', () {
      expect(read('limit: 20').limit, 20);
      expect(problem('limit: twenty').message, 'A limit is a whole number, like 20.');
      expect(problem('limit: 0').message, 'A limit is a whole number, like 20.');
    });

    test('reads names in any case, and two words as one space', () {
      expect(read('FROM: tickets\nSort  By: due').sort, const [SortKey('due')]);
    });
  });

  group('a line a query has not got', () {
    test('says which it might have meant', () {
      expect(problem('form: #bug').message, '“form” isn’t a line a query has: did you mean “from”?');
      expect(problem('shwo: table').message, '“shwo” isn’t a line a query has: did you mean “show”?');
    });

    test('lists them all where nothing is near', () {
      expect(problem('colour: red').message, '“colour” isn’t a line a query has: it has from, where, sort, group, show, columns, total and limit.');
    });

    test('says how a line is written where it has no colon', () {
      expect(problem('just some words').message, 'A query’s line is a name, a colon and what it says, like “where: status != Done”.');
    });

    test('says when a line is written twice, and where the first is', () {
      expect(problem('show: table\nfrom: #a\nshow: list'), const QueryProblem(line: 3, column: 1, message: '“show:” is written twice: a query has one, on line 1.'));
    });
  });

  group('the fields a condition names', () {
    test('walks and, or and not', () {
      final where = read('where: status != Done and (not checked or due < today)').where;
      expect(fieldsNamed(where).toList()..sort(), ['checked', 'due', 'status']);
      expect(fieldsNamed(null), isEmpty);
    });
  });
}
