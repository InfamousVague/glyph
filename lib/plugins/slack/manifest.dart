/// The Slack plugin's manifest and its host. A port of `src/app/plugins/slack/manifest.ts`.
///
/// What differs:
/// - `secrets` is new: each channel's webhook, which the page handed to Rust (`slack_save_channel`, kept in
///   `slack.json` in the app's own folder), is kept here in the device's secure store under [webhookPrefix] and the
///   channel's id. Nothing of a webhook is ever in `storage`.
/// - **Meetings post by themselves** where a channel is chosen for them (meetings.dart; Matt, 2026-10-26), the
///   port's own: the network permission says so, and two storage keys hold where they go and the posts still to try.
///   The description stays the page's, which the catalogue is measured by.
/// - `native` is kept word for word, since Settings' card reads the permission and its reason from it; none of the
///   four commands exists here (lib/plugins/types.dart), and channels.dart does their work.
library;

import '../host.dart';
import '../types.dart';

/// What a channel's webhook is kept under in the secure store, before the channel's id.
const String webhookPrefix = 'glyph-slack-webhook:';

const PluginManifest manifest = PluginManifest(
  id: 'slack',
  name: 'Slack',
  description: 'Posts a note, or a meeting’s summary, to a Slack channel when you say so, and an organization’s news to its channel.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Post a note to a Slack channel',
  adds: [
    'Post to Slack on a note’s settings, and Post the summary to Slack for a meeting',
    'A meeting’s action items and its links to the channel chosen on its page in Settings, once it is written up',
    'An organization’s news to the channel set for it',
  ],
  // Off until switched on: it sends words off the phone, and only ever when the person has set a channel up for it.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads the note you post, or its summary, to make the message. Nothing in the note changes.'),
    PluginPermission(Permission.network, 'Posts to the channels you add, straight from this device. Only what you choose to post goes: a note you post, each meeting’s action items where you chose a channel for meetings, and an organization’s news where you set a channel for it.'),
    PluginPermission(Permission.native, 'Keeps each channel’s webhook inside the app, where no page can read it back, and posts with it.'),
  ],
  hosts: ['hooks.slack.com'],
  native: PluginNative(generation: 25, commands: ['slack_channels', 'slack_save_channel', 'slack_forget_channel', 'slack_post']),
  // The channels, where each organization's news goes and what went; where meetings go and the posts still to try
  // (meetings.dart).
  storage: ['glyph-slack-channels', 'glyph-slack-news', 'glyph-slack-posted', 'glyph-slack-meetings', 'glyph-slack-meeting-queue'],
  secrets: [webhookPrefix],
);

/// The plugin's one way onto the phone. It reads the ground when it is used (lib/plugins/host.dart), so a test that
/// puts its own ground in place needs no host of its own.
final PluginHost host = createHost(manifest);

/// Why something was refused, in a sentence: the page's `Error`, or the string Rust rejected with.
class SlackFailure implements Exception {
  const SlackFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
