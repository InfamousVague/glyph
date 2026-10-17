// A query of the calendars' events (`from: events`, docs/CALENDAR.md; lib/core/query/records.dart `withEvents`,
// values.dart, run.dart): read, run, tested with where:, sorted, and shown as a list, a table, a calendar, a gantt
// and a count. The library is support.dart's; today is 5 October 2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

import 'support.dart';

final List<QueryEvent> events = [
  QueryEvent(id: 'standup', title: 'Standup', start: DateTime(2026, 10, 5, 9, 30), end: DateTime(2026, 10, 5, 9, 45), allDay: false, location: 'Room 4', calendar: 'Work'),
  QueryEvent(id: 'trip', title: 'Lisbon', start: DateTime(2026, 10, 8), end: DateTime(2026, 10, 11), allDay: true, calendar: 'Home'),
  QueryEvent(id: 'holiday', title: 'Bank holiday', start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 6), allDay: true, calendar: 'Home'),
  QueryEvent(id: 'dentist', title: 'Dentist', start: DateTime(2026, 9, 30, 14), end: DateTime(2026, 9, 30, 15), allDay: false, location: 'High Street', calendar: 'Home'),
];

QueryResult run(String body) {
  final reading = readQuery(body);
  if (reading.problem != null) fail(reading.problem!.message);
  return runQuery(reading.query!, withEvents(libraryOf(notes), events), today);
}

List<QueryRow> rows(QueryResult result) => [for (final group in result.groups) ...group.rows];
List<String> names(QueryResult result) => [for (final row in rows(result)) row.name];

void main() {
  test('`from: events` is read as the kind, and `event` too', () {
    expect(readQuery('from: events').query!.kind, QueryKind.events);
    expect(readQuery('from: event "dentist"').query!.kind, QueryKind.events);
  });

  test('lists every event and nothing else, soonest first, a day’s before its hours, in a list', () {
    final result = run('from: events');
    expect(result.kind, QueryKind.events);
    expect(result.show, ShowAs.list);
    expect(names(result), ['Dentist', 'Bank holiday', 'Standup', 'Lisbon']);
    expect([for (final column in result.columns) column.field], ['title', 'start', 'time', 'location', 'calendar']);
    expect(rows(result).every((row) => row.kind == RecordKind.event && row.noteId.isEmpty && !row.overdue), isTrue);
  });

  test('an event is in no other kind’s query', () {
    for (final kind in ['notes', 'tasks', 'tickets']) {
      expect(rows(run('from: $kind')).any((row) => row.kind == RecordKind.event), isFalse);
    }
    expect(run('from: tickets').matched, 3);
  });

  test('where: on its fields, start against today', () {
    expect(names(run('from: events\nwhere: start >= today')), ['Bank holiday', 'Standup', 'Lisbon']);
    expect(names(run('from: events\nwhere: start = today and allDay')), ['Bank holiday']);
    expect(names(run('from: events\nwhere: calendar = Home and location contains street')), ['Dentist']);
    expect(names(run('from: events\nwhere: end >= 2026-10-10')), ['Lisbon']);
    expect(names(run('from: events\nwhere: location is empty')), ['Bank holiday', 'Lisbon']);
    expect(names(run('from: events\nwhere: calendar = Home and not allDay')), ['Dentist']);
  });

  test('`"words"` look in its title, where it is and its calendar', () {
    expect(names(run('from: events "room 4"')), ['Standup']);
  });

  test('sort: and its cells: a day, its hours, all day as yes or no', () {
    final result = run('from: events\nsort: title desc\ncolumns: title, start, end, time, allDay');
    expect(names(result), ['Standup', 'Lisbon', 'Dentist', 'Bank holiday']);
    final lisbon = rows(result)[1];
    expect([for (final cell in lisbon.cells) cell.toJson()], [
      {'kind': 'text', 'text': 'Lisbon'},
      {'kind': 'day', 'day': '2026-10-08', 'tone': null},
      {'kind': 'day', 'day': '2026-10-10', 'tone': null},
      {'kind': 'empty'},
      {'kind': 'bool', 'on': true},
    ]);
    expect(rows(result).first.cells[3].toJson(), {'kind': 'text', 'text': '09:30–09:45'});
    expect(result.columns.last.label, 'All day');
  });

  test('a table, and a group by calendar', () {
    final result = run('from: events\nshow: table\ngroup: calendar');
    expect(result.show, ShowAs.table);
    expect([for (final group in result.groups) '${group.label} ${group.rows.length}'], ['Home 3', 'Work 1']);
  });

  test('a calendar places each on its first day', () {
    final result = run('from: events\nshow: calendar');
    final weeks = monthWeeks('2026-10', rows(result), today);
    final byDay = {for (final week in weeks) for (final day in week) if (day.rows.isNotEmpty) day.day: [for (final row in day.rows) row.name]};
    expect(byDay, {'2026-09-30': ['Dentist'], '2026-10-05': ['Bank holiday', 'Standup'], '2026-10-08': ['Lisbon']});
  });

  test('a gantt runs each from its first day to its last', () {
    final result = run('from: events\nshow: gantt\nwhere: allDay');
    // Mermaid's end is the start of the day it names: a bar to the 10th ends on the 11th.
    expect(result.gantt!.code, contains('  Bank holiday :2026-10-05, 2026-10-06\n  Lisbon :2026-10-08, 2026-10-11'));
    expect(result.gantt!.placed, 2);
  });

  test('a count says how many', () {
    final result = run('from: events\nshow: count\nwhere: start >= today');
    expect(result.matched, 3);
    expect(result.show, ShowAs.count);
  });

  test('with no events the kind is empty, and the rest of the library as it was', () {
    final result = runQuery(readQuery('from: events').query!, withEvents(libraryOf(notes), const []), today);
    expect(result.matched, 0);
    expect(identical(withEvents(libraryOf(notes), const []).records.length, libraryOf(notes).records.length), isTrue);
  });

  test('an event’s last day: the day before an all-day end, and a timed one’s own unless it ends at midnight', () {
    expect(events[1].endDay, '2026-10-10');
    expect(events[0].endDay, '2026-10-05');
    expect(QueryEvent(id: 'late', title: 'Late', start: DateTime(2026, 10, 5, 22), end: DateTime(2026, 10, 6), allDay: false).endDay, '2026-10-05');
    expect(events[0].hours, '09:30–09:45');
    expect(events[1].hours, isNull);
  });
}
