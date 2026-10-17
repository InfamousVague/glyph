// The calendars' events in a drawn query (lib/editor/queries/queries.dart, query_view.dart; docs/CALENDAR.md): a
// `from: events` query drawn as what it finds, an event opening nothing and picking nothing, and a calendar of to-dos
// with each day's events beside its to-dos, quieter: a ring on the day, a line above the day's to-dos, its hours
// first.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/queries/queries.dart';

import '../../support/render.dart';
import 'support.dart';

const String today = '2026-10-08';

const QueryNote shop = QueryNote(id: 'shop', body: '# Groceries\n\n- [ ] Bread 📅 $today\n', createdAt: 0, updatedAt: 0);

final List<QueryEvent> events = [
  QueryEvent(id: 'dentist', title: 'Dentist', start: DateTime(2026, 10, 8, 10), end: DateTime(2026, 10, 8, 11), allDay: false, location: 'High Street', calendar: 'Home'),
  QueryEvent(id: 'trip', title: 'Lisbon', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13), allDay: true, calendar: 'Home'),
];

late Asked asked;

QueryOptions options() => QueryOptions(
      notes: () => const [shop],
      noteId: 'here',
      open: (noteId, line) => asked.opened.add((noteId, line)),
      write: (noteId, change) => asked.written.add((noteId, change)),
      events: () => events,
    );

String fence(String lines) => '# This week\n\n```query\n$lines\n```\n';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => asked = Asked());

  testWidgets('`from: events` is drawn as the events, and a tap on one opens nothing', (tester) async {
    await pumpQueries(tester, fence('from: events'), options: options(), today: today);
    final words = wordsOf(tester, drawn);
    expect(words, contains('EVENTS'));
    expect(words, contains('Dentist'));
    expect(words, contains('Lisbon'));
    expect(words, contains('10:00–11:00'));
    await tester.tap(find.text('Dentist'));
    await tester.pump();
    expect(asked.opened, isEmpty);
    expect(asked.written, isEmpty);
  });

  testWidgets('a query of events with none to read says nothing matches', (tester) async {
    await pumpQueries(
      tester,
      fence('from: events'),
      options: QueryOptions(notes: () => const [shop], noteId: 'here', open: (_, _) {}, write: (_, _) {}),
      today: today,
    );
    expect(wordsOf(tester, drawn), contains('Nothing matches this query yet.'));
  });

  testWidgets('a calendar of to-dos shows the day’s events above its to-dos, quieter', (tester) async {
    await pumpQueries(tester, fence('from: tasks\nshow: calendar'), options: options(), today: today);
    // Today has a to-do's dot and an event's ring.
    final todayCell = find.bySemanticsLabel(RegExp(r'1 thing, 1 event$'));
    expect(todayCell, findsOneWidget);
    expect(parts('ring', drawn).evaluate().length, 2);
    // The day listed under the month is today: the event first, its hours before it, then the to-do.
    final list = wordsOf(tester, parts('dayList', drawn));
    expect(list, contains('Dentist'));
    expect(list, contains('Bread'));
    expect(list.indexOf('Dentist'), lessThan(list.indexOf('Bread')));
    expect(wordsOf(tester, parts('event', drawn)), contains('10:00–11:00'));
  });

  testWidgets('a day with only an event lists it, and does not say it has nothing', (tester) async {
    await pumpQueries(tester, fence('from: tasks\nshow: calendar'), options: options(), today: today);
    await tester.tap(find.bySemanticsLabel(RegExp(r'1 event$')).last);
    await tester.pump();
    final list = wordsOf(tester, parts('dayList', drawn));
    expect(list, contains('Lisbon'));
    expect(list, contains('All day'));
    expect(list, isNot(contains('Nothing on this day.')));
  });

  testWidgets('a calendar of tickets is not handed the events', (tester) async {
    await pumpQueries(tester, fence('from: tickets\nshow: calendar'), options: options(), today: today);
    expect(parts('ring', drawn), findsNothing);
  });
}
