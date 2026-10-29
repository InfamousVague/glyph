/// The Google Meet and Zoom plugins' setups (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the
/// voiceover onboarding for the rest of the plugins"). Neither has anything to sign in to or a key to keep: Ghost is
/// invited by the account's Email to a note address on a calendar invite, or sent in with a link from the plugin's
/// page (meeting_pane.dart), and the service does the rest (docs/MEET.md). So each is a short walk through how, seen
/// once ([setupSeen]):
///
/// - **Google Meet**: what Ghost does in a meeting, then how to invite it.
/// - **Zoom**: the same, with what the host must allow between ([zoomHostRules], the page's own card), since a Zoom's
///   host decides whether a guest from a browser gets in.
library;

import '../../art/app_icon.dart' show LucideIcon;
import '../../art/lucide.g.dart';
import '../onboarding/setup_flow.dart';
import 'meeting_pane.dart' show zoomHostRules;

const List<(LucideIcon, String)> _what = [
  (Lucide.users, 'Ghost joins as a guest, records, and leaves when the meeting ends'),
  (Lucide.squarePen, 'Each meeting filed as a note in your Inbox, written up on your device, with who said what'),
  (Lucide.lock, 'The recording comes back sealed to your account'),
];

/// Google Meet's setup (see the header). [memory] is where it was seen; the device's own where null.
PluginSetup googleMeetSetup({SetupMemory? memory}) => PluginSetup(
      id: 'google-meet',
      name: 'Google Meet',
      hues: const ['orange', 'amber', 'coral'],
      tiles: const [Lucide.users, Lucide.mail, Lucide.squarePen, Lucide.link],
      ready: setupSeen('google-meet', memory),
      watch: setupWatchesNothing,
      about: 'Two short steps: what Ghost does in a meeting, and how to invite it.',
      again: 'The steps from the start: what Ghost does, and how to invite it.',
      steps: const [
        SetupIntro(id: 'intro', title: 'Ghost in your Google Meets', icon: Lucide.users, mark: false, points: _what),
        SetupDone(id: 'done', title: 'Invite Ghost', icon: Lucide.mail),
      ],
    );

/// Zoom's setup (see the header). [memory] is where it was seen; the device's own where null.
PluginSetup zoomSetup({SetupMemory? memory}) => PluginSetup(
      id: 'zoom',
      name: 'Zoom',
      hues: const ['mint', 'cyan', 'blue'],
      tiles: const [Lucide.laptop, Lucide.mail, Lucide.squarePen, Lucide.link],
      ready: setupSeen('zoom', memory),
      watch: setupWatchesNothing,
      about: 'Three short steps: what Ghost does in a call, what the host must allow, and how to invite it.',
      again: 'The steps from the start: what Ghost does, what the host must allow, and how to invite it.',
      steps: [
        const SetupIntro(id: 'intro', title: 'Ghost in your Zoom calls', icon: Lucide.laptop, mark: false, points: _what),
        SetupIntro(id: 'host', title: 'What the host must allow', icon: Lucide.circleCheck, mark: false, points: [for (final (label, hint) in zoomHostRules) (Lucide.check, '$label: $hint')]),
        const SetupDone(id: 'done', title: 'Invite Ghost', icon: Lucide.mail),
      ],
    );

final Map<String, PluginSetup> _made = {};

/// The setup a meeting plugin's page shows the card of, made once: [kind] is `meet` or `zoom`.
PluginSetup meetingSetupOf(String kind) => _made[kind] ??= kind == 'zoom' ? zoomSetup() : googleMeetSetup();
