/// What the phone's home screen is handed of the notes (docs/FEATURES_2_1.md, "Home screen"): the to-dos for the
/// Today widget, the pinned notes for the Pinned widget, and the last notes opened for the icon's shortcuts. Pure
/// (test/home_screen/home_data_test.dart); [HomeScreenData] hands each over only when it is another than the last.
///
/// The widgets draw from what they were last handed, in the phone's own memory (HomeScreen.kt), so they show the
/// notes with the app closed, and the Today widget turns its own day at midnight: it is handed the open to-dos due
/// up to a week ahead and shows those due today and before.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../calendar/event.dart' show CalendarEvent, inDayOrder;
import '../core/book.dart' show guidePages, templatePages;
import '../core/days.dart' show isIsoDay, isoDayAfter, isoDay;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart' show hasTape;
import '../core/task_fields.dart' show fieldsOf;
import '../home/dashboard.dart' show openTasks;
import '../home/home_layout.dart' as layout show HomeKind, kindOf;
import '../reminders/dated_items.dart';
import '../reminders/tick_item.dart' show itemWords;
import '../simple/todos_groups.dart' show priorityWords;

/// How far ahead the Today widget is handed to-dos, so its midnight needs nothing of the app.
const int todayAhead = 7;

/// How many to-dos it is handed at most, the soonest due first; and how many pinned notes.
const int mostToday = 60;
const int mostPinned = 20;

/// One to-do as the Today widget draws it.
@immutable
class TodayItem {
  const TodayItem({required this.noteId, required this.line, required this.words, required this.due, required this.note, required this.tick});

  final String noteId;

  /// Its line, counting from 1; 0 for a ticket.
  final int line;
  final String words;
  final String due;

  /// The note's title, under the words.
  final String note;

  /// Whether it can be ticked from the widget.
  final bool tick;

  Map<String, Object?> toJson() => {'note': noteId, 'line': line, 'words': words.isEmpty ? 'Untitled to-do' : words, 'due': due, 'title': note.isEmpty ? 'Untitled' : note, 'tick': tick};

  @override
  bool operator ==(Object other) => other is TodayItem && other.noteId == noteId && other.line == line && other.words == words && other.due == due && other.note == note && other.tick == tick;

  @override
  int get hashCode => Object.hash(noteId, line, words, due, note, tick);
}

/// The open to-dos due by a week from [now], the soonest first: overdue, today, then the days to come.
List<TodayItem> todayItems(Iterable<Note> notes, {required DateTime now, bool Function(Note note)? skip, int most = mostToday}) {
  final last = isoDayAfter(isoDay(now), todayAhead)!;
  final out = <TodayItem>[];
  for (final note in notes) {
    if ((note.archivedAt ?? 0) != 0 || (skip?.call(note) ?? false)) continue;
    final items = DatedItems.of(note);
    if (items.isEmpty) continue;
    String? title;
    for (final item in items) {
      final due = item.due;
      if (item.done || due == null || !item.box || due.compareTo(last) > 0) continue;
      title ??= NoteFacts.of(note).title;
      out.add(TodayItem(noteId: note.id, line: item.line, words: item.words, due: due, note: title, tick: item.box));
    }
  }
  out.sort((a, b) {
    final day = a.due.compareTo(b.due);
    if (day != 0) return day;
    final note = a.note.toLowerCase().compareTo(b.note.toLowerCase());
    return note != 0 ? note : a.line.compareTo(b.line);
  });
  return out.length > most ? out.sublist(0, most) : out;
}

/// A note as the Pinned widget and a shortcut name it.
typedef NamedNote = ({String id, String title});

/// The pinned notes, the one written in last first.
List<NamedNote> pinnedNotes(Iterable<Note> notes, {bool Function(Note note)? skip, int most = mostPinned}) {
  final pinned = [
    for (final note in notes)
      if (note.starred && (note.archivedAt ?? 0) == 0 && !(skip?.call(note) ?? false)) note,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final note in pinned.take(most)) (id: note.id, title: _titled(note))];
}

String _titled(Note note) {
  final title = NoteFacts.of(note).title.trim();
  return title.isEmpty ? 'Untitled' : title;
}

/// Whether [note] has no words yet: a new note opened and not written in, which the icon does not offer.
bool blankNote(Note note) => note.body.trim().isEmpty;

/// The notes [ids] name, as the library has them now, in that order; those gone, blank or in the Trash left out.
List<NamedNote> namedNotes(List<String> ids, Note? Function(String id) noteOf, {bool Function(Note note)? skip}) => [
      for (final id in ids)
        if (noteOf(id) case final Note note when (note.archivedAt ?? 0) == 0 && !blankNote(note) && !(skip?.call(note) ?? false)) (id: id, title: _titled(note)),
    ];

String todayJson(List<TodayItem> items) => jsonEncode({'items': [for (final item in items) item.toJson()]});

