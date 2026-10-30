/// A meeting's action items posted to a Discord channel as soon as it is written up: Settings › Meetings' Post to
/// Slack (lib/plugins/slack/meetings.dart; Matt, 2026-10-26: "make the meetings plugin work hand in hand to sending
/// meeting action items and a link to the meeting transcript to a specified slack channel"), for Discord (the same
/// day: "Add a new plugin to post notes to discord chats").
///
/// What a summary holds is read as the Slack post reads it ([meetingPostOf], [MeetingAction], [MeetingPost] are
/// slack/meetings.dart's), so the two posts list the same items, decisions and sentence from the same summary. What
/// goes ([discordMeetingMessage]) is the same as Slack's, in Discord's Markdown:
///
/// - When it began is Discord's timestamp, `<t:<unix seconds>:f>`: each reader sees it in their own time zone and
///   language, where Slack's has `<!date^…>`. A due day stays the phone's words ("Sat, Oct 31"): it is a day, not a
///   moment, and a timestamp would move it across midnight for someone west of here.
/// - **The links.** The share link, where "Include a share link" is on, is `[Read the notes and transcript](https://…)`.
///   The app's own link is not a link: Discord links only `http` and `https` addresses, a `[words](ghostmd://…)`
///   is drawn as the brackets and the address as written, in its desktop, web and phone clients, and a bare
///   `ghostmd://` is not linked either. So it goes as code on a small-print line ([discordAppLine]), which whoever
///   has the note can copy into a browser's bar or the phone; the share link is the one to press.
/// - **It fits in one message**, 2000 characters, links kept: past that the decisions go first, then action items
///   from the end, with "and 3 more in Ghost.md" in their place.
///
/// The rules are Slack's, each a test (test/plugins/discord/meetings_test.dart):
///
/// - **Only where it is set up.** The plugin on, a channel on this device, one chosen for meetings and the switch on;
///   never on an iPhone (lib/core/iphone_app.dart `notOnIPhone`). The choice ([discordMeetingSettings],
///   `glyph-discord-meetings`) follows the account (lib/sync/connections.dart), so whichever device writes a meeting
///   up has the channel and the switch.
/// - **Once per meeting, for the account, on its own mark.** Before the first try the meeting is marked in the
///   synced preferences under [discordMeetingPostsKey], merged an entry at a time (lib/sync/prefs.dart): a summary
///   made again, here or on another device, posts nothing more to Discord. Slack's mark is its own: a meeting posted
///   to both is marked twice, and one that reached Slack still goes to Discord.
/// - **Tried again, a few times**, in this device's queue (`glyph-discord-meeting-queue`) with Discord's reason, at
///   the next run of the app ([MeetingDiscordPoster.resume]) or on "Try now", up to [meetingPostTriesMost] tries,
///   each counted as it begins. A 429 with a long wait is one of these; a short one is waited inside the post
///   (channels.dart).
/// - **The share link is the app's own share** ([MeetingDiscordPoster.shareLink], the root's `Shares.shareNote`), as
///   Slack's is: one share, whichever chat it is posted to.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/summary_keep.dart' show keptText;
import '../../core/background_jobs.dart';
import '../../core/iphone_app.dart' show notOnIPhone;
import '../../core/locale_dates.dart' show DateForm, localeDate;
import '../../core/note.dart' show Note;
import '../../core/note_text.dart' show noteTitle;
import '../../core/preferences.dart' show Preferences;
import '../details_cache.dart' show failureWords;
import '../registry.dart' show pluginOn;
import '../slack/meetings.dart' show MeetingAction, MeetingPost, MeetingPostTry, meetingActionsMost, meetingDecisionsMost, meetingLength, meetingPostOf, meetingPostTriesMost;
import 'channels.dart';
import 'manifest.dart';
import 'markdown.dart';

export '../slack/meetings.dart' show MeetingAction, MeetingPost, MeetingPostTry, meetingActionsMost, meetingLength, meetingPostOf, meetingPostTriesMost;

