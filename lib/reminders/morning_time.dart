/// The morning time (Settings › Notifications › Morning time): when a to-do or a ticket with a due day and no time of
/// its own is reminded at (lib/reminders/reminder_settings.dart), and when the morning's ticket digest comes
/// (lib/book/ticket_digest.dart). One time for both since Matt, 2026-11-01: "see if there are other settings that can
/// be simplified removed or moved to a plugin for extra configuration"; until then each had its own, the reminders'
/// nine o'clock on this phone and the digest's half past eight on the account.
///
/// Kept as `morningTime` in the synced preferences ([Preferences.morningTime]), so the phone that reminds and the
/// device that sends the digest read the same time. Until it is chosen it is read from the two there were: the
/// reminders' where it was changed from nine, else the digest's where it was changed from half past eight, else nine,
/// the reminders' own, which most people had.
library;

import '../book/ticket_digest.dart' show ticketDigestSettingsKey;
import '../core/preferences.dart';
import '../core/stored.dart';
import 'reminder_settings.dart' show ReminderSettings, reminderSettingsKey;

/// Nine in the morning: the reminders' own, until a morning time is chosen.
const ({int hour, int minute}) morningFallback = (hour: 9, minute: 0);

/// The morning time [prefs] say, or the one read from the two there were (see the header). [kept] is this device's
/// memory, where the reminders' time was; the app's own when null.
({int hour, int minute}) morningOf(Preferences prefs, {Stored? kept}) {
  final chosen = clockOf(prefs.morningTime);
  if (chosen != null) return chosen;
  final reminders = (kept ?? stored).read<ReminderSettings?>(reminderSettingsKey, null, ReminderSettings.fromJson);
  if (reminders != null && (reminders.hour, reminders.minute) != (morningFallback.hour, morningFallback.minute)) return (hour: reminders.hour, minute: reminders.minute);
  final digest = prefs.more[ticketDigestSettingsKey];
  if (digest is Map) {
    final hour = digest['hour'], minute = digest['minute'];
    if (hour is int && minute is int && hour >= 0 && hour < 24 && minute >= 0 && minute < 60 && (hour, minute) != (8, 30)) return (hour: hour, minute: minute);
  }
  return morningFallback;
}

/// [prefs] with the morning time [hour]:[minute].
Preferences withMorning(Preferences prefs, int hour, int minute) => prefs.copyWith(morningTime: clockWord(hour, minute));