String namedJson(List<NamedNote> notes) => jsonEncode({'notes': [for (final note in notes) {'id': note.id, 'title': note.title}]});

/// The notes opened last, the newest first, [most] of them: what the icon's shortcuts name.
List<String> openedLast(List<String> before, String opened, {int most = 3}) => [opened, ...before.where((id) => id != opened)].take(most).toList();

// ---- the four widgets (docs/WIDGETS_ANDROID.md) ---------------------------------------------------------------------
//
// Voice note, To-dos, Calendar and Recent notes on Android, each handed what it draws as JSON (HomeScreen.kt reads it,
// home/HomeData.kt groups and words it). The shapes are the shared widget snapshot's (the iPhone's
// lib/home_screen/widget_snapshot.dart: a to-do's `words`, `match`, `title`, `due`, `priority`; a note's `id`,
// `title`, `line`, `updated`, `pinned`; `calendar` and its `events` with an all-day one's days and a timed one's
// moments in UTC), with what Android draws besides: a note's `kind` and a tape's `ms`, the recordings, a ticket among
// the to-dos. Days are `YYYY-MM-DD` and times moments, never words, so the phone words them itself as the day goes on
// ("20 min ago", "Tomorrow") with the app closed.

/// How many to-dos with no due date the To-dos widget is handed (the notes touched last first), as Someday.
const int mostSomeday = 30;

/// How many notes the Recent notes widget is handed: its large size two columns of them on a wide screen.
const int mostNotes = 16;

/// How many recordings the Voice note widget is handed: the last one, and the three its large size lists.
const int mostRecordings = 3;

/// How far ahead the Calendar widget is handed events, and how many at most.
const int calendarAhead = 7;
const int mostEvents = 60;

/// One open to-do as the To-dos and Calendar widgets draw it: [words] what the row says, [match] the words its line is
/// found by again to tick it (tick_item.dart `itemWords`). Both are the line with every task field taken off by the
/// whole field grammar (a reminder's `⏰ 2026-10-16 13:53` too, which the To-dos view's reduced reading leaves in).
@immutable
class HomeTodo {
  const HomeTodo({required this.noteId, required this.line, required this.words, required this.match, this.due, required this.note, this.priority});

  final String noteId;

  /// Its line, counting from 1; 0 for a ticket.
  final int line;
  final String words;
  final String match;

  /// Its due day, `2026-10-03`, or null for none (Someday).
  final String? due;

  /// The note's title, under the words.
  final String note;

  /// `highest` or `high`, the two worth a word (`priorityWords`); null for any other.
  final String? priority;

  Map<String, Object?> toJson() => {
        'note': noteId,
        'line': line,
        'words': words.isEmpty ? (match.isEmpty ? 'Untitled to-do' : match) : words,
        'match': match,
        'title': note.isEmpty ? 'Untitled' : note,
        'due': ?due,
        'priority': ?priority,
      };

  @override
  bool operator ==(Object other) =>
      other is HomeTodo && other.noteId == noteId && other.line == line && other.words == words && other.match == match && other.due == due && other.note == note && other.priority == priority;

  @override
  int get hashCode => Object.hash(noteId, line, words, match, due, note, priority);
}

/// The open to-dos the To-dos widget lists: those due by a week from [now] ([todayItems]: overdue, today, the days to
/// come, tickets among them), then those with no date, the notes touched last first, [someday] of them. A dated
/// to-do further off than a week is not handed over: the app hands the set over again as the days come.
List<HomeTodo> homeTodos(List<Note> notes, {required DateTime now, bool Function(Note note)? skip, int someday = mostSomeday}) {
  final kept = [for (final note in notes) if (!(skip?.call(note) ?? false)) note];
  final open = openTasks(kept);
  final byId = {for (final note in kept) note.id: note};
  String? priorityOf(String noteId, int line) {
    final lines = byId[noteId]?.body.split('\n');
    if (line < 1 || lines == null || line > lines.length) return null;
    return priorityWords(fieldsOf(lines[line - 1]).priority)?.toLowerCase();
  }

  final out = <HomeTodo>[
    for (final item in todayItems(kept, now: now))
      HomeTodo(noteId: item.noteId, line: item.line, words: item.words, match: item.words, due: item.due, note: item.note, priority: priorityOf(item.noteId, item.line)),
  ];
  var undated = 0;
  for (final task in open) {
    if (undated >= someday) break;
    final note = byId[task.noteId];
    if (note == null) continue;
    final lines = note.body.split('\n');
    if (task.line >= lines.length) continue;
    final line = lines[task.line];
    final fields = fieldsOf(line);
    // Dated ones are [todayItems]'s, near or far.
    if (fields.due != null && isIsoDay(fields.due!)) continue;
    out.add(HomeTodo(noteId: note.id, line: task.line + 1, words: itemWords(line), match: itemWords(line), note: _titled(note), priority: priorityWords(fields.priority)?.toLowerCase()));
    undated += 1;
  }
  return out;
}

