/// The To-dos view's reading of the notes (GHST-105, simple mode; Matt: "spend a significant amount of time looking
/// into simple apps like todoist and others to build out a clean simple UI"): every open to-do across the notes,
/// placed in Todoist's four buckets by its due date, and the words each row shows. Pure, so the view's tests and
/// the view itself read the same thing.
///
/// A to-do is what the home page's digest counts (lib/home/dashboard.dart `openTasks`): an unticked box on a list
/// item, outside a code fence, in a note that is not archived and not one of the Guide's pages; its words are the
/// line with the task fields taken out, as the home rows show them. The due date and the priority are the task
/// fields' own (lib/core/task_fields.dart: `📅 2026-10-03`, `[due:: 2026-10-03]`, `⏫`), read off the line the
/// to-do is on, so a date written for Obsidian Tasks or Dataview places it here too.
library;

import 'package:flutter/foundation.dart';

import '../core/days.dart';
import '../core/locale_dates.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/task_fields.dart';
import '../core/trash.dart';
import '../home/dashboard.dart' show openTasks;

/// Where a to-do sits, by its due date: before today, today, after today, or undated (`Someday`, Todoist's word for
/// a to-do with no date, kept as the fourth bucket so nothing is lost for want of a date).
enum TodoGroup { overdue, today, later, someday }

/// Each group's heading.
const Map<TodoGroup, String> todoGroupWords = {
  TodoGroup.overdue: 'Overdue',
  TodoGroup.today: 'Today',
  TodoGroup.later: 'Later',
  TodoGroup.someday: 'Someday',
};

/// One open to-do as the view lists it.
@immutable
class Todo {
  const Todo({required this.noteId, required this.line, required this.text, required this.noteName, required this.touched, this.due, this.priority});

  final String noteId;

  /// The line it is on, counting from 0: what a tick rewrites (lib/core/query/tick.dart) and what opening the note
  /// lands on.
  final int line;

  /// Its words, the fields taken out.
  final String text;

  /// The name of the note it is in; "Untitled" where the note has none.
  final String noteName;

  /// When its note was last touched, which orders the undated ones.
  final int touched;

  /// Its due day as written, `2026-10-03`, or null for none.
  final String? due;

  /// Its priority's name (`highest` … `lowest`), or null for none.
  final String? priority;

  /// What tells one to-do from another across a rebuild: the note, the line and the words. The line alone is not
  /// enough, since a tick elsewhere in the note moves the lines under it.
  String get key => '$noteId:$line:$text';

  /// Whole days from [today] to its due day: negative when overdue, 0 today; null for an undated one.
  int? daysFrom(String today) => due == null ? null : daysBetween(today, due!);
}

/// The groups in their order, each with its to-dos, empty groups left out.
typedef TodoGroups = List<({TodoGroup group, List<Todo> todos})>;

/// Every open to-do in [notes], out of the trash ([held]) and the archive, grouped by its due date against [today]
/// (an ISO day, `isoDay(clock())`). Within a dated group the soonest due first, then the most urgent, then the most
/// recently touched note's: the query engine's own order for `from: tasks` (lib/core/query/run.dart). Someday is the
/// most recently touched note's first, in the order each note has them, as the home digest lists them.
TodoGroups todoGroups(List<Note> notes, String today, {TrashHeld held = const {}}) {
  final groups = <TodoGroup, List<Todo>>{};
  for (final task in openTasks(held.isEmpty ? notes : outOfTrash(notes, held))) {
    final note = _noteOf(notes, task.noteId);
    final lines = note.body.split('\n');
    final fields = task.line < lines.length ? fieldsOf(lines[task.line]) : fieldsOf('');
    final due = fields.due != null && isIsoDay(fields.due!) ? fields.due : null;
    final name = NoteFacts.of(note).shownTitle;
    final todo = Todo(noteId: task.noteId, line: task.line, text: task.text, noteName: name.isEmpty ? 'Untitled' : name, touched: task.touched, due: due, priority: fields.priority);
    (groups[_groupOf(todo.daysFrom(today))] ??= <Todo>[]).add(todo);
  }
  for (final MapEntry(key: group, value: todos) in groups.entries) {
    if (group != TodoGroup.someday) todos.sort(_dated);
  }
  return [
    for (final group in TodoGroup.values)
      if (groups[group] != null) (group: group, todos: groups[group]!),
  ];
}

TodoGroup _groupOf(int? days) => days == null
    ? TodoGroup.someday
    : days < 0
        ? TodoGroup.overdue
        : days == 0
            ? TodoGroup.today
            : TodoGroup.later;

/// The soonest due first, then the most urgent; `openTasks` already gave the most recently touched note's first, and
/// the sort is stable, so that order holds between equals.
int _dated(Todo a, Todo b) {
  final byDay = a.due!.compareTo(b.due!);
  if (byDay != 0) return byDay;
  return priorityRank(a.priority) - priorityRank(b.priority);
}

Note _noteOf(List<Note> notes, String id) {
  for (final note in notes) {
    if (note.id == id) return note;
  }
  throw StateError('openTasks named a note that is not in the list: $id');
}

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// A due day as the row says it under the words, counted from [today]: "Today", "Tomorrow", "Yesterday", the
/// weekday within a week either way ("Friday", "3 days ago"), and the date past that ("3 October", "3 October 2025"
/// in another year), in the device's own words where the locale is known (lib/core/locale_dates.dart).
String dueWords(String due, String today) {
  final days = daysBetween(today, due);
  final at = dateOfDay(due);
  if (days == null || at == null) return due;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  if (days > 1 && days < 7) return toldDate(at, DateForm.EEEE) ?? _weekdays[at.weekday - 1];
  if (days < 0 && days > -7) return '${-days} days ago';
  final sameYear = dateOfDay(today)?.year == at.year;
  return sameYear ? toldDate(at, DateForm.MMMMd) ?? '${at.day} ${_months[at.month - 1]}' : toldDate(at, DateForm.yMMMMd) ?? '${at.day} ${_months[at.month - 1]} ${at.year}';
}

/// A priority as the row says it: the two above the ordinary are worth a word ("High", "Highest"); medium is no
/// news, and a low one is not what a list of things to do is for.
String? priorityWords(String? priority) {
  final found = priorityOf(priority);
  return found != null && found.rank <= 1 ? found.label : null;
}
