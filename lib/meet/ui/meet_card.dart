import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/locale_dates.dart';
import '../../settings/account_forms.dart';
import '../../settings/kit/settings_kit.dart';
import '../meet_api.dart';
import '../meet_in.dart';

/// Ghost in meetings, Settings › Meetings (lib/settings/panes/meetings_pane.dart, lib/meet/meet_in.dart, docs/MEET.md):
/// the mail-to-note address is also the address Ghost is invited by, so the cards are drawn only once there is one
/// ([meetCardShown]). Two cards. First the ways to invite Ghost (Matt, 2026-10-23: "move the invite card to the top"):
/// a Meet link sent now, then the address to put on a Calendar invite, with Copy. Then what Ghost does and where the
/// sound goes, over the meetings Ghost is booked for and was in with where each stands, and a way to tell Ghost not to
/// join one or to leave.
bool meetCardShown(AccountServices services) => services.meetIn != null && services.meetIn!.available && services.mailIn?.address?.address != null;

/// What the card says under itself: where a meeting's sound goes.
const String meetCardFooter = 'The meeting’s sound passes through Ghost.md’s server while it records, sealed to your account as it arrives; it is written up on your device.';

String _two(int n) => n.toString().padLeft(2, '0');

/// When a meeting is, as the card says it: "Today, 14:00", "Tomorrow, 09:30", "18 Oct, 14:00".
String meetWhen(int ms, {required int now}) {
  if (ms <= 0) return 'Now';
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  final today = DateTime.fromMillisecondsSinceEpoch(now);
  final days = DateTime(at.year, at.month, at.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => localeDayMonth(at, DateForm.MMMd),
  };
  return '$day, ${_two(at.hour)}:${_two(at.minute)}';
}

/// The card.
class MeetCard extends StatefulWidget {
  const MeetCard({super.key, required this.services});

  final AccountServices services;

  @override
  State<MeetCard> createState() => _MeetCardState();
}

class _MeetCardState extends State<MeetCard> {
  String? _said;
  String _link = '';
  bool _busy = false;

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy(String address) async {
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (mounted) setState(() => _said = 'The address is copied.');
    } catch (_) {
      if (mounted) setState(() => _said = address);
    }
  }

  Future<void> _send(MeetIn meet) => _run(() async {
        final booked = await meet.sendNow(_link);
        if (!mounted) return;
        setState(() {
          _link = '';
          _said = booked == null ? null : 'Ghost is on its way into the meeting.';
        });
      });

  @override
  Widget build(BuildContext context) {
    final meet = widget.services.meetIn;
    final address = widget.services.mailIn?.address?.address;
    if (meet == null || address == null) return const SizedBox.shrink();
    meet.readSoon();
    return ListenableBuilder(
      listenable: meet,
      builder: (context, _) {
        final now = widget.services.now();
        final meetings = meet.meetings;
        final ready = meetLink(_link) != null && !_busy;
        final invite = PaneSection(
          title: 'Invite Ghost',
          description: const Text('Paste a Google Meet link to send Ghost in now, or add your address as a guest on a Google Calendar invite and Ghost joins by itself.'),
          footer: _said == null ? null : Text(_said!),
          children: [
            SettingsForm(
              children: [
                GlacierInput(
                  ariaLabel: 'Meet link',
                  placeholder: 'meet.google.com/abc-defg-hij',
                  value: _link,
                  onChange: (text) => setState(() => _link = text),
                  onSubmitted: (_) {
                    if (ready) unawaited(_send(meet));
                  },
                ),
                FormSubmit(wordKey: const ValueKey('meet-send'), _busy ? 'One moment…' : 'Send Ghost to a meeting now', onPressed: ready ? () => unawaited(_send(meet)) : null),
              ],
            ),
            SettingRow(
              key: const ValueKey('meet-address'),
              icon: const AppIcon(Lucide.calendarPlus, size: 20),
              // Broken, where a phone's width must break it, after the @ and nowhere in a word.
              label: address.replaceFirst('@', '@​'),
              hint: const Text('Add this address as a guest on a Google Calendar invite.'),
              control: RowAction(onPress: () => unawaited(_copy(address)), child: const Text('Copy')),
            ),
          ],
        );
        final list = PaneSection(
          title: 'Ghost in meetings',
          description: const Text('Ghost joins by itself, records the meeting, and files it as a note, written up with who said what.'),
          footer: const Text(meetCardFooter),
          children: [
            if (meetings == null)
              SettingRow(key: const ValueKey('meet-reading'), icon: const AppIcon(Lucide.clock, size: 20), label: meet.problem ?? 'Reading your meetings…')
            else if (meetings.isEmpty)
              const SettingRow(key: ValueKey('meet-none'), icon: AppIcon(Lucide.ghost, size: 20), label: 'No meetings yet', hint: Text('A meeting Ghost is invited to shows here, with where it stands.'))
            else
              for (final meeting in meetings)
                SettingRow(
                  key: ValueKey('meet-${meeting.id}'),
                  icon: AppIcon(switch (meeting.state) {
                    MeetState.done => Lucide.circleCheck,
                    MeetState.failed => Lucide.circleAlert,
                    MeetState.skipped || MeetState.cancelled => Lucide.ban,
                    MeetState.joining || MeetState.inCall || MeetState.leave => Lucide.ghost,
                    _ => Lucide.calendarDays,
                  }, size: 20),
                  label: meeting.title ?? 'A meeting',
                  hint: Text('${meetWhen(meeting.startsAt, now: now)} · ${meetStateWords(meeting)}'),
                  control: meeting.state.open
                      ? RowAction(
                          disabled: _busy,
                          onPress: () => unawaited(_run(() => meet.skip(meeting.id))),
                          child: Text(meeting.state == MeetState.booked ? 'Don’t join' : 'Leave now'),
                        )
                      : null,
                ),
          ],
        );
        // Two cards with the gap a pane puts between its own (PaneBody).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [invite, SizedBox(height: context.tokens.space(4)), list],
        );
      },
    );
  }
}
