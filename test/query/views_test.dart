import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

import 'support.dart' show noon;

/// The port's own query views and columns (Matt, 2026-10-30, "add all 12"): a calendar on a day field of its own,
/// the drawn timeline's plan, a chart's bars and rollups over linked notes (lib/core/query/rollup.dart, chart.dart,
/// timeline.dart), each worked out from the library a query already reads.
const String today = '2026-10-05';

QueryNote note(String id, String body, [String day = '2026-10-01']) => QueryNote(id: id, body: body, createdAt: noon(day), updatedAt: noon(day));

/// A project and the pages that name it, a notebook of tickets, and a note of to-dos.
final List<QueryNote> library = [
  note('kiln', '---\nstatus: In progress\n---\n# Kiln\n\nSee [[Glaze tests]] and [[Firing log]].\n'),
  note('glaze', '---\nproject: "[[Kiln]]"\nhours: 3\nstatus: Done\ndue: 2026-10-02\n---\n# Glaze tests\n'),
  note('firing', '---\nproject: "[[Kiln]]"\nhours: 5h\nstatus: To do\ndue: 2026-10-09\n---\n# Firing log\n'),
  note('shelf', '---\nproject: "[[Kiln]]"\nhours: 2\nstatus: Done\n---\n# Shelf\n'),
  note('book', '---\nbook: true\nkey: GHO\n---\n# Launch\n\n- [[GHO-1]]\n- [[GHO-2]]\n- [[GHO-3]]\n'),
  note('gho1', '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nstart: 2026-09-28\ndue: 2026-10-03\nestimate: 3\nassignee: Sam\n---\n# Fix the login loop\n'),
  note('gho2', '---\ntype: ticket\nid: GHO-2\nstatus: To do\ndue: 2026-10-10\nestimate: 5\nassignee: Alex\n---\n# Pricing page\n'),
  note('gho3', '---\ntype: ticket\nid: GHO-3\nstatus: Done\nstart: 2026-10-06\nestimate: 2\nassignee: Sam\n---\n# Dark mode\n'),
  note('shop', '# Groceries\n\n- [ ] Milk\n- [x] Eggs\n- [x] Bread\n- [ ] Coffee\n'),
];

QueryResult run(String body, [List<QueryNote>? notes]) {
  final reading = readQuery(body);
  expect(reading.problem, isNull, reason: reading.problem?.message);
  return runQuery(reading.query!, libraryOf(notes ?? library), today);
}

/// The cell a row has under a column.
Cell cellOf(QueryResult result, String key, String field) {
  final row = [for (final group in result.groups) ...group.rows].firstWhere((row) => row.key == key);
  return row.cells[result.columns.indexWhere((column) => column.field == field)];
}

String said(Cell cell) => switch (cell) {
      NumberCell(:final text) || TextCell(:final text) => text,
      DayCell(:final day) => day,
      EmptyCell() => '',
      _ => cell.toString(),
    };

