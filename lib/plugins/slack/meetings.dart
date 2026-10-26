/// A meeting's action items posted to a Slack channel as soon as it is written up (Matt, 2026-10-26: "Please add
/// slack integration via a plugin and make the meetings plugin work hand in hand to sending meeting action items and
/// a link to the meeting transcript to a specified slack channel"). The port's own: the web app has no such thing.
///
/// His answers, the same day: the link is **both**, a `ghostmd://note/<id>` that opens the note in Ghost.md for
/// whoever already has it (him, or his organization for a meeting in a team's workspace), and a share link, the
/// note as a read-only page anyone the link reaches can read (lib/share/share.dart, the note's own Share › Copy
/// link); and it goes **automatically**, once the meeting is written up, to the channel chosen in Settings ›
/// Meetings, with a switch to turn it off.
///
/// What goes ([meetingMessage]): the meeting's title, when it began and how long it ran, the summary's one sentence,
/// its action items as a list ([meetingActions]: the to-dos, `- [ ]`, with the `@person` and `📅` due date
/// lib/core/task_fields.dart reads; and the "Name: what" points the summary gives another person's actions, where the
/// name is someone who spoke), "No action items." where there are none, its decisions where there are a few
/// ([meetingDecisions]), and the two links. Nothing else of the note: the transcript is behind the share link, and
/// only when "Include a share link" is on.
///
/// The rules, each a test (test/plugins/slack/meetings_test.dart):
///
/// - **Only where it is set up.** The plugin on (Local only holds it off), a channel on this device, one chosen for
///   meetings and the switch on; never on an iPhone, where Slack is not yet (lib/core/iphone_app.dart
///   `notOnIPhone`). The choice ([meetingSlackSettings], in the plugin's storage beside the channels it names) follows
///   the account with them (lib/sync/connections.dart; Matt, 2026-10-26), so whichever device writes a meeting up has
///   the channel and the switch, and posts it.
/// - **Once per meeting, for the account.** The device that wrote the meeting up posts it; before the first try the
///   meeting is marked in the synced preferences ([slackMeetingPostsKey], merged an entry at a time as
///   ai/meeting_sort.dart's marks are), so a summary made again, here or on another device, posts nothing, and
///   nor does a second device that writes the same meeting up.
/// - **Tried again, a few times.** A post that fails (no connection, a webhook revoked in Slack) waits in this
///   device's queue ([meetingPostTries]) with Slack's reason, which the plugin's page shows,
///   and is tried again the next time the app runs ([MeetingSlackPoster.resume]) or when "Try now" is pressed, up to
///   [meetingPostTriesMost] tries. A try is counted as it begins, so an app stopped mid-post tries again at most
///   once more, never forever.
/// - **The share link is the app's own share.** Made by [MeetingSlackPoster.shareLink], the root's
///   `Shares.shareNote`: the same link the note's Share sheet copies, which then says the note is shared and stops
///   it, and which follows the note's edits as every share does. Where none can be made (signed out) the post goes
///   without it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/meeting_sort.dart' show attendeesOf;
import '../../ai/summary_keep.dart' show keptText;
import '../../core/iphone_app.dart' show notOnIPhone;
import '../../core/locale_dates.dart' show DateForm, localeDate;
import '../../core/note.dart' show Note;
import '../../core/note_text.dart' show noteTitle;
import '../../core/preferences.dart' show Preferences;
import '../../core/summary_text.dart' show summarySection;
import '../../core/task_fields.dart' show fieldsOf, withoutFields;
import '../details_cache.dart' show failureWords;
import '../registry.dart' show pluginOn;
import 'channels.dart';
import 'manifest.dart';
import 'mrkdwn.dart';

// ---- what a meeting's summary holds ------------------------------------------------------------------------------

/// One action item of a meeting: what is to be done, by whom and by when, where the summary says.
@immutable
class MeetingAction {
  const MeetingAction({required this.text, this.assignee, this.due, this.done = false});

  /// The words, the fields taken out: "Book the venue before the tenth".
  final String text;

