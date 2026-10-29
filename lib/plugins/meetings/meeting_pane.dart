/// A meeting plugin's page in Settings (meetings.dart): Settings › Meetings broken up, one page a kind (Matt,
/// 2026-10-26: "I want settings / meetings to be broken up into three plugins where each zoom, Google meets and discord
/// handle their own meetings"). On the Google Meet page and the Zoom page alike, in this order:
///
/// - The setup's card (meeting_setup.dart): Set up until it has been seen, Run setup again after.
/// - **Invite Ghost** ([MeetInviteCard]): Join, for a link of the page's kind alone, and the address to put on a
///   calendar invite, with Copy, a name of one's own and a new address. One address for every kind, said on the card
///   ("The same address works for Meet and Zoom invites."), so a change on either page is the other's too. With no
///   address yet the card waits, and a word says where Email to a note is turned on: Settings › Account, whose card it
///   is again now that no page of meetings holds it.
/// - **Recurring** and **Ghost in Google Meet** / **Ghost in Zoom** ([MeetingsList]): the meetings of the page's kind
///   alone, those to come, the series, the history in pages, Check now; a meeting that became a note opens it
///   ([onOpenNote], the host's: Settings shuts and the note opens).
/// - On the Zoom page, **What the host must allow** (docs/MEET.md, "What the host must allow"): Ghost joins a Zoom as
///   a guest from its browser, so the host's settings decide whether it gets in.
/// - **Where meetings go** ([MeetingsGoSection]): one row, the place every kind's meetings go in a word, which opens
///   Settings › Recording at its Meetings card. Recordings (Sync meeting recordings) and Sorting (Sort meetings into
///   workspaces) were a copy on this page and Zoom's until Matt, 2026-10-26: "All meetings plugins should sort
///   meetings to the same place on the recordings but have different settings"; they are that card's now, once
///   (lib/meet/ui/meeting_settings.dart), and the page keeps what is its kind's own.
///
/// Post to Slack and Post to Discord, which were Settings › Meetings' too, are on the Slack and Discord plugins' own
/// pages now (lib/plugins/slack/slack_pane.dart, discord/discord_pane.dart).
library;

import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../mail/ui/mail_card.dart' show mailCardShown;
import '../../meet/ui/meet_card.dart';
import '../../meet/ui/meeting_settings.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/settings_host.dart';
import '../onboarding/setup_card.dart';
import 'meeting_setup.dart';

/// What the Zoom page's card on the host is called, and found by.
const String zoomHostAllows = 'What the host must allow';

/// The Zoom page's card on the host's settings, a row each (docs/MEET.md, "What the host must allow").
const List<(String, String)> zoomHostRules = [
  ('Guests', 'Only authenticated users can join turned off, or Ghost meets a sign-in wall.'),
  ('Joining from the browser', 'Show a Join from your browser link turned on. An admin may lock it.'),
  ('The passcode in the link', 'Embed passcode in invite link, Zoom’s default. Without it Ghost has no passcode to type.'),
  ('The waiting room', 'Someone lets Ghost (notetaker) in within 10 minutes.'),
  ('Captions', 'Automated captions on and shown to participants, so the note says who said what. Without them, sound only.'),
];

/// The page for meetings of [kind] (`meet`, `zoom`).
class MeetingPluginPane extends StatelessWidget {
  const MeetingPluginPane({super.key, required this.services, required this.kind, this.onOpenNote, this.onOpenAccount, this.onOpenRecording});

  final AccountServices? services;
  final String kind;

  /// Opens a meeting's note; without it the meetings are not pressed.
  final void Function(String id)? onOpenNote;

  /// Settings › Account, at Email to a note, for an account with no address yet.
  final VoidCallback? onOpenAccount;

  /// Settings › Recording, at the Meetings card every kind shares ([MeetingsGoSection]).
  final VoidCallback? onOpenRecording;

  static Widget hosted(BuildContext context, String kind) {
    final host = SettingsHost.maybeOf(context);
    return MeetingPluginPane(
      services: AccountScope.maybeOf(context),
      kind: kind,
      onOpenNote: host?.onOpenNote,
      onOpenAccount: host == null ? null : () => host.go('account', setting: 'Email to a note'),
      onOpenRecording: host == null ? null : () => host.go(recordingSectionId, setting: meetingsGoName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    final mail = services?.mailIn;
    return AccountBuilder(
      services: services,
      builder: (context) => PaneBody(
        children: [
          PluginSetupCard(key: ValueKey('meeting-setup-$kind'), setup: meetingSetupOf(kind)),
          if (services != null && meetCardShown(services))
            MeetInviteCard(services: services, kind: kind)
          else
            SettingsCallout(
              action: onOpenAccount == null || mail == null || !mailCardShown(mail) ? null : RowAction(onPress: onOpenAccount!, child: const Text('Account')),
              child: Text(mail != null && mailCardShown(mail)
                  ? 'Ghost is invited by your Email to a note address. Turn one on in Settings › Account, then invite Ghost here.'
                  : 'Ghost is invited by an Email to a note address, which this service does not take yet.'),
            ),
          if (services != null) MeetingsList(services: services, kind: kind, onOpenNote: onOpenNote),
          if (kind == 'zoom')
            PaneSection(
              title: zoomHostAllows,
              description: const Text('Ghost joins a Zoom as a guest, from its browser, never signed in to Zoom. Whether it gets in is up to the host’s settings.'),
              children: [
                for (final (label, hint) in zoomHostRules) SettingRow(icon: const AppIcon(Lucide.check, size: 20), label: label, hint: Text(hint)),
              ],
            ),
          if (services != null) MeetingsGoSection(prefs: services.prefs, onOpen: onOpenRecording),
        ],
      ),
    );
  }
}
