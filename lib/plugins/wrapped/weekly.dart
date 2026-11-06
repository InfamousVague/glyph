/// Wrapped's weekly report (docs/WRAPPED.md, "The weekly report"; Matt, 2026-11-06: "Wrapped should also give weekly
/// reports and work using the attached AI such as Claude"): every week, at a day and time the person picks (Monday at
/// 8:00 unless changed), "Your week in notes", written as a note in the library: an entry of the "Weekly reports"
/// journal, plain Markdown that syncs as any note does (docs/MARKDOWN_FIRST.md).
///
/// Pure: the week's bounds by the locale's first day ([firstWeekdayOf], [weekStartOf]), when a week's report is due
/// ([WeeklySettings.dueFor]) and which week is due now ([dueWeek]); the counts ([weeklyCounts]); the AI's ask and its
/// answer ([weeklyPrompt], [readWeeklyAnswer]); the note's words ([weeklyMarkdown]) and the journal it is filed in
/// ([weeklyJournalBody]); and what is kept of it ([WeeklyState]). service.dart makes it, weekly_section.dart shows it.
///
/// What a week counts, from the notes as they are now (the library keeps no record of when a box was ticked):
/// - notes written in it (`createdAt`) and their words, and notes written before it and edited in it;
/// - to-dos done and added since the last report, told apart by the to-dos the last report saw ([WeeklyState.todos],
///   each by its note and the hash of its words, never the words); the first report, with nothing to compare, counts
///   the boxes ticked in the notes touched this week as done and every box in the notes written this week as added;
///   still open is every open box now;
/// - meetings and recordings written in it, the busiest day, the notes come back to most (saves since the last report,
///   by each note's revision then and now; the first time, those edited this week by their saves in all);
/// - notes that crossed the stale line this week (not edited for [staleAfter], the day falling in the week), and a few
///   unfinished to-dos worth a look, each a link to its note.
///
/// With an AI (the one Wrapped uses, service.dart `ai`), one small ask more: the counts, each note touched this week as
/// its one-line gist (the pass's own, read again only for notes whose words changed), and up to 30 open to-dos'
/// lines, never a note's words. Back come a 3 to 5 sentence summary, the week's themes and 3 next steps, each one of
/// Wrapped's own presses (check off, archive, link), applied from the Wrapped page with Undo.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../claude/claude_spend.dart' show ClaudeUsage, claudeCost, claudeDollars;
import '../../core/days.dart' show isoDay;
import '../../core/front_matter.dart' show frontMatterValue, quotedTitle;
import '../../core/note.dart';
import '../../core/note_text.dart' show noteTitle;
import '../cleanup/ai.dart' show CleanupAi;
import '../cleanup/plan.dart' show jsonObjectIn;
import 'pass.dart' show WrappedNote, WrappedPacing, tokenWords;
import 'state.dart' show WrappedRead;
import 'stats.dart' show dayNames, isMeetingNote, isRecordingNote, monthNames, noteWords;
import 'todos.dart';

/// The front matter key a weekly report wears, its week's first day: `wrapped-week: 2026-11-02`. What tells the app
/// a week has its report already, on this device or another the note synced from.
const String weeklyWeekKey = 'wrapped-week';

/// The key the reports' journal wears beside `journal: true`: `wrapped: weekly`, so it is found again when renamed.
const String weeklyJournalKey = 'wrapped';

/// The journal's name when it is first made.
const String weeklyJournalName = 'Weekly reports';

// ---- the week -------------------------------------------------------------------------------------------------------

/// Countries whose week starts on Sunday, Saturday or Friday (CLDR's `weekData`); every other on Monday.
const Set<String> _sundayFirst = {
  'AG', 'AS', 'BD', 'BR', 'BS', 'BT', 'BW', 'BZ', 'CA', 'CN', 'CO', 'DM', 'DO', 'ET', 'GT', 'GU', 'HK', 'HN', 'ID', 'IL', 'IN', 'JM', 'JP', 'KE', //
  'KH', 'KR', 'LA', 'MH', 'MM', 'MO', 'MT', 'MX', 'MZ', 'NI', 'NP', 'PA', 'PE', 'PH', 'PK', 'PR', 'PT', 'PY', 'SA', 'SG', 'SV', 'TH', 'TT', 'TW', //
  'UM', 'US', 'VE', 'VI', 'WS', 'YE', 'ZA', 'ZW',
};
const Set<String> _saturdayFirst = {'AE', 'AF', 'BH', 'DJ', 'DZ', 'EG', 'IQ', 'IR', 'JO', 'KW', 'LY', 'OM', 'QA', 'SD', 'SY'};