  /// Who it is for, as written: the to-do's `@sam`, at sign and all, or the name a point begins with ("Sam: …"); null for the
  /// person who recorded, whose to-dos the summary writes as boxes with no name.
  final String? assignee;

  /// The to-do's due day, `2026-10-24` (`📅` or `[due:: …]`); a "by Friday" in the words stays in the words.
  final String? due;

  /// Ticked already.
  final bool done;

  @override
  bool operator ==(Object other) => other is MeetingAction && other.text == text && other.assignee == assignee && other.due == due && other.done == done;

  @override
  int get hashCode => Object.hash(text, assignee, due, done);

  @override
  String toString() => 'MeetingAction($text, $assignee, $due${done ? ', done' : ''})';
}

final RegExp _box = RegExp(r'^\s*[-*+]\s+\[([ xX])\]\s+(.*)$');
final RegExp _point = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _decided = RegExp(r'^decided:\s*', caseSensitive: false);

/// A point that gives someone else an action, as the summary's prompt writes one: "Sam: the press list by Friday."
/// (lib/format/prompt.dart `recordingSummaryPrompt`). The name is one to three words, before a colon.
final RegExp _named = RegExp(r'^\*{0,2}([\p{L}][\p{L}\p{N}.\x27’-]*(?:\s+[\p{L}][\p{L}\p{N}.\x27’-]*){0,2})\*{0,2}:\*{0,2}\s+(\S.*)$', unicode: true);

String _firstWord(String name) => name.trim().split(RegExp(r'\s+')).first.toLowerCase();

/// Whether the name a point begins with is someone who spoke: the whole name, or a first name either way round
/// ("Sam" for "Sam Lee", "Sam Lee" for a "Sam" in the captions).
bool _spoke(String name, List<String> attendees) {
  final lower = name.trim().toLowerCase();
  for (final who in attendees) {
    final them = who.trim().toLowerCase();
    if (them.isEmpty) continue;
    if (them == lower || _firstWord(them) == lower || _firstWord(lower) == them) return true;
  }
  return false;
}

/// The lines of the summary's section past its heading and its one sentence.
List<String> _itemsOf(String section) {
  final lines = section.split('\n');
  return [for (final (i, line) in lines.indexed) if (i > 0 && _point.hasMatch(line)) line];
}

/// A meeting's action items, from its summary's [section] (`## Summary` and what is under it): every to-do, with its
/// `@person` and due day, then every point that names one of the [attendees] first ("Sam: the press list"), in the
/// order the summary has them. A point naming no one who spoke ("Pricing: still open") is a point, not an action:
/// with no names known (a meeting recorded on the device, with no captions) only the to-dos are actions.
List<MeetingAction> meetingActions(String section, {List<String> attendees = const []}) {
  final out = <MeetingAction>[];
  for (final line in _itemsOf(section)) {
    final box = _box.firstMatch(line);
    if (box != null) {
      final words = box[2]!.trim();
      final fields = fieldsOf(words);
      final text = withoutFields(words);
      if (text.isEmpty) continue;
      out.add(MeetingAction(text: text, assignee: fields.assignees.isEmpty ? null : '@${fields.assignees.first}', due: fields.due, done: box[1] != ' '));
      continue;
    }
    final words = _point.firstMatch(line)![1]!.trim();
    if (_decided.hasMatch(words)) continue;
    final named = _named.firstMatch(words);
    if (named == null || !_spoke(named[1]!, attendees)) continue;
    out.add(MeetingAction(text: named[2]!.trim(), assignee: named[1]!.trim()));
  }
  return out;
}

/// What the meeting decided: the summary's "Decided: …" points, the word taken off.
List<String> meetingDecisions(String section) => [
      for (final line in _itemsOf(section))
        if (_box.firstMatch(line) == null && _decided.hasMatch(_point.firstMatch(line)![1]!.trim())) _point.firstMatch(line)![1]!.trim().replaceFirst(_decided, '').trim(),
    ]..removeWhere((d) => d.isEmpty);

/// The summary's one sentence, under its heading; null where it has none.
String? meetingGist(String section) {
  final lines = section.split('\n');
  final second = lines.length > 1 ? lines[1].trim() : '';
  return second.isEmpty || _point.hasMatch(second) ? null : second;
}

