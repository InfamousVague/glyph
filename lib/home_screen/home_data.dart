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
import '../core/front_matter.dart' show frontMatterEnd;
import '../core/item_syntax.dart' show lineWords;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart' show hasTape, noteTitle, withoutAnchor;
import '../core/task_fields.dart' show fieldsOf;
import '../core/workspaces.dart' show Workspaces, orgOfWorkspace, workspaceFamily, workspacePathName;
import '../home/dashboard.dart' show openTasks;
import '../home/home_layout.dart' as layout show HomeKind, kindOf;
import '../notes/daily_notes.dart' show dailyNoteOf;
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

// ---- the eight more (docs/WIDGETS_ANDROID.md, "Twelve") -------------------------------------------------------------
//
// Pinned notes, Today, A note and A folder draw a note's own lines or a workspace's notes; Ask AI draws whether the
// app shows its assistant. Quick capture, Search and Next up are drawn from what the four are handed already (the
// links, the notes, the to-dos and the events). As with the four, nothing here is words a day changes: days are
// `YYYY-MM-DD`, times moments, and the phone words them.

/// How many pinned notes the Pinned notes widget is handed: its large size two columns of them on a wide screen.
const int mostPins = 16;

/// How many notes the configuration of A note offers to choose among, the pinned first.
const int mostPicks = 200;

/// How many of a note's lines A note and Today are handed: more than a large one on the opened Fold holds.
const int mostPageLines = 24;

/// How many workspaces and folders A folder's configuration offers, and how many of each one's notes are handed.
const int mostFolders = 80;
const int mostFolderNotes = 12;

/// The pinned notes, the one written in last first: what Pinned notes lists, in Recent notes' rows.
List<HomeNote> homePins(List<Note> notes, {bool Function(Note note)? skip, int most = mostPins}) {
  final pinned = [for (final note in _ownNotes(notes, skip)) if (note.starred) note]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final note in pinned.take(most)) _homeNote(note, at: note.updatedAt)];
}