/// The first day of the week where [country] is (`DateTime.monday` to `DateTime.sunday`): Monday where it is not
/// known.
int firstWeekdayOf(String? country) {
  final where = (country ?? '').toUpperCase();
  if (_sundayFirst.contains(where)) return DateTime.sunday;
  if (_saturdayFirst.contains(where)) return DateTime.saturday;
  if (where == 'MV') return DateTime.friday;
  return DateTime.monday;
}

/// Midnight of the first day of the week [at] is in, weeks starting on [firstDay].
DateTime weekStartOf(DateTime at, int firstDay) {
  final back = (at.weekday - firstDay + 7) % 7;
  return DateTime(at.year, at.month, at.day - back);
}

/// The week after [start]'s first day: by the calendar, so a clock change leaves it whole.
DateTime weekEndOf(DateTime start) => DateTime(start.year, start.month, start.day + 7);

/// A week's key, its first day: "2026-11-02".
String weekKeyOf(DateTime start) => isoDay(start);

/// The day a key names, at midnight; null for none.
DateTime? weekOfKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key.trim());
  return m == null ? null : DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

const List<String> _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The report's title: "Week of 2 Nov 2026".
String weekTitle(DateTime start) => 'Week of ${start.day} ${_shortMonths[start.month - 1]} ${start.year}';

/// "2 to 8 November 2026", "28 October to 3 November 2026", "29 December 2025 to 4 January 2026".
String weekSpanWords(DateTime start) {
  final last = DateTime(start.year, start.month, start.day + 6);
  if (start.year != last.year) return '${start.day} ${monthNames[start.month - 1]} ${start.year} to ${last.day} ${monthNames[last.month - 1]} ${last.year}';
  if (start.month != last.month) return '${start.day} ${monthNames[start.month - 1]} to ${last.day} ${monthNames[last.month - 1]} ${last.year}';
  return '${start.day} to ${last.day} ${monthNames[last.month - 1]} ${last.year}';
}

// ---- the settings ---------------------------------------------------------------------------------------------------

/// The weekly report's choices (the Wrapped page's Weekly reports): on, the day and time, the AI's summary, and the
/// notification. On by default once Wrapped is on, on Monday at 8:00.
@immutable
class WeeklySettings {
  const WeeklySettings({this.on = true, this.weekday = DateTime.monday, this.hour = 8, this.minute = 0, this.ai = true, this.notify = true});

  final bool on;

  /// `DateTime.monday` to `DateTime.sunday`.
  final int weekday;
  final int hour;
  final int minute;

  /// Include the AI's summary and next steps, where an AI is connected.
  final bool ai;

  /// Say so with a notification, where the device lets the app notify.
  final bool notify;

  /// When the report of the week that starts on [start] is due: the first [weekday] at [hour]:[minute] on or after the
  /// week's end.
  DateTime dueFor(DateTime start) {
    final end = weekEndOf(start);
    final ahead = (weekday - end.weekday + 7) % 7;
    return DateTime(end.year, end.month, end.day + ahead, hour, minute);
  }

  /// "Mondays at 8:00".
  String get words => '${dayNames[weekday - 1]}s at $hour:${minute.toString().padLeft(2, '0')}';

  WeeklySettings copyWith({bool? on, int? weekday, int? hour, int? minute, bool? ai, bool? notify}) =>
      WeeklySettings(on: on ?? this.on, weekday: weekday ?? this.weekday, hour: hour ?? this.hour, minute: minute ?? this.minute, ai: ai ?? this.ai, notify: notify ?? this.notify);

  Map<String, Object?> toJson() => {'on': on, 'weekday': weekday, 'hour': hour, 'minute': minute, 'ai': ai, 'notify': notify};

  static WeeklySettings fromJson(Object? json) {
    if (json is! Map) return const WeeklySettings();
    int whole(Object? v, int least, int most, int fallback) => v is num && v.isFinite ? v.toInt().clamp(least, most) : fallback;
    return WeeklySettings(
      on: json['on'] != false,
      weekday: whole(json['weekday'], 1, 7, DateTime.monday),
      hour: whole(json['hour'], 0, 23, 8),
      minute: whole(json['minute'], 0, 59, 0),
      ai: json['ai'] != false,
      notify: json['notify'] != false,
    );
  }

  @override
  bool operator ==(Object other) => other is WeeklySettings && other.on == on && other.weekday == weekday && other.hour == hour && other.minute == minute && other.ai == ai && other.notify == notify;

  @override
  int get hashCode => Object.hash(on, weekday, hour, minute, ai, notify);
}

/// The week whose report is due at [now], weeks starting on [firstDay]: the latest week whose due moment has come. A
/// week missed (the app not opened on its day) is this one still at the next launch; the weeks before it never are,
/// so a month away brings one report, not a backlog.
DateTime? dueWeek(DateTime now, WeeklySettings settings, int firstDay) {
  final current = weekStartOf(now, firstDay);
  for (var back = 1; back <= 2; back += 1) {
    final start = DateTime(current.year, current.month, current.day - 7 * back);
    if (!settings.dueFor(start).isAfter(now)) return start;
  }
  return null;
}

