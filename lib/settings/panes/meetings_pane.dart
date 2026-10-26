import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../ai/meeting_sort.dart' show sortsMeetings, withSortMeetings;
import '../../core/iphone_app.dart' show recordsVoice;
import '../../core/preferences.dart';
import '../../mail/ui/mail_card.dart';
import '../../meet/ui/meet_card.dart';
import '../../plugins/discord/meetings.dart' show meetingDiscordOffered;
import '../../plugins/discord/meetings_section.dart';
import '../../plugins/slack/meetings.dart' show meetingSlackOffered;
import '../../plugins/slack/meetings_section.dart';
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
    if (services != null) const SettingsFindable('Sort meetings into workspaces', 'ai file folder organize sort meetings workspace automatic inbox'),
    if (services != null && meetingSlackOffered()) const SettingsFindable('Post to Slack', 'slack channel action items share link transcript automatic post meetings'),
    if (services != null && meetingDiscordOffered()) const SettingsFindable('Post to Discord', 'discord channel action items share link transcript automatic post meetings'),
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
/// - **Sorting** ([MeetingSorting]): whether a meeting written up is filed into its workspace's Meetings folder by
///   the AI (lib/ai/meeting_sort.dart; Matt, 2026-10-24), on unless turned off here. In Simple too.
/// - **Post to Slack** ([MeetingsSlackSection]): each meeting's action items and its links posted to a Slack channel
///   once it is written up (lib/plugins/slack/meetings.dart; Matt, 2026-10-26: "make the meetings plugin work hand
///   in hand to sending meeting action items and a link to the meeting transcript to a specified slack channel"),
///   drawn only where the Slack plugin is on with a channel on this device. In Simple its switch, the rest behind
///   More.
/// - **Post to Discord** ([MeetingsDiscordSection]): the same for a Discord channel (lib/plugins/discord/meetings.dart;
///   Matt, 2026-10-26: "Add a new plugin to post notes to discord chats"), a section of its own under Slack's, drawn
///   only where the Discord plugin is on with a channel on this device. A meeting can go to both.
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
          if (services != null) MeetingSorting(prefs: services.prefs),
          // Asked here as well as in the section, which draws nothing where meetings cannot post: an empty child would
          // still take a gap of the page's.
          if (services != null && meetingSlackOffered()) MeetingsSlackSection(prefs: services.prefs),
          if (services != null && meetingDiscordOffered()) MeetingsDiscordSection(prefs: services.prefs),
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

/// Sort meetings into workspaces (lib/ai/meeting_sort.dart): a meeting written up is filed by the AI into the
/// Meetings folder of the workspace it is about, an organization's included. On unless turned off; the key is
/// `sortMeetings` in the synced preferences.
class MeetingSorting extends StatelessWidget {
  const MeetingSorting({super.key, required this.prefs});

  final PreferencesStore prefs;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Preferences>(
      valueListenable: prefs,
      builder: (context, now, _) => PaneSection(
        title: 'Sorting',
        children: [
          SettingRow(
            label: 'Sort meetings into workspaces',
            hint: const Text("Once a meeting is written up, the AI files it in the Meetings folder of the workspace it's about. Meetings you've filed yourself stay where they are."),
            control: GlacierSwitch(
              ariaLabel: 'Sort meetings into workspaces',
              checked: sortsMeetings(now),
              onCheckedChange: (on) => prefs.update((was) => withSortMeetings(was, on)),
            ),
          ),
        ],
      ),
    );
  }
}
