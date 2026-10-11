import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/core/task_fields.dart' show TaskFields;

import 'support.dart';

/// The query core held to the web's, answer for answer: everything `tool/query_fixtures.mjs` wrote from
/// `tauri/src/app/core/query/` is read and run again here and must come out the same, as JSON writes it. Every
/// query the web's own tests read or run, the ready-made databases, the queries the Guide and docs/QUERIES.md write,
/// and a few hundred made to reach every operator on every kind of value, over three libraries: the web tests' own,
/// Ghost.md: The Guide whole, and one with every edge in it.
///
/// A fixture is one test, so its count is printed once and the cases that fail are named (the first twenty), each
/// with the first place it parts from the web.
void main() {
  String told(List<String> failures) => failures.take(20).join('\n');

  final libraries = <String, List<QueryNote>>{
    for (final MapEntry(key: name, value: list) in (fixture['libraries'] as Map<String, dynamic>).entries)
      name: [
        for (final note in list as List) QueryNote(id: note[0] as String, body: note[1] as String, createdAt: noon(note[2] as String), updatedAt: noon(note[3] as String)),
      ],
  };
  final built = {for (final MapEntry(key: name, value: list) in libraries.entries) name: libraryOf(list)};
  final day = fixture['today'] as String;

  test('the library in the test support is the web tests\' own', () {
    expect(day, today);
    expect([for (final note in notes) note.id], [for (final note in libraries['fixture']!) note.id]);
    for (var i = 0; i < notes.length; i += 1) {
      expect(notes[i].body, libraries['fixture']![i].body, reason: notes[i].id);
      expect(notes[i].createdAt, libraries['fixture']![i].createdAt);
      expect(notes[i].updatedAt, libraries['fixture']![i].updatedAt);
    }
  });

  test('every note and to-do is read as the web reads it', () {
    List<int> summed(String text) {
      var sum = 0;
      for (final unit in text.codeUnits) {
        sum = (sum * 31 + unit) & 0xFFFFFFFF;
      }
      return [text.length, sum];
    }

    Map<String, Object?>? fields(TaskFields? f) => f == null
        ? null
        : {
            'due': f.due,
            'start': f.start,
            'scheduled': f.scheduled,
            'done': f.done,
            'created': f.created,
            'cancelled': f.cancelled,
            'recurs': f.recurs,
            'priority': f.priority,
            'assignees': f.assignees,
            'id': f.id,
            'dependsOn': f.dependsOn,
            'onCompletion': f.onCompletion,
            'fields': f.fields,
          };
    final failures = <String>[];
    var count = 0;
    for (final MapEntry(key: name, value: library) in built.entries) {
      final web = (fixture['records'] as Map<String, dynamic>)[name] as List;
      final mine = [
        for (final record in library.records)
          {
            'kind': record.kind.name,
            'noteId': record.noteId,
            'line': record.line,
            'source': record.source,
            'title': record.title,
            'text': record.kind == RecordKind.task ? record.text : summed(record.text),
            'done': record.done,
            'anchor': record.anchor,
            'notebook': record.notebook,
            'books': record.books,
            'workflow': record.workflow,
            'tags': record.tags,
            'created': record.created,
            'updated': record.updated,
            'props': record.props,
            'ticket': record.ticket?.toJson(),
            'fields': fields(record.fields),
            'linksTo': record.linksTo.toList()..sort(),
            'linkKeys': record.linkKeys,
            'haystack': summed(record.haystack),
          },
      ];
      count += web.length;
      if (mine.length != web.length) failures.add('$name: ${mine.length} records, the web\'s ${web.length}');
      for (var i = 0; i < mine.length && i < web.length; i += 1) {
        final difference = firstDifference(mine[i], web[i]);
        if (difference != null) failures.add('$name ${mine[i]['kind']} ${mine[i]['noteId']}:${mine[i]['line']}: $difference');
      }
    }
    // ignore: avoid_print
    print('records: ${count - failures.length} of $count');
    expect(count, 76);
    expect(failures, isEmpty, reason: told(failures));
  });

  test('every query is read as the web reads it, and run as the web runs it', () {
    final cases = fixture['cases'] as List;
    final failures = <String>[];
    var read = 0, runs = 0;
    for (final one in cases) {
      final body = one[0] as String;
      final label = jsonEncode(body);
      final Reading reading;
      try {
        reading = readQuery(body);
      } catch (error) {
        failures.add('$label: reading threw $error');
        continue;
      }
      final parted = firstDifference(reading.toJson(), one[1]);
      if (parted != null) {
        failures.add('$label: read $parted');
        continue;
      }
      final query = reading.query;
      if (query == null) continue;
      read += 1;
      for (final MapEntry(key: name, value: web) in (one[2] as Map<String, dynamic>).entries) {
        runs += 1;
        try {
          final difference = firstDifference(runQuery(query, built[name]!, day).toJson(), web);
          if (difference != null) failures.add('$label over $name: $difference');
        } catch (error, stack) {
          failures.add('$label over $name: threw $error\n${stack.toString().split('\n').take(4).join('\n')}');
        }
      }
    }
    // ignore: avoid_print
    print('queries: ${cases.length} read ($read without a problem), $runs runs, ${failures.length} that part from the web');
    expect(cases.length, 711);
    expect(runs, 1144);
    expect(failures, isEmpty, reason: told(failures));
  });

  test('every query fence is found where the web finds it', () {
    // The documents are the web's own files, so the test reads the fences back out of what the fixture holds of them.
    final fences = fixture['fences'] as List;
    expect(fences.length, 3);
    final guide = {for (final note in libraries['guide']!) note.id: note.body};
    for (final one in fences) {
      final name = one[0] as String;
      final found = one[1] as List;
      if (name == 'shapes') {
        const doc = '~~~~QUERY height=900 wide=yes\nfrom: tasks\n```\n~~~~\n\n```query height=12.3em\n```\n\n````query\nshow: board\n```\n````\n```query notes\n```\n\n```query\nfrom: never closed\n';
        expect(firstDifference([for (final fence in queryFencesIn(doc)) fence.toJson()], found), isNull);
      } else if (name.startsWith('guidebook/chapters/')) {
        final id = 'ch${name.substring('guidebook/chapters/'.length, 'guidebook/chapters/'.length + 2)}';
        expect(firstDifference([for (final fence in queryFencesIn(guide[id]!)) fence.toJson()], found), isNull, reason: name);
      }
    }
    // And no chapter the web found none in has one here.
    final withFences = {for (final one in fences) one[0] as String};
    for (final MapEntry(key: id, value: body) in guide.entries) {
      if (queryFencesIn(body).isEmpty) continue;
      expect(withFences.any((name) => name.contains('/${id.substring(2)}-')), isTrue, reason: id);
    }
  });

  test('a calendar opens on the web\'s month and lays out the web\'s weeks', () {
    final months = fixture['months'] as List;
    expect(months.length, 5);
    for (final one in months) {
      final result = runQuery(readQuery(one[0] as String).query!, built['fixture']!, day);
      final rows = [for (final group in result.groups) ...group.rows];
      final month = openingMonth(rows, day);
      expect(month, one[1], reason: one[0] as String);
      final weeks = [
        for (final week in monthWeeks(month, rows, day))
          [
            for (final each in week) [each.day, each.date, each.inMonth, each.today, [for (final row in each.rows) row.key]],
          ],
      ];
      expect(firstDifference(weeks, one[2]), isNull, reason: one[0] as String);
    }
  });

  test('a lane of a ticket board drafts the ticket the web drafts', () {
    final drafts = fixture['drafts'] as List;
    expect(drafts.length, 92);
    for (final one in drafts) {
      final query = readQuery(one[0] as String).query!;
      final result = runQuery(query, built['fixture']!, day);
      final draft = ticketDraft(query, result.group, one[1] as String?);
      expect(firstDifference(draft?.toJson(), one[2]), isNull, reason: '${one[0]} / ${one[1]}');
    }
  });

  test('words are ordered as the page orders them', () {
    final collation = fixture['collation'] as Map<String, dynamic>;
    final words = (collation['words'] as List).cast<String>();
    String mark(int order) => order < 0 ? '<' : (order > 0 ? '>' : '=');
    final failures = <String>[];
    var pairs = 0;
    for (var i = 0; i < words.length; i += 1) {
      final plain = (collation['plain'] as List)[i] as String;
      final numeric = (collation['numeric'] as List)[i] as String;
      for (var j = 0; j < words.length; j += 1) {
        pairs += 2;
        final one = mark(localeCompare(words[i], words[j]));
        if (one != plain[j]) failures.add('${jsonEncode(words[i])} $one ${jsonEncode(words[j])}, the page\'s ${plain[j]}');
        final two = mark(localeCompare(words[i], words[j], numeric: true, base: true));
        if (two != numeric[j]) failures.add('numeric, base: ${jsonEncode(words[i])} $two ${jsonEncode(words[j])}, the page\'s ${numeric[j]}');
      }
    }
    // ignore: avoid_print
    print('collation: ${words.length} words, ${pairs - failures.length} of $pairs pairs');
    expect(failures, isEmpty, reason: told(failures));
  });
}