/// When the next report falls due after [now]: what the timer waits for.
DateTime nextDue(DateTime now, WeeklySettings settings, int firstDay) {
  final current = weekStartOf(now, firstDay);
  for (var back = 1; back >= -1; back -= 1) {
    final due = settings.dueFor(DateTime(current.year, current.month, current.day - 7 * back));
    if (due.isAfter(now)) return due;
  }
  return settings.dueFor(DateTime(current.year, current.month, current.day + 7));
}

// ---- the counts -----------------------------------------------------------------------------------------------------

/// A note and a number, for the report's lists.
typedef WeeklyNote = ({String id, String title, int count});

/// An open to-do worth a look.
typedef WeeklyTodo = ({String key, String noteId, String title, String words});

/// Whether [note] is a weekly report or the reports' journal: never counted, never read by the pass.
bool isWeeklyNote(Note note) => (frontMatterValue(note.body, weeklyWeekKey)?.trim() ?? '').isNotEmpty || frontMatterValue(note.body, weeklyJournalKey)?.trim() == 'weekly';

/// The week a report is of, from its front matter; null for a note that is none.
String? weekOfNote(Note note) {
  final key = frontMatterValue(note.body, weeklyWeekKey)?.trim();
  return key == null || key.isEmpty ? null : key;
}

/// A week's counts (see the library doc).
@immutable
class WeeklyCounts {
  const WeeklyCounts({
    required this.start,
    this.written = 0,
    this.edited = 0,
    this.words = 0,
    this.todosDone = 0,
    this.todosAdded = 0,
    this.todosOpen = 0,
    this.meetings = 0,
    this.recordings = 0,
    this.busiestDay,
    this.cameBack = const [],
    this.stale = const [],
    this.unfinished = const [],
    this.touched = const [],
  });

  final DateTime start;
  final int written;
  final int edited;
  final int words;
  final int todosDone;
  final int todosAdded;
  final int todosOpen;
  final int meetings;
  final int recordings;

  /// The day with the most notes written or edited, and how many.
  final ({DateTime day, int count})? busiestDay;

  /// The notes written before the week and come back to most in it, by saves.
  final List<WeeklyNote> cameBack;

  /// Notes that crossed the stale line in it, with the day they were last edited (ms).
  final List<WeeklyNote> stale;
  final List<WeeklyTodo> unfinished;

  /// The notes written or edited in it, newest edit first, by id.
  final List<String> touched;

  bool get empty => written == 0 && edited == 0;

  /// The numbers alone, as the report keeps them: what the AI is told when the summary is added later.
  Map<String, int> get numbers => {
        'written': written,
        'edited': edited,
        'words': words,
        'done': todosDone,
        'added': todosAdded,
        'open': todosOpen,
        'meetings': meetings,
        'recordings': recordings,
      };

  /// These counts with the numbers [kept] by the report made earlier, the lists as they are now.
  WeeklyCounts withNumbers(Map<String, int> kept) => WeeklyCounts(
        start: start,
        written: kept['written'] ?? written,
        edited: kept['edited'] ?? edited,
        words: kept['words'] ?? words,
        todosDone: kept['done'] ?? todosDone,
        todosAdded: kept['added'] ?? todosAdded,
        todosOpen: kept['open'] ?? todosOpen,
        meetings: kept['meetings'] ?? meetings,
        recordings: kept['recordings'] ?? recordings,
        busiestDay: busiestDay,
        cameBack: cameBack,
        stale: stale,
        unfinished: unfinished,
        touched: touched,
      );

