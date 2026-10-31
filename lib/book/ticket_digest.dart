/// The morning's word on a person's tickets (Matt, 2026-10-31: "Each morning (default 8:30 local, set in Settings ›
/// Notifications or the tickets settings), one notification per person: what's due today, what's overdue and what's
/// blocked, across their notebooks and teams").
///
/// **Whose.** A ticket not done that is assigned to the person (`assignee: sam` or `@sam`, in any case), or, in a
/// note of their own rather than a team's, assigned to nobody: across every notebook and organization this device has.
/// Due today, overdue (its day passed), and blocked (it waits on a ticket that is not done; lib/book/ticket_links.dart
/// `openBlockers`). A morning with none of them says nothing.
///
/// **Once, from one device** ([DigestClaims]): the day's digest is claimed in the synced settings, as a meeting's
/// summary handed on is (lib/ai/summary_handoff.dart): the claim, `{day, by, name, at, phone}`, written, a sync run, and
/// only a claim the account then holds as this device's sends it. Of two devices that claim at once the second's write
/// is refused, it reads the first's, and the merge keeps the account's ([chosenDigestClaim]).
/// - **A phone** claims the next morning's ahead of time, whenever it looks (the app opened, the notes changed), and
///   hands the reminders' alarms one more (lib/reminders/reminder_plan.dart `ReminderKind.digest`): it rings at the
///   time with the app closed, in the reminders' own notification, the words as they were at the last look.
/// - **A Mac or a PC** claims it at the time, if no phone has, and sends it as a row in the bell, sealed under the
///   account key as the app's own rows are, under an id made from the day ([digestRowId]): sent twice, it lands once.
///   The account's phones post that row as theirs, so a person whose phone was not opened since yesterday still hears.
/// - **Write a digest note** (off unless turned on) puts the same as a note in the Inbox, by the device that sends it,
///   at the time or at its first look after.
///
/// A tap opens the digest page ([digestNoteId], the root's), or the digest note where one was written.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ai/summary_handoff.dart' show SummaryDevice;
import '../core/days.dart' show isoDay, isoDayAfter, daysBetween;
import '../core/preferences.dart' show Preferences;
import '../core/properties.dart';
import '../mentions/mention_syntax.dart' show handleKey;
import '../reminders/reminder_plan.dart' show Reminder, ReminderKind, stableId;
import '../reminders/reminder_syntax.dart' show ReminderTime;
import 'ticket_links.dart' show openBlockers;
import 'ticket_watchers.dart' show handleOf;
import 'tickets.dart';

/// The synced setting the day's claim is kept in, in [Preferences.more].
const String ticketDigestKey = 'ticketDigest';

/// The synced choices: on, the time, and whether a note is written.
const String ticketDigestSettingsKey = 'ticketDigestSettings';

/// What a tap on the digest opens where no note was written: the root opens the digest page for it.
const String digestNoteId = 'ghost-ticket-digest';

/// How long after its time a device that was not running still sends the morning's digest.
const Duration digestLateBy = Duration(hours: 6);

/// The choices (Settings › Notifications › Ticket digest): on, at 8:30, and no note, unless changed.
@immutable
class DigestSettings {
  const DigestSettings({this.on = true, this.hour = 8, this.minute = 30, this.note = false});

  static DigestSettings fromJson(Object? raw) {
    if (raw is! Map) return const DigestSettings();
    int clamp(Object? v, int least, int most, int fallback) => v is num && v.isFinite ? v.toInt().clamp(least, most) : fallback;
    return DigestSettings(on: raw['on'] != false, hour: clamp(raw['hour'], 0, 23, 8), minute: clamp(raw['minute'], 0, 59, 30), note: raw['note'] == true);
  }

  final bool on;
  final int hour;
  final int minute;
  final bool note;

  Map<String, Object?> toJson() => {'on': on, 'hour': hour, 'minute': minute, 'note': note};

  DigestSettings copyWith({bool? on, int? hour, int? minute, bool? note}) => DigestSettings(on: on ?? this.on, hour: hour ?? this.hour, minute: minute ?? this.minute, note: note ?? this.note);