/// The notes A note's configuration offers: the person's own, the pinned first, then the one written in last first.
List<HomeNote> homePicks(List<Note> notes, {bool Function(Note note)? skip, int most = mostPicks}) {
  final own = _ownNotes(notes, skip)
    ..sort((a, b) {
      if (a.starred != b.starred) return a.starred ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  return [for (final note in own.take(most)) _homeNote(note, at: note.updatedAt)];
}

/// What one of a note's lines is, as A note and Today draw it: words, a heading, a list item, a quote, or a to-do
/// open or ticked (the To-dos view's round tick, which ticks it in place).
enum PageLineKind { text, heading, bullet, quote, todo, done }

/// One line of a note as A note and Today draw it: [line] its number in the note, counting from 1 (the tick finds it
/// by that and [match], tick_item.dart's `itemWords`), [words] what it says with the Markdown's marks taken off,
/// [depth] how far a list item is in.
@immutable
class PageLine {
  const PageLine({required this.line, required this.kind, required this.words, this.match, this.depth = 0});

  final int line;
  final PageLineKind kind;
  final String words;

  /// What a to-do's line is found by again to tick it; null for any other line.
  final String? match;
  final int depth;

  Map<String, Object?> toJson() => {'line': line, 'kind': kind.name, 'words': words, 'match': ?match, if (depth > 0) 'depth': depth};

  @override
  bool operator ==(Object other) => other is PageLine && other.line == line && other.kind == kind && other.words == words && other.match == match && other.depth == depth;

  @override
  int get hashCode => Object.hash(line, kind, words, match, depth);

  @override
  String toString() => 'PageLine($line ${kind.name} "$words"${depth > 0 ? ' +$depth' : ''})';
}

/// A note as A note and Today draw it: its row (its name, its kind's mark, when it was written in) and its first
/// lines after its name.
@immutable
class HomePage {
  const HomePage({required this.note, required this.lines});

  final HomeNote note;
  final List<PageLine> lines;

  Map<String, Object?> toJson() => {...note.toJson(), 'lines': [for (final line in lines) line.toJson()]};

  @override
  bool operator ==(Object other) => other is HomePage && other.note == note && listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(note, Object.hashAll(lines));
}

final RegExp _boxLead = RegExp(r'^(\s*)(?:>\s?)*[-*+]\s+\[([ xX])\](?:\s|$)');
final RegExp _listLead = RegExp(r'^(\s*)(?:[-*+]|\d+[.)])\s+');
final RegExp _headingLead = RegExp(r'^#{1,6}\s+');
final RegExp _quoteLead = RegExp(r'^\s*>');
final RegExp _fenceLead = RegExp(r'^\s*(```|~~~)');
final RegExp _pictureOnly = RegExp(r'^\s*!\[[^\]]*\]\([^)]*\)\s*$');
final RegExp _ruleLine = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
final RegExp _htmlComment = RegExp(r'^\s*<!--');
final RegExp _wikiLink = RegExp(r'!?\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');
final RegExp _mdLink = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
final RegExp _marks = RegExp(r'\*\*|__|~~|==|`');

/// What a line says on a widget: tick_item.dart's words (no lead, no box, no anchor, no field), a link's words for
/// the link, and the stars and backticks taken off.
String _plain(String words) => words
    .replaceAllMapped(_wikiLink, (m) => m.group(2) ?? m.group(1) ?? '')
    .replaceAllMapped(_mdLink, (m) => m.group(1) ?? '')
    .replaceAll(_marks, '')
    .trim();

/// [note]'s first [most] lines after its name, as A note and Today draw them: front matter, a fenced block (a board,
/// code, comments), a picture alone on its line, a table, a rule and blank lines left out, each line said plainly.
List<PageLine> pageLines(Note note, {int most = mostPageLines}) {
  final lines = note.body.split('\n');
  final title = noteTitle(note.body).trim();
  var titleSeen = title.isEmpty;
  String? fence;
  final out = <PageLine>[];
  for (var index = frontMatterEnd(lines); index < lines.length && out.length < most; index += 1) {
    final raw = lines[index];
    final fenced = _fenceLead.firstMatch(raw);
    if (fence != null) {
      if (fenced != null && raw.trim().startsWith(fence)) fence = null;
      continue;
    }
    if (fenced != null) {
      fence = fenced.group(1);
      continue;
    }
    if (raw.trim().isEmpty || _pictureOnly.hasMatch(raw) || _ruleLine.hasMatch(raw) || raw.trimLeft().startsWith('|') || _htmlComment.hasMatch(raw)) continue;
    final number = index + 1;
    final box = _boxLead.firstMatch(raw);
    if (box != null) {
      final match = itemWords(raw);
      final words = _plain(match);
      if (words.isEmpty) continue;
      titleSeen = true;
      final ticked = box.group(2)!.toLowerCase() == 'x';
      out.add(PageLine(line: number, kind: ticked ? PageLineKind.done : PageLineKind.todo, words: words, match: match, depth: _depth(box.group(1)!)));
      continue;
    }
    final heading = _headingLead.hasMatch(raw.trimLeft());
    final words = _plain(withoutAnchor(heading ? raw.trimLeft().replaceFirst(_headingLead, '') : lineWords(raw)));
    if (words.isEmpty) continue;
    // The name is the widget's heading, not one of its lines.
    if (!titleSeen && words == _plain(title)) {
      titleSeen = true;
      continue;
    }
    titleSeen = true;
    final list = _listLead.firstMatch(raw);
    final kind = heading
        ? PageLineKind.heading
        : _quoteLead.hasMatch(raw)
            ? PageLineKind.quote
            : list != null
                ? PageLineKind.bullet
                : PageLineKind.text;
    out.add(PageLine(line: number, kind: kind, words: words, depth: list == null ? 0 : _depth(list.group(1)!)));
  }
  return out;
}

/// How far a list item is in: a level for each tab or two spaces, three at most.
int _depth(String lead) {
  final depth = lead.replaceAll('\t', '  ').length ~/ 2;
  return depth > 3 ? 3 : depth;
}

/// [note] as A note and Today draw it.
HomePage homePage(Note note, {int most = mostPageLines}) => HomePage(note: _homeNote(note, at: note.updatedAt), lines: pageLines(note, most: most));

/// The notes the phone's A note widgets show ([chosen], by id, as HomeScreen.kt keeps them): each drawn ([homePage]),
/// and those deleted or in the Trash said as gone, so the widget can say so and offer another.
({List<HomePage> pages, List<String> gone}) homePages(List<String> chosen, Note? Function(String id) noteOf, {bool Function(Note note)? skip}) {
  final pages = <HomePage>[], gone = <String>[];
  for (final id in chosen.toSet()) {
    final note = noteOf(id);
    if (note == null || (skip?.call(note) ?? false)) {
      gone.add(id);
    } else {
      pages.add(homePage(note));
    }
  }
  return (pages: pages, gone: gone);
}

String pagesJson(({List<HomePage> pages, List<String> gone}) chosen) => jsonEncode({'pages': [for (final page in chosen.pages) page.toJson()], 'gone': chosen.gone});

/// What Today is handed: the day it is for (the phone says nothing is written yet once the day has turned), and
/// that day's note (lib/notes/daily_notes.dart `dailyNoteOf`, the note Today's note opens) drawn as A note draws one,
/// where there is one.
String dailyJson(List<Note> notes, {required DateTime now, bool Function(Note note)? skip}) {
  final note = dailyNoteOf([for (final note in notes) if (!(skip?.call(note) ?? false)) note], now);
  return jsonEncode({'day': isoDay(now), if (note != null) 'note': homePage(note).toJson()});
}

/// A workspace or a folder as A folder draws it: its own name, its name with its parents' before it (an
/// organization's folder "Ghost.md › Clients", workspacePathName), whether it is in an organization, its hue, how
/// many notes are in it and the folders under it, and the ones written in last.
@immutable
class HomeFolder {
  const HomeFolder({required this.id, required this.name, required this.path, this.org = false, this.hue, required this.count, required this.notes});

  final String id;
  final String name;
  final String path;
  final bool org;
  final String? hue;
  final int count;
  final List<HomeNote> notes;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'path': path, if (org) 'org': true, 'hue': ?hue, 'count': count, 'notes': [for (final note in notes) note.toJson()]};

  @override
  bool operator ==(Object other) =>
      other is HomeFolder && other.id == id && other.name == name && other.path == path && other.org == org && other.hue == hue && other.count == count && listEquals(other.notes, notes);

  @override
  int get hashCode => Object.hash(id, name, path, org, hue, count, Object.hashAll(notes));
}

/// Every workspace and folder, organizations' among them, in the order of their names with their parents' (so a
/// folder comes under the one it is in), each with its notes: those filed in it or in a folder under it, as choosing
/// it on the home page shows them, the one written in last first.
List<HomeFolder> homeFolders(List<Note> notes, Workspaces spaces, {bool Function(Note note)? skip, int most = mostFolders, int each = mostFolderNotes}) {
  final own = _ownNotes(notes, skip)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final named = [for (final space in spaces.list) (space: space, path: workspacePathName(spaces.list, space.id))]..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  final out = <HomeFolder>[];
  for (final (:space, :path) in named.take(most)) {
    final family = workspaceFamily(spaces.list, space.id).toSet();
    final inside = [for (final note in own) if (family.contains(spaces.of[note.id])) note];
    out.add(HomeFolder(
      id: space.id,
      name: space.name,
      path: path,
      org: orgOfWorkspace(spaces.list, space.id) != null,
      hue: space.hue,
      count: inside.length,
      notes: [for (final note in inside.take(each)) _homeNote(note, at: note.updatedAt)],
    ));
  }
  return out;
}

String foldersJson(List<HomeFolder> folders) => jsonEncode({'folders': [for (final folder in folders) folder.toJson()]});

/// What Ask AI is handed: whether the app's own Claude is on (its plugin's switch) and whether an API key is entered
/// on this device, the two the dock waits for before it shows Claude's rings (lib/root/ghost_root.dart
/// `_claudeShown`). Either missing, the widget says where to put it right.
String assistantJson({required bool on, required bool key}) => jsonEncode({'on': on, 'key': key});