  /// The home card's line: "12 notes · 4 to-dos done".
  String get line => [
        '${written + edited} ${written + edited == 1 ? 'note' : 'notes'}',
        if (todosDone > 0) '$todosDone ${todosDone == 1 ? 'to-do' : 'to-dos'} done',
        if (todosDone == 0 && words > 0) '${_thousands(words)} words',
      ].join(' · ');
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// The counts of [notes] (the person's own, out of the Trash, reports left out) for the week from [start], as at
/// [now]. [todosBefore] and [revsBefore] are what the last report saw (null the first time); [dismissed] the review's
/// Keep and Dismiss, so a to-do or note kept is not raised again; [staleAfter] the stale line.
WeeklyCounts weeklyCounts(
  List<Note> notes, {
  required DateTime start,
  Map<String, bool>? todosBefore,
  Map<String, int>? revsBefore,
  Set<String> dismissed = const {},
  Duration staleAfter = const Duration(days: 270),
  int most = 5,
}) {
  final end = weekEndOf(start);
  final from = start.millisecondsSinceEpoch, to = end.millisecondsSinceEpoch;
  bool inside(int ms) => ms >= from && ms < to;
  final live = [for (final n in notes) if (!n.inTrash && !isWeeklyNote(n)) n];
  final written = [for (final n in live) if (inside(n.createdAt)) n];
  final edited = [for (final n in live) if (n.createdAt < from && inside(n.updatedAt)) n];
  final touched = [...written, ...edited]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  // The to-dos, now and as the last report saw them.
  final now = <String, bool>{};
  for (final n in live) {
    if ((n.archivedAt ?? 0) != 0) continue;
    now.addAll(todoStates(n.id, n.body));
  }
  var done = 0, added = 0;
  if (todosBefore != null) {
    for (final MapEntry(:key, :value) in now.entries) {
      if (!todosBefore.containsKey(key)) added += 1;
      if (value && todosBefore[key] != true) done += 1;
    }
  } else {
    for (final n in written) {
      added += todoStates(n.id, n.body).length;
    }
    for (final n in touched) {
      done += todoStates(n.id, n.body).values.where((d) => d).length;
    }
  }

  // The busiest day: each note written on its day, each edit of an older one on its.
  final days = <DateTime, int>{};
  DateTime dayOf(int ms) {
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(at.year, at.month, at.day);
  }

  for (final n in written) {
    days.update(dayOf(n.createdAt), (c) => c + 1, ifAbsent: () => 1);
    if (dayOf(n.updatedAt) != dayOf(n.createdAt) && inside(n.updatedAt)) days.update(dayOf(n.updatedAt), (c) => c + 1, ifAbsent: () => 1);
  }
  for (final n in edited) {
    days.update(dayOf(n.updatedAt), (c) => c + 1, ifAbsent: () => 1);
  }
  final busiest = days.isEmpty ? null : (days.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key))).first;

  String titleOf(Note n) => noteTitle(n.body).trim();
  final back = [
    for (final n in edited)
      if (titleOf(n).isNotEmpty) (id: n.id, title: titleOf(n), count: revsBefore?[n.id] == null ? math.max(1, n.revision) : n.revision - revsBefore![n.id]!, at: n.updatedAt),
  ].where((b) => b.count > 0).toList()
    ..sort((a, b) => b.count != a.count ? b.count - a.count : b.at.compareTo(a.at));

  final stale = [
    for (final n in live)
      if ((n.archivedAt ?? 0) == 0 && !dismissed.contains('stale:${n.id}') && inside(n.updatedAt + staleAfter.inMilliseconds) && titleOf(n).isNotEmpty) (id: n.id, title: titleOf(n), count: n.updatedAt),
  ]..sort((a, b) => a.count.compareTo(b.count));

  // A few unfinished to-dos: the week's own notes' first, then the oldest notes'.
  final unfinished = <WeeklyTodo>[];
  final older = [for (final n in live) if ((n.archivedAt ?? 0) == 0 && !touched.contains(n)) n]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  for (final n in [...touched, ...older]) {
    if (unfinished.length >= most) break;
    if ((n.archivedAt ?? 0) != 0 || titleOf(n).isEmpty) continue;
    for (final todo in openTodos(n.id, n.body)) {
      if (unfinished.length >= most) break;
      if (dismissed.contains('todo:${todo.key}')) continue;
      unfinished.add((key: todo.key, noteId: n.id, title: titleOf(n), words: todo.words.trim()));
    }
  }

  return WeeklyCounts(
    start: start,
    written: written.length,
    edited: edited.length,
    words: written.fold(0, (sum, n) => sum + noteWords(n.body)),
    todosDone: done,
    todosAdded: added,
    todosOpen: now.values.where((d) => !d).length,
    meetings: written.where(isMeetingNote).length,
    recordings: written.where(isRecordingNote).length,
    busiestDay: busiest == null ? null : (day: busiest.key, count: busiest.value),
    cameBack: [for (final b in back.take(3)) (id: b.id, title: b.title, count: b.count)],
    stale: stale.take(most).toList(),
    unfinished: unfinished,
    touched: [for (final n in touched) n.id],
  );
}

/// What the next report compares with: every to-do of [notes] and every note's revision, now.
({Map<String, bool> todos, Map<String, int> revs}) weeklySnapshot(List<Note> notes) {
  final todos = <String, bool>{}, revs = <String, int>{};
  for (final n in notes) {
    if (n.inTrash || isWeeklyNote(n)) continue;
    revs[n.id] = n.revision;
    if ((n.archivedAt ?? 0) == 0) todos.addAll(todoStates(n.id, n.body));
  }
  return (todos: todos, revs: revs);
}

// ---- the AI's part --------------------------------------------------------------------------------------------------