  /// The moment of the digest on [day].
  DateTime momentOn(String day) {
    final parts = day.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2], hour, minute);
  }

  @override
  bool operator ==(Object other) => other is DigestSettings && other.on == on && other.hour == hour && other.minute == minute && other.note == note;

  @override
  int get hashCode => Object.hash(on, hour, minute, note);
}

/// The choices the settings hold.
DigestSettings digestSettingsOf(Preferences prefs) => DigestSettings.fromJson(prefs.more[ticketDigestSettingsKey]);

/// [prefs] with [settings] as the digest's choices.
Preferences withDigestSettings(Preferences prefs, DigestSettings settings) => prefs.copyWith(more: {...prefs.more, ticketDigestSettingsKey: settings.toJson()});

// ---- what it says -------------------------------------------------------------------------------------------------

/// One ticket in the digest.
@immutable
class DigestItem {
  const DigestItem({required this.noteId, required this.key, required this.title, this.due, this.waitsOn = const []});

  final String noteId;
  final String? key;
  final String title;
  final String? due;

  /// What it waits on, by key or title.
  final List<String> waitsOn;

  /// `GHO-12 Fix the login loop`.
  String get named => key == null ? title : (title.isEmpty || title == key ? key! : '$key $title');

  /// How a note links it: by its key, or its title.
  String get link => '[[${key ?? title}]]';
}

/// A person's morning: due today, overdue, blocked.
@immutable
class TicketDigest {
  const TicketDigest({required this.day, this.dueToday = const [], this.overdue = const [], this.blocked = const []});

  final String day;
  final List<DigestItem> dueToday;
  final List<DigestItem> overdue;
  final List<DigestItem> blocked;

  bool get empty => dueToday.isEmpty && overdue.isEmpty && blocked.isEmpty;

  /// The notification's title: "2 due today · 1 overdue · 1 blocked".
  String get title => [
        if (dueToday.isNotEmpty) '${dueToday.length} due today',
        if (overdue.isNotEmpty) '${overdue.length} overdue',
        if (blocked.isNotEmpty) '${blocked.length} blocked',
      ].join(' · ');

  /// The line under it: the tickets by name, the most pressing first, cut at about a hundred and twenty characters.
  String get text {
    final names = [for (final item in [...overdue, ...dueToday, ...blocked]) item.named];
    final seen = <String>{};
    final out = StringBuffer();
    for (final name in names) {
      if (!seen.add(name)) continue;
      final next = out.isEmpty ? name : ', $name';
      if (out.length + next.length > 120) {
        out.write(', …');
        break;
      }
      out.write(next);
    }
    return out.toString();
  }

  /// The digest as a note: a heading for the day and a list for each part, each ticket linked.
  String get markdown {
    final out = StringBuffer('# Tickets for $day\n');
    void part(String heading, List<DigestItem> items, String Function(DigestItem item) after) {
      if (items.isEmpty) return;
      out.write('\n## $heading\n\n');
      for (final item in items) {
        final title = item.key != null && item.title.isNotEmpty && item.title != item.key ? ' ${item.title}' : '';
        out.write('- ${item.link}$title${after(item)}\n');
      }
    }

    part('Due today', dueToday, (_) => '');
    part('Overdue', overdue, (item) => item.due == null ? '' : ' · due ${item.due}');
    part('Blocked', blocked, (item) => item.waitsOn.isEmpty ? '' : ' · waits on ${item.waitsOn.map((t) => '[[$t]]').join(', ')}');
    return out.toString();
  }
}

/// Whether [entry] is [me]'s: assigned to them, or, in a note of their own, to nobody.
bool _mine(TicketEntry entry, String? me, bool Function(String noteId) team) {
  final assignee = handleOf(entry.ticket.assignee) ?? entry.ticket.assignee?.trim();
  if (assignee == null || assignee.isEmpty) return !team(entry.note.id);
  return me != null && handleKey(assignee) == handleKey(me);
}

