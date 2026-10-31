// The planning of tickets through a query (lib/core/query/planning.dart; Matt, 2026-10-31): cycles, estimates and
// velocity, epics and milestones, priority and aging, over a notebook of tickets that is a team's (its notes carry a
// comment and the ```comments fence a shared note has), on Thursday 5 November 2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/planning/cycles.dart';
import 'package:ghost_md/core/planning/history.dart';
import 'package:ghost_md/core/query/query.dart';

import 'planning_library.dart';

QueryResult run(String lines, {StatusPast? past, List<QueryNote>? notes}) {
  final reading = readQuery(lines);
  expect(reading.problem, isNull, reason: lines);
  return runQuery(reading.query!, libraryOf(notes ?? library), today, past: past);
}

List<String> ids(QueryResult result) => [for (final group in result.groups) for (final row in group.rows) row.id ?? row.name];

void main() {
  group('cycles', () {
    test('cycle = current is a ticket in its notebook’s cycle today, however its cycle is written', () {
      expect(ids(run('from: tickets [[Kiln]]\nwhere: cycle = current\nsort: id')), ['KLN-5', 'KLN-6', 'KLN-7']);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: cycle = previous\nsort: id')), ['KLN-2', 'KLN-3', 'KLN-4']);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: cycle != current and cycle is not empty\nsort: id')), ['KLN-2', 'KLN-3', 'KLN-4']);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: cycle = 2026-C43\nsort: id')), ['KLN-2', 'KLN-3', 'KLN-4']);
      // A quoted word is a cycle's name, not today's.
      expect(ids(run('from: tickets\nwhere: cycle = "current"')), isEmpty);
    });

    test('a board of the current cycle has the workflow’s lanes', () {
      final board = run('from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board');
      expect([for (final group in board.groups) '${group.label} ${group.rows.length}'], ['Backlog 0', 'To do 1', 'In progress 0', 'In review 1', 'Done 1']);
    });

    test('groups by cycle, with each cycle’s estimate added up, and each person’s', () {
      final byCycle = run('from: tickets [[Kiln]]\ngroup: cycle\ntotal: estimate');
      expect([for (final group in byCycle.groups) '${group.label}: ${group.totals.single.text}'], ['2026-C43: 10', '2026-C45: 13', 'No cycle: 0']);
      final byWho = run('from: tickets [[Kiln]]\nwhere: cycle = current\ngroup: assignee\ntotal: estimate');
      expect([for (final group in byWho.groups) '${group.label}: ${group.totals.single.text}'], ['Kim: 4', 'Priya: 8', 'Sam: 1']);
    });

    test('a query of the current cycle offers to carry the last one’s unfinished tickets on', () {
      final offer = run('from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board').carry!;
      expect(offer.from.name, '2026-C43');
      expect(offer.to.name, '2026-C45');
      expect(offer.noteIds, ['k3']);
      expect(offer.words, 'Move 1 unfinished to 2026-C45');
      // Carried: its cycle written, its comments and the rest of its words as they were.
      final carried = withCycle(library.firstWhere((each) => each.id == 'k3').body, offer.to);
      expect(carried, contains('cycle: 2026-C45\n'));
      expect(carried, endsWith(comments));
      final after = [for (final each in library) each.id == 'k3' ? each.withBody(carried) : each];
      expect(run('from: tickets [[Kiln]]\nwhere: cycle = current', notes: after).carry, isNull);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: cycle = current\nsort: id', notes: after)), ['KLN-3', 'KLN-5', 'KLN-6', 'KLN-7']);
      // A query that says nothing of cycles offers nothing.
      expect(run('from: tickets [[Kiln]]').carry, isNull);
    });
  });

  group('a burndown', () {
    // KLN-5 was finished on the 3rd, by its versions; KLN-7 is not done; KLN-6 not started.
    final past = TicketHistory((id) async => const [])
      ..hold('k5', const [StatusChange(day: '2026-11-02', status: 'To do'), StatusChange(day: '2026-11-03', status: 'Done')]);

    test('counts the current cycle’s points down by the day each was finished, and draws the ideal', () {
      final result = run('from: tickets [[Kiln]]\nshow: burndown', past: past);
      final chart = result.chart!;
      expect(result.show, ShowAs.chart);
      expect(result.cycle!.name, '2026-C45');
      expect(chart.kind, ChartKind.line);
      expect(chart.yLabel, 'Points left');
      expect(chart.buckets.length, 14);
      expect(chart.buckets.first.label, '2 Nov');
      expect(chart.buckets[1].label, '3');
      // 1 + 8 + 4 (hours read as their number) = 13; KLN-5 done on the 3rd; nothing after today.
      expect([for (final bar in chart.points) bar[0].value], [13, 12, 12, 12, null, null, null, null, null, null, null, null, null, null]);
      expect(chart.points.first[1].value, 13);
      expect(chart.points.last[1].value, 0);
      expect([for (final series in chart.series) series.label], ['Remaining', 'Ideal']);
      expect(chart.points[1][0].keys, ['k6', 'k7']);
    });

    test('of tickets when none is estimated, or when y: count says so', () {
      final counted = run('from: tickets [[Kiln]]\nshow: burndown\ny: count', past: past).chart!;
      expect(counted.yLabel, 'Tickets left');
      expect([for (final bar in counted.points.take(4)) bar[0].value], [3, 2, 2, 2]);
    });

    test('of the cycle a cycle: line names, and a cycle note’s', () {
      final before = run('from: tickets [[Kiln]]\nshow: burndown\ncycle: previous').chart!;
      expect(before.buckets.first.key, '2026-10-19');
      // Its two finished were last changed on the 4th, which is after it ended: still open on its last day.
      expect(before.points.last[0].value, 10);
      final sprint = run('from: tickets [[Kiln]]\nshow: burndown\ncycle: [[Sprint 9]]');
      expect(sprint.cycle!.name, 'Sprint 9');
      expect(sprint.chart!.buckets.length, 12);
      expect(sprint.warnings, ['Nothing is in Sprint 9 yet: give a ticket “cycle: [[Sprint 9]]”.']);
    });

    test('is written back as it was read', () {
      expect(queryText(readQuery('from: tickets [[Kiln]]\nshow: burndown\ncycle: previous').query!), 'from: tickets [[Kiln]]\nshow: burndown\ncycle: previous');
      expect(queryText(readQuery('from: tickets\nshow: chart\nchart: velocity').query!), 'from: tickets\nshow: velocity');
      expect(queryText(readQuery('from: notes [[Kiln]]\nshow: roadmap').query!), 'from: [[Kiln]]\nshow: roadmap');
    });
  });

  group('velocity', () {
    test('is what each cycle finished, up to today’s, as bars', () {
      final chart = run('from: tickets [[Kiln]]\nshow: velocity').chart!;
      expect(chart.kind, ChartKind.bar);
      expect([for (final bucket in chart.buckets) bucket.label], ['C33', 'C35', 'C37', 'C39', 'C41', 'C43', 'C45']);
      expect([for (final bar in chart.points) bar.single.value], [0, 0, 0, 0, 0, 5, 1]);
      expect(chart.points[5].single.keys, ['k2', 'k4']);
      expect(chart.yLabel, 'Points finished');
    });
  });

  group('epics and milestones', () {
    test('an epic’s progress, and the epic and milestone its tickets are under', () {
      final result = run('from: tickets [[Kiln]]\ncolumns: id, epic, milestone, progress\nsort: id');
      String cell(String id, int column) {
        final row = [for (final group in result.groups) ...group.rows].firstWhere((row) => row.id == id);
        return switch (row.cells[column]) {
          TextCell(:final text) || NumberCell(:final text) => text,
          _ => '',
        };
      }

      // Two of its four done, five of eighteen points.
      expect(cell('KLN-1', 3), '28%');
      expect(cell('KLN-3', 1), 'Second kiln');
      expect(cell('KLN-3', 2), 'v2 launch');
      expect(cell('KLN-5', 1), '');
      final epic = [for (final group in result.groups) ...group.rows].firstWhere((row) => row.id == 'KLN-1').plan!;
      expect(epic.epic, isTrue);
      expect(epic.progress!.words, '2 of 4 done · 5 of 18 points');
      expect(ids(run('from: tickets\nwhere: epic = "Second kiln"\nsort: id')), ['KLN-2', 'KLN-3', 'KLN-4', 'KLN-6']);
    });

    test('a roadmap is its epics and milestones over time, an epic from its tickets’ days to its milestone', () {
      final roadmap = run('from: notes [[Kiln]]\nshow: roadmap');
      expect(roadmap.show, ShowAs.timeline);
      expect(roadmap.plan, PlanView.roadmap);
      final rows = [for (final group in roadmap.groups) ...group.rows];
      expect([for (final row in rows) '${row.name} ${row.start}…${row.end}'], ['Second kiln 2026-10-20…2026-12-01', 'v2 launch 2026-12-01…2026-12-01']);
      expect(roadmap.startField, 'roadmap-start');
    });
  });

  group('priority and aging', () {
    test('sort the most urgent first, urgent above high, and filter by it', () {
      expect(ids(run('from: tickets [[Kiln]]\nwhere: priority is not empty\nsort: priority, id')), ['KLN-3', 'KLN-1', 'KLN-6', 'KLN-5']);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: priority = urgent')), ['KLN-3']);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: priority >= high\nsort: id')), ['KLN-1', 'KLN-3']);
    });

    test('stale is a ticket left in its status past its notebook’s stale-after, read from its last change or its versions', () {
      expect(ids(run('from: tickets [[Kiln]]\nwhere: stale\nsort: id')), ['KLN-3', 'KLN-6', 'KLN-8']);
      final aged = run('from: tickets [[Kiln]]\nwhere: stale\ncolumns: id, age\nsort: age desc');
      expect([for (final row in aged.groups.single.rows) '${row.id} ${(row.cells[1] as NumberCell).text} ${row.plan!.staleDays}'], ['KLN-8 65 days 65', 'KLN-3 16 days 16', 'KLN-6 11 days 11']);
      // Its versions say KLN-6 moved to To do on 1 November: four days, fresh.
      final past = TicketHistory((id) async => const [])..hold('k6', const [StatusChange(day: '2026-11-01', status: 'To do')]);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: stale\nsort: id', past: past)), ['KLN-3', 'KLN-8']);
      expect(ids(run('from: tickets [[Kiln]]\nwhere: not stale and status != Done\nsort: id', past: past)), ['KLN-1', 'KLN-6', 'KLN-7']);
    });

    test('a notebook that says stale-after: off has nothing stale', () {
      final off = [for (final each in library) each.id == 'kiln' ? each.withBody(each.body.replaceFirst('stale-after: 7d', 'stale-after: off')) : each];
      expect(ids(run('from: tickets [[Kiln]]\nwhere: stale', notes: off)), isEmpty);
    });
  });
}