void main() {
  group('the view lines are read', () {
    test('each one field or word, and a rollup a line', () {
      final query = readQuery('from: tickets\nview: chart\nchart: pie\nx: assignee\ny: sum(estimate)\nseries: status\ndate: due\nstart: start\nend: due\nzoom: month\nrollup: open = count(links where status != done)\nrollup: hours = sum(hours of backlinks.project)').query!;
      expect(query.show, ShowAs.chart);
      expect(query.chart, ChartKind.pie);
      expect(query.x, 'assignee');
      expect(query.y, const Measure(Aggregate.sum, 'estimate'));
      expect(query.series, 'status');
      expect((query.date, query.start, query.end, query.zoom), ('due', 'start', 'due', TimelineZoom.month));
      expect(query.rollups.map((rollup) => (rollup.name, rollup.measure.fn, rollup.way, rollup.through)), [
        ('open', Aggregate.count, RollupWay.links, null),
        ('hours', Aggregate.sum, RollupWay.backRelation, 'project'),
      ]);
      expect(query.rollups.first.where, const Compare('status', Op.ne, WordsLiteral('done', quoted: false)));
    });

    test('a y of a field alone is its sum, and the other words for a measure and a chart', () {
      expect(readQuery('y: hours').query!.y, const Measure(Aggregate.sum, 'hours'));
      expect(readQuery('y: avg(hours)').query!.y, const Measure(Aggregate.average, 'hours'));
      expect(readQuery('y: count').query!.y, const Measure(Aggregate.count));
      expect(readQuery('chart: columns').query!.chart, ChartKind.bar);
      expect(readQuery('chart: donut').query!.chart, ChartKind.pie);
    });

    test('says what is wrong, and where', () {
      QueryProblem problem(String body) => readQuery(body).problem!;
      expect(problem('chart: radar').message, '“radar” isn’t a chart: bar, line, pie, burndown or velocity.');
      expect(problem('zoom: decade').message, '“decade” isn’t a zoom: week, month or quarter.');
      expect(problem('y: sum').message, '“sum” needs a field to work out, like sum(hours).');
      expect(problem('date: due, start').message, 'date: is one field, like due.');
      expect(problem('rollup: open count links').message, startsWith('This isn’t a rollup'));
      expect(problem('rollup: open = tally(links)').message, '“tally” isn’t something a rollup works out: count, sum, average, min, max or percent.');
      expect(problem('rollup: h = sum(backlinks)').message, 'sum( ) needs a field of the notes, like sum(hours of links).');
      final inner = problem('rollup: open = count(links where status !=)');
      expect(inner.message, startsWith('After “status !=”'));
      expect(inner.column, 'rollup: open = count(links where status !='.length + 1);
      expect(problem('rollup: a = count(links)\nrollup: a = count(backlinks)').message, 'A rollup called “a” is written twice.');
    });
  });

  group('rollups', () {
    test('count the notes a record links to, those a where passes', () {
      final result = run('where: title = Launch\ncolumns: title, open, all\nrollup: open = count(links where status != done)\nrollup: all = count(links)');
      expect(said(cellOf(result, 'book', 'open')), '2');
      expect(said(cellOf(result, 'book', 'all')), '3');
    });

    test('sum, average, least and most through a relation from the other side, units kept', () {
      final result = run('from: notes "Kiln"\nwhere: title = Kiln\ncolumns: title, hours, mean, least, most, last\nrollup: hours = sum(hours of backlinks.project)\nrollup: mean = average(hours of backlinks.project)\nrollup: least = min(hours of backlinks.project)\nrollup: most = max(hours of backlinks.project)\nrollup: last = max(due of backlinks.project)');
      expect(said(cellOf(result, 'kiln', 'hours')), '10');
      expect(said(cellOf(result, 'kiln', 'mean')), '3.33');
      expect(said(cellOf(result, 'kiln', 'least')), '2');
      expect(said(cellOf(result, 'kiln', 'most')), '5h');
      expect(said(cellOf(result, 'kiln', 'last')), '2026-10-09');
    });

    test('percent done, by count and weighed by a field, of backlinks and of a note\'s own to-dos', () {
      final kiln = run('where: title = Kiln\ncolumns: title, done, weighed\nrollup: done = percent(backlinks)\nrollup: weighed = percent(hours of backlinks)');
      // Glaze tests and Shelf are done, Firing log is not: two of three, and 5 of 10 hours.
      expect(said(cellOf(kiln, 'kiln', 'done')), '67%');
      expect(said(cellOf(kiln, 'kiln', 'weighed')), '50%');
      final shop = run('where: title = Groceries\ncolumns: title, share\nrollup: share = percent(tasks)');
      expect(said(cellOf(shop, 'shop', 'share')), '50%');
    });

    test('through a relation forward, and nothing to work out', () {
      final result = run('where: project\ncolumns: title, kiln, none\nrollup: kiln = count(project where status = In progress)\nrollup: none = average(hours of links)');
      expect(said(cellOf(result, 'glaze', 'kiln')), '1');
      expect(cellOf(result, 'glaze', 'none'), const EmptyCell());
    });

    test('is a field: tested, sorted, totalled', () {
      final result = run('where: hours > 0\ncolumns: title, hours\nsort: hours desc\ntotal: hours\nrollup: hours = sum(hours of backlinks.project)');
      expect([for (final row in result.groups.single.rows) row.key], ['kiln']);
      expect(result.totals.single.text, '10');
    });
  });

  group('a calendar on its own day field', () {
    test('puts each row on the field date: names, and says which field it came from', () {
      final result = run('from: tickets\nshow: calendar\ndate: start');
      final days = {for (final row in result.groups.single.rows) row.key: (row.day, row.dayField)};
      expect(days['gho1'], ('2026-09-28', 'start'));
      expect(days['gho2'], (null, null));
      expect(days['gho3'], ('2026-10-06', 'start'));
      // Unsaid, the first day field each has, due first.
      final first = run('from: tickets\nshow: calendar');
      expect({for (final row in first.groups.single.rows) row.key: row.dayField}, {'gho1': 'due', 'gho2': 'due', 'gho3': 'start'});
    });

    test('a week of days, Monday first', () {
      final week = weekDays('2026-10-08', const [], today);
      expect([for (final day in week) day.day], ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10', '2026-10-11']);
      expect([for (final day in week) if (day.today) day.day], ['2026-10-05']);
      expect(weekName('2026-10-05'), '5 – 11 Oct 2026');
      expect(weekName('2026-09-28'), '28 Sep – 4 Oct 2026');
    });
  });

  group('the timeline\'s plan', () {
    test('a bar from each start to each end, one day where there is one, and the rest counted', () {
      final result = run('from: tickets\nshow: timeline');
      final plan = timelineOf(result.groups, today, zoom: TimelineZoom.week);
      final bars = {for (final bar in plan.lanes.single.bars) bar.row.key: (bar.start, bar.end, bar.to - bar.from)};
      expect(bars, {'gho1': ('2026-09-28', '2026-10-03', 6), 'gho2': ('2026-10-10', '2026-10-10', 1), 'gho3': ('2026-10-06', '2026-10-06', 1)});
      expect(plan.undated, 0);
      // From a Monday, before the first bar; today on it.
      expect(dateOfDayWeekday(plan.first), DateTime.monday);
      expect(plan.first.compareTo('2026-09-28') <= 0, isTrue);
      expect(plan.dayAt(plan.today), today);
      expect(plan.ticks.first.at, 0);
    });

    test('its own fields, in groups, at the zoom its span asks for', () {
      final result = run('from: tickets\nshow: timeline\nstart: due\nend: due\ngroup: assignee');
      expect(result.startField, 'due');
      final plan = timelineOf(result.groups, today);
      expect(plan.zoom, TimelineZoom.week);
      expect([for (final lane in plan.lanes) lane.group.label], ['Alex', 'Sam']);
      expect(plan.undated, 1);
      expect(zoomFor(10), TimelineZoom.week);
      expect(zoomFor(60), TimelineZoom.month);
      expect(zoomFor(200), TimelineZoom.quarter);
      final quarter = timelineOf(result.groups, today, zoom: TimelineZoom.quarter);
      expect(quarter.first.endsWith('-01'), isTrue);
      expect(quarter.ticks.every((tick) => tick.day.endsWith('-01')), isTrue);
    });

    test('a bar carried by its ends never turns round', () {
      expect(movedBar('2026-10-01', '2026-10-05', 2, moveStart: false, moveEnd: true), (start: '2026-10-01', end: '2026-10-07'));
      expect(movedBar('2026-10-01', '2026-10-05', 9, moveStart: true, moveEnd: false), (start: '2026-10-05', end: '2026-10-05'));
      expect(movedBar('2026-10-01', '2026-10-05', -3, moveStart: true, moveEnd: true), (start: '2026-09-28', end: '2026-10-02'));
    });
  });

  group('a chart', () {
    test('counts by status, the statuses in the workflow\'s order', () {
      final chart = run('from: tickets\nshow: chart').chart!;
      expect(chart.kind, ChartKind.bar);
      expect([for (final bucket in chart.buckets) bucket.label], ['To do', 'In progress', 'Done']);
      expect([for (final bar in chart.points) bar.single.value], [1, 1, 1]);
      expect(chart.yLabel, 'Count');
      expect(chart.keysOf(1), ['gho1']);
    });

    test('adds a field up, split by a series', () {
      final chart = run('from: tickets\nshow: chart\nx: assignee\ny: sum(estimate)\nseries: status').chart!;
      expect([for (final bucket in chart.buckets) bucket.label], ['Alex', 'Sam']);
      expect([for (final each in chart.series) each.label], ['To do', 'In progress', 'Done']);
      expect([for (final bar in chart.points) [for (final point in bar) point.value]], [
        [5, 0, 0],
        [0, 3, 2],
      ]);
      expect(chart.whole(1), 5);
      expect(chart.most, 5);
      expect(chart.keysOf(1, 2), ['gho3']);
      expect(chart.yLabel, 'Sum of estimate');
    });

    test('a pie leaves its series out, and a rollup is a measure too', () {
      final chart = run('show: chart\nchart: pie\nx: status\nseries: assignee\ny: sum(open)\nwhere: book\nrollup: open = count(links where status != done)').chart!;
      expect(chart.series.single.key, '');
      expect(chart.points.single.single.value, 2);
    });

    test('is in the result\'s JSON only where it is asked for', () {
      expect(run('from: tickets').toJson() as Map, isNot(contains('chart')));
      expect(run('from: tickets\nshow: chart').toJson() as Map, contains('chart'));
    });
  });
}

int dateOfDayWeekday(String day) => DateTime.parse(day).weekday;
