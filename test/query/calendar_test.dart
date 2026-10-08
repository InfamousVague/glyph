import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/properties.dart' show StatusCategory;
import 'package:ghost_md/core/query/query.dart';

/// A query's records laid out as a month (lib/core/query/calendar.dart), case for case with the web's
/// `core/query/calendar.test.ts`.
QueryRow row(String name, String? day) => QueryRow(
      key: name,
      kind: RecordKind.task,
      noteId: 'n',
      line: 0,
      source: '',
      anchor: null,
      name: name,
      id: null,
      done: false,
      category: StatusCategory.todo,
      workflow: const [],
      cells: const [],
      day: day,
      start: null,
      due: day,
      overdue: false,
    );

void main() {
  group('months', () {
    test('counts on and back across years', () {
      expect(monthOf('2026-10-05'), '2026-10');
      expect(monthAfter('2026-10', 1), '2026-11');
      expect(monthAfter('2026-12', 1), '2027-01');
      expect(monthAfter('2026-01', -1), '2025-12');
      expect(monthAfter('2026-10', -22), '2024-12');
    });

    test('names a month in the language asked', () {
      // In English whatever is asked: see calendar.dart.
      expect(monthName('2026-10', 'en-GB'), 'October 2026');
    });

    test('opens on today’s month, unless everything is in another', () {
      expect(openingMonth([row('a', '2026-10-09')], '2026-10-05'), '2026-10');
      expect(openingMonth([], '2026-10-05'), '2026-10');
      expect(openingMonth([row('a', '2026-12-01'), row('b', '2026-11-20'), row('c', '2026-02-01')], '2026-10-05'), '2026-11');
      expect(openingMonth([row('a', '2026-02-01'), row('b', '2026-03-01')], '2026-10-05'), '2026-03');
    });
  });

  group('a month of weeks', () {
    test('starts on the Monday of the week the 1st is in, and ends with the week the last day is in', () {
      // 1 October 2026 is a Thursday.
      final weeks = monthWeeks('2026-10', [], '2026-10-05');
      expect(weeks, hasLength(5));
      expect([for (final day in weeks[0]) day.day], ['2026-09-28', '2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04']);
      expect([for (final day in weeks[0]) day.inMonth], [false, false, false, true, true, true, true]);
      expect(weeks.last.last.day, '2026-11-01');
      expect([for (final week in weeks) for (final day in week) if (day.today) day.day], ['2026-10-05']);
    });

    test('is four weeks for a February that starts on a Monday', () {
      expect(monthWeeks('2027-02', [], '2027-02-01'), hasLength(4));
    });

    test('puts each row on its day, and none that has no day', () {
      final weeks = monthWeeks('2026-10', [row('Milk', '2026-10-04'), row('Bread', '2026-10-04'), row('Undated', null), row('Late', '2026-11-01')], '2026-10-05');
      List<String> on(String day) => [for (final week in weeks) for (final each in week) if (each.day == day) ...each.rows.map((row) => row.name)];
      expect(on('2026-10-04'), ['Milk', 'Bread']);
      expect(on('2026-11-01'), ['Late']);
      expect(inMonth([row('Milk', '2026-10-04'), row('Late', '2026-11-01'), row('Undated', null)], '2026-10'), 1);
    });
  });
}
