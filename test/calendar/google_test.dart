// Google Calendar through glyph-api's sign-in (lib/calendar/google.dart, docs/CALENDAR.md), against Google in memory
// (fake_google.dart): whether Connect is offered, the claim, the refresh when a token runs out, the calendars and
// their events, and the to-dos put on a calendar by ids made from the to-do, with the app's mark, never touching an
// event the app did not make.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart' show FetchResponse;
import 'package:ghost_md/calendar/google.dart';
import 'package:ghost_md/core/query/query.dart';

import 'fake_google.dart';

late FakeGoogle google;
int now = DateTime.utc(2026, 10, 17, 12).millisecondsSinceEpoch;

GoogleCalendarApi api() => GoogleCalendarApi(base: fakeBase, fetch: google.fetch, clock: () => now);

GoogleSession session({GoogleTokens? tokens}) => GoogleSession(api: api(), refreshToken: 'refresh-1', tokens: tokens ?? GoogleTokens(accessToken: google.access, expiresAt: now + 3600000));

const GoogleCalendarInfo me = GoogleCalendarInfo(id: 'me@example.com', name: 'Me', primary: true, writable: true);

QueryLibrary library(String body, {String id = 'plans'}) => libraryOf([QueryNote(id: id, body: body, createdAt: 0, updatedAt: 0)]);

