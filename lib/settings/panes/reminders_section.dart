/// Settings › Notifications › Reminders (docs/FEATURES_2_1.md): whether this phone reminds, the time a due day with
/// no time of its own is reminded at, and the day before. Drawn only where the phone reminds (Android, over the real
/// library: lib/reminders/reminder_host.dart `phoneReminders`); a Mac, an iPhone and a test draw nothing, and the
/// pane is as it was.
///
/// Under them, what Android is keeping from them, with the way to allow it: notifications not allowed, or alarms
/// that may not ring on their minute (Android 12 and later ask the person for that, under Alarms and reminders; a
/// reminder then comes a few minutes late, never not at all). Read as the page opens and again every second while
/// something is kept from them, as the page's On this phone is read.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/phone_notices.dart' show NoticesHost, PhoneNoticesHost;
import '../../reminders/remind_choices.dart' show clockWords;
import '../../reminders/reminder_host.dart';
import '../../reminders/reminder_settings.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'pane_parts.dart';

/// What Settings' search finds of it, where it is drawn.
const List<SettingsFindable> remindersFindable = [
  SettingsFindable('Reminders', 'remind me due date to-do task ticket alarm time notification'),
  SettingsFindable('The day before', 'reminder day before due early'),
];

class RemindersSection extends StatefulWidget {
  const RemindersSection({super.key, required this.host, this.settings, this.notices});

  final ReminderHost host;

  /// The choices; the app's own unless given.
  final ReminderSettingsStore? settings;

  /// What asks Android to let the app notify: the phone's own unless given.
  final NoticesHost? notices;

  @override
  State<RemindersSection> createState() => _RemindersSectionState();
}

class _RemindersSectionState extends State<RemindersSection> {
  ReminderAbility? _ability;
  Timer? _again;

  ReminderSettingsStore get _store => widget.settings ?? reminderSettings;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final ability = await widget.host.state();
    if (!mounted) return;
    setState(() => _ability = ability);
    final kept = ability != null && (!ability.notify || !ability.exact);
    if (!kept) {
      _again?.cancel();
      _again = null;
    } else {
      _again ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_read()));
    }
  }

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  Future<void> _pickTime(ReminderSettings now) async {
    final picked = await widget.host.pickTime(now.hour, now.minute);
    if (picked == null || !mounted) return;
    _store.update((was) => was.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReminderSettings>(
      valueListenable: _store,
      builder: (context, settings, _) {
        final ability = _ability;
        final at = clockWords(settings.hour, settings.minute);
        final quiet = settings.on && ability != null && !ability.notify;
        final late = settings.on && ability != null && ability.notify && !ability.exact;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneSection(
              title: 'Reminders',
              footer: Text('A to-do with a due date reminds you at $at on the day. Hold a to-do and choose Remind me for a time of its own.'),
              children: [
                SettingRow(
                  label: 'Remind me',
                  hint: Text(
                    quiet
                        ? 'It’s on, but Android is not showing notifications from Ghost.md. Allow them below.'
                        : late
                            ? 'Android may send a reminder a few minutes late. Allow exact times below to have it on the minute.'
                            : 'To-dos and tickets with a due date, and any line with a time set.',
                  ),
                  control: GlacierSwitch(ariaLabel: 'Remind me', checked: settings.on, onCheckedChange: (on) => _store.update((now) => now.copyWith(on: on))),
                ),
                SettingRow(
                  label: 'Time',
                  hint: const Text('When a due date with no time of its own reminds you.'),
                  value: Text(at),
                  disabled: !settings.on,
                  onPress: settings.on ? () => unawaited(_pickTime(settings)) : null,
                ),
                SettingRow(
                  label: 'The day before',
                  hint: Text('Also at $at the day before it is due.'),
                  disabled: !settings.on,
                  control: GlacierSwitch(ariaLabel: 'The day before', checked: settings.dayBefore, disabled: !settings.on, onCheckedChange: (on) => _store.update((now) => now.copyWith(dayBefore: on))),
                ),
              ],
            ),
            // The pane's own gap between its parts (PaneBody), since these are one of its children.
            if (quiet || late) SizedBox(height: context.tokens.space(4)),
            if (quiet)
              PaneActions(
                children: [
                  RowAction(
                    onPress: () => unawaited(() async {
                      await (widget.notices ?? const PhoneNoticesHost()).allow();
                      await _read();
                    }()),
                    child: const Text('Allow notifications'),
                  ),
                ],
              ),
            if (late)
              PaneActions(
                children: [
                  RowAction(
                    onPress: () => unawaited(() async {
                      await widget.host.allowExact();
                      await _read();
                    }()),
                    child: const Text('Allow exact times'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
