/// What a line's Remind me offers (lib/editor/items/field_items.dart draws them): in an hour, this evening while
/// there is evening left, tomorrow at Settings' time, a day and a time picked on the phone's own calendar and clock,
/// and Remove where the line has one. Pure but for the picker, so each is a test with a clock of its own.
library;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../core/days.dart' show isoDayAfterDate, isoDay;
import 'reminder_host.dart';
import 'reminder_settings.dart';
import 'reminder_syntax.dart';

/// A time as the menu says it: `9:00`, `18:30`, the phone's own clock in twenty-four hours as the line writes it.
String clockWords(int hour, int minute) => '$hour:${minute.toString().padLeft(2, '0')}';

/// One of the times offered.
@immutable
class RemindChoice {
  const RemindChoice(this.id, this.label, this.name, this.at);

  /// `hour`, `evening` or `tomorrow`.
  final String id;
  final String label;

  /// What a screen reader hears.
  final String name;
  final ReminderTime at;

  @override
  bool operator ==(Object other) => other is RemindChoice && other.id == id && other.label == label && other.name == name && other.at == at;

  @override
  int get hashCode => Object.hash(id, label, name, at);

  @override
  String toString() => 'RemindChoice($id, $label, ${at.written})';
}

/// The hour of the evening a reminder is offered for, and the last hour that offer stands.
const int eveningHour = 18;

/// The times offered at [now]: an hour on, to the next five minutes; this evening at six until five; tomorrow at
/// [settings]' time.
List<RemindChoice> remindChoices(DateTime now, ReminderSettings settings) {
  final soon = now.add(const Duration(hours: 1));
  final rounded = DateTime(soon.year, soon.month, soon.day, soon.hour, soon.minute).add(Duration(minutes: (5 - soon.minute % 5) % 5));
  final hour = ReminderTime.of(rounded);
  final choices = <RemindChoice>[RemindChoice('hour', 'In an hour', 'Remind me at ${clockWords(hour.hour, hour.minute)}', hour)];
  if (now.hour < eveningHour - 1) {
    choices.add(RemindChoice('evening', 'This evening', 'Remind me this evening at ${clockWords(eveningHour, 0)}', ReminderTime(isoDay(now), eveningHour, 0)));
  }
  final at = clockWords(settings.hour, settings.minute);
  choices.add(RemindChoice('tomorrow', 'Tomorrow, $at', 'Remind me tomorrow at $at', ReminderTime(isoDayAfterDate(now, 1), settings.hour, settings.minute)));
  return choices;
}

/// A day and a time picked: the phone's calendar first ([day], where there is one: else today, or tomorrow once the
/// time has passed), then its clock, from [current] or Settings' time.
typedef PickDay = Future<String?> Function(Offset at, String? current);

/// Pick a time, over the phone's calendar and its clock: the day and the time chosen, or null where either was put
/// away.
Future<ReminderTime?> Function(Offset at, ReminderTime? current) phoneReminderPicker(ReminderHost host, PickDay? day, {DateTime Function()? clock, ValueListenable<ReminderSettings>? settings}) {
  return (at, current) async {
    final now = (clock ?? DateTime.now)();
    final chosen = settings?.value ?? reminderSettings.value;
    String? picked;
    if (day != null) {
      picked = await day(at, current?.day ?? isoDay(now));
      if (picked == null) return null;
    }
    final time = await host.pickTime(current?.hour ?? chosen.hour, current?.minute ?? chosen.minute);
    if (time == null) return null;
    var on = picked ?? isoDay(now);
    // No calendar: a time already gone today is tomorrow's.
    if (picked == null && (time.hour < now.hour || (time.hour == now.hour && time.minute <= now.minute))) on = isoDayAfterDate(now, 1);
    return ReminderTime(on, time.hour, time.minute);
  };
}
