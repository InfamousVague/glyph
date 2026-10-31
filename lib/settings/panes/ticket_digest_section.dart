/// Settings › Notifications › Ticket digest (Matt, 2026-10-31: "Each morning (default 8:30 local, set in Settings ›
/// Notifications or the tickets settings), one notification per person"; lib/book/ticket_digest.dart): on or off, its
/// time, and Write a digest note, off unless turned on. The choices follow the account (the synced settings), so the
/// one device that sends it sends it at the time chosen anywhere.
///
/// The time is picked on the phone's own clock where it has one (the reminders' `pickTime`), and from a sheet of the
/// half hours of the morning anywhere else.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../book/ticket_digest.dart';
import '../../core/preferences.dart';
import '../../reminders/remind_choices.dart' show clockWords;
import '../../reminders/reminder_host.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';

/// What Settings' search finds of it.
const List<SettingsFindable> ticketDigestFindable = [
  SettingsFindable('Ticket digest', 'morning tickets due today overdue blocked digest summary time'),
  SettingsFindable('Write a digest note', 'digest note inbox morning tickets'),
];

/// The half hours a digest may be sent at where there is no clock to pick on: six in the morning to noon.
final List<(int, int)> digestTimes = [for (var minutes = 6 * 60; minutes <= 12 * 60; minutes += 30) (minutes ~/ 60, minutes % 60)];

class TicketDigestSection extends StatefulWidget {
  const TicketDigestSection({super.key, required this.store, this.reminders});

  final PreferencesStore store;

  /// The phone's clock to pick the time on, where it has one.
  final ReminderHost? reminders;

  @override
  State<TicketDigestSection> createState() => _TicketDigestSectionState();
}

class _TicketDigestSectionState extends State<TicketDigestSection> {
  bool _picking = false;

  void _set(DigestSettings Function(DigestSettings now) change) => widget.store.update((prefs) => withDigestSettings(prefs, change(digestSettingsOf(prefs))));

  Future<void> _pickTime(DigestSettings now) async {
    final host = widget.reminders;
    if (host != null) {
      final picked = await host.pickTime(now.hour, now.minute);
      if (picked != null && mounted) _set((was) => was.copyWith(hour: picked.hour, minute: picked.minute));
      return;
    }
    setState(() => _picking = true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Preferences>(
      valueListenable: widget.store,
      builder: (context, prefs, _) {
        final digest = digestSettingsOf(prefs);
        final at = clockWords(digest.hour, digest.minute);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaneSection(
              title: 'Ticket digest',
              footer: Text('Once each morning at $at, from one of your devices: the tickets due today, overdue and blocked that are yours, across your notebooks and teams. A morning with none says nothing.'),
              children: [
                SettingRow(
                  key: const ValueKey('digest-on'),
                  label: 'Morning digest',
                  hint: const Text('Tickets assigned to you, and your own that nobody is assigned.'),
                  control: GlacierSwitch(ariaLabel: 'Morning digest', checked: digest.on, onCheckedChange: (on) => _set((now) => now.copyWith(on: on))),
                ),
                SettingRow(
                  key: const ValueKey('digest-time'),
                  label: 'Time',
                  hint: const Text('When it comes, on this device’s clock.'),
                  value: Text(at),
                  disabled: !digest.on,
                  onPress: digest.on ? () => unawaited(_pickTime(digest)) : null,
                ),
                SettingRow(
                  key: const ValueKey('digest-note'),
                  label: 'Write a digest note',
                  hint: const Text('The same, as a note in your Inbox, at that time.'),
                  disabled: !digest.on,
                  control: GlacierSwitch(ariaLabel: 'Write a digest note', checked: digest.note, disabled: !digest.on, onCheckedChange: (on) => _set((now) => now.copyWith(note: on))),
                ),
              ],
            ),
            if (_picking)
              Sheet(
                key: const ValueKey('digest-times'),
                label: 'Digest time',
                onClose: () => setState(() => _picking = false),
                children: [
                  SheetTitle.text('Digest time'),
                  SheetGroup(
                    children: [
                      for (final (hour, minute) in digestTimes)
                        SheetRow(
                          key: ValueKey('digest-time:$hour:$minute'),
                          label: clockWords(hour, minute),
                          chosen: hour == digest.hour && minute == digest.minute,
                          onPress: () {
                            setState(() => _picking = false);
                            _set((now) => now.copyWith(hour: hour, minute: minute));
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
