// Today's events on the home page (lib/home/home_events.dart, home_screen.dart; docs/CALENDAR.md): the calendars'
// events on today's date at the head of the page, under Today, each its hours or All day, its title and where it is;
// nothing at all, and no room taken, on a day with none; and drawn again as the calendars change.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/calendar/event.dart';
import 'package:ghost_md/core/sample_library.dart' show seedNow;
import 'package:ghost_md/home/home_events.dart';
import 'package:ghost_md/home/home_organizations.dart';

import '../support/render.dart';
import 'support.dart';

/// The seeded library's day: Monday 28 September 2026, ten in the morning.
final DateTime today = DateTime.fromMillisecondsSinceEpoch(seedNow);

CalendarEvent event(String id, String title, DateTime start, DateTime end, {bool allDay = false, String? location}) =>
    CalendarEvent(id: id, source: 'ical:work', calendar: 'Work', title: title, start: start, end: end, allDay: allDay, location: location);

/// Takes the page down, and puts back the binding's switch for shadows that [pumpApp] turned on.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadAppFonts);

  final day = DateTime(today.year, today.month, today.day);
  final events = ValueNotifier<List<CalendarEvent>>([
    event('standup', 'Standup', day.add(const Duration(hours: 9, minutes: 30)), day.add(const Duration(hours: 9, minutes: 45)), location: 'Room 4'),
    event('holiday', 'Team day', day, day.add(const Duration(days: 1)), allDay: true),
    event('tomorrow', 'Dentist', day.add(const Duration(days: 1, hours: 14)), day.add(const Duration(days: 1, hours: 15))),
    event('yesterday', 'Gym', day.subtract(const Duration(hours: 14)), day.subtract(const Duration(hours: 13))),
  ]);

  List<String> headings(WidgetTester tester) => [
        for (final heading in tester.widgetList<HomeHeading>(find.byType(HomeHeading))) heading.count == null ? heading.words : '${heading.words} ${heading.count}',
      ];

  testWidgets('today’s events head the page under Today, a day’s first, its hours after', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, events: events));
    await settle(tester);
    expect(find.byType(HomeTodayEvents), findsOneWidget);
    expect(headings(tester).first, 'Today 2');
    expect(find.bySemanticsLabel('All day, Team day'), findsOneWidget);
    expect(find.bySemanticsLabel('09:30–09:45, Standup, Room 4'), findsOneWidget);
    expect(tester.getTopLeft(find.bySemanticsLabel('All day, Team day')).dy, lessThan(tester.getTopLeft(find.bySemanticsLabel('09:30–09:45, Standup, Room 4')).dy));
    // Above the notes.
    expect(tester.getTopLeft(find.text('Team day')).dy, lessThan(tester.getTopLeft(find.text('Pinned')).dy));
    expect(find.text('Dentist'), findsNothing);
    expect(find.text('Gym'), findsNothing);
    await away(tester);
  });

  testWidgets('a day with none draws nothing and takes no room, and the page follows the calendars', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
    await settle(tester);
    final bare = tester.getTopLeft(find.text('Pinned')).dy;
    await away(tester);

    final none = ValueNotifier<List<CalendarEvent>>([events.value[2]]);
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, events: none));
    await settle(tester);
    expect(headings(tester), isNot(contains('Today 1')));
    expect(tester.getTopLeft(find.text('Pinned')).dy, bare);

    none.value = [...none.value, events.value[1]];
    await settle(tester);
    expect(headings(tester).first, 'Today 1');
    expect(tester.getTopLeft(find.text('Pinned')).dy, greaterThan(bare));
    await away(tester);
  });

  test('an event’s hours, and All day', () {
    expect(eventHours(events.value[0]), '09:30–09:45');
    expect(eventHours(events.value[1]), 'All day');
    expect(eventsOn(events.value, '2026-09-28').map((e) => e.title), ['Team day', 'Standup']);
  });
}