// ---- the message -------------------------------------------------------------------------------------------------

const int _decisionsChars = 600;

/// When the meeting began, as Discord's timestamp: "October 21, 2026 2:00 PM" in each reader's own zone.
String discordMeetingWhen(int at) => '<t:${at ~/ 1000}:f>';

/// The app's link to a note, as the message writes it: code, since Discord links no `ghostmd://` (see the header).
String discordAppLine(String noteId) => '-# In Ghost.md: `ghostmd://note/$noteId`';

/// A due day, `2026-10-24`, as "Fri, Oct 24"; as written when it is not a day.
String _dueWords(String due) {
  final day = DateTime.tryParse(due);
  return day == null ? due : localeDate(day, DateForm.MMMEd);
}

String _who(String name) => name.startsWith('@') ? name.substring(1) : name;

String _actionLine(MeetingAction action, String? me) {
  final who = action.assignee ?? (me == null || me.isEmpty ? null : '@${_who(me)}');
  final words = discordInline(action.text);
  final said = action.done ? '~~$words~~' : words;
  final due = action.due == null ? '' : ' *(due ${discordEscaped(_dueWords(action.due!))})*';
  return '- ${who == null ? '' : '**${discordEscaped(who)}**: '}$said$due';
}

/// The message a meeting posts, in Discord's Markdown, in one message:
///
/// ```
/// ## Launch sync
/// <t:1792591200:f> · 45 min · HelloTrade
/// *A call that fixed the launch date and who does what next.*
///
/// **Action items**
/// - **@matt**: First pass at the site copy by Friday
/// - **Sam**: the press list
///
/// **Decisions**
/// - No paid ads until the beta closes.
///
/// [Read the notes and transcript](https://ghostmarkdown.com/read.html#…)
/// -# In Ghost.md: `ghostmd://note/…`
/// ```
String discordMeetingMessage(MeetingPost post) {
  final title = post.title.trim();
  final head = <String>['## ${title.isEmpty ? 'Untitled meeting' : discordEscaped(title)}'];
  final facts = [
    if (post.startedAt case final at? when at > 0) discordMeetingWhen(at),
    if (post.lengthMs case final ms? when ms > 0) meetingLength(ms),
    if (post.team case final team? when team.trim().isNotEmpty) discordEscaped(team.trim()),
  ];
  if (facts.isNotEmpty) head.add(facts.join(' · '));
  if (post.gist case final gist? when gist.trim().isNotEmpty) head.add('*${discordPlain(gist.trim())}*');
  final tail = <String>[
    '',
    if (post.shareLink case final link? when link.isNotEmpty) '[Read the notes and transcript](${discordLinkUrl(link)})',
    discordAppLine(post.noteId),
  ];
  final decisions = post.decisions;
  var withDecisions = decisions.isNotEmpty && decisions.length <= meetingDecisionsMost && decisions.fold<int>(0, (n, d) => n + d.length) <= _decisionsChars;
  var shown = post.actions.length < meetingActionsMost ? post.actions.length : meetingActionsMost;

  String made() {
    final out = [...head, ''];
    if (post.actions.isEmpty) {
      out.add('No action items.');
    } else {
      out.add('**Action items**');
      for (final action in post.actions.take(shown)) {
        out.add(_actionLine(action, post.me));
      }
      final more = post.actions.length - shown;
      if (more > 0) out.add('*and $more more in Ghost.md*');
    }
    if (withDecisions) {
      out
        ..add('')
        ..add('**Decisions**');
      for (final decision in decisions) {
        out.add('- ${discordInline(decision)}');
      }
    }
    return [...out, ...tail].join('\n');
  }

  // Held under Discord's length with the links kept: the decisions go first, then action items from the end.
  var text = made();
  while (discordTooLong(text) && withDecisions) {
    withDecisions = false;
    text = made();
  }
  while (discordTooLong(text) && shown > 0) {
    shown -= 1;
    text = made();
  }
  return discordFitted(text);
}

