/// Settings › Notifications › Reminders: whether this phone reminds at all, the time a to-do or a ticket with a due
/// day and no time of its own is reminded at, and whether it is reminded the day before too. This device's own, kept
/// in its memory under `glyph-reminders` (lib/core/stored.dart), never synced: only a phone reminds, and each phone
/// is its owner's to set.
library;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';

/// What the person chose.
@immutable
class ReminderSettings {
  const ReminderSettings({this.on = true, this.hour = 9, this.minute = 0, this.dayBefore = false});

  /// Whether this phone reminds: on unless turned off, since a due day written is a reminder asked for.
  final bool on;

  /// The time a due day with no time of its own is reminded at: nine in the morning unless set.
  final int hour;
  final int minute;

  /// Whether a due day is also reminded the day before, at the same time.
  final bool dayBefore;

  /// `09:00`.
  String get clock => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ReminderSettings copyWith({bool? on, int? hour, int? minute, bool? dayBefore}) =>
      ReminderSettings(on: on ?? this.on, hour: hour ?? this.hour, minute: minute ?? this.minute, dayBefore: dayBefore ?? this.dayBefore);

  Map<String, Object?> toJson() => {'on': on, 'hour': hour, 'minute': minute, 'dayBefore': dayBefore};

  /// What was kept, each part checked; anything else is the default's.
  static ReminderSettings? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int? clockPart(Object? value, int most) => value is int && value >= 0 && value <= most ? value : null;
    const fallback = ReminderSettings();
    return ReminderSettings(
      on: raw['on'] is bool ? raw['on'] as bool : fallback.on,
      hour: clockPart(raw['hour'], 23) ?? fallback.hour,
      minute: clockPart(raw['minute'], 59) ?? fallback.minute,
      dayBefore: raw['dayBefore'] is bool ? raw['dayBefore'] as bool : fallback.dayBefore,
    );
  }

  @override
  bool operator ==(Object other) => other is ReminderSettings && other.on == on && other.hour == hour && other.minute == minute && other.dayBefore == dayBefore;

  @override
  int get hashCode => Object.hash(on, hour, minute, dayBefore);

  @override
  String toString() => 'ReminderSettings(${toJson()})';
}

/// The key the choices are kept under.
const String reminderSettingsKey = 'glyph-reminders';

/// The choices, read once from this device's memory and written back as they change.
class ReminderSettingsStore extends ValueNotifier<ReminderSettings> {
  ReminderSettingsStore([Stored? kept])
      : _kept = kept ?? stored,
        super((kept ?? stored).read<ReminderSettings>(reminderSettingsKey, const ReminderSettings(), ReminderSettings.fromJson));

  final Stored _kept;

  /// Changes the choices, and keeps them.
  void update(ReminderSettings Function(ReminderSettings now) change) {
    final next = change(value);
    if (next == value) return;
    value = next;
    _kept.write(reminderSettingsKey, next.toJson());
  }
}

ReminderSettingsStore? _settings;

/// The app's own, over the device's memory as it is when first asked: after the launch has opened it.
ReminderSettingsStore get reminderSettings => _settings ??= ReminderSettingsStore();

/// For a test, or a reset: the next ask reads the memory again.
@visibleForTesting
void forgetReminderSettings() => _settings = null;