/// What a next step does, as one of Wrapped's own presses.
enum WeeklyStepKind {
  checkOff('check_off'),
  archive('archive'),
  link('link'),
  look('look');

  const WeeklyStepKind(this.wire);
  final String wire;

  static WeeklyStepKind? of(Object? wire) => values.where((k) => k.wire == wire).firstOrNull;
}

/// One next step the AI suggests: its words, and what it would do.
@immutable
class WeeklyStep {
  const WeeklyStep({required this.kind, required this.words, this.todos = const [], this.notes = const [], this.record, this.dismissed = false});

  final WeeklyStepKind kind;
  final String words;

  /// The to-dos it checks off, by key.
  final List<String> todos;

  /// The notes it archives, or the two it links (from, to), or the one to look at.
  final List<String> notes;

  /// The press's record once applied, for Undo.
  final String? record;
  final bool dismissed;

  WeeklyStep copyWith({String? Function()? record, bool? dismissed}) =>
      WeeklyStep(kind: kind, words: words, todos: todos, notes: notes, record: record == null ? this.record : record(), dismissed: dismissed ?? this.dismissed);

  Map<String, Object?> toJson() => {'kind': kind.wire, 'words': words, if (todos.isNotEmpty) 'todos': todos, if (notes.isNotEmpty) 'notes': notes, 'record': ?record, if (dismissed) 'dismissed': true};

  static WeeklyStep? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = WeeklyStepKind.of(json['kind']);
    if (kind == null || json['words'] is! String) return null;
    List<String> list(String key) => [if (json[key] case final List l) for (final e in l) if (e is String) e];
    return WeeklyStep(kind: kind, words: json['words'] as String, todos: list('todos'), notes: list('notes'), record: json['record'] is String ? json['record'] as String : null, dismissed: json['dismissed'] == true);
  }
}

/// What the AI said of the week.
@immutable
class WeeklyAi {
  const WeeklyAi({this.summary = '', this.themes = const [], this.steps = const []});
  final String summary;
  final List<String> themes;
  final List<WeeklyStep> steps;

  bool get isEmpty => summary.isEmpty && themes.isEmpty && steps.isEmpty;
}

/// The most notes and to-dos one weekly ask is shown.
const int weeklyMostNotes = 40, weeklyMostTodos = 30;

const String weeklySystem = '''You write a short weekly report of someone's notes, "Your week in notes". You are shown the week's counts, a one-line gist of each note they wrote or edited (refs n1, n2, …), and some of their open to-dos (refs t1, t2, …, each with the note it is in).
Answer with:
- "summary": 3 to 5 plain sentences on what the week was about, written to them ("You spent most of the week on …"). No lists, no counts they can already see.
- "themes": 2 to 4 short themes of the week, lower case.
- "steps": exactly 3 next steps or tidy-ups, most useful first, each one of:
  {"kind": "check_off", "todos": ["t1", "t4"], "words": "These 2 to-dos about the launch look finished"} — only to-dos the gists suggest are already done;
  {"kind": "archive", "notes": ["n3"], "words": "…"} — notes that look finished with or abandoned;
  {"kind": "link", "from": "n1", "to": "n2", "words": "…"} — two notes on one subject that should link;
  {"kind": "look", "notes": ["n5"], "words": "…"} — a note worth coming back to.
  Each "words" one short sentence, at most 16 words.
Refer to notes and to-dos only by their refs; never invent one. Answer with one JSON object and nothing else.''';

/// What the weekly ask is sent: [counts] in words, then each of [notes] with its gist from [reads], then [todos].
String weeklyPrompt(WeeklyCounts counts, List<WrappedNote> notes, Map<String, WrappedRead> reads, List<WeeklyTodo> todos) => [
      'The week of ${weekSpanWords(counts.start)}:',
      '- ${counts.written} notes written (${counts.words} words), ${counts.edited} older notes edited',
      '- ${counts.todosDone} to-dos done, ${counts.todosAdded} added, ${counts.todosOpen} still open',
      '- ${counts.meetings} meetings, ${counts.recordings} recordings',
      if (counts.busiestDay case final busiest?) '- busiest day: ${dayNames[busiest.day.weekday - 1]}',
      '',
      'Notes (${notes.length}):',
      if (notes.isEmpty) '(none)',
      for (var i = 0; i < notes.length; i += 1)
        '[n${i + 1}] ${notes[i].title.trim().isEmpty ? '(no title)' : '“${notes[i].title.trim()}”'} · ${notes[i].folder.isEmpty ? 'no folder' : notes[i].folder} · ${notes[i].createdAt >= counts.start.millisecondsSinceEpoch ? 'new' : 'edited'} · ${reads[notes[i].id]?.gist ?? ''}',
      '',
      'Open to-dos (${todos.length}):',
      if (todos.isEmpty) '(none)',
      for (var i = 0; i < todos.length; i += 1) '[t${i + 1}] ${_short(todos[i].words, 100)} (in “${_short(todos[i].title, 60)}”)',
    ].join('\n');