void main() {
  setUp(() => google = FakeGoogle());

  group('signing in', () {
    test('Connect is offered only where start turns the probe away as a broken link or busy, and the probe starts no sign-in', () async {
      expect(await api().offered(), isTrue);
      expect(google.calls.single, startsWith('GET /api/google/start?state=probe'));
      google.configured = false;
      expect(await api().offered(), isFalse);
      expect(await GoogleCalendarApi(base: fakeBase, fetch: (_) async => throw Exception('offline')).offered(), isFalse);
      // A service from before it had Google: "no such route", which the button once led to.
      expect(await GoogleCalendarApi(base: fakeBase, fetch: (_) async => FetchResponse(404, bytes: utf8.encode('{"error":"no such route"}'))).offered(), isFalse);
      expect(await GoogleCalendarApi(base: fakeBase, fetch: (_) async => FetchResponse(429)).offered(), isTrue);
    });

    test('the browser goes to start with the state and the verifier’s SHA-256', () {
      final url = api().startUrl('the-state', googleChallenge('the-verifier'));
      expect(url.toString(), startsWith('$fakeBase/start?state=the-state&challenge='));
      // base64url of SHA-256("the-verifier"), with no padding.
      expect(googleChallenge('the-verifier'), hasLength(43));
      expect(googleChallenge('the-verifier'), isNot(contains('=')));
    });

    test('a claim waits while the person is on Google’s page, then answers the tokens', () async {
      expect(await api().claim('state', 'verifier'), isA<GooglePending>());
      final signed = await api().claim('state', 'verifier') as GoogleSignedIn;
      expect(signed.tokens.accessToken, 'access-1');
      expect(signed.tokens.refreshToken, 'refresh-1');
      // A minute early.
      expect(signed.tokens.expiresAt, now + 3540 * 1000);
    });

    test('a claim that ran out of time, or a service with no sign-in, says so', () async {
      await expectLater(api().claim('gone', 'verifier'), throwsA(isA<GoogleFailure>().having((f) => f.status, 'status', 404)));
      google.configured = false;
      await expectLater(api().claim('state', 'verifier'), throwsA(isA<GoogleFailure>().having((f) => f.message, 'message', 'Google sign-in is not set up yet.')));
    });
  });

  group('calls', () {
    test('a token that ran out is refreshed before the call, and the fresh one told', () async {
      GoogleTokens? told;
      final calls = GoogleSession(api: api(), refreshToken: 'refresh-1', tokens: GoogleTokens(accessToken: 'old', expiresAt: now - 1), onTokens: (next) => told = next);
      google.access = 'access-1';
      final list = await calls.calendars();
      expect(google.refreshes, 1);
      expect(told?.accessToken, 'access-2');
      expect([for (final c in list) c.name], ['Me', 'Team']);
    });

    test('a 401 is answered by a fresh token, once', () async {
      final calls = GoogleSession(api: api(), refreshToken: 'refresh-1', tokens: GoogleTokens(accessToken: 'revoked', expiresAt: now + 3600000));
      await calls.calendars();
      expect(google.refreshes, 1);
      expect(google.calls.where((call) => call.contains('calendarList')), hasLength(2));
    });

    test('a refresh refused is signed out, in words', () async {
      google.refreshRefused = true;
      final calls = GoogleSession(api: api(), refreshToken: 'refresh-1', tokens: GoogleTokens(accessToken: 'old', expiresAt: now - 1));
      await expectLater(calls.calendars(), throwsA(isA<GoogleFailure>().having((f) => f.status, 'status', 401)));
    });

    test('the calendars, the primary first, and which the app may write to', () async {
      google.calendars.insert(0, google.calendars.removeAt(1));
      final list = await session().calendars();
      expect([for (final c in list) '${c.id} ${c.primary} ${c.writable}'], ['me@example.com true true', 'team@group.calendar.google.com false false']);
    });

    test('events: each instance, all-day and timed, over the window; cancelled ones and the app’s own to-dos left out', () async {
      google.events['me@example.com']!.addAll({
        'a': {'id': 'a', 'summary': 'Standup', 'location': 'Room 4', 'start': {'dateTime': '2026-10-19T09:30:00-04:00'}, 'end': {'dateTime': '2026-10-19T09:45:00-04:00'}},
        'b': {'id': 'b', 'summary': 'Away', 'start': {'date': '2026-10-20'}, 'end': {'date': '2026-10-22'}},
        'c': {'id': 'c', 'status': 'cancelled', 'summary': 'Off'},
        'd': {
          'id': 'd',
          'summary': 'Buy milk',
          'start': {'date': '2026-10-20'},
          'end': {'date': '2026-10-21'},
          'extendedProperties': {'private': {'ghostmd': '1'}},
        },
      });
      final from = DateTime(2026, 8, 18), to = DateTime(2027, 11, 22);
      final read = await session().events(me, from: from, to: to);
      expect([for (final e in read) e.title], ['Standup', 'Away']);
      expect(read[0].start, DateTime.utc(2026, 10, 19, 13, 30));
      expect(read[0].location, 'Room 4');
      expect(read[0].source, 'google:me@example.com');
      expect(read[0].calendar, 'Me');
      expect(read[1].allDay, isTrue);
      expect(read[1].start, DateTime(2026, 10, 20));
      expect(read[1].end, DateTime(2026, 10, 22));
      final asked = google.calls.firstWhere((call) => call.contains('/events'));
      expect(asked, contains('singleEvents=true'));
      expect(asked, contains('timeMin=${Uri.encodeQueryComponent(from.toUtc().toIso8601String())}'));
      expect(asked, contains('timeMax='));
    });
  });

  group('to-dos on the calendar', () {
    test('an id is made from the note and the to-do’s anchor or words: base32hex, the same every time', () {
      final one = todoEventId('plans', words: 'Buy milk');
      expect(one, matches(RegExp(r'^[a-v0-9]{5,1024}$')));
      expect(one, todoEventId('plans', words: '  buy MILK '));
      expect(one, isNot(todoEventId('other', words: 'Buy milk')));
      expect(todoEventId('plans', anchor: 'milk', words: 'Buy milk'), todoEventId('plans', anchor: 'milk', words: 'Buy oat milk'));
    });

    test('only open to-dos with a due date, by their words and day', () {
      final todos = todoEvents(library('# Plans\n\n- [ ] Buy milk 📅 2026-10-20\n- [x] Done thing 📅 2026-10-20\n- [ ] No date\n- [ ] Call Sam ⏫ 📅 2026-10-21 ^call\n'));
      expect([for (final t in todos) '${t.title} ${t.day}'], ['Buy milk 2026-10-20', 'Call Sam 2026-10-21']);
      expect(todos.last.id, todoEventId('plans', anchor: 'call', words: 'Call Sam'));
      expect(todos.first.description, 'ghostmd://note/plans');
    });

    test('a new to-do is inserted all day with the link back and the mark', () async {
      final todos = todoEvents(library('- [ ] Buy milk 📅 2026-10-20\n'));
      final done = await exportTodos(session(), 'me@example.com', todos);
      expect(done, (added: 1, moved: 0, removed: 0));
      final made = google.events['me@example.com']![todos.single.id]!;
      expect(made['summary'], 'Buy milk');
      expect(made['description'], 'ghostmd://note/plans');
      expect(made['start'], {'date': '2026-10-20'});
      expect(made['end'], {'date': '2026-10-21'});
      expect(made['extendedProperties'], {'private': {'ghostmd': '1'}});
    });

    test('a changed date moves it, the same to-do stays put, and a ticked one is deleted', () async {
      final first = todoEvents(library('- [ ] Buy milk 📅 2026-10-20\n- [ ] Call Sam 📅 2026-10-21\n'));
      await exportTodos(session(), 'me@example.com', first);
      google.calls.clear();
      expect(await exportTodos(session(), 'me@example.com', first), (added: 0, moved: 0, removed: 0));
      expect(google.changes, isEmpty);
      final next = todoEvents(library('- [ ] Buy milk 📅 2026-10-23\n- [x] Call Sam 📅 2026-10-21\n'));
      expect(await exportTodos(session(), 'me@example.com', next), (added: 0, moved: 1, removed: 1));
      final milk = google.events['me@example.com']![first[0].id]!;
      expect(milk['start'], {'date': '2026-10-23'});
      expect(google.events['me@example.com']![first[1].id]!['status'], 'cancelled');
      expect(google.changes, ['PATCH /${first[0].id}', 'DELETE /${first[1].id}']);
    });

    test('a to-do back after it was deleted is put back where it was', () async {
      final todos = todoEvents(library('- [ ] Buy milk 📅 2026-10-20\n'));
      await exportTodos(session(), 'me@example.com', todos);
      await exportTodos(session(), 'me@example.com', const []);
      expect(google.events['me@example.com']![todos.single.id]!['status'], 'cancelled');
      expect(await exportTodos(session(), 'me@example.com', todos), (added: 1, moved: 0, removed: 0));
      expect(google.events['me@example.com']![todos.single.id]!['status'], 'confirmed');
    });

    test('never touches an event the app did not make, even one with the same id', () async {
      final todos = todoEvents(library('- [ ] Buy milk 📅 2026-10-20\n'));
      final theirs = <String, Object?>{'id': todos.single.id, 'summary': 'Someone else’s', 'start': {'date': '2026-01-01'}, 'end': {'date': '2026-01-02'}};
      google.events['me@example.com']!
        ..[todos.single.id] = theirs
        ..['meeting'] = {'id': 'meeting', 'summary': 'Board meeting', 'start': {'dateTime': '2026-10-20T10:00:00Z'}, 'end': {'dateTime': '2026-10-20T11:00:00Z'}};
      expect(await exportTodos(session(), 'me@example.com', todos), (added: 0, moved: 0, removed: 0));
      expect(await exportTodos(session(), 'me@example.com', const []), (added: 0, moved: 0, removed: 0));
      expect(google.events['me@example.com']![todos.single.id], theirs);
      expect(google.events['me@example.com']!['meeting']!['summary'], 'Board meeting');
      expect(google.changes.where((call) => call.startsWith('PATCH') || call.startsWith('DELETE')), isEmpty);
    });

    test('the app’s own events are listed by their mark alone', () async {
      await exportTodos(session(), 'me@example.com', const []);
      expect(google.calls.single, contains('privateExtendedProperty=ghostmd%3D1'));
    });
  });

  test('a Google iCal address names its calendar', () {
    expect(googleCalendarOfAddress('https://calendar.google.com/calendar/ical/me%40example.com/private-abc123/basic.ics'), 'me@example.com');
    expect(googleCalendarOfAddress('https://p01-caldav.icloud.com/published/2/abc'), isNull);
  });
}
