import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../core/iphone_app.dart' show recordsVoice;
import '../../core/preferences.dart';
import '../../mail/ui/mail_card.dart';
import '../../meet/ui/meet_card.dart';
import '../../sync/notes.dart' show longestSyncedSaid, stayedHere;
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'settings_host.dart';

/// Whether Settings lists Meetings: an account whose service has Ghost in meetings (docs/MEET.md). Without an Email
/// to a note address the page is there all the same and turns one on, since that address is what Ghost is invited by.
bool meetingsOffered(AccountServices? services) => services != null && services.signedIn && (services.meetIn?.available ?? false);

/// What the search finds on the page, by the names it draws: the two meeting cards once there is an address to
/// invite Ghost by, Email to a note where the service takes mail, and the recordings' switch where this device
/// records (not an iPhone, [recordsVoice]).
List<SettingsFindable> meetingsFindable(AccountServices? services) {
  final mail = services?.mailIn;
  return [
    if (services != null && meetCardShown(services)) ...const [
      SettingsFindable('Invite Ghost', 'send ghost meet link join now invite calendar guest address copy new refresh regenerate'),
      SettingsFindable('Ghost in meetings', 'meetings booked recording written up don’t join leave open note'),
    ],
    if (mail != null && mailCardShown(mail)) const SettingsFindable('Email to a note', 'mail inbox address turn off'),
    if (recordsVoice) const SettingsFindable('Sync meeting recordings', 'audio meeting meetings tapes'),
  ];
}

/// The row's second line: how many meetings Ghost is booked for or in, or what the page is for.
String meetingsSummary(AccountServices? services) {
  final meetings = services?.meetIn?.meetings;
  final open = meetings?.where((m) => m.state.open).length ?? 0;
  if (open > 0) return open == 1 ? 'Ghost is booked for 1 meeting' : 'Ghost is booked for $open meetings';
  return 'Invite Ghost to a Google Meet';
}

/// Settings › Meetings (Matt, 2026-10-23: "Make the meeting section its own section in settings and move the invite
/// card to the top"): the cards that were Account's Ghost in meetings ([MeetCard]), the invite first; then
/// everything else that is about meetings, which was Account's until Matt, 2026-10-24: "remove the meetings stuff
/// from the account page the account settings page is overwhelming move all google meet related stuff to under the
/// meet section":
///
/// - **Email to a note** ([MailCard] with `addressAbove`): the address is Ghost's invite as much as mail's, so it is
///   kept in one place, the invite card, with Copy and a new one, and this card says what a mail becomes and turns
///   the address off. With no address yet, this card is where one is turned on, and the invite card waits for it.
/// - **Recordings** ([MeetingRecordings]): Sync meeting recordings, and how many recordings stayed on this phone.
///
/// A meeting that became a note opens it ([onOpenNote], the host's: Settings shuts and the note opens).
class MeetingsPane extends StatelessWidget {
  const MeetingsPane({super.key, required this.services, this.onOpenNote});

  final AccountServices? services;

  /// Opens a meeting's note; without it the meetings are not pressed.
  final void Function(String id)? onOpenNote;

  static Widget hosted(BuildContext context) => MeetingsPane(services: AccountScope.maybeOf(context), onOpenNote: SettingsHost.maybeOf(context)?.onOpenNote);

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    final mail = services?.mailIn;
    return AccountBuilder(
      services: services,
      builder: (context) => PaneBody(
        children: [
          if (services != null && meetCardShown(services))
            MeetCard(services: services, onOpenNote: onOpenNote)
          else
            SettingsCallout(
              child: Text(mail != null && mailCardShown(mail)
                  ? 'Ghost is invited by your Email to a note address. Turn one on below, then invite Ghost here.'
                  : 'Ghost is invited by an Email to a note address, which this service does not take yet.'),
            ),
          if (services != null && mail != null && mailCardShown(mail)) MailCard(services: services, addressAbove: true),
          if (services != null && recordsVoice) MeetingRecordings(services: services),
        ],
      ),
    );
  }
}

/// The recordings of meetings, from Account's Sync card (GHST-112): whether a meeting's audio syncs, and how many
/// recordings stayed on this phone, counted from [AccountServices.listNotes] as the page opens and whenever the two
/// rules change (none without it). Not on an iPhone, which records nothing ([recordsVoice]).
class MeetingRecordings extends StatefulWidget {
  const MeetingRecordings({super.key, required this.services});

  final AccountServices services;

  @override
  State<MeetingRecordings> createState() => _MeetingRecordingsState();
}

class _MeetingRecordingsState extends State<MeetingRecordings> {
  int _stayed = 0;
  Object? _stayedFor;

  void _countStayed(Preferences prefs) {
    final list = widget.services.listNotes;
    final rules = (prefs.meetings, prefs.syncMeetingRecordings);
    if (list == null || rules == _stayedFor) return;
    _stayedFor = rules;
    unawaited(() async {
      try {
        final count = stayedHere(await list(), meetings: prefs.meetings, syncMeetingRecordings: prefs.syncMeetingRecordings);
        if (mounted && rules == _stayedFor) setState(() => _stayed = count);
      } catch (_) {
        // The footer says nothing of them.
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.services.prefs;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        _countStayed(prefs);
        final stayed = _stayed;
        return PaneSection(
          title: 'Recordings',
          footer: stayed == 0
              ? null
              : Text('${stayed == 1 ? '1 recording' : '$stayed recordings'} stayed on this phone: ${prefs.syncMeetingRecordings ? 'longer than the account takes, over $longestSyncedSaid.' : 'meetings, while their recordings stay, and any over $longestSyncedSaid.'}'),
          children: [
            SettingRow(
              label: 'Sync meeting recordings',
              hint: const Text("On, a meeting's audio goes to your other devices, and with a team's note to everyone in the team. A meeting is other people's voices: off, the words sync and the audio stays on the device it was made on."),
              control: GlacierSwitch(
                ariaLabel: 'Sync meeting recordings',
                checked: prefs.syncMeetingRecordings,
                onCheckedChange: (on) => store.update((now) => now.copyWith(syncMeetingRecordings: on, syncMeetingRecordingsChosen: true)),
              ),
            ),
          ],
        );
      },
    );
  }
}
