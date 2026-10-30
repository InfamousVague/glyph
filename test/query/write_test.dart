import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

import 'support.dart';

/// A query written back as its fence's lines (lib/core/query/write.dart) reads as the query it was written from:
/// every query the web's fixtures read, and the port's own view lines and rollups.
void main() {
  Object? json(Query query) => jsonDecode(jsonEncode(query.toJson()));

  test('every query the web reads comes back from its lines the same', () {
    var held = 0;
    final failures = <String>[];
    for (final one in fixture['cases'] as List) {
      final query = readQuery(one[0] as String).query;
      if (query == null) continue;
      final text = queryText(query);
      final again = readQuery(text);
      if (again.problem != null) {
        failures.add('${jsonEncode(one[0])} wrote ${jsonEncode(text)}: ${again.problem!.message}');
        continue;
      }
      final parted = firstDifference(json(again.query!), json(query));
      if (parted != null) failures.add('${jsonEncode(one[0])} wrote ${jsonEncode(text)}: $parted');
      held += 1;
    }
    // ignore: avoid_print
    print('round trips: $held');
    expect(held, greaterThan(600));
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
  });

  test('the view lines and rollups, written in the order the grammar teaches', () {
    const body = 'from: tickets [[Kiln]] -#wontfix\n'
        'where: (status != Done or due < today+7) and not assignee is empty\n'
        'show: timeline\n'
        'date: due\n'
        'start: start\n'
        'end: due\n'
        'zoom: quarter\n'
        'chart: line\n'
        'x: assignee\n'
        'y: average(hours)\n'
        'series: status\n'
        'rollup: open = count(links where status != Done and title contains "a, b")\n'
        'rollup: spent = sum(hours of backlinks.project)\n'
        'rollup: share = percent(tasks)';
    final query = readQuery(body).query!;
    final text = queryText(query);
    expect(text, 'from: tickets [[Kiln]] not #wontfix\n'
        'where: (status != Done or due < today+7) and not assignee is empty\n'
        'show: timeline\n'
        'date: due\n'
        'start: start\n'
        'end: due\n'
        'zoom: quarter\n'
        'chart: line\n'
        'x: assignee\n'
        'y: average(hours)\n'
        'series: status\n'
        'rollup: open = count(links where status != Done and title contains "a, b")\n'
        'rollup: spent = sum(hours of backlinks.project)\n'
        'rollup: share = percent(tasks)');
    expect(readQuery(text).query, query);
  });

  test('brackets where the grammar needs them, and a quote that holds a quote', () {
    for (final body in const [
      'from: (#a or #b) #c\nwhere: (a = 1 or b = 2) or c = 3',
      'from: #a (#b #c)\nwhere: a and (b and c)',
      'from: not (#a or @sam)\nwhere: not (a = 1 and b = "x")',
      "where: title = 'say \"hi\"'",
      'from: tasks\nwhere: due',
    ]) {
      final query = readQuery(body).query!;
      expect(readQuery(queryText(query)).query, query, reason: '$body wrote ${queryText(query)}');
    }
  });

  test('a fence the switcher and the builder write is read back the same as one written whole', () {
    var body = 'from: tickets';
    body = withClause(body, 'show', 'chart');
    body = withClause(body, 'chart', 'pie');
    body = withClause(body, 'x', 'assignee');
    body = withClause(body, 'rollup', 'open = count(links)');
    final query = readQuery(body).query!;
    expect(readQuery(queryText(query)).query, query);
    expect(query.show, ShowAs.chart);
    expect(query.rollups.single.name, 'open');
  });
}