// ---- the setting -------------------------------------------------------------------------------------------------

/// Whether meetings post to Discord, and where. In the plugin's storage, which follows the account.
@immutable
class DiscordMeetingSettings {
  const DiscordMeetingSettings({this.channel, this.on = false, this.share = true});

  /// The channel's id (channels.dart), or null until one is chosen.
  final String? channel;

  /// The switch: off until a channel is chosen, then on until turned off.
  final bool on;

  /// "Include a share link": on unless turned off, as Slack's is.
  final bool share;
}

/// The setting as kept.
DiscordMeetingSettings discordMeetingSettings() {
  final Object? kept = host.storage.get<Object?>(discordMeetingsKey, const <String, Object?>{});
  if (kept is! Map) return const DiscordMeetingSettings();
  final channel = kept['channel'];
  return DiscordMeetingSettings(channel: channel is String && channel.isNotEmpty ? channel : null, on: kept['on'] == true, share: kept['share'] != false);
}

void _keepSettings(DiscordMeetingSettings next) =>
    host.storage.set(discordMeetingsKey, {if (next.channel != null) 'channel': next.channel, 'on': next.on, 'share': next.share});

/// The channel meetings go to, or null: none chosen, or the one chosen since forgotten.
DiscordChannel? discordMeetingChannel() => discordChannelById(discordMeetingSettings().channel);

/// A channel chosen for meetings. The first choice turns the switch on: choosing where they go is saying they go.
void chooseDiscordMeetingChannel(String channelId) {
  final now = discordMeetingSettings();
  _keepSettings(DiscordMeetingSettings(channel: channelId, on: now.on || discordMeetingChannel() == null, share: now.share));
}

/// The switch. On with no channel chosen and one channel on the device, that channel is chosen; with several, the
/// switch waits for a choice.
void setDiscordMeetingPosts(bool on) {
  final now = discordMeetingSettings();
  var channel = discordMeetingChannel()?.id;
  if (on && channel == null) {
    final list = discordChannels();
    if (list.length != 1) return;
    channel = list.single.id;
  }
  _keepSettings(DiscordMeetingSettings(channel: channel ?? now.channel, on: on, share: now.share));
}

/// "Include a share link".
void setDiscordMeetingShareLink(bool on) {
  final now = discordMeetingSettings();
  _keepSettings(DiscordMeetingSettings(channel: now.channel, on: now.on, share: on));
}

/// Whether the Discord plugin's page offers Post to Discord: the plugin on, not an iPhone, with a channel here.
bool meetingDiscordOffered() => pluginOn(manifest) && notOnIPhone('discord') == null && discordChannels().isNotEmpty;

/// Whether a meeting written up now is posted to Discord.
bool postsMeetingsToDiscord() => meetingDiscordOffered() && discordMeetingSettings().on && discordMeetingChannel() != null;

// ---- once, for the account ---------------------------------------------------------------------------------------

/// Which meetings have been posted to Discord, in [Preferences.more], synced: `{noteId: {"at": ms}}` once a device
/// takes it, with `"posted": ms` once it lands or `"failed": ms` once its tries ran out. Any mark at all and no
/// device posts it to Discord again.
const String discordMeetingPostsKey = 'discordMeetingPosts';

Map<String, Object?> _marks(Preferences prefs) {
  final raw = prefs.more[discordMeetingPostsKey];
  return raw is Map ? raw.cast<String, Object?>() : const {};
}

/// Whether [noteId] has been taken by a device to post to Discord, landed or not.
bool discordMeetingPostMarked(Preferences prefs, String noteId) => _marks(prefs).containsKey(noteId);

/// [noteId] marked: taken at [at], and [posted] or [failed] once it is.
Preferences withDiscordMeetingPostMark(Preferences prefs, String noteId, {required int at, int? posted, int? failed}) {
  final was = _marks(prefs)[noteId];
  final from = was is Map && was['at'] is num ? (was['at'] as num).toInt() : at;
  return prefs.copyWith(more: {
    ...prefs.more,
    discordMeetingPostsKey: {
      ..._marks(prefs),
      noteId: {'at': from, 'posted': ?posted, 'failed': ?failed},
    },
  });
}