/// [me]'s digest on [today] from [entries] (see the header). [team] says whether a note is a team's; none, where the
/// app does not say. [skip] leaves out a ticket by its note (the Trash, the archive).
TicketDigest digestFor(List<TicketEntry> entries, {required String? me, required String today, bool Function(String noteId)? team, bool Function(TicketEntry entry)? skip}) {
  final isTeam = team ?? (_) => false;
  final find = ticketFinder(entries);
  final dueToday = <DigestItem>[], overdue = <DigestItem>[], blocked = <DigestItem>[];
  for (final entry in entries) {
    if (entry.ticket.category == StatusCategory.done || (skip != null && skip(entry)) || !_mine(entry, me, isTeam)) continue;
    final due = entry.ticket.due;
    final item = DigestItem(noteId: entry.note.id, key: entry.ticket.id, title: entry.title, due: due);
    final between = due == null ? null : daysBetween(today, due);
    if (between == 0) dueToday.add(item);
    if (between != null && between < 0) overdue.add(item);
    if (entry.ticket.blockedBy.isNotEmpty) {
      final blockers = openBlockers(entry, find);
      if (blockers.isNotEmpty) blocked.add(DigestItem(noteId: entry.note.id, key: entry.ticket.id, title: entry.title, due: due, waitsOn: [for (final b in blockers) b.ticket.id ?? b.title]));
    }
  }
  int byDue(DigestItem a, DigestItem b) => (a.due ?? '').compareTo(b.due ?? '');
  overdue.sort(byDue);
  return TicketDigest(day: today, dueToday: dueToday, overdue: overdue, blocked: blocked);
}

/// The id of the day's row in the bell: the same from every device, so a second sending lands once.
String digestRowId(int accountId, String day) => 'digest-$accountId-$day';

// ---- once, from one device ----------------------------------------------------------------------------------------

/// The day's claim, as the synced settings carry it.
@immutable
class DigestClaim {
  const DigestClaim({required this.day, required this.by, this.name = '', required this.at, this.phone = false, this.sent});

  static DigestClaim? fromJson(Object? raw) {
    if (raw is! Map || raw['day'] is! String || raw['by'] is! String) return null;
    int? ms(Object? v) => v is num && v.isFinite ? v.toInt() : null;
    return DigestClaim(day: raw['day'] as String, by: raw['by'] as String, name: raw['name'] is String ? raw['name'] as String : '', at: ms(raw['at']) ?? 0, phone: raw['phone'] == true, sent: ms(raw['sent']));
  }

  final String day;
  final String by;
  final String name;
  final int at;

  /// Whether it is a phone's, which rings with the app closed.
  final bool phone;

  /// When it was sent, or null before.
  final int? sent;

  Map<String, Object?> toJson() => {'day': day, 'by': by, 'name': name, 'at': at, if (phone) 'phone': true, if (sent != null) 'sent': sent};

  DigestClaim sentAt(int now) => DigestClaim(day: day, by: by, name: name, at: at, phone: phone, sent: now);
}

DigestClaim? digestClaimOf(Preferences prefs) => DigestClaim.fromJson(prefs.more[ticketDigestKey]);

Preferences _withClaim(Preferences prefs, DigestClaim claim) => prefs.copyWith(more: {...prefs.more, ticketDigestKey: claim.toJson()});

/// Which of two devices' claims stands where both changed it since they last agreed (lib/sync/prefs.dart `merged`):
/// the later day's; on one day, one sent, then the account's (theirs) where it is another device's, else this one's.
Object? chosenDigestClaim(Object? mine, Object? theirs) {
  final m = DigestClaim.fromJson(mine), t = DigestClaim.fromJson(theirs);
  if (t == null) return mine;
  if (m == null) return theirs;
  final order = m.day.compareTo(t.day);
  if (order != 0) return order > 0 ? mine : theirs;
  if (t.sent != null && m.sent == null) return theirs;
  if (m.sent != null && t.sent == null) return mine;
  if (t.by != m.by) return theirs;
  return mine;
}

