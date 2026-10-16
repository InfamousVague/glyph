import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/task_fields.dart';
import 'package:ghost_md/reminders/reminder_syntax.dart';

/// A reminder as a line writes it (lib/reminders/reminder_syntax.dart): `⏰ 2026-10-03 09:00`, read as one of Tasks'
/// others in the one field grammar, and written before the run of Tasks' fields so Obsidian Tasks still reads the
/// dates after it.
void main() {
  group('reading', () {
    test('a day and a time after the sign, with or without the variation selector and the space', () {
      expect(reminderOn('- [ ] Call the plumber ⏰ 2026-10-03 09:00'), const ReminderTime('2026-10-03', 9, 0));
      expect(reminderOn('- [ ] Call ⏰️ 2026-10-03 18:30 📅 2026-10-03'), const ReminderTime('2026-10-03', 18, 30));
      expect(reminderOn('- [ ] Call ⏰2026-10-03 7:05'), const ReminderTime('2026-10-03', 7, 5));
    });

    test('nothing that is not a day of the calendar and a time on the clock', () {
      expect(reminderOn('- [ ] Call ⏰ 2026-02-30 09:00'), isNull);
      expect(reminderOn('- [ ] Call ⏰ 2026-10-03 24:00'), isNull);
      expect(reminderOn('- [ ] Call ⏰ 2026-10-03'), isNull);
      expect(reminderOn('- [ ] Call at 09:00'), isNull);
      expect(reminderOn('- [ ] Call `⏰ 2026-10-03 09:00`'), isNull, reason: 'code is quiet');
    });

    test('is a field: kept out of an item’s words, as a date is', () {
      expect(withoutFields('Call the plumber ⏰ 2026-10-03 09:00 📅 2026-10-03'), 'Call the plumber');
      expect([for (final span in fieldsIn('Call ⏰ 2026-10-03 09:00')) '${span.kind.name} ${span.key}=${span.value}'], ['tasks reminder=2026-10-03 09:00']);
    });

    test('a ticket’s front matter value, with a space or a T', () {
      expect(readReminderTime('2026-10-03 09:00'), const ReminderTime('2026-10-03', 9, 0));
      expect(readReminderTime('2026-10-03T21:15'), const ReminderTime('2026-10-03', 21, 15));
      expect(readReminderTime('soon'), isNull);
    });
  });

  group('writing', () {
    const at = ReminderTime('2026-10-03', 9, 0);

    test('at the end of the words, before the anchor', () {
      expect(withReminder('- [ ] Call the plumber', at), '- [ ] Call the plumber ⏰ 2026-10-03 09:00');
      expect(withReminder('- [ ] Ship it ^ship-it', at), '- [ ] Ship it ⏰ 2026-10-03 09:00 ^ship-it');
    });

    test('before the run of Tasks’ fields, so Tasks still reads the due date', () {
      expect(withReminder('- [ ] Fix the login @sam #bug ⏫ 📅 2026-10-03', at), '- [ ] Fix the login @sam #bug ⏰ 2026-10-03 09:00 ⏫ 📅 2026-10-03');
    });

    test('in place of the one it had, and taken off with null', () {
      final once = withReminder('- [ ] Call ⏰ 2026-10-02 08:00 📅 2026-10-03', at);
      expect(once, '- [ ] Call ⏰ 2026-10-03 09:00 📅 2026-10-03');
      expect(withReminder(once, null), '- [ ] Call 📅 2026-10-03');
    });

    test('and a field set after it goes where Tasks reads it', () {
      final reminded = withReminder('- [ ] Call', at);
      expect(withField(reminded, 'due', '2026-10-04'), '- [ ] Call ⏰ 2026-10-03 09:00 📅 2026-10-04');
      expect(withField(withField(reminded, 'due', '2026-10-04'), 'priority', 'high'), '- [ ] Call ⏰ 2026-10-03 09:00 ⏫ 📅 2026-10-04');
      expect(withAssignee(reminded, 'sam'), '- [ ] Call @sam ⏰ 2026-10-03 09:00');
    });
  });
}
