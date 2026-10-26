/// The Discord plugin, built in and off until switched on: a note, or a meeting's summary, posted to a Discord channel
/// when the person chooses, and each meeting's action items once it is written up (Matt, 2026-10-26: "Add a new
/// plugin to post notes to discord chats as well as join discord calls to summarize meetings"). The posting half;
/// Ghost joining a Discord call is meet/'s and server/'s, not this plugin's.
///
/// It is the Slack plugin (lib/plugins/slack/slack.dart) for Discord, and keeps its rule: posting is the one moment
/// words leave the encryption, so it is always a press, or a meeting set up on its page to go. The
/// channels are incoming webhooks, pasted on the plugin's page and kept in the secure store (channels.dart).
///
/// - On a note's More sheet, once a channel is added: **Post to Discord**, the whole note as a message
///   (markdown.dart), and **Post the summary to Discord** on a note with a meeting's summary, that section alone.
///   With more than one channel the row opens them to choose from. A note longer than one message (2000 characters)
///   is cut at a line, with a share link to the rest, made by the app's own share ([discordShareLink]); the row says
///   so before it is pressed, since the share is the whole note readable by whoever the link reaches. Signed out, or
///   with no share to make, the cut says the rest is in Ghost.md.
/// - Once a meeting is written up: its action items and its links, to the channel chosen on its page's Post to Discord
///   (meetings.dart), beside Slack's.
/// - In Settings: the channels, a test message for each, and where meetings go (discord_pane.dart).
///
/// What it leaves out of Slack's: an organization's news. Matt asked for notes and meetings; the news would be one
/// more thing every device with a channel set posts (slack/news.dart), and can follow if he wants it.
///
/// Not on an iPhone, as Slack is not (lib/core/iphone_app.dart): the rows are not drawn there, and a post says so.
library;

import 'package:glacier/glacier.dart' show HapticFn, HapticKind, fireMotor;

import '../../ai/summary_keep.dart' show keptText;
import '../../core/iphone_app.dart' show notOnIPhone;
import '../../core/summary_text.dart' show summarySection;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../details_cache.dart' show failureWords;
import '../types.dart';
import 'channels.dart';
import 'discord_pane.dart';
import 'manifest.dart';
import 'marks.dart';
import 'markdown.dart';

export 'channels.dart';
export 'discord_pane.dart';
export 'manifest.dart' show DiscordFailure, discordWebhookPrefix;
export 'marks.dart';
export 'markdown.dart';
export 'meetings.dart';
export 'meetings_section.dart';

/// The buzz when a post lands.
HapticFn discordFelt = fireMotor;

/// The section the app wrote as a note's summary, word for word, or null (lib/ai/summary_keep.dart `keptText`).
String? Function(String noteId) discordKeptText = keptText;

/// The note's share link, made (or found again) by the app's own share, for a note too long for one message: the
/// root's `Shares.shareNote` over the note by its id. Null where there is no share to make (no account, a test).
Future<String> Function(String noteId)? discordShareLink;

/// Whether [discordShareLink] can make a link now (an account signed in), for what a row says before it is pressed.
bool Function() discordCanShare = () => discordShareLink != null;

/// The channels as the More sheet's rows to choose from.
List<ActionChoice> _channelChoices(String noteId) => [for (final c in discordChannels()) ActionChoice(id: c.id, label: c.name)];

/// "#launch", or how many to choose from.
String _where() {
  final list = discordChannels();
  return list.length == 1 ? 'to ${list.first.name}' : 'to one of ${list.length} channels';
}

bool _here() => notOnIPhone('discord') == null && discordChannels().isNotEmpty;

/// What the row says of a message of [text]: whole, or cut with a link to the rest.
String _goes(String text, String whole) {
  if (!discordTooLong(text)) return whole;
  final rest = discordShareLink == null || !discordCanShare() ? 'saying the rest is in Ghost.md' : 'with a share link to the rest of the note, which anyone with the link can read';
  return 'It is longer than one Discord message: the first part goes ${_where()}, $rest.';
}

/// Posts what [message] makes of the note on screen to the channel chosen, then says so on the note, or says why
/// not in Discord's words (channels.dart [discordAnswer]). A message too long for one post is cut with the note's
/// share link, where one can be made.
Future<void> _post(NoteEditing editing, String? choice, String? Function(String body) message) async {
  final list = discordChannels();
  final channel = discordChannelById(choice) ?? (list.length == 1 ? list.first : null);
  if (channel == null) {
    editing.say('That Discord channel isn’t on this device any more.');
    return;
  }
  final text = message(editing.body());
  if (text == null || text.isEmpty) {
    editing.say('There is no summary in this note to post.');
    return;
  }
  String? rest;
  final share = discordShareLink;
  if (discordTooLong(text) && share != null && discordCanShare()) {
    try {
      rest = await share(editing.noteId);
    } catch (_) {
      // Signed out, or offline: cut with the word that the rest is in Ghost.md.
      rest = null;
    }
  }
  try {
    await postToDiscord(channel, discordFitted(text, rest: rest));
    discordFelt(HapticKind.success);
    editing.say('Posted to ${channel.name}.');
  } catch (failure) {
    editing.say('Not posted to ${channel.name}. ${failureWords(failure)}');
  }
}

/// The meeting's summary in the note as it stands, or null.
String? _summaryOf(String noteId, String body) => summarySection(body, discordKeptText(noteId))?.text;

final NoteAction postNoteToDiscord = NoteAction(
  id: 'discord-post-note',
  label: 'Post to Discord',
  icon: (context, size) => DiscordMark(size: size),
  visible: (noteId, body) => _here(),
  hint: (noteId, body) => discordHasWords(body) ? _goes(discordNoteText(body), 'The whole note goes ${_where()}, as it reads now.') : 'Nothing to post yet.',
  enabled: (noteId, body) => discordHasWords(body),
  choices: _channelChoices,
  run: (editing, [choice]) => _post(editing, choice, discordNoteText),
);

final NoteAction postSummaryToDiscord = NoteAction(
  id: 'discord-post-summary',
  label: 'Post the summary to Discord',
  icon: (context, size) => DiscordMark(size: size),
  visible: (noteId, body) => _here() && _summaryOf(noteId, body) != null,
  hint: (noteId, body) {
    final section = _summaryOf(noteId, body);
    final whole = 'The meeting’s summary goes ${_where()}, and nothing else of the note.';
    return section == null ? whole : _goes(discordSummaryText(body, section), whole);
  },
  enabled: (noteId, body) => true,
  choices: _channelChoices,
  run: (editing, [choice]) => _post(editing, choice, (body) {
    final section = _summaryOf(editing.noteId, body);
    return section == null ? null : discordSummaryText(body, section);
  }),
);

String _summary() {
  final count = discordChannels().length;
  return count > 0 ? '$count ${count == 1 ? 'channel' : 'channels'}' : 'Channels to post to';
}

/// What Settings' search finds on the plugin's page: its cards, by their titles.
const List<SettingsFindable> discordFindable = [
  SettingsFindable('Channels', 'discord webhook test message server'),
  SettingsFindable('Add a channel', 'incoming webhook discord.com integrations'),
];

final GlyphPlugin discordPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'message-square',
  settings: PluginSettings(pane: (context) => const DiscordPane(), hue: 'indigo', summary: _summary, settings: discordFindable),
  noteActions: [postNoteToDiscord, postSummaryToDiscord],
);