String _short(String text, int most) {
  final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length > most ? '${one.substring(0, most - 1)}…' : one;
}

/// The AI's answer read, every ref checked against [notes] and [todos]; at most 3 steps. Never throws.
WeeklyAi readWeeklyAnswer(String output, List<WrappedNote> notes, List<WeeklyTodo> todos) {
  final answer = jsonObjectIn(output);
  if (answer == null) return const WeeklyAi();
  String? note(Object? ref) {
    final i = ref is String ? int.tryParse(ref.trim().toLowerCase().replaceFirst('n', '')) : null;
    return i == null || i < 1 || i > notes.length ? null : notes[i - 1].id;
  }

  String? todo(Object? ref) {
    final i = ref is String ? int.tryParse(ref.trim().toLowerCase().replaceFirst('t', '')) : null;
    return i == null || i < 1 || i > todos.length ? null : todos[i - 1].key;
  }

  final steps = <WeeklyStep>[];
  if (answer['steps'] case final List list) {
    for (final e in list) {
      if (steps.length >= 3) break;
      if (e is! Map) continue;
      final kind = WeeklyStepKind.of(e['kind']);
      final words = e['words'] is String ? _short(e['words'] as String, 140) : '';
      if (kind == null || words.isEmpty) continue;
      List<String> refs(String key, String? Function(Object?) of) => <String>{
            if (e[key] case final List l)
              for (final r in l) ?of(r),
          }.toList();
      final step = switch (kind) {
        WeeklyStepKind.checkOff => WeeklyStep(kind: kind, words: words, todos: refs('todos', todo)),
        WeeklyStepKind.archive || WeeklyStepKind.look => WeeklyStep(kind: kind, words: words, notes: refs('notes', note)),
        WeeklyStepKind.link => WeeklyStep(kind: kind, words: words, notes: [?note(e['from']), ?note(e['to'])]),
      };
      final whole = switch (kind) {
        WeeklyStepKind.checkOff => step.todos.isNotEmpty,
        WeeklyStepKind.link => step.notes.length == 2 && step.notes.first != step.notes.last,
        _ => step.notes.isNotEmpty,
      };
      if (whole) steps.add(step);
    }
  }
  final themes = answer['themes'];
  final summary = answer['summary'] is String ? (answer['summary'] as String).trim() : '';
  return WeeklyAi(
    summary: summary.length > 900 ? '${summary.substring(0, 899)}…' : summary,
    themes: [if (themes is List) for (final t in themes.take(4)) if (t is String && t.trim().isNotEmpty) _short(t, 40).toLowerCase()],
    steps: steps,
  );
}

/// About what one week's report costs with [ai]: [toGist] notes read for their gists ([WrappedPacing]'s batches), and
/// the one weekly ask with [notes] gists and [todos] to-dos.
({int tokens, double? dollars, String words}) weeklyEstimate(CleanupAi ai, {required int toGist, required int notes, required int todos, WrappedPacing? pacing}) {
  final pace = pacing ?? WrappedPacing.of(ai);
  final asks = (toGist / pace.notesPerAsk).ceil();
  final input = toGist * ((pace.charsPerNote / 4).ceil() + 40) + asks * 380 + 700 + math.min(notes, weeklyMostNotes) * 35 + math.min(todos, weeklyMostTodos) * 25;
  final output = toGist * 60 + 600;
  if (ai.local) return (tokens: input + output, dollars: null, words: 'on this device, nothing sent');
  final dollars = ai.id == 'claude' && ai.model != null ? claudeCost(ai.model!, ClaudeUsage(input: input, output: output)) : null;
  final money = dollars == null ? 'on your ${ai.name} key' : '· about ${claudeDollars(math.max(0.01, dollars))}';
  return (tokens: input + output, dollars: dollars, words: '~${tokenWords(input + output)} tokens $money a week');
}

// ---- the note -------------------------------------------------------------------------------------------------------

/// A link to a note by its title, as the editor writes one; a title a link cannot hold is said plainly.
String _link(String title) => title.contains(RegExp(r'[\[\]|#\n]')) ? '“$title”' : '[[$title]]';

String _day(DateTime at) => '${dayNames[at.weekday - 1]} ${at.day} ${monthNames[at.month - 1]}';

String _dayOfMs(int ms) {
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${at.day} ${_shortMonths[at.month - 1]} ${at.year}';
}

String _n(int n, String one, String many) => '${_thousands(n)} ${n == 1 ? one : many}';