// ---- the tries, on this device -----------------------------------------------------------------------------------

/// The meetings waiting to be posted to Discord from this device, oldest first.
List<MeetingPostTry> discordMeetingPostTries() {
  final Object? kept = host.storage.get<Object?>(discordMeetingQueueKey, const <Object?>[]);
  return [
    if (kept is List)
      for (final raw in kept)
        if (raw is Map && raw['note'] is String)
          MeetingPostTry(
            noteId: raw['note'] as String,
            title: raw['title'] is String ? raw['title'] as String : '',
            tries: raw['tries'] is num ? (raw['tries'] as num).toInt() : 0,
            said: raw['said'] is String ? raw['said'] as String : null,
            at: raw['at'] is num ? (raw['at'] as num).toInt() : 0,
          ),
  ];
}

void _keepTries(List<MeetingPostTry> list) {
  if (list.isEmpty) {
    host.storage.remove(discordMeetingQueueKey);
  } else {
    host.storage.set(discordMeetingQueueKey, [for (final each in list) each.toJson()]);
  }
}

void _putTry(MeetingPostTry next) {
  final list = discordMeetingPostTries();
  final at = list.indexWhere((t) => t.noteId == next.noteId);
  if (at >= 0) {
    list[at] = next;
  } else {
    list.add(next);
  }
  _keepTries(list);
}

/// A meeting no longer waited on: posted, gone, or let go from the page's "Don't post".
void forgetDiscordMeetingPost(String noteId) => _keepTries([for (final t in discordMeetingPostTries()) if (t.noteId != noteId) t]);

/// The tries that failed, for the pages to say: each with Discord's reason.
List<MeetingPostTry> failedDiscordMeetingPosts() => [for (final t in discordMeetingPostTries()) if (t.said != null) t];

// ---- the poster --------------------------------------------------------------------------------------------------

/// The posting, as the root wires it beside Slack's: the preferences that remember what was posted, the notes, and
/// the share.
class MeetingDiscordPoster {
  MeetingDiscordPoster({
    required this.preferences,
    required this.setPreferences,
    required this.getNote,
    this.shareLink,
    this.teamOf,
    this.me,
    String? Function(String noteId)? kept,
    Future<void> Function(DiscordChannel channel, String text)? post,
    int Function()? now,
    this.warn,
  })  : kept = kept ?? keptText,
        _post = post ?? postToDiscord,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;
  final Future<Note?> Function(String id) getNote;

  /// The note's share link, made or written again through the app's share (`Shares.shareNote`); null where there is
  /// none to make here.
  final Future<String> Function(Note note)? shareLink;

  /// The organization's name for a note in a team's workspace, else null.
  final String? Function(String noteId)? teamOf;

  /// The account's handle, for the recorder's own to-dos.
  final String? Function()? me;

  /// What the app wrote as the note's summary (lib/ai/summary_keep.dart `keptText`).
  final String? Function(String noteId) kept;
  final Future<void> Function(DiscordChannel channel, String text) _post;
  final int Function() _now;
  final void Function(String message)? warn;

  /// One pass at a time: a write-up landing while the queue is being tried waits for it.
  Future<int>? _running;

  /// A meeting's note written up on this device: marked for the account and posted, if meetings post to Discord
  /// here and it has not been marked before. Answers whether it went.
  Future<bool> meetingSummarized(String noteId, String body) async {
    if (!postsMeetingsToDiscord() || discordMeetingPostMarked(preferences(), noteId)) return false;
    final at = _now();
    // Marked before it goes: no other device, and no summary made again, posts it after this.
    setPreferences((now) => withDiscordMeetingPostMark(now, noteId, at: at));
    final title = noteTitle(body);
    _putTry(MeetingPostTry(noteId: noteId, title: title.isEmpty ? 'Untitled meeting' : title));
    await _pass(only: noteId);
    return !discordMeetingPostTries().any((t) => t.noteId == noteId);
  }

