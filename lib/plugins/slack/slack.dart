/// The Slack plugin, built in and off until switched on: a note, or a meeting's summary, posted to a Slack channel
/// when the person chooses, and an organization's news to the channel chosen for it. A port of
/// `src/app/plugins/slack/index.tsx`.
///
/// Matt: "include #6 as a plugin as well as #5", where #5 was "Slack: post a meeting's summary, or a note, to a
/// channel when you choose to. It pairs well with organizations: a team's news could go to its channel too. Sending
/// is always your choice, so the encryption holds." Posting is the one moment words leave the encryption, so it is
/// always a press: nothing of a note goes unless "Post to Slack" is pressed on it, and an organization's news only
/// once a channel is set for it. The channels are incoming webhooks, pasted in the plugin's page, kept on this
/// device (channels.dart).
///
/// - On a note's More sheet, once a channel is added: "Post to Slack", the whole note as a message (mrkdwn.dart),
///   and "Post the summary to Slack" on a note with a meeting's summary, that section alone. With more than one
///   channel the row opens them to choose from.
/// - After each pass of the feed: an organization's new news to its channel (news.dart).
/// - Once a meeting is written up: its action items and its links, to the channel chosen on its page's Post to Slack
///   (meetings.dart; Matt, 2026-10-26: "make the meetings plugin work hand in hand to sending meeting action items
///   and a link to the meeting transcript to a specified slack channel").
/// - In Settings: the channels, a test message for each, and where each organization's news goes
///   (slack_pane.dart).
///
/// What differs: the plugin's icon is the kit's by name (`hash`); the buzz after a post is [slackFelt], which a
/// test stills; a failure's words are lib/plugins/details_cache.dart `failureWords`; what the app kept as a note's
/// summary is lib/ai/summary_keep.dart `keptText` through [slackKeptText], so a test or another build of lib/ai can
/// stand in for it.
library;

import 'package:glacier/glacier.dart' show HapticFn, HapticKind, fireMotor;

import '../../ai/summary_keep.dart' show keptText;
import '../../core/summary_text.dart' show summarySection;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../details_cache.dart' show failureWords;
import '../types.dart';
import 'channels.dart';
import 'manifest.dart';
import 'marks.dart';
import 'meetings.dart' show meetingSlackPoster;
import 'mrkdwn.dart';
import 'news.dart';
import 'slack_pane.dart';
import 'slack_setup.dart';

export 'channels.dart';
export 'manifest.dart' show SlackFailure, webhookPrefix;
export 'marks.dart';
export 'meetings.dart';
export 'meetings_section.dart';
export 'mrkdwn.dart';
export 'news.dart';
export 'slack_pane.dart';
export 'slack_setup.dart';

/// The buzz when a post lands (`fireNativeHaptic('success')`).
HapticFn slackFelt = fireMotor;

/// The section the app wrote as a note's summary, word for word, or null (`ai/summaryKeep.ts` `keptText`).
String? Function(String noteId) slackKeptText = keptText;

/// The channels as the More sheet's rows to choose from.
List<ActionChoice> _channelChoices(String noteId) => [for (final c in channels()) ActionChoice(id: c.id, label: c.name)];

/// "#launch", or how many to choose from.
String _where() {
  final list = channels();
  return list.length == 1 ? 'to ${list.first.name}' : 'to one of ${list.length} channels';
}

/// Posts what [message] makes of the note on screen to the channel chosen, then says so on the note, or says why
/// not in Slack's words (channels.dart [slackAnswer]).
Future<void> _post(NoteEditing editing, String? choice, String? Function(String body) message, {void Function()? posted}) async {
  final list = channels();
  final channel = channelById(choice) ?? (list.length == 1 ? list.first : null);
  if (channel == null) {
    editing.say('That Slack channel isn’t on this device any more.');
    return;
  }
  final text = message(editing.body());
  if (text == null || text.isEmpty) {
    editing.say('There is no summary in this note to post.');
    return;
  }
  try {
    await postToChannel(channel, text);
    posted?.call();
    slackFelt(HapticKind.success);
    editing.say('Posted to ${channel.name}.');
  } catch (failure) {
    editing.say('Not posted to ${channel.name}. ${failureWords(failure)}');
  }
}

/// The meeting's summary in the note as it stands, or null (lib/core/summary_text.dart, closed by what the app
/// kept).
String? _summaryOf(String noteId, String body) => summarySection(body, slackKeptText(noteId))?.text;

/// `postNote`.
final NoteAction postNote = NoteAction(
  id: 'slack-post-note',
  label: 'Post to Slack',
  icon: (context, size) => SlackMark(size: size),
  visible: (noteId, body) => slackReadyNow() && channels().isNotEmpty,
  hint: (noteId, body) => hasWords(body) ? 'The whole note goes ${_where()}, as it reads now.' : 'Nothing to post yet.',
  enabled: (noteId, body) => hasWords(body),
  choices: _channelChoices,
  run: (editing, [choice]) => _post(editing, choice, noteMessage),
);

/// `postSummary`.
final NoteAction postSummary = NoteAction(
  id: 'slack-post-summary',
  label: 'Post the summary to Slack',
  icon: (context, size) => SlackMark(size: size),
  visible: (noteId, body) => slackReadyNow() && channels().isNotEmpty && _summaryOf(noteId, body) != null,
  hint: (noteId, body) => 'The meeting’s action items, a brief summary and the link to its notes go ${_where()}.',
  enabled: (noteId, body) => true,
  choices: _channelChoices,
  run: (editing, [choice]) async {
    // A meeting's summary goes as the meeting's own post (lib/plugins/slack/meetings.dart [meetingMessage]): its action
    // items, a brief summary, then the public link (Matt, 2026-10-28), and counts as its one post for the account.
    final poster = meetingSlackPoster;
    final note = poster == null ? null : await poster.getNote(editing.noteId);
    if (poster != null && note != null) {
      final text = await poster.messageFor(note.copyWith(body: editing.body()));
      await _post(editing, choice, (_) => text, posted: () => poster.postedByHand(note.id));
      return;
    }
    await _post(editing, choice, (body) {
      final section = _summaryOf(editing.noteId, body);
      return section == null ? null : summaryMessage(body, section);
    });
  },
);

String _summary() {
  final count = channels().length;
  return count > 0 ? '$count ${count == 1 ? 'channel' : 'channels'}' : 'Channels to post to';
}

final GlyphPlugin slackPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'hash',
  setup: slackSetup,
  settings: PluginSettings(
    pane: (context) => const SlackPane(),
    hue: 'magenta',
    summary: _summary,
    // What Settings' search finds on the page: its cards, by their titles.
    settings: const [SettingsFindable('Channels', 'webhook test message organizations news'), SettingsFindable('Add a channel', 'incoming webhook hooks.slack.com')],
  ),
  noteActions: [postNote, postSummary],
  newRows: (before, rows) async {
    if (before <= 0 || channels().isEmpty) return;
    if (await slackAvailable()) await forwardNews(before, rows);
  },
);