String todosJson(List<HomeTodo> todos) => jsonEncode({'todos': [for (final todo in todos) todo.toJson()]});

/// A note as the Recent notes and Voice note widgets list it: its name, how it starts, when it was touched (a
/// recording: when it was made), whether it is pinned, and what Android draws besides: its kind (`note`, `tape`,
/// `book`, `canvas`: its mark) and how long its recording is.
@immutable
class HomeNote {
  const HomeNote({required this.id, required this.title, required this.line, required this.updated, required this.kind, this.ms = 0, this.pinned = false});

  final String id;
  final String title;
  final String line;
  final int updated;
  final String kind;
  final int ms;
  final bool pinned;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'line': line, 'updated': updated, if (pinned) 'pinned': true, 'kind': kind, if (ms > 0) 'ms': ms};

  @override
  bool operator ==(Object other) => other is HomeNote && other.id == id && other.title == title && other.line == line && other.updated == updated && other.kind == kind && other.ms == ms && other.pinned == pinned;

  @override
  int get hashCode => Object.hash(id, title, line, updated, kind, ms, pinned);
}

/// The person's own notes: not archived, not blank, not in the Trash, not the Guide's pages or a template.
List<Note> _ownNotes(List<Note> notes, bool Function(Note note)? skip) {
  final apart = {...guidePages(notes), ...templatePages(notes)};
  return [
    for (final note in notes)
      if ((note.archivedAt ?? 0) == 0 && !blankNote(note) && !apart.contains(note.id) && !(skip?.call(note) ?? false)) note,
  ];
}

HomeNote _homeNote(Note note, {required int at}) {
  final facts = NoteFacts.of(note);
  final kind = switch (layout.kindOf(note)) {
    layout.HomeKind.book => 'book',
    layout.HomeKind.canvas => 'canvas',
    layout.HomeKind.tape => 'tape',
    layout.HomeKind.note => 'note',
  };
  final title = facts.shownTitle.trim();
  return HomeNote(id: note.id, title: title.isEmpty ? 'Untitled' : title, line: facts.shownFirstLine, updated: at, kind: kind, ms: note.recordingMs ?? 0, pinned: note.starred);
}

/// The notes touched last, newest first: what Recent notes lists.
List<HomeNote> homeNotes(List<Note> notes, {bool Function(Note note)? skip, int most = mostNotes}) {
  final own = _ownNotes(notes, skip)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final note in own.take(most)) _homeNote(note, at: note.updatedAt)];
}

/// The recordings, the last recorded first (by when the note was made, as the app's tapes are ordered): what Voice
/// note says beside its microphone.
List<HomeNote> homeRecordings(List<Note> notes, {bool Function(Note note)? skip, int most = mostRecordings}) {
  final taped = [for (final note in _ownNotes(notes, skip)) if (hasTape(note)) note]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return [for (final note in taped.take(most)) _homeNote(note, at: note.createdAt)];
}

String notesJson(List<HomeNote> notes) => jsonEncode({'notes': [for (final note in notes) note.toJson()]});

/// What the Calendar widget is handed: whether the Calendar plugin is on (`calendar`), and the events from today to a
/// week on, [inDayOrder], [most] of them, each as the shared snapshot writes one: an all-day one's first day and the
/// day after its last, a timed one's moments in UTC. Off, no events: the widget says where to turn it on.
String calendarJson({required bool on, required List<CalendarEvent> events, required DateTime now, int most = mostEvents}) {
  if (!on) return jsonEncode({'calendar': false, 'events': const <Object>[]});
  final today = isoDay(now), last = isoDayAfter(today, calendarAhead)!;
  final shown = [
    for (final event in inDayOrder(events))
      if (event.lastDay.compareTo(today) >= 0 && event.firstDay.compareTo(last) <= 0) event,
  ].take(most);
  return jsonEncode({
    'calendar': true,
    'events': [
      for (final event in shown)
        {
          'id': '${event.source}/${event.id}',
          'title': event.title.trim().isEmpty ? 'Untitled event' : event.title.trim(),
          'calendar': event.calendar,
          'allDay': event.allDay,
          'start': event.allDay ? isoDay(event.start) : event.start.toUtc().toIso8601String(),
          'end': event.allDay ? isoDay(event.end) : event.end.toUtc().toIso8601String(),
          if (event.location != null) 'location': event.location,
        },
    ],
  });
}

/// Which look the widgets are drawn in: the app's own theme's side (`themeScheme`: `dark`, `light`, or `system` to
/// follow the phone), so a widget is the app's Dark on a phone that is light, as the app is.
String lookJson(String scheme) => jsonEncode({'theme': scheme == 'dark' || scheme == 'light' ? scheme : 'system'});
