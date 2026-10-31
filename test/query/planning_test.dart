// The planning of tickets through a query (lib/core/query/planning.dart; Matt, 2026-10-31): cycles, estimates and
// velocity, epics and milestones, priority and aging, over a notebook of tickets that is a team's (its notes carry a
// comment and the ```comments fence a shared note has), on Thursday 5 November 2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/planning/cycles.dart';
import 'package:ghost_md/core/planning/history.dart';
import 'package:ghost_md/core/query/query.dart';

import 'support.dart' show noon;

const String today = '2026-11-05';

QueryNote note(String id, String body, {String updated = '2026-11-04'}) => QueryNote(id: id, body: body, createdAt: noon('2026-10-01'), updatedAt: noon(updated));

/// A team's note ends with its comments (lib/comments), which nothing here may read as a ticket's.
const String comments = '\nThe kiln[^c1] is wired.\n\n```comments\n[^c1]: @priya: is the vent in?\n```\n';

String ticket(int n, String title, {required String status, String? cycle, String? estimate, String? who, String? priority, String? parent, String? milestone, String? start, String? due, String type = 'ticket', String extra = ''}) =>
    '---\ntype: $type\nid: KLN-$n\nstatus: $status\n${who == null ? '' : 'assignee: $who\n'}${priority == null ? '' : 'priority: $priority\n'}${estimate == null ? '' : 'estimate: $estimate\n'}${cycle == null ? '' : 'cycle: $cycle\n'}${parent == null ? '' : 'parent: "[[$parent]]"\n'}${milestone == null ? '' : 'milestone: "[[$milestone]]"\n'}${start == null ? '' : 'start: $start\n'}${due == null ? '' : 'due: $due\n'}$extra---\n# $title\n$comments';

final List<QueryNote> library = [
  note(
    'kiln',
    '---\nbook: true\nkey: KLN\ncycles: {length: 2w, start: 2026-11-02}\nstale-after: 7d\n---\n# Kiln\n\n- [[Second kiln]]\n- [[Wire the controller]]\n- [[Glaze tests]]\n- [[Firing log]]\n- [[Order shelves]]\n- [[Vent the room]]\n- [[Price list]]\n- [[Shop window]]\n- [[v2 launch]]\n- [[Sprint 9]]\n',
  ),
  note('k1', ticket(1, 'Second kiln', status: 'In progress', type: 'epic', milestone: 'v2 launch', priority: 'high')),
  // The cycle before, ended: two finished, one left over.
  note('k2', ticket(2, 'Wire the controller', status: 'Done', cycle: '2026-C43', estimate: '3', who: 'Sam', parent: 'KLN-1', start: '2026-10-20', due: '2026-10-28')),
  note('k3', ticket(3, 'Glaze tests', status: 'In progress', cycle: '2026-C43', estimate: '5', who: 'Priya', priority: 'urgent', parent: 'KLN-1', start: '2026-10-26', due: '2026-11-12'), updated: '2026-10-20'),
  note('k4', ticket(4, 'Firing log', status: 'Done', cycle: '2026-C43', estimate: '2', who: 'Alex', parent: 'KLN-1')),
  // This cycle.
  note('k5', ticket(5, 'Order shelves', status: 'Done', cycle: '2026-C45', estimate: '1', who: 'Sam', priority: 'low')),
  note('k6', ticket(6, 'Vent the room', status: 'To do', cycle: '"[[2026-C45]]"', estimate: '8', who: 'Priya', priority: 'medium', parent: 'KLN-1', due: '2026-11-20'), updated: '2026-10-25'),
  note('k7', ticket(7, 'Price list', status: 'In review', cycle: '2026-C45', estimate: '4h', who: 'Kim')),
  // In no cycle, waiting a long while.
  note('k8', ticket(8, 'Shop window', status: 'Backlog', who: 'Kim'), updated: '2026-09-01'),
  note('v2', '---\ntype: milestone\ndate: 2026-12-01\n---\n# v2 launch\n'),
  note('s9', '---\ntype: cycle\nstart: 2026-11-16\nend: 2026-11-27\n---\n# Sprint 9\n'),
];

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