// ---- the message -------------------------------------------------------------------------------------------------

/// What a meeting's post is made from.
@immutable
class MeetingPost {
  const MeetingPost({
    required this.noteId,
    required this.title,
    this.startedAt,
    this.lengthMs,
    this.gist,
    this.actions = const [],
    this.decisions = const [],
    this.team,
    this.shareLink,
    this.me,
  });

  final String noteId;
  final String title;

  /// When it began, in ms; null where nothing says.
  final int? startedAt;

  /// How long it ran, in ms; null where nothing says.
  final int? lengthMs;
  final String? gist;
  final List<MeetingAction> actions;
  final List<String> decisions;

  /// The organization whose workspace the meeting is in, by name; null for the person's own.
  final String? team;

  /// The note's share link, when one goes with it.
  final String? shareLink;

  /// The account's handle, for the to-dos that are the recorder's own (a box with no `@person`).
  final String? me;
}

/// How many action items a post lists before "and 3 more in Ghost.md".
const int meetingActionsMost = 25;

/// Decisions go only while there are this many at most, and they are this short together: the post is the actions'.
const int meetingDecisionsMost = 5;
const int _decisionsChars = 600;

/// "45 min", "1 hr 5 min", "2 hr"; a minute at least.
String meetingLength(int ms) {
  final minutes = (ms / 60000).round().clamp(1, 1 << 20);
  final hours = minutes ~/ 60, rest = minutes % 60;
  if (hours == 0) return '$minutes min';
  return rest == 0 ? '$hours hr' : '$hours hr $rest min';
}

/// When the meeting began, as Slack's date token: each reader sees it in their own time zone ("Today at 2:00 PM"),
/// and a reader Slack cannot do that for sees [at] in the phone's words.
String meetingWhen(int at) {
  final day = DateTime.fromMillisecondsSinceEpoch(at);
  final fallback = '${localeDate(day, DateForm.MMMEd)}, ${localeDate(day, DateForm.hm)}';
  return '<!date^${at ~/ 1000}^{date_short_pretty} at {time}|${escapedMrkdwn(fallback)}>';
}

/// A due day, `2026-10-24`, as "Fri, Oct 24"; as written when it is not a day.
String _dueWords(String due) {
  final day = DateTime.tryParse(due);
  return day == null ? due : localeDate(day, DateForm.MMMEd);
}

String _who(String name) => name.startsWith('@') ? name.substring(1) : name;

String _actionLine(MeetingAction action, String? me) {
  final who = action.assignee ?? (me == null || me.isEmpty ? null : '@${_who(me)}');
  final words = inlineMrkdwn(action.text);
  final said = action.done ? '~$words~' : words;
  final due = action.due == null ? '' : ' _(due ${escapedMrkdwn(_dueWords(action.due!))})_';
  return '• ${who == null ? '' : '*${escapedMrkdwn(who)}*: '}$said$due';
}

