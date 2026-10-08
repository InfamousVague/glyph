import 'dart:convert';
import 'dart:io';

import 'package:ghost_md/core/query/query.dart';

/// The small library the query's tests read (the web's `core/query/library.fixture.ts`): a notebook of tickets with
/// the key GHO, a shopping list of to-dos with fields, a note with tags, and a note that links to a ticket. "Today"
/// in these tests is Monday 5 October 2026.
const String today = '2026-10-05';

/// Noon on [day] by this device's clock, in milliseconds: the web's `new Date('${day}T12:00:00').getTime()`.
int noon(String day) {
  final parts = day.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2], 12).millisecondsSinceEpoch;
}

QueryNote _note(String id, String body, String updated, [String created = '2026-09-01']) => QueryNote(id: id, body: body, createdAt: noon(created), updatedAt: noon(updated));

final List<QueryNote> notes = [
  _note('launch', '---\ntitle: "Launch"\nbook: true\nkey: GHO\n---\n# Launch\n\n- [[Fix the login loop]]\n- [[Pricing page]]\n- [[Dark mode]]\n', '2026-09-20'),
  _note(
    'gho1',
    '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nassignee: Sam\npriority: high\ndue: 2026-10-03\nstart: 2026-09-28\nestimate: 3\nlabels: [bug, auth]\n---\n# Fix the login loop\n\nThe token is refreshed twice.\n\n- [ ] Write the failing test 📅 2026-10-06\n',
    '2026-10-04',
  ),
  _note('gho2', '---\ntype: ticket\nid: GHO-2\nstatus: To do\nassignee: Alex\npriority: highest\ndue: 2026-10-10\nestimate: 5\nblocked-by: "[[GHO-1]]"\n---\n# Pricing page\n', '2026-10-02'),
  _note('gho3', '---\ntype: ticket\nid: GHO-3\nstatus: Done\npriority: low\nestimate: 2\n---\n# Dark mode\n', '2026-09-25'),
  _note(
    'shop',
    '---\ntags: [errands]\n---\n# Groceries\n\n- [ ] Milk 📅 2026-10-04 @sam #dairy\n- [x] Eggs ✅ 2026-10-01\n- [ ] Bread ⏫ 📅 2026-10-05\n- [ ] Coffee beans [cost:: \$12]\n- [ ] Butter [cost:: \$4.50] @alex\n- [ ]\n\n```\n- [ ] not a to-do, it is code\n```\n',
    '2026-10-05',
  ),
  _note('ideas', '# Book ideas\n\nA ghost who writes notes #writing/fiction for people who forget.\n', '2026-08-01'),
  _note('standup', '# Standup\n\nWe talked about [[GHO-1]] and the [[Pricing page]].\n', '2026-10-01'),
];

/// What `tool/query_fixtures.mjs` wrote: the web's own answers.
final Map<String, dynamic> fixture = jsonDecode(File('test/query/fixtures/queries.json').readAsStringSync()) as Map<String, dynamic>;

/// Where two JSON values first part, as a path and the two values; null where they say the same. A whole number is
/// the same number however it is held.
String? firstDifference(Object? mine, Object? web, [String path = r'$']) {
  if (mine is num && web is num) return mine == web ? null : '$path: $mine, the web\'s $web';
  if (mine is Map && web is Map) {
    for (final key in {...mine.keys, ...web.keys}) {
      if (!mine.containsKey(key)) return '$path.$key: missing, the web\'s ${_short(web[key])}';
      if (!web.containsKey(key)) return '$path.$key: ${_short(mine[key])}, which the web has not got';
      final inside = firstDifference(mine[key], web[key], '$path.$key');
      if (inside != null) return inside;
    }
    return null;
  }
  if (mine is List && web is List) {
    for (var i = 0; i < mine.length && i < web.length; i += 1) {
      final inside = firstDifference(mine[i], web[i], '$path[$i]');
      if (inside != null) return inside;
    }
    return mine.length == web.length ? null : '$path: ${mine.length} long, the web\'s ${web.length}';
  }
  return mine == web ? null : '$path: ${_short(mine)}, the web\'s ${_short(web)}';
}

String _short(Object? value) {
  final text = jsonEncode(value);
  return text.length > 160 ? '${text.substring(0, 160)}…' : text;
}