/// The day's digest claimed for this device in the synced settings (see the header).
class DigestClaims {
  DigestClaims({required this.device, required this.preferences, required this.setPreferences, required this.syncNow, this.accountHeld, int Function()? clock, void Function(String message)? warn})
      : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        warn = warn ?? debugPrint;

  final SummaryDevice Function() device;
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;
  final Future<void> Function() syncNow;

  /// The synced settings as the account holds them; null where this device syncs nothing, and then the digest is
  /// this device's to send.
  final Map<String, Object?>? Function()? accountHeld;
  final int Function() clock;
  final void Function(String message) warn;

  DigestClaim? get current => digestClaimOf(preferences());

  /// Whether [day]'s digest is another device's.
  bool elsewhere(String day) {
    final claim = current;
    return claim != null && claim.day == day && claim.by != device().id;
  }

  /// Whether [day]'s digest is this device's, as this device last saw the settings.
  bool mine(String day) {
    final claim = current;
    return claim != null && claim.day == day && claim.by == device().id;
  }

  /// Claims [day]'s digest for this device: true where it is this device's to send.
  Future<bool> claim(String day, {required bool phone}) async {
    final me = device();
    if (elsewhere(day)) return false;
    final now = clock();
    final was = current;
    if (was == null || was.day != day || was.by != me.id) {
      setPreferences((prefs) {
        final had = digestClaimOf(prefs);
        if (had != null && had.day == day && had.by != me.id) return prefs;
        if (had != null && had.day.compareTo(day) > 0) return prefs;
        return _withClaim(prefs, DigestClaim(day: day, by: me.id, name: me.name, at: now, phone: phone));
      });
    }
    if (accountHeld == null || accountHeld!() == null) return mine(day);
    try {
      await syncNow();
    } catch (failure) {
      warn('[digest] the morning’s digest could not be claimed: $failure');
    }
    final held = DigestClaim.fromJson(accountHeld?.call()?[ticketDigestKey]);
    if (held == null) return mine(day);
    return held.day == day && held.by == me.id;
  }

  /// [day]'s digest sent here.
  void sent(String day) {
    final me = device().id;
    final now = clock();
    setPreferences((prefs) {
      final had = digestClaimOf(prefs);
      if (had == null || had.day != day || had.by != me || had.sent != null) return prefs;
      return _withClaim(prefs, had.sentAt(now));
    });
  }

  /// Whether [day]'s digest has been sent, anywhere.
  bool wasSent(String day) {
    final claim = current;
    return claim != null && claim.day == day && claim.sent != null;
  }
}

// ---- the runner ---------------------------------------------------------------------------------------------------

/// The digest as the app runs it: looked at when the notes change and on a timer to the next time, it claims and
/// sends as the header says. [phone] says whether this device rings alarms with the app closed (the reminders' host);
/// [send] puts a digest in the bell; [writeNote] writes it as a note, answering its id; [planChanged] asks the
/// reminders for a pass, once a phone's claim or the words change.
class TicketDigestRunner {
  TicketDigestRunner({
    required this.claims,
    required this.choices,
    required this.digest,
    required this.send,
    required this.phone,
    this.writeNote,
    this.planChanged,
    DateTime Function()? clock,
    void Function(String message)? warn,
  })  : clock = clock ?? DateTime.now,
        warn = warn ?? debugPrint;

  final DigestClaims claims;

  /// The choices as the settings hold them now ([digestSettingsOf]).
  final DigestSettings Function() choices;

  /// The digest of [day] as the notes are now.
  final TicketDigest Function(String day) digest;
  final Future<void> Function(TicketDigest digest) send;
  final bool Function() phone;
  final Future<String?> Function(TicketDigest digest)? writeNote;
  final VoidCallback? planChanged;
  final DateTime Function() clock;
  final void Function(String message) warn;

  Timer? _next;
  bool _looking = false;
  bool _again = false;
  bool _gone = false;

  /// The note written for a day, by day: where a tap on that day's alarm goes once it is written.
  final Map<String, String> _notes = {};

  /// The alarm the phone holds for its claimed morning, if any: what the reminders' plan adds.
  ({String day, DateTime at, String title, String text, String noteId})? alarm;

  DigestSettings get settings => choices();