/// The message a meeting posts, in Slack's mrkdwn, held under Slack's length:
///
/// ```
/// *Launch sync*
/// <!date^…|Tue, Oct 21, 2:00 PM> · 45 min · HelloTrade
/// _A call that fixed the launch date and who does what next._
///
/// *Action items*
/// • *@matt*: First pass at the site copy by Friday
/// • *Sam*: the press list
///
/// *Decisions*
/// • No paid ads until the beta closes.
///
/// <ghostmd://note/…|Open in Ghost.md> · <https://ghostmarkdown.com/read.html#…|Read the notes and transcript>
/// ```
String meetingMessage(MeetingPost post) {
  final out = <String>['*${escapedMrkdwn(post.title.trim().isEmpty ? 'Untitled meeting' : post.title.trim())}*'];
  final facts = [
    if (post.startedAt case final at? when at > 0) meetingWhen(at),
    if (post.lengthMs case final ms? when ms > 0) meetingLength(ms),
    if (post.team case final team? when team.trim().isNotEmpty) escapedMrkdwn(team.trim()),
  ];
  if (facts.isNotEmpty) out.add(facts.join(' · '));
  if (post.gist case final gist? when gist.trim().isNotEmpty) out.add('_${inlineMrkdwn(gist.trim()).replaceAll('_', '')}_');
  out.add('');
  if (post.actions.isEmpty) {
    out.add('No action items.');
  } else {
    out.add('*Action items*');
    for (final action in post.actions.take(meetingActionsMost)) {
      out.add(_actionLine(action, post.me));
    }
    final more = post.actions.length - meetingActionsMost;
    if (more > 0) out.add('_and $more more in Ghost.md_');
  }
  final decisions = post.decisions;
  if (decisions.isNotEmpty && decisions.length <= meetingDecisionsMost && decisions.fold<int>(0, (n, d) => n + d.length) <= _decisionsChars) {
    out
      ..add('')
      ..add('*Decisions*');
    for (final decision in decisions) {
      out.add('• ${inlineMrkdwn(decision)}');
    }
  }
  final links = [
    '<${slackLinkUrl('ghostmd://note/${post.noteId}')}|Open in Ghost.md>',
    if (post.shareLink case final link? when link.isNotEmpty) '<${slackLinkUrl(link)}|Read the notes and transcript>',
  ];
  out
    ..add('')
    ..add(links.join(' · '));
  return fittedMrkdwn(out.join('\n'));
}

/// The post a meeting's note makes: its title, when it began ([startedAt], else the note's own), how long it ran,
/// and what its summary says ([kept], the section the app wrote, where it is known).
MeetingPost meetingPostOf(Note note, {int? startedAt, String? kept, String? team, String? shareLink, String? me}) {
  final section = summarySection(note.body, kept)?.text ?? '';
  final title = noteTitle(note.body);
  return MeetingPost(
    noteId: note.id,
    title: title,
    startedAt: startedAt ?? (note.createdAt > 0 ? note.createdAt : null),
    lengthMs: note.recordingMs,
    gist: section.isEmpty ? null : meetingGist(section),
    actions: section.isEmpty ? const [] : meetingActions(section, attendees: attendeesOf(note.body)),
    decisions: section.isEmpty ? const [] : meetingDecisions(section),
    team: team,
    shareLink: shareLink,
    me: me,
  );
}

// ---- the setting, on this device ---------------------------------------------------------------------------------

const String _settingsKey = 'glyph-slack-meetings';
const String _queueKey = 'glyph-slack-meeting-queue';

/// Whether meetings post to Slack on this device, and where.
@immutable
class MeetingSlackSettings {
  const MeetingSlackSettings({this.channel, this.on = false, this.share = true});

  /// The channel's id (channels.dart), or null until one is chosen.
  final String? channel;

  /// The switch: off until a channel is chosen, then on until turned off.
  final bool on;

  /// "Include a share link": on unless turned off (Matt's "Both").
  final bool share;
}

/// The setting as kept.
MeetingSlackSettings meetingSlackSettings() {
  final Object? kept = host.storage.get<Object?>(_settingsKey, const <String, Object?>{});
  if (kept is! Map) return const MeetingSlackSettings();
  final channel = kept['channel'];
  return MeetingSlackSettings(channel: channel is String && channel.isNotEmpty ? channel : null, on: kept['on'] == true, share: kept['share'] != false);
}

void _keepSettings(MeetingSlackSettings next) =>
    host.storage.set(_settingsKey, {if (next.channel != null) 'channel': next.channel, 'on': next.on, 'share': next.share});

/// The channel meetings go to, or null: none chosen, or the one chosen since forgotten.
Channel? meetingChannel() => channelById(meetingSlackSettings().channel);

/// A channel chosen for meetings. The first choice turns the switch on: choosing where they go is saying they go.
void chooseMeetingChannel(String channelId) {
  final now = meetingSlackSettings();
  _keepSettings(MeetingSlackSettings(channel: channelId, on: now.on || meetingChannel() == null, share: now.share));
}

/// The switch. On with no channel chosen and one channel on the device, that channel is chosen; with several, the
/// switch waits for a choice.
void setMeetingPosts(bool on) {
  final now = meetingSlackSettings();
  var channel = meetingChannel()?.id;
  if (on && channel == null) {
    final list = channels();
    if (list.length != 1) return;
    channel = list.single.id;
  }
  _keepSettings(MeetingSlackSettings(channel: channel ?? now.channel, on: on, share: now.share));
}

