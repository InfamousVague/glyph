// Today's events on the home page (lib/home/home_events.dart, home_screen.dart; docs/CALENDAR.md): the calendars'
// events on today's date at the head of the page, under Today, each its hours or All day, its title and where it is;
// nothing at all, and no room taken, on a day with none; and drawn again as the calendars change.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/calendar/event.dart';
import 'package:ghost_md/core/note.dart';
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

  group('a meeting with its notes here opens them (Matt, 2026-10-19: the meetings at the top could not be opened)', () {
    final start = day.add(const Duration(hours: 13, minutes: 20)), end = day.add(const Duration(hours: 13, minutes: 40));
    final meeting = event('tidepool', 'Tidepool Series A planning', start, end);
    Note note(String id, String body, DateTime at, {int? recordingMs}) =>
        Note(id: id, body: body, createdAt: at.millisecondsSinceEpoch, updatedAt: at.millisecondsSinceEpoch, recordingMs: recordingMs);

    test('the note named as the meeting, made while it ran, is its notes; the recorded one first', () {
      final filed = note('filed', '# Tidepool Series A planning\n\nGhost was in this meeting.\n', start.add(const Duration(minutes: 1)), recordingMs: 869000);
      final typed = note('typed', '# Tidepool series A planning\n\n- Raise 18M\n', start.add(const Duration(minutes: 5)));
      final invite = note('invite', '# Invitation: Tidepool Series A planning @ Mon\n', start.subtract(const Duration(minutes: 20)));
      final lastWeek = note('old', '# Tidepool Series A planning\n', start.subtract(const Duration(days: 7)));
      expect(meetingNoteOf(meeting, [invite, typed, filed, lastWeek])?.id, 'filed');
      expect(meetingNoteOf(meeting, [invite, typed, lastWeek])?.id, 'typed', reason: 'no recording: the note named as it is');
      expect(meetingNoteOf(meeting, [invite, lastWeek]), isNull, reason: 'an invitation is not its notes, nor last week\'s');
      expect(meetingNoteOf(event('day', 'Tidepool Series A planning', day, day.add(const Duration(days: 1)), allDay: true), [filed]), isNull, reason: 'an all-day event is no meeting');
    });

    testWidgets('its line wears the notes\' mark and opens them; a meeting with none opens nothing', (tester) async {
      final opened = <String>[];
      final filed = note('filed', '# Tidepool Series A planning\n\nGhost was in this meeting.\n', start.add(const Duration(minutes: 1)), recordingMs: 869000);
      await pumpApp(tester, home: HomeTodayEvents(events: [meeting, event('standup', 'Standup', day.add(const Duration(hours: 9, minutes: 30)), day.add(const Duration(hours: 9, minutes: 45)))], notes: [filed], onOpen: opened.add));
      await tester.pump();
      expect(find.byKey(const ValueKey('home-event-notes-filed')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-event-notes-filed')));
      await tester.pump();
      expect(opened, ['filed']);
      await tester.tap(find.text('Standup'), warnIfMissed: false);
      await tester.pump();
      expect(opened, ['filed'], reason: 'an event with no notes here opens nothing');
      await away(tester);
    });
  });
}