/// The report's words: front matter (its title, its day for the journal, its week), then "In numbers", what was come
/// back to, what went stale, what is worth a look, and with the AI its summary, themes and next steps first. Plain
/// Markdown: links by title, no boxes (a report's lines are never counted as to-dos).
String weeklyMarkdown(WeeklyCounts c, {WeeklyAi? ai, String? aiName, String Function(String id)? titleOf}) {
  final title = weekTitle(c.start);
  final lines = <String>[
    '---',
    'title: ${quotedTitle(title, title)}',
    'date: ${weekKeyOf(c.start)}',
    '$weeklyWeekKey: ${weekKeyOf(c.start)}',
    '---',
    '# $title',
    '',
    '*${weekSpanWords(c.start)} · Your week in notes, by Wrapped*',
    '',
  ];
  if (ai != null) lines.addAll(_aboutLines(ai));
  lines.addAll([
    '## In numbers',
    '',
    '- ${_n(c.written, 'note', 'notes')} written, ${_n(c.edited, 'older note', 'older notes')} edited',
    '- ${_n(c.words, 'word', 'words')} written',
    '- ${_n(c.todosDone, 'to-do', 'to-dos')} done, ${c.todosAdded} added, ${c.todosOpen} still open',
    '- ${_n(c.meetings, 'meeting', 'meetings')}, ${_n(c.recordings, 'recording', 'recordings')}',
    if (c.busiestDay case final b?) '- Busiest day: ${_day(b.day)}, ${_n(b.count, 'note', 'notes')}',
    '',
  ]);
  if (c.cameBack.isNotEmpty) {
    lines.addAll(['## Came back to', '', for (final n in c.cameBack) '- ${_link(n.title)}, ${_n(n.count, 'save', 'saves')}', '']);
  }
  if (c.stale.isNotEmpty) {
    lines.addAll(['## Gone stale this week', '', for (final n in c.stale) '- ${_link(n.title)}, not edited since ${_dayOfMs(n.count)}', '']);
  }
  if (c.unfinished.isNotEmpty) {
    lines.addAll(['## Worth a look', '', for (final t in c.unfinished) '- ${_short(t.words, 120)}, in ${_link(t.title)}', '']);
  }
  if (ai != null) lines.addAll(_stepLines(ai, titleOf));
  if ((ai == null || ai.isEmpty) && aiName != null) lines.addAll([_countsAlone(aiName), '']);
  return lines.join('\n');
}

String _countsAlone(String aiName) => '*Made from the counts alone. Add the AI summary in Wrapped to have $aiName write what the week was about.*';

List<String> _aboutLines(WeeklyAi ai) => [
      if (ai.summary.isNotEmpty) ...['## What it was about', '', ai.summary, ''],
      if (ai.themes.isNotEmpty) ...['Themes: ${ai.themes.join(', ')}', ''],
    ];

List<String> _stepLines(WeeklyAi ai, String Function(String id)? titleOf) => ai.steps.isEmpty
    ? const []
    : [
        '## Next steps',
        '',
        for (var i = 0; i < ai.steps.length; i += 1)
          '${i + 1}. ${ai.steps[i].words}${ai.steps[i].notes.isEmpty || titleOf == null ? '' : ': ${[for (final id in ai.steps[i].notes) if (titleOf(id).isNotEmpty) _link(titleOf(id))].join(', ')}'}',
        '',
        '*Each can be done from Wrapped, with Undo.*',
        '',
      ];

/// A report made from the counts alone ([body], as it is now, the person's own edits kept) with the AI's part added:
/// what it was about over "In numbers", the next steps at its foot, and the counts-alone line taken out.
String withWeeklyAi(String body, WeeklyAi ai, {String Function(String id)? titleOf}) {
  final lines = body.split('\n');
  lines.removeWhere((line) => line.startsWith('*Made from the counts alone.'));
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  final numbers = lines.indexOf('## In numbers');
  final about = _aboutLines(ai);
  if (numbers >= 0) {
    lines.insertAll(numbers, about);
  } else {
    lines.addAll(['', ...about]);
  }
  final steps = _stepLines(ai, titleOf);
  return [...lines, if (steps.isNotEmpty) '', ...steps, if (steps.isEmpty) ''].join('\n');
}

/// A new reports' journal: `book: true`, `journal: true` and `wrapped: weekly`, its index empty.
String weeklyJournalBody() =>
    '---\ntitle: "$weeklyJournalName"\nbook: true\njournal: true\ntemplate: ${jsonEncode('# {{date}}\n\n')}\n$weeklyJournalKey: weekly\n---\n# $weeklyJournalName\n\nYour week in notes, each Monday, by Wrapped.\n\n';

// ---- what is kept ---------------------------------------------------------------------------------------------------