/// "Include a share link".
void setMeetingShareLink(bool on) {
  final now = meetingSlackSettings();
  _keepSettings(MeetingSlackSettings(channel: now.channel, on: now.on, share: on));
}

/// Whether the Slack plugin's page offers Post to Slack: the plugin on, on a build and a platform that can post, with a
/// channel on this device.
bool meetingSlackOffered() => pluginOn(manifest) && slackReadyNow() && notOnIPhone('slack') == null && channels().isNotEmpty;

/// Whether a meeting written up now is posted.
bool postsMeetings() => meetingSlackOffered() && meetingSlackSettings().on && meetingChannel() != null;

// ---- once, for the account ---------------------------------------------------------------------------------------

/// Which meetings have been posted, in [Preferences.more], synced: `{noteId: {"at": ms}}` once a device takes it,
/// with `"posted": ms` once it lands, or `"failed": ms` once its tries ran out. Any mark at all and no device posts it
/// again (lib/sync/prefs.dart merges it an entry at a time).
const String slackMeetingPostsKey = 'slackMeetingPosts';

Map<String, Object?> _marks(Preferences prefs) {
  final raw = prefs.more[slackMeetingPostsKey];
  return raw is Map ? raw.cast<String, Object?>() : const {};
}

/// Whether [noteId] has been taken by a device to post, landed or not.
bool meetingPostMarked(Preferences prefs, String noteId) => _marks(prefs).containsKey(noteId);

/// [noteId] marked: taken at [at], and [posted] or [failed] once it is.
Preferences withMeetingPostMark(Preferences prefs, String noteId, {required int at, int? posted, int? failed}) {
  final was = _marks(prefs)[noteId];
  final from = was is Map && was['at'] is num ? (was['at'] as num).toInt() : at;
  return prefs.copyWith(more: {
    ...prefs.more,
    slackMeetingPostsKey: {
      ..._marks(prefs),
      noteId: {'at': from, 'posted': ?posted, 'failed': ?failed},
    },
  });
}

// ---- the tries, on this device -----------------------------------------------------------------------------------

/// How many times a meeting's post is tried before it waits for "Try now".
const int meetingPostTriesMost = 5;

/// A meeting this device has to post: its title for the page's line, how many tries it has had, and why the last
/// failed.
@immutable
class MeetingPostTry {
  const MeetingPostTry({required this.noteId, required this.title, this.tries = 0, this.said, this.at = 0});

  final String noteId;
  final String title;
  final int tries;

  /// Slack's reason, in a sentence, for the last try that failed; null before one has.
  final String? said;

  /// When the last try was, in ms.
  final int at;

  /// The tries ran out: it waits for "Try now".
  bool get spent => tries >= meetingPostTriesMost;

  Map<String, Object?> toJson() => {'note': noteId, 'title': title, 'tries': tries, 'said': ?said, 'at': at};

  MeetingPostTry copyWith({int? tries, String? said, int? at}) => MeetingPostTry(noteId: noteId, title: title, tries: tries ?? this.tries, said: said ?? this.said, at: at ?? this.at);
}

/// The meetings waiting to be posted from this device, oldest first.
List<MeetingPostTry> meetingPostTries() {
  final Object? kept = host.storage.get<Object?>(_queueKey, const <Object?>[]);
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
    host.storage.remove(_queueKey);
  } else {
    host.storage.set(_queueKey, [for (final each in list) each.toJson()]);
  }
}

void _putTry(MeetingPostTry next) {
  final list = meetingPostTries();
  final at = list.indexWhere((t) => t.noteId == next.noteId);
  if (at >= 0) {
    list[at] = next;
  } else {
    list.add(next);
  }
  _keepTries(list);
}

/// A meeting no longer waited on: posted, gone, or let go from the page's "Don't post".
void forgetMeetingPost(String noteId) => _keepTries([for (final t in meetingPostTries()) if (t.noteId != noteId) t]);

