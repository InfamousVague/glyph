import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_digest.dart' show digestSettingsOf, ticketDigestSettingsKey;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences, PreferencesStore;
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/home_screen/home_host.dart';
import 'package:ghost_md/reminders/morning_time.dart';
import 'package:ghost_md/reminders/reminder_host.dart';
import 'package:ghost_md/reminders/reminder_scheduler.dart';
import 'package:ghost_md/reminders/reminder_settings.dart';
import 'package:ghost_md/root/phone_extras.dart';

import '../support/fake_reminders.dart';

/// Reminders kept in step with the notes (lib/reminders/reminder_scheduler.dart, lib/root/phone_extras.dart), against
/// a phone of the test's own that keeps what it is handed, a clock of its own, and a timer that waits for nothing.

/// A timer whose wait is the test's to end.
class HeldTimer implements Timer {
  HeldTimer(this.then);
  final void Function() then;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    then();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

Note note(String id, String body, {int updatedAt = 1}) => Note(id: id, body: body, createdAt: 1, updatedAt: updatedAt);

void main() {
  final now = DateTime(2026, 10, 2, 8);

  group('the scheduler', () {
    test('hands the phone the plan once, and again only when it is another', () async {
      final phone = FakeReminders();
      final settings = ReminderSettingsStore(MemoryStored(), PreferencesStore());
      final scheduler = ReminderScheduler(host: phone, settings: settings, clock: () => now);
      final notes = [note('a', '- [ ] Call the plumber 📅 2026-10-03')];
      expect(await scheduler.pass(notes), isTrue);
      expect(phone.last, ['2026-10-03 09:00 Call the plumber']);
      expect(await scheduler.pass(notes), isFalse);
      expect(await scheduler.pass([note('a', '- [ ] Call the plumber 📅 2026-10-03'), note('b', 'words')]), isFalse, reason: 'a note with no dates changes nothing');
      expect(phone.sets, hasLength(1));
      settings.update((was) => was.copyWith(hour: 10));
      expect(await scheduler.pass(notes), isTrue);
      expect(phone.last, ['2026-10-03 10:00 Call the plumber']);
    });

    test('a plan the phone did not take is handed over again at the next pass', () async {
      final phone = FakeReminders()..takes = false;
      final scheduler = ReminderScheduler(host: phone, settings: ReminderSettingsStore(MemoryStored(), PreferencesStore()), clock: () => now);
      final notes = [note('a', '- [ ] Call 📅 2026-10-03')];
      await scheduler.pass(notes);
      phone.takes = true;
      await scheduler.pass(notes);
      expect(phone.sets, hasLength(2));
    });

    test('a reminder that has rung leaves the plan as the clock passes it', () async {
      final phone = FakeReminders();
      var clock = now;
      final scheduler = ReminderScheduler(host: phone, settings: ReminderSettingsStore(MemoryStored(), PreferencesStore()), clock: () => clock);
      final notes = [note('a', '- [ ] Call ⏰ 2026-10-02 08:30\n- [ ] Pay 📅 2026-10-03')];
      await scheduler.pass(notes);
      expect(phone.last, ['2026-10-02 08:30 Call', '2026-10-03 09:00 Pay']);
      clock = DateTime(2026, 10, 2, 8, 31);
      await scheduler.pass(notes);
      expect(phone.last, ['2026-10-03 09:00 Pay']);
    });

    test('the settings are this device’s, kept, and read back; the time is the morning time, synced', () {
      final kept = MemoryStored();
      final prefs = PreferencesStore();
      ReminderSettingsStore(kept, prefs).update((was) => was.copyWith(on: false, hour: 7, minute: 15, dayBefore: true));
      expect(prefs.value.morningTime, '07:15');
      expect(ReminderSettingsStore(kept, prefs).value, const ReminderSettings(on: false, hour: 7, minute: 15, dayBefore: true));
      kept.writeText(reminderSettingsKey, '{"hour": 99, "on": "yes"}');
      expect(ReminderSettingsStore(kept, PreferencesStore()).value, const ReminderSettings());
    });

    // Matt, 2026-11-01: "see if there are other settings that can be simplified". The reminders' time and the ticket
    // digest's are one morning time (lib/reminders/morning_time.dart): chosen anywhere, heard by the store at once.
    test('the morning time chosen elsewhere is the reminders’ time at once, and the scheduler hears it', () async {
      final prefs = PreferencesStore();
      final settings = ReminderSettingsStore(MemoryStored(), prefs);
      final phone = FakeReminders();
      final scheduler = ReminderScheduler(host: phone, settings: settings, clock: () => now);
      final notes = [note('a', '- [ ] Call the plumber 📅 2026-10-03')];
      await scheduler.pass(notes);
      expect(phone.last, ['2026-10-03 09:00 Call the plumber']);
      prefs.update((p) => p.copyWith(morningTime: '06:30'));
      expect((settings.value.hour, settings.value.minute), (6, 30));
      expect(await scheduler.pass(notes), isTrue);
      expect(phone.last, ['2026-10-03 06:30 Call the plumber']);
    });

    test('until a morning time is chosen, the reminders’ old time is it where it was changed, else the digest’s, else nine', () {
      final prefs = PreferencesStore();
      expect(morningOf(prefs.value, kept: MemoryStored()), (hour: 9, minute: 0));
      final kept = MemoryStored()..write(reminderSettingsKey, const ReminderSettings(hour: 7, minute: 45).toJson());
      expect(morningOf(prefs.value, kept: kept), (hour: 7, minute: 45));
      expect(ReminderSettingsStore(kept, prefs).value.hour, 7);
      final digest = Preferences.defaults.copyWith(more: {ticketDigestSettingsKey: {'on': true, 'hour': 8, 'minute': 0, 'note': false}});
      expect(morningOf(digest, kept: MemoryStored()), (hour: 8, minute: 0));
      expect(digestSettingsOf(digest).hour, 8);
      // The reminders' changed time over the digest's; the digest's untouched half past eight is no choice.
      expect(morningOf(digest, kept: kept), (hour: 7, minute: 45));
      final untouched = Preferences.defaults.copyWith(more: {ticketDigestSettingsKey: {'on': true, 'hour': 8, 'minute': 30, 'note': true}});
      expect(morningOf(untouched, kept: MemoryStored()), (hour: 9, minute: 0));
      // Chosen, it is the one time for both.
      final chosen = digest.copyWith(morningTime: '06:15');
      expect(morningOf(chosen, kept: kept), (hour: 6, minute: 15));
      expect((digestSettingsOf(chosen).hour, digestSettingsOf(chosen).minute), (6, 15));
    });
  });

  group('settling', () {
    test('a burst of changes is one pass, once the notes have been still', () async {
      final timers = <HeldTimer>[];
      var passes = 0;
      final settle = Settle(const Duration(seconds: 1), () async => passes += 1, timer: (wait, then) => (timers..add(HeldTimer(then))).last);
      for (var i = 0; i < 10; i += 1) {
        settle.poke();
      }
      expect(timers.where((t) => t.isActive), hasLength(1));
      timers.last.fire();
      await Future<void>.delayed(Duration.zero);
      expect(passes, 1);
      settle.dispose();
      settle.poke();
      expect(timers.where((t) => t.isActive), isEmpty);
    });
  });

  group('the phone’s extras over a library', () {
    testWidgets('a pass at once, then a moment after each change: reminders and the home screen, a synced note too', (tester) async {
      final library = SampleLibrary([note('a', '# Errands\n- [ ] Call the plumber 📅 2026-10-03')]);
      final trash = MemoryTrash();
      final phone = FakeReminders();
      final home = FakeHome();
      final timers = <HeldTimer>[];
      final extras = PhoneExtras(
        library: library,
        trash: trash,
        reminders: phone,
        home: home,
        settings: ReminderSettingsStore(MemoryStored(), PreferencesStore()),
        kept: MemoryStored(),
        clock: () => now,
        timer: (wait, then) => (timers..add(HeldTimer(then))).last,
      );
      addTearDown(extras.dispose);
      await tester.runAsync(() async {
        extras.start();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(phone.last, ['2026-10-03 09:00 Call the plumber']);
      expect(home.puts[HomeKind.todos], hasLength(1));
      expect(home.puts[HomeKind.calendar], hasLength(1), reason: 'the Calendar widget told the plugin is off');
      expect(phoneReminders.value, same(phone));
      // A note that arrives by a sync is a change to the library like any other.
      library.value = [...library.value, note('b', '- [ ] Pay the rent ⏰ 2026-10-02 18:00')];
      expect(timers.where((t) => t.isActive), hasLength(1));
      await tester.runAsync(() async {
        timers.last.fire();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(phone.last, ['2026-10-02 18:00 Pay the rent', '2026-10-03 09:00 Call the plumber']);
      // Into the Trash: no longer reminded.
      trash.trashNote('b');
      await tester.runAsync(() async {
        timers.last.fire();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(phone.last, ['2026-10-03 09:00 Call the plumber']);
      // Done handed back by the phone ticks the line through the library.
      final ticked = await tester.runAsync(() => phone.tick!('a', 2, 'Call the plumber'));
      expect(ticked, isTrue);
      expect(library.noteOf('a')!.body, '# Errands\n- [x] Call the plumber 📅 2026-10-03');
      extras.dispose();
      expect(phoneReminders.value, isNull);
    });
  });
}