/// The last report made, as the page and the home card show it.
@immutable
class WeeklyReport {
  const WeeklyReport({required this.week, required this.noteId, required this.made, this.line = '', this.summary = '', this.steps = const [], this.viewed = false, this.ai = false, this.numbers = const {}});

  /// Its week's key ("2026-11-02") and its note.
  final String week;
  final String noteId;
  final DateTime made;

  /// The home card's line, and the AI's summary where there was one.
  final String line;
  final String summary;
  final List<WeeklyStep> steps;
  final bool viewed;

  /// Whether the AI wrote any of it.
  final bool ai;

  /// Its counts' numbers ([WeeklyCounts.numbers]), for the summary added later.
  final Map<String, int> numbers;

  WeeklyReport copyWith({bool? viewed, List<WeeklyStep>? steps, String? summary, bool? ai}) => WeeklyReport(
        week: week,
        noteId: noteId,
        made: made,
        line: line,
        summary: summary ?? this.summary,
        steps: steps ?? this.steps,
        viewed: viewed ?? this.viewed,
        ai: ai ?? this.ai,
        numbers: numbers,
      );

  Map<String, Object?> toJson() => {
        'week': week,
        'note': noteId,
        'made': made.toUtc().toIso8601String(),
        if (line.isNotEmpty) 'line': line,
        if (summary.isNotEmpty) 'summary': summary,
        if (steps.isNotEmpty) 'steps': [for (final s in steps) s.toJson()],
        if (viewed) 'viewed': true,
        if (ai) 'ai': true,
        if (numbers.isNotEmpty) 'numbers': numbers,
      };

  static WeeklyReport? fromJson(Object? json) {
    if (json is! Map || json['week'] is! String || json['note'] is! String) return null;
    final made = json['made'] is String ? DateTime.tryParse(json['made'] as String) : null;
    return WeeklyReport(
      week: json['week'] as String,
      noteId: json['note'] as String,
      made: made?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      line: json['line'] is String ? json['line'] as String : '',
      summary: json['summary'] is String ? json['summary'] as String : '',
      steps: [if (json['steps'] case final List l) for (final s in l) ?WeeklyStep.fromJson(s)],
      viewed: json['viewed'] == true,
      ai: json['ai'] == true,
      numbers: {if (json['numbers'] case final Map m) for (final MapEntry(:key, :value) in m.entries) if (key is String && value is int) key: value},
    );
  }
}

/// What the weekly report keeps, in Wrapped's file (state.dart): the choices, the weeks made, the last report, the
/// AIs the person said may be spent on for it, and what the last report saw (to-dos by key, revisions by note).
@immutable
class WeeklyState {
  const WeeklyState({this.settings = const WeeklySettings(), this.weeks = const [], this.report, this.allowed = const {}, this.todos, this.revs});

  final WeeklySettings settings;

  /// The weeks made, by key, newest last: never made twice.
  final List<String> weeks;
  final WeeklyReport? report;

  /// The cloud AIs the person said yes to spending on each week, by id: the first report with one asks.
  final Set<String> allowed;

  /// What the last report saw: null before the first.
  final Map<String, bool>? todos;
  final Map<String, int>? revs;

  /// The most weeks remembered.
  static const int mostWeeks = 60;

  bool made(String week) => weeks.contains(week);

  WeeklyState copyWith({WeeklySettings? settings, List<String>? weeks, WeeklyReport? Function()? report, Set<String>? allowed, Map<String, bool>? todos, Map<String, int>? revs}) => WeeklyState(
        settings: settings ?? this.settings,
        weeks: weeks ?? this.weeks,
        report: report == null ? this.report : report(),
        allowed: allowed ?? this.allowed,
        todos: todos ?? this.todos,
        revs: revs ?? this.revs,
      );

  Map<String, Object?> toJson() => {
        'settings': settings.toJson(),
        'weeks': weeks,
        'report': ?report?.toJson(),
        if (allowed.isNotEmpty) 'allowed': (allowed.toList()..sort()),
        'todos': ?todos,
        'revs': ?revs,
      };

  static WeeklyState fromJson(Object? json) {
    if (json is! Map) return const WeeklyState();
    final todos = json['todos'], revs = json['revs'];
    return WeeklyState(
      settings: WeeklySettings.fromJson(json['settings']),
      weeks: [if (json['weeks'] case final List l) for (final w in l) if (w is String) w],
      report: WeeklyReport.fromJson(json['report']),
      allowed: {if (json['allowed'] case final List l) for (final a in l) if (a is String) a},
      todos: todos is Map ? {for (final MapEntry(:key, :value) in todos.entries) if (key is String && value is bool) key: value} : null,
      revs: revs is Map ? {for (final MapEntry(:key, :value) in revs.entries) if (key is String && value is int) key: value} : null,
    );
  }
}