  /// The app has started: every meeting still waiting with tries left is tried again, while meetings post here.
  Future<int> resume() => postsMeetingsToDiscord() ? _pass() : Future<int>.value(0);

  /// "Try now": [noteId] (or every one waiting), its tries spent or not.
  Future<int> tryNow([String? noteId]) => postsMeetingsToDiscord() ? _pass(only: noteId, spent: true) : Future<int>.value(0);

  Future<int> _pass({String? only, bool spent = false}) async {
    while (_running != null) {
      await _running;
    }
    final run = _passNow(only: only, spent: spent);
    _running = run;
    try {
      return await run;
    } finally {
      _running = null;
    }
  }

  Future<int> _passNow({String? only, bool spent = false}) async {
    var went = 0;
    for (final waiting in discordMeetingPostTries()) {
      if (only != null && waiting.noteId != only) continue;
      if (waiting.spent && !spent) continue;
      if (await _try(waiting)) went += 1;
    }
    return went;
  }

  Future<bool> _try(MeetingPostTry waiting) async {
    final channel = discordMeetingChannel();
    if (channel == null) return false;
    Note? note;
    try {
      note = await getNote(waiting.noteId);
    } catch (_) {
      note = null;
    }
    if (note == null) {
      // Deleted meanwhile: nothing to post.
      forgetDiscordMeetingPost(waiting.noteId);
      return false;
    }
    // Counted as it begins: an app stopped mid-post tries again once more, not forever.
    final tries = waiting.tries + 1;
    _putTry(waiting.copyWith(tries: tries, at: _now()));
    // On the app's record of running work (lib/core/background_jobs.dart; docs/ACTIVITY.md), as Slack's meeting post is:
    // "Posting Standup to Discord" with Discord's mark, then "Posted to #team" as a chip, or red with Discord's words
    // once its tries are spent, with Retry; a try short of the last goes quietly, as the queue tries again.
    final title = noteTitle(note.body);
    final job = activity.begin('discord:${note.id}', kind: JobKind.meetings, title: 'Posting ${title.isEmpty ? 'the meeting' : title} to Discord', line: 'Posting to ${channel.name}', onOpen: activityRoutes.noteOpener(note.id), plugin: manifest.id);
    String? link;
    final share = shareLink;
    if (discordMeetingSettings().share && share != null) {
      try {
        link = await share(note);
      } catch (failure) {
        // Signed out, or offline: the post goes with the app's line alone, and offline it fails below anyway.
        warn?.call('[ghost] no share link for the meeting: $failure');
      }
    }
    final text = discordMeetingMessage(meetingPostOf(note, startedAt: preferences().meetings[note.id]?.toInt(), kept: kept(note.id), team: teamOf?.call(note.id), shareLink: link, me: me?.call()));
    try {
      await _post(channel, text);
    } catch (failure) {
      final said = failureWords(failure);
      _putTry(waiting.copyWith(tries: tries, said: said, at: _now()));
      if (tries >= meetingPostTriesMost) {
        setPreferences((now) => withDiscordMeetingPostMark(now, note!.id, at: _now(), failed: _now()));
        job.failed(said, fix: JobFix(JobFixKind.retry, () => unawaited(tryNow(note!.id))));
      } else {
        job.stopped();
      }
      return false;
    }
    forgetDiscordMeetingPost(waiting.noteId);
    setPreferences((now) => withDiscordMeetingPostMark(now, note!.id, at: _now(), posted: _now()));
    job.done(result: JobResult('Posted to ${channel.name}', action: 'Open', onOpen: activityRoutes.noteOpener(note.id)), tally: const JobTally('Discord post', 'Discord posts'));
    return true;
  }
}

/// The root's poster, once it is made: "Try now" on the pages asks it.
MeetingDiscordPoster? meetingDiscordPoster;