/// The tries that failed, for the pages to say: each with Slack's reason.
List<MeetingPostTry> failedMeetingPosts() => [for (final t in meetingPostTries()) if (t.said != null) t];

// ---- the poster --------------------------------------------------------------------------------------------------

/// The posting, as the root wires it: the preferences that remember what was posted, the notes, and the share.
class MeetingSlackPoster {
  MeetingSlackPoster({
    required this.preferences,
    required this.setPreferences,
    required this.getNote,
    this.shareLink,
    this.teamOf,
    this.me,
    String? Function(String noteId)? kept,
    Future<void> Function(Channel channel, String text)? post,
    int Function()? now,
    this.warn,
  })  : kept = kept ?? keptText,
        _post = post ?? postToChannel,
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
  final Future<void> Function(Channel channel, String text) _post;
  final int Function() _now;
  final void Function(String message)? warn;

  /// One pass at a time: a write-up landing while the queue is being tried waits for it.
  Future<int>? _running;

  /// A meeting's note written up on this device: marked for the account and posted, if meetings post here and it
  /// has not been marked before. Answers whether it went.
  Future<bool> meetingSummarized(String noteId, String body) async {
    if (!postsMeetings() || meetingPostMarked(preferences(), noteId)) return false;
    final at = _now();
    // Marked before it goes: no other device, and no summary made again, posts it after this.
    setPreferences((now) => withMeetingPostMark(now, noteId, at: at));
    final title = noteTitle(body);
    _putTry(MeetingPostTry(noteId: noteId, title: title.isEmpty ? 'Untitled meeting' : title));
    await _pass(only: noteId);
    return !meetingPostTries().any((t) => t.noteId == noteId);
  }

  /// The app has started: every meeting still waiting with tries left is tried again, while meetings post here.
  /// Answers how many went.
  Future<int> resume() => postsMeetings() ? _pass() : Future<int>.value(0);

  /// "Try now": [noteId] (or every one waiting), its tries spent or not. Answers how many went.
  Future<int> tryNow([String? noteId]) => postsMeetings() ? _pass(only: noteId, spent: true) : Future<int>.value(0);

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
    for (final waiting in meetingPostTries()) {
      if (only != null && waiting.noteId != only) continue;
      if (waiting.spent && !spent) continue;
      if (await _try(waiting)) went += 1;
    }
    return went;
  }

  Future<bool> _try(MeetingPostTry waiting) async {
    final channel = meetingChannel();
    if (channel == null) return false;
    Note? note;
    try {
      note = await getNote(waiting.noteId);
    } catch (_) {
      note = null;
    }
    if (note == null) {
      // Deleted meanwhile: nothing to post.
      forgetMeetingPost(waiting.noteId);
      return false;
    }
    // Counted as it begins: an app stopped mid-post tries again once more, not forever.
    final tries = waiting.tries + 1;
    _putTry(waiting.copyWith(tries: tries, at: _now()));
    String? link;
    final share = shareLink;
    if (meetingSlackSettings().share && share != null) {
      try {
        link = await share(note);
      } catch (failure) {
        // Signed out, or offline: the post goes with the app's link alone, and offline it fails below anyway.
        warn?.call('[ghost] no share link for the meeting: $failure');
      }
    }
    final text = meetingMessage(meetingPostOf(note, startedAt: preferences().meetings[note.id]?.toInt(), kept: kept(note.id), team: teamOf?.call(note.id), shareLink: link, me: me?.call()));
    try {
      await _post(channel, text);
    } catch (failure) {
      final said = failureWords(failure);
      _putTry(waiting.copyWith(tries: tries, said: said, at: _now()));
      if (tries >= meetingPostTriesMost) setPreferences((now) => withMeetingPostMark(now, note!.id, at: _now(), failed: _now()));
      return false;
    }
    forgetMeetingPost(waiting.noteId);
    setPreferences((now) => withMeetingPostMark(now, note!.id, at: _now(), posted: _now()));
    return true;
  }
}

/// The root's poster, once it is made: "Try now" on the pages asks it.
MeetingSlackPoster? meetingSlackPoster;
