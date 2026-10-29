/// Ghost in meetings as plugins: **Google Meet** and **Zoom**, each a plugin of its own with its switch, its listing in
/// the Market and its page in Settings (Matt, 2026-10-26: "Make sure the Google Meet and the Zoom plugins are two
/// different plugins", and the same day: "I want settings / meetings to be broken up into three plugins where each
/// zoom, Google meets and discord handle their own meetings"). Settings › Meetings, the one page every kind shared,
/// is gone: each plugin's page is its own kind's meetings (meeting_pane.dart), and the Discord plugin's has Discord's
/// calls (lib/plugins/discord/).
///
/// What a switch governs:
///
/// - **Here**: the plugin's page is listed, and Join takes its kind ([MeetIn.sendNow] refuses a kind whose plugin is
///   off, "Turn on the Zoom plugin to send Ghost to Zoom calls.").
/// - **On the service**: invites are booked there from mail, so the account keeps which kinds it wants
///   (`PUT /api/v1/meet/kinds`; server/src/meet.rs, "TWO PLUGINS, ONE ADDRESS"). The device sends it when a switch
///   moves and, until the service has it, at each sync (lib/meet/meet_kinds.dart). An invite of a kind turned off
///   books nothing, and the mail's note ends "Ghost wasn't booked: the Zoom plugin is off."; what was booked of it is
///   skipped, and booked again when it is turned back on.
/// - **On the account's other devices**: the switch travels sealed as Claude's and Slack's do
///   (lib/sync/connections.dart `syncedSwitches`).
///
/// Both ship ON: Google Meet is what every account with Ghost in meetings had before it was a plugin, and Zoom is what
/// Matt asked for the same day. With both off, nothing of meetings is in Settings; the meetings already filed are
/// notes, and stay on the home page's shelf.
///
/// The icons are Lucide's, not the services' marks (docs/store/, "no third-party brands"), as Slack's hash and
/// Discord's speech bubble are: a group of people for Google Meet (`users`), and a laptop for Zoom (`laptop`), Ghost
/// joining from a browser. The set has no camera to draw.
///
/// Each has a short setup (meeting_setup.dart): what Ghost does, and how to invite it, seen once as the plugin is added
/// and from the head of its page.
///
/// Not on an iPhone, where Ghost in meetings is not offered (lib/share/sites.dart `publishingOffered`): the page is not
/// listed there ([PluginSettings.offered]).
library;

import '../../account/ui_state.dart';
import '../../meet/meet_api.dart' show MeetBooking;
import '../../meet/meet_kinds.dart';
import '../../meet/ui/meet_card.dart' show meetCardShown;
import '../../meet/ui/meeting_settings.dart' show meetingsGoName;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../types.dart';
import 'meeting_pane.dart';
import 'meeting_setup.dart';

export 'meeting_pane.dart';
export 'meeting_setup.dart';

/// Whether a meeting plugin's page is listed: an account whose service has Ghost in meetings (docs/MEET.md). Without
/// an Email to a note address the page is there all the same and says where one is turned on, since that address is
/// what Ghost is invited by. What Settings › Meetings' `meetingsOffered` was.
bool meetingPluginOffered(AccountServices? services) => services != null && services.signedIn && (services.meetIn?.available ?? false);

/// The page's row: how many meetings of [kind] Ghost is booked for or in, or what the page is for.
String meetingPluginSummary(String kind, AccountServices? services) {
  final open = services?.meetIn?.meetings?.where((MeetBooking m) => m.kind == kind && m.state.open).length ?? 0;
  if (open > 0) return open == 1 ? 'Ghost is booked for 1 meeting' : 'Ghost is booked for $open meetings';
  return kind == 'zoom' ? 'Invite Ghost to a Zoom call' : 'Invite Ghost to a Google Meet';
}

