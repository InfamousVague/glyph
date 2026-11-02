/// Settings › Notifications › Morning time (lib/reminders/morning_time.dart): the one time a due day with no time of its
/// own is reminded at and the morning's ticket digest comes. It was two rows, the reminders' Time and the digest's,
/// until Matt, 2026-11-01: "see if there are other settings that can be simplified removed or moved to a plugin for
/// extra configuration". Drawn where either is: on a phone that reminds, or where the digest is on.
///
/// The time is picked on the phone's own clock where it has one (the reminders' `pickTime`), and from a sheet of the
/// half hours of the morning anywhere else.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/preferences.dart';
import '../../reminders/morning_time.dart';
import '../../reminders/remind_choices.dart' show clockWords;
import '../../reminders/reminder_host.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';

/// What Settings' search finds of it.
const SettingsFindable morningFindable = SettingsFindable('Morning time', 'reminder reminders digest ticket time morning due day when');

/// The half hours a morning time may be where there is no clock to pick on: six in the morning to noon.
final List<(int, int)> morningTimes = [for (var minutes = 6 * 60; minutes <= 12 * 60; minutes += 30) (minutes ~/ 60, minutes % 60)];

class MorningSection extends StatefulWidget {
  const MorningSection({super.key, required this.store, this.reminders});

  final PreferencesStore store;

  /// The phone's clock to pick the time on, where it has one.
  final ReminderHost? reminders;

  @override
  State<MorningSection> createState() => _MorningSectionState();
}

class _MorningSectionState extends State<MorningSection> {
  bool _picking = false;

  void _set(int hour, int minute) => widget.store.update((now) => withMorning(now, hour, minute));

  Future<void> _pick(({int hour, int minute}) now) async {
    final host = widget.reminders;
    if (host != null) {
      final picked = await host.pickTime(now.hour, now.minute);
      if (picked != null && mounted) _set(picked.hour, picked.minute);
      return;
    }
    setState(() => _picking = true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Preferences>(
      valueListenable: widget.store,
      builder: (context, prefs, _) {
        final morning = morningOf(prefs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneSection(
              title: 'Morning',
              children: [
                SettingRow(
                  key: const ValueKey('morning-time'),
                  label: 'Morning time',
                  hint: const Text('When a due date with no time of its own reminds you, and when the morning’s ticket digest comes, on this device’s clock.'),
                  value: Text(clockWords(morning.hour, morning.minute)),
                  onPress: () => unawaited(_pick(morning)),
                ),
              ],
            ),
            if (_picking)
              Sheet(
                key: const ValueKey('morning-times'),
                label: 'Morning time',
                onClose: () => setState(() => _picking = false),
                children: [
                  SheetTitle.text('Morning time'),
                  SheetGroup(
                    children: [
                      for (final (hour, minute) in morningTimes)
                        SheetRow(
                          key: ValueKey('morning-time:$hour:$minute'),
                          label: clockWords(hour, minute),
                          chosen: hour == morning.hour && minute == morning.minute,
                          onPress: () {
                            setState(() => _picking = false);
                            _set(hour, minute);
                          },
                        ),
                    ],
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
