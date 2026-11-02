/// Settings › Notifications › Ticket digest (Matt, 2026-10-31: "Each morning (default 8:30 local, set in Settings ›
/// Notifications or the tickets settings), one notification per person"; lib/book/ticket_digest.dart): on or off, and
/// Write a digest note, off unless turned on. The choices follow the account (the synced settings), so the one device
/// that sends it sends it at the time chosen anywhere. Its time is the morning time since 2026-11-01, a row of its
/// own the reminders share (morning_section.dart; Matt: "see if there are other settings that can be simplified").
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../book/ticket_digest.dart';
import '../../core/preferences.dart';
import '../../reminders/remind_choices.dart' show clockWords;
import '../../reminders/reminder_host.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';

/// What Settings' search finds of it.
const List<SettingsFindable> ticketDigestFindable = [
  SettingsFindable('Ticket digest', 'morning tickets due today overdue blocked digest summary'),
  SettingsFindable('Write a digest note', 'digest note inbox morning tickets'),
];

class TicketDigestSection extends StatefulWidget {
  const TicketDigestSection({super.key, required this.store, this.reminders});

  final PreferencesStore store;

  /// The phone's reminders, where it has them: kept for the callers, the time being the morning time's now.
  final ReminderHost? reminders;

  @override
  State<TicketDigestSection> createState() => _TicketDigestSectionState();
}

class _TicketDigestSectionState extends State<TicketDigestSection> {
  void _set(DigestSettings Function(DigestSettings now) change) => widget.store.update((prefs) => withDigestSettings(prefs, change(digestSettingsOf(prefs))));

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
              footer: Text('Once each morning at $at, the morning time, from one of your devices: the tickets due today, overdue and blocked that are yours, across your notebooks and teams. A morning with none says nothing.'),
              children: [
                SettingRow(
                  key: const ValueKey('digest-on'),
                  label: 'Morning digest',
                  hint: const Text('Tickets assigned to you, and your own that nobody is assigned.'),
                  control: GlacierSwitch(ariaLabel: 'Morning digest', checked: digest.on, onCheckedChange: (on) => _set((now) => now.copyWith(on: on))),
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
          ],
        );
      },
    );
  }
}