/// What the search finds on a meeting plugin's page, by the names it draws: the invite card once there is an address
/// to invite Ghost by, the meetings, what a Zoom's host must allow, and Where meetings go. Sync meeting recordings and
/// Sort meetings into workspaces are found on Settings › Recording, the one place for every kind
/// (lib/meet/ui/meeting_settings.dart).
List<SettingsFindable> meetingPluginFindable(String kind, AccountServices? services) {
  final words = kind == 'zoom' ? 'zoom us link' : 'meet google link';
  return [
    if (services != null && meetCardShown(services)) SettingsFindable('Invite Ghost', 'send ghost $words join now invite calendar guest address copy new refresh regenerate name'),
    if (services != null) SettingsFindable('Ghost in ${meetKindWords(kind)}', 'meetings booked recording written up don’t join leave open note check now recurring'),
    if (kind == 'zoom') const SettingsFindable(zoomHostAllows, 'zoom guests authenticated browser passcode waiting room captions host'),
    if (services != null) const SettingsFindable(meetingsGoName, 'recordings sort sorting folder workspace inbox filed summaries'),
  ];
}

const List<PluginPermission> _permissions = [
  PluginPermission(Permission.notes, 'Files each meeting Ghost was in as a note in your Inbox, and opens it from the meeting’s row.'),
  PluginPermission(
    Permission.network,
    'Ghost.md’s server books Ghost into the meetings you invite it to and joins them from there. Each recording comes back sealed to your account and is written up on your device.',
  ),
];

/// Google Meet's manifest.
const PluginManifest googleMeetManifest = PluginManifest(
  id: 'google-meet',
  name: 'Google Meet',
  description:
      'Ghost joins your Google Meet meetings, records them, and files each as a note written up on your device, with who said what. Invite it with your address on a calendar invite, or send it in with a link.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Send Ghost to take notes in a Google Meet',
  adds: [
    'Its page in Settings: invite Ghost by a Meet link or by your address, and the Meet meetings it is booked for and was in',
    'Each meeting Ghost was in filed as a note, written up on your device',
  ],
  // On: Ghost in a Google Meet is what every account with it had before it was a plugin.
  standard: true,
  permissions: _permissions,
  hosts: ['ghostmarkdown.com'],
  storage: [],
);

/// Zoom's manifest.
const PluginManifest zoomManifest = PluginManifest(
  id: 'zoom',
  name: 'Zoom',
  description:
      'Ghost joins your Zoom calls as a guest from its browser, records them, and files each as a note written up on your device, with who said what. Invite it with your address on a calendar invite, or send it in with a link.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Send Ghost to take notes in a Zoom call',
  adds: [
    'Its page in Settings: invite Ghost by a Zoom link or by your address, the Zoom calls it is booked for and was in, and what a host must allow',
    'Each call Ghost was in filed as a note, written up on your device',
  ],
  // On as well (Matt asked for Zoom on 2026-10-26); off, an invite on Zoom books nothing.
  standard: true,
  permissions: _permissions,
  hosts: ['ghostmarkdown.com'],
  storage: [],
);

/// A meeting plugin's page in Settings, kept in Simple as Settings › Meetings was.
PluginSettings _settingsFor(String kind, String hue) => PluginSettings(
      pane: (context) => MeetingPluginPane.hosted(context, kind),
      summary: () => meetingPluginSummary(kind, null),
      hue: hue,
      simple: true,
      offered: meetingPluginOffered,
      accountSummary: (services) => meetingPluginSummary(kind, services),
      findable: (services) => meetingPluginFindable(kind, services),
    );

final GlyphPlugin googleMeetPlugin = GlyphPlugin(manifest: googleMeetManifest, icon: 'users', settings: _settingsFor('meet', 'orange'), setup: googleMeetSetup);

final GlyphPlugin zoomPlugin = GlyphPlugin(manifest: zoomManifest, icon: 'laptop', settings: _settingsFor('zoom', 'mint'), setup: zoomSetup);
