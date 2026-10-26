/// Where every meeting goes, one setting for them all, on Settings › Recording's Meetings card (Matt, 2026-10-26: "All
/// meetings plugins should sort meetings to the same place on the recordings but have different settings"). A meeting
/// Ghost was in on Google Meet, on Zoom or in a Discord call, and one recorded here, is filed, written up, sorted and
/// shelved the same way: the meeting step files each take as a note in the Inbox whatever its kind (lib/meet/
/// meet_in.dart `syncMeet`, `prefs.meetings`), the summary queue writes it up as any meeting (Summaries, Write up
/// straight away), the sorting files it into its workspace's Meetings folder (lib/ai/meeting_sort.dart, which never
/// asks the kind), and the home page's shelf holds every meeting with a tape (lib/home/meeting_shelf.dart). So the
/// settings of that are not any one plugin's, and live once, with the recordings.
///
/// Until that day the two switches here were drawn on the Google Meet page and the Zoom page alike, a copy on each
/// (and on Settings › Meetings before that, GHST-110). They were always one preference each, synced with the account,
/// never one a kind: nothing is moved for anyone, and a choice made on either page reads the same here.
///
/// - **The Meetings card** ([MeetingsCard]), on Settings › Recording: the device's own meeting rows the page hands it
///   (Include sound from other apps, Tell me when a meeting is written up, Write up straight away; the computer's
///   sound on the Mac), then **Sync meeting recordings**, with how many recordings stayed on this phone under the
///   card, for a signed-in account where this device records, and **Sort meetings into workspaces** (on unless
///   turned off; the key is `sortMeetings` in the synced preferences). Kept in Simple: the card is what Simple's
///   Recording page shows first, the rest behind More (lib/settings/panes/recording_pane.dart).
/// - **Where meetings go** ([MeetingsGoSection]), on each meeting plugin's page (Google Meet, Zoom, Discord): one row
///   saying where its meetings go, which opens the Meetings card, lit ([meetingsGoName]).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../ai/meeting_sort.dart' show sortsMeetings, withSortMeetings;
import '../../core/preferences.dart';
import '../../settings/kit/settings_kit.dart';
import '../../sync/notes.dart' show longestSyncedSaid, stayedHere;

/// The Recording page's section id, which the plugin pages' row opens.
const String recordingSectionId = 'recording';

/// The name the Meetings card is found by, and the plugin pages' row's label: a link to it lights the whole card.
const String meetingsGoName = 'Where meetings go';

/// The Meetings card's title on Settings › Recording.
const String meetingsCardTitle = 'Meetings';

/// Where a meeting goes, in a word for the plugin pages' row: into a workspace's Meetings folder while the sorting is
/// on, else the Inbox, where the meeting step files every kind.
String meetingsGoSaid(Preferences prefs) => sortsMeetings(prefs) ? 'Workspaces' : 'Inbox';

/// The Meetings card on Settings › Recording (see the header). [before] are the page's own rows for this device's
/// meetings, first in the card; [signedIn] and [records] decide Sync meeting recordings, which is about the account's
/// devices and is not on an iPhone.
class MeetingsCard extends StatefulWidget {
  const MeetingsCard({super.key, required this.store, this.services, this.before = const [], this.signedIn = false, this.records = true});

  final PreferencesStore store;

  /// The account, for counting the recordings that stayed on this phone; none, and nothing is counted.
  final AccountServices? services;
  final List<Widget> before;
  final bool signedIn;
  final bool records;

  @override
  State<MeetingsCard> createState() => _MeetingsCardState();
}

class _MeetingsCardState extends State<MeetingsCard> {
  int _stayed = 0;
  Object? _stayedFor;

  /// How many recordings stayed on this phone, counted from [AccountServices.listNotes] as the card is put up and
  /// whenever the two rules change (GHST-112, from Account's Sync card).
  void _countStayed(Preferences prefs) {
    final list = widget.services?.listNotes;
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
    final store = widget.store;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        final sync = widget.signedIn && widget.records;
        if (sync) _countStayed(prefs);
        final stayed = sync ? _stayed : 0;
        return SettingsFindableMark(
          name: meetingsGoName,
          child: PaneSection(
            title: meetingsCardTitle,
            description: const Text('The same for every meeting: one recorded here, and one Ghost was in on Google Meet, Zoom or Discord. Each is written up, filed and shelved alike.'),
            footer: stayed == 0
                ? null
                : Text('${stayed == 1 ? '1 recording' : '$stayed recordings'} stayed on this phone: ${prefs.syncMeetingRecordings ? 'longer than the account takes, over $longestSyncedSaid.' : 'meetings, while their recordings stay, and any over $longestSyncedSaid.'}'),
            children: [
              ...widget.before,
              if (sync)
                SettingRow(
                  label: 'Sync meeting recordings',
                  hint: const Text("On, a meeting's audio goes to your other devices, and with a team's note to everyone in the team. A meeting is other people's voices: off, the words sync and the audio stays on the device it was made on."),
                  control: GlacierSwitch(
                    ariaLabel: 'Sync meeting recordings',
                    checked: prefs.syncMeetingRecordings,
                    onCheckedChange: (on) => store.update((now) => now.copyWith(syncMeetingRecordings: on, syncMeetingRecordingsChosen: true)),
                  ),
                ),
              SettingRow(
                label: 'Sort meetings into workspaces',
                hint: const Text("Once a meeting is written up, the AI files it in the Meetings folder of the workspace it's about. Meetings you've filed yourself stay where they are."),
                control: GlacierSwitch(
                  ariaLabel: 'Sort meetings into workspaces',
                  checked: sortsMeetings(prefs),
                  onCheckedChange: (on) => store.update((was) => withSortMeetings(was, on)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Where meetings go, on a meeting plugin's page: one row with the shared place in a word ([meetingsGoSaid]), which
/// opens Settings › Recording at the Meetings card ([onOpen]; without it the row is not pressed).
class MeetingsGoSection extends StatelessWidget {
  const MeetingsGoSection({super.key, required this.prefs, this.onOpen});

  final PreferencesStore prefs;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Preferences>(
      valueListenable: prefs,
      builder: (context, now, _) => PaneSection(
        children: [
          SettingRow(
            key: const ValueKey('meetings-go'),
            label: meetingsGoName,
            hint: const Text('The same for every meeting, whichever plugin it came from: set in Settings › Recording.'),
            value: Text(meetingsGoSaid(now)),
            onPress: onOpen,
          ),
        ],
      ),
    );
  }
}
