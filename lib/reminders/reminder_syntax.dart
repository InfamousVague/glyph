/// A reminder as a line writes it: `⏰ 2026-10-03 09:00`, a day and a time on the clock, after the item's words and
/// before the run of Obsidian Tasks' fields (docs/FEATURES_2_1.md, "Reminders").
///
///     - [ ] Call the plumber ⏰ 2026-10-03 09:00 📅 2026-10-03
///
/// The sign and the form are the Obsidian Reminder plugin's, which reads them beside Tasks, so the line is a reminder
/// there too, and the words read as they are written in any other app. The time is the phone's own clock where it is
/// read: a reminder written for nine is at nine wherever the phone has gone. The grammar is lib/core/task_fields.dart's
/// (the `reminder` key, one of Tasks' others), so a board's card and a title sent elsewhere leave it out as they leave
/// out a date. A ticket keeps its reminder in its front matter, `remind: 2026-10-03 09:00`, beside its `due:`.
///
/// A to-do with a due day and no `⏰` is reminded at the time Settings › Notifications › Reminders sets, on the day and,
/// if asked, the day before (reminder_plan.dart): nothing is written for that.
library;

import '../core/days.dart' show dateOfDay, isIsoDay, isoDay;
import '../core/task_fields.dart' show FieldKind, fieldsIn, withWrittenField;

/// A time on the clock: a day and its hour and minute, read where the phone is.
class ReminderTime implements Comparable<ReminderTime> {
  const ReminderTime(this.day, this.hour, this.minute);

  /// The same moment, as the phone's clock has it.
  factory ReminderTime.of(DateTime at) => ReminderTime(isoDay(at), at.hour, at.minute);

  /// `2026-10-03`.
  final String day;
  final int hour;
  final int minute;

  /// The moment on this phone's clock, or null for a day the calendar has not got.
  DateTime? get local {
    final date = dateOfDay(day);
    return date == null ? null : DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// `09:00`.
  String get clock => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// `2026-10-03 09:00`, as a line and a ticket's front matter write it, and as the phone is handed it.
  String get written => '$day $clock';

  @override
  int compareTo(ReminderTime other) => written.compareTo(other.written);

  @override
  bool operator ==(Object other) => other is ReminderTime && other.day == day && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(day, hour, minute);

  @override
  String toString() => 'ReminderTime($written)';
}

final RegExp _written = RegExp(r'^\s*(\d{4}-\d{2}-\d{2})[ T]+([01]?\d|2[0-3]):([0-5]\d)\s*$');

/// A reminder's value read: `2026-10-03 09:00` (or with a `T`, as a ticket's front matter may have been given it),
/// or null for anything that is not a day of the calendar and a time.
ReminderTime? readReminderTime(String? value) {
  final found = _written.firstMatch(value ?? '');
  if (found == null || !isIsoDay(found.group(1)!)) return null;
  return ReminderTime(found.group(1)!, int.parse(found.group(2)!), int.parse(found.group(3)!));
}

/// The sign a line writes a reminder with.
const String reminderSign = '⏰';

/// Whether [line] could hold a reminder, asked before it is read: the sign is there.
bool mayRemind(String line) => line.contains(reminderSign);

/// The reminder [line] carries, the first where it has two, or null.
ReminderTime? reminderOn(String line) {
  if (!mayRemind(line)) return null;
  for (final span in fieldsIn(line)) {
    if (span.kind == FieldKind.tasks && span.key == 'reminder') return readReminderTime(span.value);
  }
  return null;
}

/// [line] with its reminder set to [at], or taken off with null: one `⏰`, before Tasks' fields.
String withReminder(String line, ReminderTime? at) => withWrittenField(line, 'reminder', at == null ? null : '$reminderSign ${at.written}');

/// The front matter key a ticket keeps its reminder under.
const String ticketReminderKey = 'remind';
