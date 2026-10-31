// The calendars read and kept for the life of the app (lib/calendar/calendar.dart, docs/CALENDAR.md): an iCal address
// checked, added, read and named, Local only obeyed, an address taken off and forgotten; Google connected through the
// claim, its primary ticked and read, an iCal address of a ticked calendar not read twice, the to-dos put on it when
// switched on, and Google forgotten. Against calendars in memory, on a clock of the test's own.
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/calendar/calendar.dart';
import 'package:ghost_md/calendar/setup.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/export_all.dart' show settingsFile;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/kept_secrets.dart';
import 'package:ghost_md/plugins/calendar/calendar.dart' show calendarInUse, calendarManifest, calendarPlugin;
import 'package:ghost_md/plugins/registry.dart' show MemorySwitches, createRegistry;

import 'fake_google.dart';

const String work = 'https://cal.test/work.ics';

String icsOf(String name, List<String> lines) => ['BEGIN:VCALENDAR', 'X-WR-CALNAME:$name', 'BEGIN:VEVENT', ...lines, 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');

late FakeGoogle google;
late Map<String, String> calendars;
late List<String> fetched;
late PreferencesStore prefs;
late MemoryStored kept;
late MemorySecureStore secure;
late KeptSecrets secrets;
late List<String> opened;
int now = DateTime(2026, 10, 17, 12).millisecondsSinceEpoch;

/// The calendars as the settings and the secure store together hold them (lib/calendar/setup.dart).
CalendarSetup setupNow() => calendarSetupOf(prefs.value, secret: secrets.peek);

/// The settings as the export's settings.json would dump them (lib/core/export_all.dart `settingsFile`).
String exported() => settingsFile((key) => key == 'glyph-preferences' ? jsonEncode(prefs.value.toJson()) : null);

Future<FetchResponse> fetch(FetchRequest request) async {
  if (request.url.host == 'cal.test') {
    fetched.add(request.url.toString());
    final text = calendars[request.url.toString()];
    return text == null ? FetchResponse(404) : FetchResponse(200, bytes: utf8.encode(text));
  }
  return google.fetch(request);
}

CalendarService service({String? base = fakeBase}) => CalendarService(fetch: fetch, prefs: prefs, kept: () => kept, secrets: secrets, googleBase: () => base, clock: () => now, open: (url) async => opened.add(url));

void main() {
  setUp(() {
    google = FakeGoogle();
    calendars = {work: icsOf('Work', ['UID:standup', 'DTSTART:20261019T090000Z', 'DTEND:20261019T091500Z', 'RRULE:FREQ=DAILY;COUNT=2', 'SUMMARY:Standup'])};
    fetched = [];
    prefs = PreferencesStore()..startWithoutStorage();
    kept = MemoryStored();
    secure = MemorySecureStore();
    secrets = KeptSecrets(secure);
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
      final setup = setupNow();
      expect(setup.addresses.single.url, work);
      expect(setup.addresses.single.name, 'Work');
      expect(calendar.queryEvents().first.calendar, 'Work');
      expect(calendar.on('2026-10-20').single.title, 'Standup');
      // Kept with the account's settings, which travel: the address's id and name, never the address itself, which is
      // a secret and lives in the secure store (decision 22). So the export's settings.json carries no address.
      expect(prefs.value.toJson()['calendars'], isA<Map<String, Object?>>());
      expect(jsonEncode(prefs.value.toJson()), isNot(contains('cal.test')));
      expect(secure.held[icalAddressName(setup.addresses.single.id)], work);
      expect(exported(), isNot(contains('cal.test')));
      expect(exported(), contains(setup.addresses.single.id));
    });

    test('added twice is said, and a refusal is the line under it', () async {
      final calendar = service();
      await calendar.addAddress(work);
      expect(await calendar.addAddress(work), 'That calendar is here already.');
      await calendar.addAddress('https://cal.test/missing.ics');
      final missing = setupNow().addresses.last;
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

    test('a pass is a job on the app\'s record of running work, out of sight unless slow, never counted', () async {
      final record = Activity(store: () => MemoryStored());
      useActivity(record);
      addTearDown(() => useActivity(Activity()));
      final begun = <String>[];
      final hearing = record.events.listen((e) => begun.add('${e.kind.name} ${e.job?.id}'));
      addTearDown(hearing.cancel);
      final calendar = service();
      await calendar.addAddress(work);
      final slow = calendar.syncIcal(force: true);
      expect(record['calendar:ical'], isNotNull);
      expect(record['calendar:ical']!.kind, JobKind.sync);
      expect(record.value, isEmpty, reason: 'a quick pass is never seen');
      await slow;
      expect(record['calendar:ical'], isNull);
      expect(begun, isEmpty);
      expect(record.log.today.isEmpty, isTrue);
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
      final id = setupNow().addresses.single.id;
      calendar.removeAddress(id);
      expect(calendar.events.value, isEmpty);
      expect(setupNow().isEmpty, isTrue);
      expect(prefs.value.toJson().containsKey('calendars'), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(secure.held.containsKey(icalAddressName(id)), isFalse, reason: 'its secret goes with it');
    });

    test('written in the clear by an older build, is moved to the secure store and taken out of the settings', () async {
      // The blob as a build before 2026-10-31 wrote it: the address itself, and Google's refresh token.
      prefs.update((p) => p.copyWith(more: {
            ...p.more,
            'calendars': {
              'addresses': [
                {'id': addressId(work), 'url': work, 'name': 'Work'},
              ],
              'google': {'refreshToken': 'refresh-old', 'ticked': ['me@example.com'], 'todos': false},
            },
          }));
      kept.write('glyph-google-token', {'accessToken': 'access-old', 'expiresAt': now + 3600000});
      final calendar = service();
      // Read-both: before anything has moved, the setup reads whole from the blob.
      expect((setupNow().addresses.single.url, setupNow().google!.refreshToken), (work, 'refresh-old'));
      await calendar.ready();
      expect(secure.held[icalAddressName(addressId(work))], work);
      expect(secure.held[googleRefreshName], 'refresh-old');
      expect(jsonDecode(secure.held[googleAccessName]!), {'accessToken': 'access-old', 'expiresAt': now + 3600000});
      expect(kept.read<Object?>('glyph-google-token', null), isNull, reason: 'the access token moved too');
      final blob = jsonEncode(prefs.value.toJson()['calendars']);
      expect(blob, isNot(contains('cal.test')));
      expect(blob, isNot(contains('refresh-old')));
      expect(exported(), isNot(contains('refresh-old')));
      // And the setup still reads whole, from the store now.
      expect((setupNow().addresses.single.url, setupNow().addresses.single.name, setupNow().google!.refreshToken), (work, 'Work', 'refresh-old'));
      expect(setupNow().google!.ticked, ['me@example.com']);
      await calendar.syncIcal(force: true);
      expect(fetched, [work], reason: 'read from the store\'s address');
      calendar.dispose();
    });

    test('named by the settings from another device, is listed once its secret arrives, and Google waits for its token', () async {
      // What a newer device's settings carry: the id and the choices. The secrets come by the sealed keys, later.
      prefs.update((p) => p.copyWith(more: {
            ...p.more,
            'calendars': {
              'addresses': [
                {'id': addressId(work), 'name': 'Work'},
              ],
              'google': {'ticked': ['me@example.com'], 'todos': false},
            },
          }));
      final calendar = service();
      await calendar.ready();
      expect(setupNow().addresses, isEmpty, reason: 'an address with no secret here cannot be read');
      expect(setupNow().google, isNotNull);
      expect(setupNow().google!.refreshToken, '');
      await calendar.syncGoogle();
      expect(google.calls, isEmpty);
      expect(calendar.statusOf(googleSource)!.problem, contains('hasn’t reached this device yet'));
      // The sealed key arrives (lib/sync/connections.dart writes it here).
      await secrets.write(icalAddressName(addressId(work)), work);
      await secrets.write(googleRefreshName, 'refresh-1');
      expect(setupNow().addresses.single.url, work);
      expect(setupNow().google!.refreshToken, 'refresh-1');
      await calendar.syncIcal(force: true);
      expect(fetched, [work]);
      calendar.dispose();
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
      expect(setupNow().google, isNull);
      await calendar.collectGoogle();
      final setup = setupNow().google!;
      expect(setup.refreshToken, 'refresh-1');
      expect(setup.ticked, ['me@example.com']);
      expect(setup.todos, isFalse);
      expect(calendar.connecting, isFalse);
      // The token is the secure store's, never the settings' (decision 22): nothing of it in the export.
      expect(secure.held[googleRefreshName], 'refresh-1');
      expect(jsonEncode(prefs.value.toJson()), isNot(contains('refresh-1')));
      expect(exported(), isNot(contains('refresh-1')));
      expect(kept.read<Object?>('glyph-google-token', null), isNull, reason: 'the access token is in the secure store too');
      expect(secure.held[googleAccessName], contains('accessToken'));
      await calendar.syncGoogle();
      expect([for (final e in calendar.events.value) '${e.title} ${e.calendar}'], ['Dentist Me']);
      expect([for (final c in calendar.googleCalendars) c.name], ['Me', 'Team']);
      calendar.dispose();
    });

    test('a claim turned away as rate limited is asked again, the sign-in still in flight', () async {
      // Matt, 2026-10-17: the page said Connected, the phone said Connect again. glyph-api lets a phone 30 calls a
      // minute across its Google routes; a claim refused with 429 ended the sign-in.
      final calendar = service();
      await calendar.connectGoogle();
      google.limitedClaims = 2;
      await calendar.collectGoogle();
      await calendar.collectGoogle();
      expect(calendar.connecting, isTrue, reason: 'still waiting on the sign-in');
      expect(setupNow().google, isNull);
      await calendar.collectGoogle();
      await calendar.collectGoogle();
      expect(setupNow().google?.refreshToken, 'refresh-1');
      expect(calendar.connecting, isFalse);
      await calendar.syncGoogle();
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

    test('to-dos follow the notes within moments: one added, moved, ticked; nothing asked of Google when nothing changed', () async {
      // Matt, 2026-10-17: "so all of these events show up on my personal calendar in real time and are removed when
      // removed". The wait is [todosSoon] in the app.
      final calendar = CalendarService(fetch: fetch, prefs: prefs, kept: () => kept, googleBase: () => fakeBase, clock: () => now, open: (url) async => opened.add(url), todosWait: const Duration(milliseconds: 10));
      await calendar.connectGoogle();
      await calendar.collectGoogle();
      await calendar.collectGoogle();
      var body = '- [ ] Buy milk 📅 2026-10-20\n';
      final changed = ValueNotifier(0);
      calendar.start(notes: () => [QueryNote(id: 'plans', body: body, createdAt: 0, updatedAt: 0)], notesChanged: changed);
      await calendar.syncGoogle();
      calendar.setTodos(true);
      await calendar.syncGoogle();
      // The switch is a settings change, which reads Google whole 300 ms on: let that pass be the one before the
      // edits (a timer due later fires later), so what is counted below is the to-dos' own.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await calendar.syncGoogle();
      List<String> live() => [
            for (final event in google.events['me@example.com']!.values)
              if (event['status'] != 'cancelled') '${event['summary']} ${(event['start'] as Map)['date']}',
          ];
      Future<void> edit(String next) async {
        body = next;
        changed.value++;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await calendar.exportTodosNow();
      }

      expect(live(), ['Buy milk 2026-10-20']);
      await edit('- [ ] Buy milk 📅 2026-10-20\n- [ ] Pack the hospital bag 📅 2026-11-02\n');
      expect(live(), unorderedEquals(['Buy milk 2026-10-20', 'Pack the hospital bag 2026-11-02']));
      await edit('- [ ] Buy milk 📅 2026-10-22\n- [ ] Pack the hospital bag 📅 2026-11-02\n');
      expect(live(), unorderedEquals(['Buy milk 2026-10-22', 'Pack the hospital bag 2026-11-02']));
      await edit('- [ ] Buy milk 📅 2026-10-22\n- [x] Pack the hospital bag 📅 2026-11-02\n');
      expect(live(), ['Buy milk 2026-10-22']);
      await edit('');
      expect(live(), isEmpty, reason: 'a to-do taken out of the note is taken off the calendar');
      final asked = google.calls.length;
      await edit('');
      expect(google.calls.length, asked, reason: 'the same to-dos are not put there again');
      calendar.dispose();
      changed.dispose();
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

  // The Calendar plugin's switch (lib/plugins/calendar), handed to start by the app's root.
  group('under the Calendar plugin', () {
    test('switched off reads nothing and shows no event, keeping what it read; switched on shows it at once and reads soon', () async {
      final first = service();
      await first.addAddress(work);
      first.dispose();
      fetched.clear();

      final on = ValueNotifier<bool>(false);
      final calendar = service()..start(on: () => on.value, switched: on);
      expect(calendar.active, isFalse);
      expect(calendar.events.value, isEmpty);
      expect(calendar.queryEvents(), isEmpty);
      await calendar.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fetched, isEmpty);

      on.value = true;
      expect([for (final e in calendar.events.value) e.title], ['Standup', 'Standup']);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(fetched, [work]);

      on.value = false;
      expect(calendar.events.value, isEmpty);
      calendar.dispose();
      on.dispose();
    });

    test('a service started with no switch is always on', () {
      final calendar = service()..start();
      expect(calendar.active, isTrue);
      calendar.dispose();
    });

    test('ships off, and finds a device that already had a calendar in use', () async {
      expect(calendarManifest.standard, isFalse);
      final unused = service();
      expect(calendarInUse(unused), isFalse);
      await unused.addAddress(work);
      expect(calendarInUse(unused), isTrue);
      unused.dispose();
      final registry = createRegistry([calendarPlugin], store: MemorySwitches());
      expect(registry.isEnabled('calendar'), isFalse);
      registry.adopt('calendar', inUse: true);
      expect(registry.isEnabled('calendar'), isTrue);
      // Once: switched off after, it stays off.
      registry.setEnabled('calendar', false);
      registry.adopt('calendar', inUse: true);
      expect(registry.isEnabled('calendar'), isFalse);
    });
  });
}
