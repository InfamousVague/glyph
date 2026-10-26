/// The Discord plugin's manifest and its host (Matt, 2026-10-26: "Add a new plugin to post notes to discord chats as
/// well as join discord calls to summarize meetings"). This is the posting half; joining a call is Ghost in
/// meetings' (meet/, server/), and is not here.
///
/// It is the Slack plugin's shape (lib/plugins/slack/manifest.dart) for Discord's own incoming webhooks: no sign-in,
/// nothing on the server, each post straight from the device to `discord.com/api/webhooks/<id>/<token>`.
///
/// - `secrets` is each channel's webhook, kept in the device's secure store under [discordWebhookPrefix] and the
///   channel's id. Nothing of a webhook is ever in `storage`, which holds the channels' names
///   (`glyph-discord-channels`), where meetings go (`glyph-discord-meetings`) and the meetings still to try
///   (`glyph-discord-meeting-queue`).
/// - `hosts` is Discord's two names, which cover `ptb.` and `canary.` under them (lib/plugins/host.dart takes a name
///   under a listed one); channels.dart holds a webhook to Discord's shapes itself, before it is kept and again before
///   it is posted to.
/// - **No `native`.** The Slack plugin's commands were the Tauri app's, and its manifest keeps them word for word
///   for Settings' card; Discord was never in the Tauri app, so it asks the binary for nothing.
library;

import '../host.dart';
import '../types.dart';

/// What a channel's webhook is kept under in the secure store, before the channel's id.
const String discordWebhookPrefix = 'glyph-discord-webhook:';

/// The channels' names and ids (channels.dart).
const String discordChannelsKey = 'glyph-discord-channels';

/// Where meetings go, the switch and the share link (meetings.dart).
const String discordMeetingsKey = 'glyph-discord-meetings';

/// The meetings this device still has to post (meetings.dart).
const String discordMeetingQueueKey = 'glyph-discord-meeting-queue';

const PluginManifest manifest = PluginManifest(
  id: 'discord',
  name: 'Discord',
  description: 'Posts a note, or a meeting’s summary, to a Discord channel when you say so, and each meeting’s action items once it is written up.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Post a note to a Discord channel',
  adds: [
    'Post to Discord on a note’s settings, and Post the summary to Discord for a meeting',
    'A meeting’s action items and its links to the channel chosen in Settings › Meetings, once it is written up',
  ],
  // Off until switched on: it sends words off the phone, and only ever when the person has set a channel up for it.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads the note you post, or its summary, to make the message. Nothing in the note changes.'),
    PluginPermission(Permission.network, 'Posts to the channels you add, straight from this device. Only what you choose to post goes: a note you post, and each meeting’s action items where you chose a channel for meetings.'),
  ],
  hosts: ['discord.com', 'discordapp.com'],
  storage: [discordChannelsKey, discordMeetingsKey, discordMeetingQueueKey],
  secrets: [discordWebhookPrefix],
);

/// The plugin's one way onto the phone. It reads the ground when it is used (lib/plugins/host.dart), so a test that
/// puts its own ground in place needs no host of its own.
final PluginHost host = createHost(manifest);

/// Why something was refused, in a sentence.
class DiscordFailure implements Exception {
  const DiscordFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
