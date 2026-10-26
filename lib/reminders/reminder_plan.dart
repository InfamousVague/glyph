/// Which reminders the phone is to hold, decided from the notes: pure, so every case is a test with a clock of its
/// own (test/reminders/reminder_plan_test.dart).
///
/// - An item with its own `⏰` is reminded then, ticked or not on any list item; a ticked or cancelled one is not.
/// - A to-do or a ticket with a due day and no time is reminded on the day at Settings' time, and the day before at
///   the same time where Settings asks. A list item with no box is reminded only where it says `⏰`: a due day on a
///   plain line is a date, not a task.
/// - Nothing in the Trash, the archive, a template, or a note this phone cannot read as words (a canvas).
/// - Only what is still to come, the soonest [mostReminders] of it: Android holds a few hundred alarms for an app, and
///   the next pass (any change to the notes, or the app opened) hands over the next ones.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/days.dart' show isoDayAfter;
import '../format/body_hash.dart' show fnvOffsetBasis;
import '../core/note.dart';
import '../core/note_facts.dart';
import 'dated_items.dart';
import 'reminder_settings.dart';
import 'reminder_syntax.dart';

/// How many reminders the phone is handed at once: the soonest.
const int mostReminders = 64;

/// Why an item is reminded: its own time, its due day, or the day before it.
enum ReminderKind { set, due, before }

/// One reminder, as the phone is handed it.
@immutable
class Reminder {
  const Reminder({required this.id, required this.at, required this.kind, required this.noteId, required this.line, required this.words, required this.note, required this.tick});

  /// The same for the same item at the same time for the same reason, from one pass to the next and one run to the
  /// next: what the phone knows an alarm by.
  final String id;
  final ReminderTime at;
  final ReminderKind kind;
  final String noteId;

  /// The item's line, counting from 1; 0 for a ticket.
  final int line;

  /// What the item says, and the note's title.
  final String words;
  final String note;

  /// Whether the notification offers Done: a to-do's box or a ticket.
  final bool tick;

  /// The notification's title: what the item says.
  String get title => words.isEmpty ? 'A to-do in ${note.isEmpty ? 'a note' : note}' : words;

  /// The line under it: the note, and why now.
  String get text {
    final where = note.isEmpty ? 'Untitled' : note;
    return switch (kind) {
      ReminderKind.set => where,
      ReminderKind.due => '$where · Due today',
      ReminderKind.before => '$where · Due tomorrow',
    };
  }

  Map<String, Object?> toJson() => {'id': id, 'at': at.written, 'note': noteId, 'line': line, 'words': words, 'title': title, 'text': text, 'tick': tick};

  @override
  bool operator ==(Object other) =>
      other is Reminder && other.id == id && other.at == at && other.kind == kind && other.noteId == noteId && other.line == line && other.words == words && other.note == note && other.tick == tick;

  @override
  int get hashCode => Object.hash(id, at, kind, noteId, line, words, note, tick);

  @override
  String toString() => 'Reminder(${at.written} ${kind.name} "$words" in $noteId:$line)';
}

/// FNV-1a over the text's UTF-16 units, 64 bits as 16 hex digits: the same in every run, as `hashCode` is not
/// promised to be. The two halves are written apart, since a 64-bit int with its top bit set is negative here.
String stableId(String text) {
  var hash = fnvOffsetBasis;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash *= 0x100000001b3;
  }
  String half(int bits) => (bits & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '${half(hash >> 32)}${half(hash)}';
}

/// The reminders one note asks for, at any time, in the order its items are written.
List<Reminder> remindersOf(Note note, ReminderSettings settings) {
  if (!settings.on) return const [];
  final items = DatedItems.of(note);
  if (items.isEmpty) return const [];
  final title = NoteFacts.of(note).title;
  final out = <Reminder>[];
  void add(DatedItem item, ReminderTime at, ReminderKind kind) {
    final id = stableId('${note.id}\u0000${item.line == 0 ? '' : item.words}\u0000${at.written}\u0000${kind.name}');
    out.add(Reminder(id: id, at: at, kind: kind, noteId: note.id, line: item.line, words: item.words, note: title, tick: item.box));
  }

  for (final item in items) {
    if (item.done) continue;
    final at = item.at;
    if (at != null) {
      add(item, at, ReminderKind.set);
      continue;
    }
    final due = item.due;
    if (due == null || !item.box) continue;
    add(item, ReminderTime(due, settings.hour, settings.minute), ReminderKind.due);
    final before = settings.dayBefore ? isoDayAfter(due, -1) : null;
    if (before != null) add(item, ReminderTime(before, settings.hour, settings.minute), ReminderKind.before);
  }
  return out;
}

/// Each note's reminders, kept while the note and the settings are what they were: a pass over the library reads
/// again only the notes that changed.
class ReminderPlanner {
  final Map<String, ({Note note, List<Reminder> reminders})> _kept = {};
  ReminderSettings? _for;

  /// How many notes were read in the last [plan]: for a test, and a bench.
  int lastRead = 0;

  /// The soonest [most] reminders after [now], from [notes] less those [skip] says to leave out (the Trash).
  List<Reminder> plan(List<Note> notes, {required ReminderSettings settings, required DateTime now, bool Function(Note note)? skip, int most = mostReminders}) {
    if (_for != settings) {
      _kept.clear();
      _for = settings;
    }
    lastRead = 0;
    final seen = <String>{};
    final all = <Reminder>[];
    final from = ReminderTime.of(now);
    for (final note in notes) {
      seen.add(note.id);
      if ((note.archivedAt ?? 0) != 0 || (skip?.call(note) ?? false)) continue;
      final kept = _kept[note.id];
      final List<Reminder> reminders;
      if (kept != null && identical(kept.note, note)) {
        reminders = kept.reminders;
      } else {
        lastRead += 1;
        reminders = remindersOf(note, settings);
        _kept[note.id] = (note: note, reminders: reminders);
      }
      for (final reminder in reminders) {
        // Still to come: a minute that has begun is passed.
        if (reminder.at.compareTo(from) > 0) all.add(reminder);
      }
    }
    _kept.removeWhere((id, _) => !seen.contains(id));
    all.sort((a, b) {
      final when = a.at.compareTo(b.at);
      return when != 0 ? when : a.id.compareTo(b.id);
    });
    // One alarm per id: the same item twice on a line written twice is reminded once.
    final ids = <String>{};
    final out = <Reminder>[];
    for (final reminder in all) {
      if (!ids.add(reminder.id)) continue;
      out.add(reminder);
      if (out.length >= most) break;
    }
    return out;
  }
}

/// The plan as the phone is handed it.
String planJson(List<Reminder> plan) => jsonEncode({'items': [for (final reminder in plan) reminder.toJson()]});