  /// The next morning a phone claims: today's until its time, then tomorrow's.
  String nextDay(DateTime now) {
    final today = isoDay(now);
    return now.isBefore(settings.momentOn(today)) ? today : isoDayAfter(today, 1)!;
  }

  /// One look (see the header), one at a time; a look asked for meanwhile runs after it.
  Future<void> look() async {
    if (_gone) return;
    if (_looking) {
      _again = true;
      return;
    }
    _looking = true;
    try {
      do {
        _again = false;
        await _look();
      } while (_again && !_gone);
    } catch (failure) {
      warn('[digest] the morning’s digest was not looked at: $failure');
    } finally {
      _looking = false;
    }
    _schedule();
  }

  Future<void> _look() async {
    final choice = settings;
    final now = clock();
    final today = isoDay(now);
    final time = choice.momentOn(today);
    if (!choice.on) {
      _setAlarm(null);
      return;
    }
    final due = !now.isBefore(time) && now.difference(time) <= digestLateBy;
    if (phone()) {
      // This morning's, rung already by the alarm: marked sent, and its note written where asked for.
      if (due && claims.mine(today) && !claims.wasSent(today)) {
        claims.sent(today);
        await _note(today, choice);
      }
      // Ahead of time: the next morning claimed, and its alarm handed over with the words as they are now.
      final day = nextDay(now);
      final held = claims.mine(day) || await claims.claim(day, phone: true);
      if (held) {
        final words = digest(day);
        _setAlarm(words.empty ? null : (day: day, at: choice.momentOn(day), title: words.title, text: words.text, noteId: _notes[day] ?? digestNoteId));
      } else {
        _setAlarm(null);
      }
      return;
    }
    // A later morning claimed already (a phone ahead of time): this one's was dealt with.
    final claimed = claims.current;
    if (claimed != null && claimed.day.compareTo(today) > 0) return;
    if (!due || claims.wasSent(today) || claims.elsewhere(today)) return;
    if (!await claims.claim(today, phone: false)) return;
    final words = digest(today);
    claims.sent(today);
    if (!words.empty) await send(words);
    await _note(today, choice, words);
  }

  Future<void> _note(String day, DigestSettings choice, [TicketDigest? made]) async {
    final write = writeNote;
    if (!choice.note || write == null) return;
    final words = made ?? digest(day);
    if (words.empty) return;
    final id = await write(words);
    if (id != null) _notes[day] = id;
  }

  void _setAlarm(({String day, DateTime at, String title, String text, String noteId})? next) {
    final was = alarm;
    if (was == next || (was != null && next != null && was.day == next.day && was.at == next.at && was.title == next.title && was.text == next.text && was.noteId == next.noteId)) return;
    alarm = next;
    planChanged?.call();
  }

  /// The next look: at the digest's time, or in an hour at most (a phone's claim made ahead is looked at again then).
  void _schedule() {
    _next?.cancel();
    if (_gone) return;
    final now = clock();
    final today = isoDay(now);
    final time = settings.momentOn(today);
    final until = now.isBefore(time) ? time.difference(now) : const Duration(hours: 1);
    _next = Timer(Duration(milliseconds: math.max(1000, math.min(until.inMilliseconds, const Duration(hours: 1).inMilliseconds))), () => unawaited(look()));
  }

  void dispose() {
    _gone = true;
    _next?.cancel();
  }
}

/// The phone's alarm for the morning it claimed, as the reminders' plan holds it (lib/reminders/reminder_scheduler.dart
/// `extraReminders`): the digest's title, its tickets under it, and a tap that opens the digest (or its note).
Reminder? digestReminderOf(TicketDigestRunner runner) {
  final alarm = runner.alarm;
  if (alarm == null) return null;
  return Reminder(
    id: stableId('ticket-digest\u0000${alarm.day}'),
    at: ReminderTime.of(alarm.at),
    kind: ReminderKind.digest,
    noteId: alarm.noteId,
    line: 0,
    words: 'Your tickets: ${alarm.title}',
    note: alarm.text,
    tick: false,
  );
}
