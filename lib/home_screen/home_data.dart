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

import '../core/days.dart' show isoDayAfter, isoDay;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../reminders/dated_items.dart';

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
