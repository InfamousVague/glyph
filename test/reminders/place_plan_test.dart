// Which places the phone watches (lib/reminders/place_plan.dart), kept in step with the notes
// (lib/reminders/place_scheduler.dart, lib/root/phone_extras.dart): every open to-do with a `📍`, not a ticked one,
// a cancelled one or a plain line; the nearest hundred where there are more; and the whole set handed over again,
// or cleared, as the notes and the switches change, against a phone of the test's own.

import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/reminders/place_host.dart';
import 'package:ghost_md/reminders/place_plan.dart';
import 'package:ghost_md/reminders/place_scheduler.dart';
import 'package:ghost_md/reminders/place_settings.dart';
import 'package:ghost_md/reminders/reminder_settings.dart';
import 'package:ghost_md/root/phone_extras.dart';

import '../support/fake_places.dart';
import '../support/fake_reminders.dart';
import 'reminder_scheduler_test.dart' show HeldTimer;

Note note(String id, String body, {int? archivedAt}) => Note(id: id, body: body, createdAt: 1, updatedAt: 1, archivedAt: archivedAt);

const String target = '[Target](geo:35.7002,-81.3084)';
const String costco = '[Costco](geo:35.7301,-81.3399)';

List<String> said(List<PlaceReminder> places) => [for (final place in places) '${place.words} @ ${place.place}'];

bool on() => true;

