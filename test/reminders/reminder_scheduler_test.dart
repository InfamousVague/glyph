import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/home_screen/home_host.dart';
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
      final settings = ReminderSettingsStore(MemoryStored());
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
      final scheduler = ReminderScheduler(host: phone, settings: ReminderSettingsStore(MemoryStored()), clock: () => now);
      final notes = [note('a', '- [ ] Call 📅 2026-10-03')];
      await scheduler.pass(notes);
      phone.takes = true;
      await scheduler.pass(notes);
      expect(phone.sets, hasLength(2));
    });

    test('a reminder that has rung leaves the plan as the clock passes it', () async {
      final phone = FakeReminders();
      var clock = now;
      final scheduler = ReminderScheduler(host: phone, settings: ReminderSettingsStore(MemoryStored()), clock: () => clock);
      final notes = [note('a', '- [ ] Call ⏰ 2026-10-02 08:30\n- [ ] Pay 📅 2026-10-03')];
      await scheduler.pass(notes);
      expect(phone.last, ['2026-10-02 08:30 Call', '2026-10-03 09:00 Pay']);
      clock = DateTime(2026, 10, 2, 8, 31);
      await scheduler.pass(notes);
      expect(phone.last, ['2026-10-03 09:00 Pay']);
    });

    test('the settings are this device’s, kept, and read back', () {
      final kept = MemoryStored();
      ReminderSettingsStore(kept).update((was) => was.copyWith(on: false, hour: 7, minute: 15, dayBefore: true));
      expect(ReminderSettingsStore(kept).value, const ReminderSettings(on: false, hour: 7, minute: 15, dayBefore: true));
      kept.writeText(reminderSettingsKey, '{"hour": 99, "on": "yes"}');
      expect(ReminderSettingsStore(kept).value, const ReminderSettings());
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
        settings: ReminderSettingsStore(MemoryStored()),
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
      expect(home.puts[HomeKind.today], hasLength(1));
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
