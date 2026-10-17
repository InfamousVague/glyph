// An iCalendar file read and laid out (lib/calendar/ics.dart, docs/CALENDAR.md): the lines unfolded and their escapes
// undone, all-day and timed events, a time in UTC, on a TZID the file describes and on this device's clock, every
// shape of rule the app lays out, EXDATE, COUNT and UNTIL, a changed instance, and the window.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/calendar/ics.dart';

/// A calendar of one VEVENT of [lines] (two, where they close one and open another), with New York's VTIMEZONE as
/// Google writes it.
String ics(List<String> lines, {String name = 'Work'}) => [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Google Inc//Google Calendar 70.9054//EN',
      'X-WR-CALNAME:$name',
      'BEGIN:VTIMEZONE',
      'TZID:America/New_York',
      'BEGIN:DAYLIGHT',
      'TZOFFSETFROM:-0500',
      'TZOFFSETTO:-0400',
      'TZNAME:EDT',
      'DTSTART:19700308T020000',
      'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU',
      'END:DAYLIGHT',
      'BEGIN:STANDARD',
      'TZOFFSETFROM:-0400',
      'TZOFFSETTO:-0500',
      'TZNAME:EST',
      'DTSTART:19701101T020000',
      'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU',
      'END:STANDARD',
      'END:VTIMEZONE',
      'BEGIN:VEVENT',
      ...lines,
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');

final DateTime from = DateTime(2026, 8, 18);
final DateTime to = DateTime(2027, 11, 22);

List<IcsEvent> read(List<String> lines) => parseIcs(ics(lines), from: from, to: to).events;

List<DateTime> starts(List<IcsEvent> events) => [for (final event in events) event.start];

void main() {
  group('the lines', () {
    test('a folded line is put back together, less the one space or tab that folded it', () {
      expect(unfoldIcs('DESCRIPTION:A long de\r\n scription that\r\n\t goes on\r\nSUMMARY:x\r\n'), ['DESCRIPTION:A long description that goes on', 'SUMMARY:x']);
    });

    test('a text value has its escapes undone', () {
      expect(icsText(r'Lunch\, then a walk\; maybe\nback\Nhome \\ done'), 'Lunch, then a walk; maybe\nback\nhome \\ done');
    });

    test('a property keeps its parameters, a quoted one holding a colon and a semicolon', () {
      final property = IcsProperty.parse('ATTENDEE;CN="Doe; Jane: PM";ROLE=REQ-PARTICIPANT:mailto:jane@example.com')!;
      expect(property.name, 'ATTENDEE');
      expect(property.params, {'CN': 'Doe; Jane: PM', 'ROLE': 'REQ-PARTICIPANT'});
      expect(property.value, 'mailto:jane@example.com');
      expect(IcsProperty.parse('no colon here'), isNull);
    });

    test('a folded, escaped summary reads as its words, and the calendar its name', () {
      final calendar = parseIcs(
        ics(['UID:a', 'DTSTART;VALUE=DATE:20261017', 'SUMMARY:Dinner with Sam\\, Alex \r\n and Jo\\; bring wine'], name: 'Home\\, family'),
        from: from,
        to: to,
      );
      expect(calendar.name, 'Home, family');
      expect(calendar.events.single.title, 'Dinner with Sam, Alex and Jo; bring wine');
    });
  });

  group('times', () {
    test('an all-day event is its days on this device, the end the day after', () {
      final event = read(['UID:a', 'DTSTART;VALUE=DATE:20261017', 'DTEND;VALUE=DATE:20261019', 'SUMMARY:Away', 'LOCATION:Lisbon']).single;
      expect(event.allDay, isTrue);
      expect(event.start, DateTime(2026, 10, 17));
      expect(event.end, DateTime(2026, 10, 19));
      expect(event.location, 'Lisbon');
    });

    test('a date with no end is one day', () {
      final event = read(['UID:a', 'DTSTART;VALUE=DATE:20261017', 'SUMMARY:Holiday']).single;
      expect(event.end, DateTime(2026, 10, 18));
    });

    test('a time in UTC is that moment', () {
      final event = read(['UID:a', 'DTSTART:20261017T090000Z', 'DTEND:20261017T103000Z', 'SUMMARY:Standup']).single;
      expect(event.allDay, isFalse);
      expect(event.start, DateTime.utc(2026, 10, 17, 9));
      expect(event.end, DateTime.utc(2026, 10, 17, 10, 30));
    });

    test('a TZID is read through the file’s VTIMEZONE, either side of the clocks changing', () {
      final summer = read(['UID:a', 'DTSTART;TZID=America/New_York:20261017T090000', 'DTEND;TZID=America/New_York:20261017T100000', 'SUMMARY:x']).single;
      expect(summer.start, DateTime.utc(2026, 10, 17, 13));
      expect(summer.end, DateTime.utc(2026, 10, 17, 14));
      final winter = read(['UID:b', 'DTSTART;TZID=America/New_York:20261210T090000', 'SUMMARY:x']).single;
      expect(winter.start, DateTime.utc(2026, 12, 10, 14));
    });

    test('a southern VTIMEZONE, whose summer is the turn of the year', () {
      const sydney = [
        'BEGIN:VCALENDAR',
        'BEGIN:VTIMEZONE',
        'TZID:Australia/Sydney',
        'BEGIN:STANDARD',
        'TZOFFSETFROM:+1100',
        'TZOFFSETTO:+1000',
        'DTSTART:19700405T030000',
        'RRULE:FREQ=YEARLY;BYMONTH=4;BYDAY=1SU',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'TZOFFSETFROM:+1000',
        'TZOFFSETTO:+1100',
        'DTSTART:19701004T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=1SU',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
        'BEGIN:VEVENT',
        'UID:a',
        'DTSTART;TZID=Australia/Sydney:20270115T090000',
        'SUMMARY:Summer',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:b',
        'DTSTART;TZID=Australia/Sydney:20270715T090000',
        'SUMMARY:Winter',
        'END:VEVENT',
        'END:VCALENDAR',
      ];
      final events = parseIcs(sydney.join('\n'), from: from, to: to).events;
      expect(starts(events), [DateTime.utc(2027, 1, 14, 22), DateTime.utc(2027, 7, 14, 23)]);
    });

    test('a TZID the file does not describe is UTC by its name, else this device’s clock', () {
      expect(read(['UID:a', 'DTSTART;TZID=UTC:20261017T090000', 'SUMMARY:x']).single.start, DateTime.utc(2026, 10, 17, 9));
      expect(read(['UID:b', 'DTSTART;TZID=Etc/GMT:20261017T090000', 'SUMMARY:x']).single.start, DateTime.utc(2026, 10, 17, 9));
      expect(read(['UID:c', 'DTSTART;TZID=Mars/Olympus:20261017T090000', 'SUMMARY:x']).single.start, DateTime(2026, 10, 17, 9).toUtc());
    });

    test('a floating time is on this device’s clock', () {
      final event = read(['UID:a', 'DTSTART:20261017T090000', 'DURATION:PT45M', 'SUMMARY:x']).single;
      expect(event.start, DateTime(2026, 10, 17, 9).toUtc());
      expect(event.end, DateTime(2026, 10, 17, 9, 45).toUtc());
    });

    test('a DURATION is read in weeks, days, hours, minutes and seconds', () {
      expect(icsDuration('PT1H30M'), const Duration(hours: 1, minutes: 30));
      expect(icsDuration('P1D'), const Duration(days: 1));
      expect(icsDuration('P2W'), const Duration(days: 14));
      expect(icsDuration('-PT15M'), const Duration(minutes: -15));
      expect(icsDuration('P1DT2H3M4S'), const Duration(days: 1, hours: 2, minutes: 3, seconds: 4));
      expect(icsDuration('PT'), isNull);
      expect(icsDuration('soon'), isNull);
    });

    test('an event without a summary is untitled, and a cancelled one is not shown', () {
      expect(read(['UID:a', 'DTSTART;VALUE=DATE:20261017']).single.title, 'Untitled event');
      expect(read(['UID:a', 'DTSTART;VALUE=DATE:20261017', 'SUMMARY:Off', 'STATUS:CANCELLED']), isEmpty);
    });
  });

  group('rules', () {
    test('DAILY with COUNT: the first is DTSTART, and COUNT counts it', () {
      final events = read(['UID:a', 'DTSTART:20261017T090000Z', 'RRULE:FREQ=DAILY;COUNT=3', 'SUMMARY:x']);
      expect(starts(events), [DateTime.utc(2026, 10, 17, 9), DateTime.utc(2026, 10, 18, 9), DateTime.utc(2026, 10, 19, 9)]);
      expect(events.map((event) => event.uid).toSet(), hasLength(3));
    });

    test('DAILY with INTERVAL and UNTIL in UTC', () {
      final events = read(['UID:a', 'DTSTART:20261017T090000Z', 'RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261023T090000Z', 'SUMMARY:x']);
      expect(starts(events), [DateTime.utc(2026, 10, 17, 9), DateTime.utc(2026, 10, 19, 9), DateTime.utc(2026, 10, 21, 9), DateTime.utc(2026, 10, 23, 9)]);
    });

    test('WEEKLY on its weekdays, UNTIL a date', () {
      // Monday 19 October 2026.
      final events = read(['UID:a', 'DTSTART:20261019T080000Z', 'RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261028', 'SUMMARY:Gym']);
      expect([for (final at in starts(events)) at.day], [19, 21, 23, 26, 28]);
    });

    test('WEEKLY every other week, on DTSTART’s weekday where BYDAY says none', () {
      final events = read(['UID:a', 'DTSTART;VALUE=DATE:20261017', 'RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=3', 'SUMMARY:Bins']);
      expect(starts(events), [DateTime(2026, 10, 17), DateTime(2026, 10, 31), DateTime(2026, 11, 14)]);
    });

    test('WEEKLY on a TZID keeps its hour on that clock across the change', () {
      // Saturday 24 October 2026; New York's clocks go back on Sunday 1 November.
      final events = read(['UID:a', 'DTSTART;TZID=America/New_York:20261024T090000', 'RRULE:FREQ=WEEKLY;COUNT=3', 'SUMMARY:x']);
      expect(starts(events), [DateTime.utc(2026, 10, 24, 13), DateTime.utc(2026, 10, 31, 13), DateTime.utc(2026, 11, 7, 14)]);
    });

    test('MONTHLY on the second Tuesday, and on the last Friday', () {
      final second = read(['UID:a', 'DTSTART:20261013T170000Z', 'RRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=3', 'SUMMARY:x']);
      expect(starts(second), [DateTime.utc(2026, 10, 13, 17), DateTime.utc(2026, 11, 10, 17), DateTime.utc(2026, 12, 8, 17)]);
      final last = read(['UID:b', 'DTSTART:20261030T170000Z', 'RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=3', 'SUMMARY:x']);
      expect(starts(last), [DateTime.utc(2026, 10, 30, 17), DateTime.utc(2026, 11, 27, 17), DateTime.utc(2026, 12, 25, 17)]);
    });

    test('MONTHLY on the 31st passes over the months without one', () {
      final events = read(['UID:a', 'DTSTART;VALUE=DATE:20261031', 'RRULE:FREQ=MONTHLY;COUNT=3', 'SUMMARY:Rent']);
      expect(starts(events), [DateTime(2026, 10, 31), DateTime(2026, 12, 31), DateTime(2027, 1, 31)]);
    });

    test('MONTHLY by BYMONTHDAY, from the end where it is below 0', () {
      final events = read(['UID:a', 'DTSTART;VALUE=DATE:20261031', 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3', 'SUMMARY:Invoice']);
      expect(starts(events), [DateTime(2026, 10, 31), DateTime(2026, 11, 30), DateTime(2026, 12, 31)]);
    });

    test('YEARLY: a birthday, and Thanksgiving by BYMONTH and BYDAY', () {
      final birthday = read(['UID:a', 'DTSTART;VALUE=DATE:19900120', 'RRULE:FREQ=YEARLY', 'SUMMARY:Sam’s birthday']);
      expect(starts(birthday), [DateTime(2027, 1, 20)]);
      final thanks = read(['UID:b', 'DTSTART;VALUE=DATE:20201126', 'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=4TH', 'SUMMARY:Thanksgiving']);
      // The next, 25 November 2027, is past the window's end.
      expect(starts(thanks), [DateTime(2026, 11, 26)]);
    });

    test('EXDATE takes an instance out, as UTC, on a TZID and as a date', () {
      final utc = read(['UID:a', 'DTSTART:20261017T090000Z', 'RRULE:FREQ=DAILY;COUNT=4', 'EXDATE:20261018T090000Z', 'SUMMARY:x']);
      expect([for (final at in starts(utc)) at.day], [17, 19, 20]);
      final zoned = read([
        'UID:b',
        'DTSTART;TZID=America/New_York:20261017T090000',
        'RRULE:FREQ=DAILY;COUNT=4',
        'EXDATE;TZID=America/New_York:20261019T090000,20261020T090000',
        'SUMMARY:x',
      ]);
      expect(starts(zoned), [DateTime.utc(2026, 10, 17, 13), DateTime.utc(2026, 10, 18, 13)]);
      final dates = read(['UID:c', 'DTSTART;VALUE=DATE:20261017', 'RRULE:FREQ=DAILY;COUNT=3', 'EXDATE;VALUE=DATE:20261018', 'SUMMARY:x']);
      expect(starts(dates), [DateTime(2026, 10, 17), DateTime(2026, 10, 19)]);
    });

    test('a changed instance takes the place of the one it names', () {
      final events = read([
        'UID:standup',
        'DTSTART:20261019T090000Z',
        'DTEND:20261019T091500Z',
        'RRULE:FREQ=DAILY;COUNT=3',
        'SUMMARY:Standup',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:standup',
        'RECURRENCE-ID:20261020T090000Z',
        'DTSTART:20261020T110000Z',
        'DTEND:20261020T111500Z',
        'SUMMARY:Standup (late)',
      ]);
      expect([for (final event in events) '${event.start.day} ${event.start.hour} ${event.title}'], ['19 9 Standup', '20 11 Standup (late)', '21 9 Standup']);
    });

    test('RDATE adds an instance', () {
      final events = read(['UID:a', 'DTSTART:20261017T090000Z', 'RRULE:FREQ=WEEKLY;COUNT=2', 'RDATE:20261020T090000Z', 'SUMMARY:x']);
      expect([for (final at in starts(events)) at.day], [17, 20, 24]);
    });

    test('a rule is read whatever its order and case, and an unknown frequency is no rule', () {
      final rule = RecurRule.parse('count=2;byday=TU,TH;freq=weekly;wkst=SU')!;
      expect(rule.freq, Freq.weekly);
      expect(rule.count, 2);
      expect(rule.byDay, [(weekday: DateTime.tuesday, nth: 0), (weekday: DateTime.thursday, nth: 0)]);
      expect(rule.weekStart, DateTime.sunday);
      expect(RecurRule.parse('FREQ=HOURLY'), isNull);
    });
  });

  group('the window', () {
    test('only what overlaps it, however long ago the rule began', () {
      final events = read(['UID:a', 'DTSTART:20150101T090000Z', 'RRULE:FREQ=DAILY', 'SUMMARY:Pills']);
      expect(events.first.start, DateTime.utc(2026, 8, 18, 9));
      expect(events.last.start.isBefore(to), isTrue);
      expect(events.length, greaterThan(400));
    });

    test('an event before it or after it is not there, one across its start is', () {
      expect(read(['UID:a', 'DTSTART;VALUE=DATE:20250101', 'SUMMARY:x']), isEmpty);
      expect(read(['UID:a', 'DTSTART;VALUE=DATE:20280101', 'SUMMARY:x']), isEmpty);
      expect(read(['UID:a', 'DTSTART;VALUE=DATE:20260810', 'DTEND;VALUE=DATE:20260820', 'SUMMARY:Trip']), hasLength(1));
    });

    test('is 60 days back and 400 ahead', () {
      final window = calendarWindow(DateTime(2026, 10, 17, 15, 30));
      expect(window.from, DateTime(2026, 8, 18));
      expect(window.to, DateTime(2027, 11, 22));
    });

    test('a file with nothing readable in it has no events', () {
      expect(parseIcs('not a calendar', from: from, to: to).events, isEmpty);
      expect(parseIcs(ics(['UID:a', 'SUMMARY:no start']), from: from, to: to).events, isEmpty);
    });
  });
}
