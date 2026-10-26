/// What every meeting plugin's page has besides its own meetings (lib/plugins/meetings/meeting_pane.dart): the two
/// settings that are about meetings of every kind, which were Settings › Meetings' until it became the plugins' pages
/// (Matt, 2026-10-26: "I want settings / meetings to be broken up into three plugins where each zoom, Google meets and
/// discord handle their own meetings"). Each is one setting, synced as it was, so it reads and changes the same on the
/// Google Meet page and the Zoom page; and a page of the Discord plugin's calls can draw them too.
///
/// - **Recordings** ([MeetingRecordings]): Sync meeting recordings, and how many recordings stayed on this phone.
/// - **Sorting** ([MeetingSorting]): whether a meeting written up is filed into its workspace's Meetings folder by
///   the AI (lib/ai/meeting_sort.dart; Matt, 2026-10-24), on unless turned off. In Simple too.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../ai/meeting_sort.dart' show sortsMeetings, withSortMeetings;
import '../../core/preferences.dart';
import '../../settings/kit/settings_kit.dart';
import '../../sync/notes.dart' show longestSyncedSaid, stayedHere;

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