void main() {
  group('the set', () {
    test('each open to-do with a place, with its line, words, note and the notification’s words', () {
      final places = placesIn([note('a', '# Errands\n- [ ] Buy diapers 📍 $target\n- [ ] Return the lamp 📍 $costco 📅 2026-10-18')]);
      expect(said(places), ['Buy diapers @ Target', 'Return the lamp @ Costco']);
      final first = places.first;
      expect((first.noteId, first.line, first.note, first.radius), ('a', 2, 'Errands', 150.0));
      expect((first.title, first.text), ('Buy diapers — you’re at Target', 'Errands'));
      expect(first.toJson(), {
        'id': first.id,
        'lat': 35.7002,
        'lon': -81.3084,
        'radius': 150.0,
        'title': 'Buy diapers — you’re at Target',
        'text': 'Errands',
        'place': 'Target',
        'noteId': 'a',
        'line': 2,
        'words': 'Buy diapers',
      });
    });

    test('not a ticked to-do, a cancelled or done one, a plain line, fenced code or front matter', () {
      final body = [
        '---',
        'where: 📍 $target',
        '---',
        '- [x] Bought diapers 📍 $target',
        '- [ ] Return it 📍 $target ❌ 2026-10-16',
        '- [ ] Return it again 📍 $target ✅ 2026-10-16',
        '- A plain item 📍 $target',
        '```',
        '- [ ] In code 📍 $target',
        '```',
        '- [ ] Still to do 📍 $target',
      ].join('\n');
      expect(said(placesIn([note('a', body)])), ['Still to do @ Target']);
    });

    test('nothing in the Trash, the archive, a template or a canvas', () {
      final notes = [
        note('kept', '- [ ] One 📍 $target'),
        note('trashed', '- [ ] Two 📍 $target'),
        note('archived', '- [ ] Three 📍 $target', archivedAt: 5),
        note('canvas', '{"nodes":[{"id":"a","type":"text","text":"- [ ] Four 📍 $target","x":0,"y":0,"width":1,"height":1}],"edges":[]}'),
      ];
      expect(said(placesIn(notes, skip: (n) => n.id == 'trashed')), ['One @ Target']);
    });

    test('the id is the same from one pass to the next, another for another place, once for a line written twice', () {
      final one = placesIn([note('a', '- [ ] Buy diapers 📍 $target')]).single;
      final again = placesIn([note('a', '# Moved\n\n- [ ] Buy diapers 📍 $target')]).single;
      final elsewhere = placesIn([note('a', '- [ ] Buy diapers 📍 $costco')]).single;
      expect(again.id, one.id);
      expect(elsewhere.id, isNot(one.id));
      expect(placesIn([note('a', '- [ ] Buy diapers 📍 $target\n- [ ] Buy diapers 📍 $target')]), hasLength(1));
    });

    test('a note read once while it is the same note', () {
      final kept = note('a', '- [ ] Buy diapers 📍 $target');
      expect(identical(PlacedItems.of(kept), PlacedItems.of(kept)), isTrue);
    });
  });

  group('the nearest hundred', () {
    // A to-do a kilometre further north each time, from Hickory.
    final many = [
      for (var n = 0; n < 130; n += 1) note('n$n', '- [ ] Thing $n 📍 [Place $n](geo:${(35.0 + n * 0.009).toStringAsFixed(4)},-81.3400)'),
    ];

    test('every one where there are no more than a hundred', () {
      final all = placesIn(many.take(100).toList());
      expect(nearestPlaces(all, near: (lat: 40, lon: 0)), same(all));
    });

    test('the nearest to where the phone last was, the nearer first', () {
      final all = placesIn(many);
      final near = nearestPlaces(all, near: (lat: 35.0 + 129 * 0.009, lon: -81.34));
      expect(near, hasLength(mostPlaces));
      expect(near.first.words, 'Thing 129');
      expect(near.last.words, 'Thing 30');
    });

    test('where the phone has never said, the first hundred as the notes have them', () {
      final near = nearestPlaces(placesIn(many));
      expect([near.first.words, near.last.words], ['Thing 0', 'Thing 99']);
    });

    test('a kilometre north is a kilometre', () {
      expect(metresBetween(35, -81.34, 35.009, -81.34), closeTo(1000.8, 1));
      expect(metresBetween(35, -81.34, 35, -81.34), 0);
    });

    test('the scheduler asks where the phone was only when there are more than a hundred', () async {
      final phone = FakePlaces()..where = (lat: 35.0, lon: -81.34);
      final scheduler = PlaceScheduler(host: phone, on: on, reminders: ReminderSettingsStore(MemoryStored()));
      await scheduler.pass(many.take(3).toList());
      expect(phone.asked, isEmpty);
      await scheduler.pass(many);
      expect(phone.asked, ['lastKnown']);
      expect(phone.sets.last, hasLength(100));
      expect(phone.sets.last.last.words, 'Thing 99');
    });
  });

  group('the scheduler', () {
    test('hands the whole set once, again only when it is another, and clears it once none is left', () async {
      final phone = FakePlaces();
      final scheduler = PlaceScheduler(host: phone, on: on, reminders: ReminderSettingsStore(MemoryStored()));
      final notes = [note('a', '- [ ] Buy diapers 📍 $target')];
      expect(await scheduler.pass(notes), isTrue);
      expect(phone.last, ['Buy diapers @ Target']);
      expect(await scheduler.pass([...notes, note('b', 'words')]), isFalse);
      expect(await scheduler.pass([note('a', '- [ ] Buy diapers 📍 $target\n- [ ] Return the lamp 📍 $costco')]), isTrue);
      expect(phone.last, ['Buy diapers @ Target', 'Return the lamp @ Costco']);
      // Ticked: its geofence goes with the next set.
      expect(await scheduler.pass([note('a', '- [x] Buy diapers 📍 $target\n- [ ] Return the lamp 📍 $costco')]), isTrue);
      expect(phone.last, ['Return the lamp @ Costco']);
      // Deleted: none left, and the phone is told to clear them.
      expect(await scheduler.pass([note('a', 'words')]), isTrue);
      expect(phone.clears, 1);
      expect(phone.last, isEmpty);
      expect(phone.sets, hasLength(3));
    });

    test('nothing is watched with the plugin off, and switched off every geofence goes; nor with Remind me off', () async {
      final phone = FakePlaces();
      var plugin = false;
      final reminders = ReminderSettingsStore(MemoryStored());
      final scheduler = PlaceScheduler(host: phone, on: () => plugin, reminders: reminders);
      final notes = [note('a', '- [ ] Buy diapers 📍 $target')];
      await scheduler.pass(notes);
      expect(phone.sets, isEmpty, reason: 'off until switched on');
      expect(phone.clears, 1);
      plugin = true;
      await scheduler.pass(notes);
      expect(phone.last, ['Buy diapers @ Target']);
      plugin = false;
      await scheduler.pass(notes);
      expect(phone.clears, 2);
      expect(phone.last, isEmpty);
      plugin = true;
      await scheduler.pass(notes);
      expect(phone.last, ['Buy diapers @ Target']);
      reminders.update((was) => was.copyWith(on: false));
      await scheduler.pass(notes);
      expect(phone.clears, 3);
      expect(phone.last, isEmpty);
    });

    test('a set the phone did not take is handed over again; forget hands it over whatever it is', () async {
      final phone = FakePlaces()..takes = false;
      final scheduler = PlaceScheduler(host: phone, on: on, reminders: ReminderSettingsStore(MemoryStored()));
      final notes = [note('a', '- [ ] Buy diapers 📍 $target')];
      await scheduler.pass(notes);
      phone.takes = true;
      await scheduler.pass(notes);
      await scheduler.pass(notes);
      expect(phone.sets, hasLength(2));
      scheduler.forget();
      await scheduler.pass(notes);
      expect(phone.sets, hasLength(3));
    });

    test('the set as JSON, as two passes are compared', () {
      final places = placesIn([note('a', '- [ ] Buy diapers 📍 $target')]);
      expect(jsonDecode(placesJson(places)), [places.single.toJson()]);
    });
  });

  group('the first one', () {
    test('the first place reminder made on this phone is when the location is asked for, and only that one', () {
      final kept = MemoryStored();
      final store = PlaceSettingsStore(kept);
      expect(store.value.asked, isFalse);
      expect(store.firstMade(), isTrue);
      expect(store.firstMade(), isFalse);
      expect(PlaceSettingsStore(kept).value, const PlaceSettings(asked: true));
      expect(PlaceSettingsStore(kept).firstMade(), isFalse);
      kept.writeText(placeSettingsKey, '{"asked": "yes"}');
      expect(PlaceSettingsStore(kept).value, const PlaceSettings());
    });
  });

  group('the phone’s extras over a library', () {
    testWidgets('the set at once, and again a moment after a change, a synced note’s too; the chips warn while it is not allowed', (tester) async {
      final library = SampleLibrary([note('a', '# Errands\n- [ ] Buy diapers 📍 $target')]);
      final trash = MemoryTrash();
      final phone = FakePlaces()..now = PlaceAccess.whileUsing;
      final plugin = ValueNotifier<bool>(true);
      final timers = <HeldTimer>[];
      final extras = PhoneExtras(
        library: library,
        trash: trash,
        reminders: FakeReminders(),
        places: phone,
        home: FakeHome(),
        settings: ReminderSettingsStore(MemoryStored()),
        placesOn: () => plugin.value,
        placesSwitch: plugin,
        kept: MemoryStored(),
        clock: () => DateTime(2026, 10, 17, 9),
        timer: (wait, then) => (timers..add(HeldTimer(then))).last,
      );
      addTearDown(extras.dispose);
      await tester.runAsync(() async {
        extras.start();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(phone.last, ['Buy diapers @ Target']);
      expect(phonePlaces.value, same(phone));
      expect(placeWarning.value, isTrue);
      library.value = [...library.value, note('b', '- [ ] Return the lamp 📍 $costco')];
      await tester.runAsync(() async {
        timers.last.fire();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(phone.last, ['Buy diapers @ Target', 'Return the lamp @ Costco']);
      trash.trashNote('b');
      await tester.runAsync(() async {
        timers.last.fire();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(phone.last, ['Buy diapers @ Target']);
      // Allowed all the time in the phone's settings, and the app back in front.
      phone.now = PlaceAccess.always;
      await tester.runAsync(() async {
        extras.resumed();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        timers.last.fire();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(placeWarning.value, isFalse);
      expect(phone.sets, hasLength(4), reason: 'back in front, the set is handed over whatever it is');
      expect(placeRemindersOn.value, isTrue);
      // The plugin switched off: Remind me at a place goes, and so does every geofence.
      plugin.value = false;
      await tester.runAsync(() async {
        timers.last.fire();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(placeRemindersOn.value, isFalse);
      expect(phone.clears, 1);
      expect(phone.last, isEmpty);
      expect(placeWarning.value, isFalse);
      extras.dispose();
      expect(phonePlaces.value, isNull);
    });
  });
}
