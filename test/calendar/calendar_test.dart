// The calendars read and kept for the life of the app (lib/calendar/calendar.dart, docs/CALENDAR.md): an iCal address
// checked, added, read and named, Local only obeyed, an address taken off and forgotten; Google connected through the
// claim, its primary ticked and read, an iCal address of a ticked calendar not read twice, the to-dos put on it when
// switched on, and Google forgotten. Against calendars in memory, on a clock of the test's own.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/calendar/calendar.dart';
import 'package:ghost_md/calendar/setup.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/core/stored.dart';

import 'fake_google.dart';

const String work = 'https://cal.test/work.ics';

String icsOf(String name, List<String> lines) => ['BEGIN:VCALENDAR', 'X-WR-CALNAME:$name', 'BEGIN:VEVENT', ...lines, 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');

late FakeGoogle google;
late Map<String, String> calendars;
late List<String> fetched;
late PreferencesStore prefs;
late MemoryStored kept;
late List<String> opened;
int now = DateTime(2026, 10, 17, 12).millisecondsSinceEpoch;

Future<FetchResponse> fetch(FetchRequest request) async {
  if (request.url.host == 'cal.test') {
    fetched.add(request.url.toString());
    final text = calendars[request.url.toString()];
    return text == null ? FetchResponse(404) : FetchResponse(200, bytes: utf8.encode(text));
  }
  return google.fetch(request);
}

CalendarService service({String? base = fakeBase}) => CalendarService(fetch: fetch, prefs: prefs, kept: () => kept, googleBase: () => base, clock: () => now, open: (url) async => opened.add(url));

void main() {
  setUp(() {
    google = FakeGoogle();
    calendars = {work: icsOf('Work', ['UID:standup', 'DTSTART:20261019T090000Z', 'DTEND:20261019T091500Z', 'RRULE:FREQ=DAILY;COUNT=2', 'SUMMARY:Standup'])};
    fetched = [];
    prefs = PreferencesStore()..startWithoutStorage();
    kept = MemoryStored();
    opened = [];
  });

  group('an iCal address', () {
    test('is checked: a secure web address, webcal read as https', () {
      expect(calendarAddress('').problem, 'Paste the calendar’s iCal address.');
      expect(calendarAddress('http://cal.test/a.ics').problem, contains('secure'));
      expect(calendarAddress('ftp://cal.test/a.ics').problem, isNotNull);
      expect(calendarAddress('not an address').problem, isNotNull);
      expect(calendarAddress('webcal://p01-calendars.icloud.com/published/2/abc').url, 'https://p01-calendars.icloud.com/published/2/abc');
      expect(calendarAddress('  https://cal.test/a.ics ').url, 'https://cal.test/a.ics');
    });

    test('added, is read at once, its events kept and its calendar named', () async {
      final calendar = service();
      expect(await calendar.addAddress(work), isNull);
      expect(fetched, [work]);
      expect([for (final e in calendar.events.value) '${e.title} ${e.calendar} ${e.start.day}'], ['Standup Work 19', 'Standup Work 20']);
      final setup = calendarSetupOf(prefs.value);
      expect(setup.addresses.single.url, work);
      expect(setup.addresses.single.name, 'Work');
      expect(calendar.queryEvents().first.calendar, 'Work');
      expect(calendar.on('2026-10-20').single.title, 'Standup');
      // Kept with the account's settings, which travel.
      expect(prefs.value.toJson()['calendars'], isA<Map<String, Object?>>());
    });

    test('added twice is said, and a refusal is the line under it', () async {
      final calendar = service();
      await calendar.addAddress(work);
      expect(await calendar.addAddress(work), 'That calendar is here already.');
      await calendar.addAddress('https://cal.test/missing.ics');
      final missing = calendarSetupOf(prefs.value).addresses.last;
      expect(calendar.statusOf('ical:${missing.id}')!.problem, 'The calendar isn’t at that address any more.');
      expect(calendar.lastRead.problem, 'The calendar isn’t at that address any more.');
    });

    test('is read again only when it is due, unless asked', () async {
      final calendar = service();
      await calendar.addAddress(work);
      await calendar.syncIcal();
      expect(fetched, hasLength(1));
      now += const Duration(minutes: 31).inMilliseconds;
      await calendar.syncIcal();
      expect(fetched, hasLength(2));
      await calendar.syncIcal(force: true);
      expect(fetched, hasLength(3));
    });

    test('is never fetched with Local only on', () async {
      prefs.update((p) => p.copyWith(localOnly: true));
      final calendar = service();
      expect(await calendar.addAddress(work), isNull);
      await calendar.syncNow();
      expect(fetched, isEmpty);
      expect(google.calls, isEmpty);
    });

    test('taken off, is forgotten with what it gave', () async {
      final calendar = service();
      await calendar.addAddress(work);
      calendar.removeAddress(calendarSetupOf(prefs.value).addresses.single.id);
      expect(calendar.events.value, isEmpty);
      expect(calendarSetupOf(prefs.value).isEmpty, isTrue);
      expect(prefs.value.toJson().containsKey('calendars'), isFalse);
    });
  });

  group('Google', () {
    Future<CalendarService> connected() async {
      final calendar = service();
      await calendar.connectGoogle();
      await calendar.collectGoogle();
      await calendar.collectGoogle();
      await calendar.syncGoogle();
      return calendar;
    }

    test('is not offered in a build with no service, nor where start answers 503', () async {
      expect(await service(base: null).checkOffered(), isFalse);
      google.configured = false;
      expect(await service().checkOffered(), isFalse);
      google.configured = true;
      expect(await service().checkOffered(), isTrue);
    });

    test('connects: the browser at start, the claim waited for, the primary ticked and read', () async {
      google.events['me@example.com']!['a'] = {'id': 'a', 'summary': 'Dentist', 'start': {'dateTime': '2026-10-19T14:00:00Z'}, 'end': {'dateTime': '2026-10-19T15:00:00Z'}};
      final calendar = service();
      await calendar.connectGoogle();
      expect(opened.single, startsWith('$fakeBase/start?state='));
      expect(opened.single, contains('&challenge='));
      expect(calendar.connecting, isTrue);
      await calendar.collectGoogle();
      expect(calendarSetupOf(prefs.value).google, isNull);
      await calendar.collectGoogle();
      final setup = calendarSetupOf(prefs.value).google!;
      expect(setup.refreshToken, 'refresh-1');
      expect(setup.ticked, ['me@example.com']);
      expect(setup.todos, isFalse);
      expect(calendar.connecting, isFalse);
      await calendar.syncGoogle();
      expect([for (final e in calendar.events.value) '${e.title} ${e.calendar}'], ['Dentist Me']);
      expect([for (final c in calendar.googleCalendars) c.name], ['Me', 'Team']);
      calendar.dispose();
    });

    test('a ticked calendar’s iCal address is not read twice', () async {
      calendars['https://calendar.google.com/calendar/ical/me%40example.com/private-x/basic.ics'] = icsOf('Me', ['UID:x', 'DTSTART;VALUE=DATE:20261019', 'SUMMARY:From iCal']);
      final calendar = await connected();
      prefs.update((p) => withCalendarSetup(p, calendarSetupOf(p).copyWith(addresses: [const CalendarAddress(id: 'g', url: 'https://calendar.google.com/calendar/ical/me%40example.com/private-x/basic.ics')])));
      await calendar.syncIcal(force: true);
      expect(fetched, isEmpty);
      calendar.dispose();
    });

    test('to-dos go on the calendar once switched on, and not before', () async {
      final calendar = await connected();
      calendar.start(notes: () => const [QueryNote(id: 'plans', body: '- [ ] Buy milk 📅 2026-10-20\n', createdAt: 0, updatedAt: 0)]);
      await calendar.syncGoogle();
      expect(google.events['me@example.com'], isEmpty);
      calendar.setTodos(true);
      await calendar.syncGoogle();
      final made = google.events['me@example.com']!.values.single;
      expect(made['summary'], 'Buy milk');
      expect(made['description'], 'ghostmd://note/plans');
      // The app's own to-do is not read back as an event.
      expect(calendar.events.value, isEmpty);
      calendar.dispose();
    });

    test('a ticked calendar is read, and one unticked forgotten', () async {
      google.events['team@group.calendar.google.com']!['t'] = {'id': 't', 'summary': 'Offsite', 'start': {'date': '2026-10-22'}, 'end': {'date': '2026-10-23'}};
      final calendar = await connected();
      calendar.tick('team@group.calendar.google.com', true);
      await calendar.syncGoogle();
      expect([for (final e in calendar.events.value) e.title], ['Offsite']);
      calendar.tick('team@group.calendar.google.com', false);
      expect(calendar.events.value, isEmpty);
      calendar.dispose();
    });

    test('disconnected, is forgotten: the sign-in, the calendars and their events', () async {
      google.events['me@example.com']!['a'] = {'id': 'a', 'summary': 'Dentist', 'start': {'date': '2026-10-19'}, 'end': {'date': '2026-10-20'}};
      final calendar = await connected();
      expect(calendar.events.value, hasLength(1));
      calendar.disconnectGoogle();
      expect(calendarSetupOf(prefs.value).google, isNull);
      expect(calendar.events.value, isEmpty);
      expect(calendar.googleCalendars, isEmpty);
      expect(kept.allKeys.where((key) => key.startsWith('glyph-google-token')), isEmpty);
      calendar.dispose();
    });

    test('a sign-in left too long is given up', () async {
      final calendar = service();
      await calendar.connectGoogle();
      now += const Duration(minutes: 11).inMilliseconds;
      await calendar.collectGoogle();
      expect(calendar.connecting, isFalse);
      expect(calendar.problem, contains('ran out of time'));
      calendar.dispose();
    });
  });
}
