import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../meet/ui/meet_card.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'settings_host.dart';

/// Whether Settings lists Meetings: an account whose service has Ghost in meetings (docs/MEET.md). Without an Email
/// to a note address the page is there all the same and says where to make one, since that address is what Ghost
/// is invited by.
bool meetingsOffered(AccountServices? services) => services != null && services.signedIn && (services.meetIn?.available ?? false);

/// What the search finds on the page.
const List<SettingsFindable> meetingsFindable = [
  SettingsFindable('Invite Ghost', 'send ghost meet link join now invite calendar guest address copy'),
  SettingsFindable('Ghost in meetings', 'meetings booked recording written up don’t join leave'),
];

/// The row's second line: how many meetings Ghost is booked for or in, or what the page is for.
String meetingsSummary(AccountServices? services) {
  final meetings = services?.meetIn?.meetings;
  final open = meetings?.where((m) => m.state.open).length ?? 0;
  if (open > 0) return open == 1 ? 'Ghost is booked for 1 meeting' : 'Ghost is booked for $open meetings';
  return 'Invite Ghost to a Google Meet';
}

/// Settings › Meetings (Matt, 2026-10-23: "Make the meeting section its own section in settings and move the invite
/// card to the top"): the cards that were Account's Ghost in meetings ([MeetCard]), the invite first. With no
/// address yet, a word on where to turn one on.
class MeetingsPane extends StatelessWidget {
  const MeetingsPane({super.key, required this.services, this.onOpenAccount});

  final AccountServices? services;

  /// Lands on Account, where Email to a note is; without it the word is a plain word.
  final VoidCallback? onOpenAccount;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return MeetingsPane(
      services: AccountScope.maybeOf(context),
      onOpenAccount: host == null ? null : () => host.go('account'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    return AccountBuilder(
      services: services,
      builder: (context) => PaneBody(
        children: [
          if (services != null && meetCardShown(services))
            MeetCard(services: services)
          else
            SettingsCallout(
              action: onOpenAccount == null ? null : RowAction(onPress: onOpenAccount!, child: const Text('Open Account')),
              child: const Text('Ghost is invited by your Email to a note address. Turn it on in Account, then come back here to invite Ghost.'),
            ),
        ],
      ),
    );
  }
}
