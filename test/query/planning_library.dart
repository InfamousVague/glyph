// A notebook of a team's tickets, planned in cycles (lib/core/query/planning.dart; Matt, 2026-10-31): what the planning
// tests read, the query core's and the drawn ones'. Its notes carry a comment and the ```comments fence a shared note
// has. "Today" is Thursday 5 November 2026, in its second cycle.
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
