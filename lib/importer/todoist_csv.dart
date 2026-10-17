/// A Todoist project's CSV export brought in (Settings › Import › Todoist CSV export): what a project's ⋯ › Manage
/// data › Export as CSV gives, which is also Todoist's template format. Each file is a project, named by its file
/// (`Work.csv` is Work), and becomes a note as a project read through the API does (lib/importer/todoist.dart
/// `todoistProjectBody`), at the top of the import's workspace.
///
/// The format, as Todoist's help ("Import or export a project as a CSV file") and its sample file have it: UTF-8, a
/// header row, then one row a line (a quoted cell may hold commas, quotes doubled, and line breaks), with the
/// columns found by their names in the header, never by place:
///
///     TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE,DURATION,DURATION_UNIT,DEADLINE,DEADLINE_LANG
///     meta,view_style=list,,,,,,,,,,,,
///     task,Call the client @work,,1,1,,,every friday,en,,30,minute,2025-03-31,en
///     note,Only on Tuesdays,,,,,,,,,,,,
///
/// - `TYPE` is `task`, `section` or `note` (a comment on the task above it, kept as text under it); `meta` rows
///   (`view_style=board`) and empty ones are passed over.
/// - `PRIORITY` counts the way Todoist's own screens do, the API's other way: 1 is p1 (⏫), 2 🔼, 3 🔽, 4 none. An
///   empty cell is none here (Todoist's own import would make it p1).
/// - `INDENT` 1 is a task at the top, 2 a sub-task of the 1 above it, and on.
/// - Labels are `@words` in `CONTENT`; they become `#tags`, and are taken out of the words, where an `@name` would
///   be read as a person (lib/core/task_fields.dart).
/// - `DATE` is Todoist's words (`today at 11:00`, `every Friday`, `Oct 20 2026`), never a day the format promises.
///   A day is read from it where it says one plainly (an ISO day, `today`, `tomorrow`, a month's name and a day);
///   one beginning `every` is a recurrence, `🔁` and its words; any other is kept in its words, `[when:: …]`, and
///   counted for the report. `DEADLINE` is an ISO day.
/// - Completed tasks are never in an export.
/// - A file may be written with `;` between cells, as a spreadsheet in some languages saves it: the header says.
library;

import 'dart:convert';
import 'dart:io';

import 'import_paths.dart' show cleanStem;
import 'import_report.dart';
import 'import_sources.dart';
import 'import_target.dart';
import 'task_lines.dart';
import 'todoist.dart';

/// The rows of a CSV text, each a list of its cells: RFC 4180's quoting (a cell in `"`, a `""` inside it one
/// quote, a line break inside it kept), with [separator] between cells.
List<List<String>> csvRows(String text, {String separator = ','}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var i = 0;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        cell.write(c);
      }
      i += 1;
      continue;
    }
    if (c == '"' && cell.isEmpty) {
      quoted = true;
    } else if (c == separator) {
      endCell();
    } else if (c == '\r') {
      endRow();
      if (i + 1 < text.length && text[i + 1] == '\n') i += 1;
    } else if (c == '\n') {
      endRow();
    } else {
      cell.write(c);
    }
    i += 1;
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

const List<String> _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

int? _month(String word) {
  final low = word.toLowerCase().replaceAll('.', '');
  if (low.length < 3) return null;
  final at = _months.indexOf(low.substring(0, 3));
  if (at < 0) return null;
  // `March` and `Mar` are March; `Marching` is not a month.
  const long = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
  if (low.length > 3 && !long[at].startsWith(low) && low != 'sept') return null;
  return at + 1;
}

String? _validDay(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final at = DateTime(year, month, day);
  if (at.month != month) return null;
  return isoDay(at);
}

/// The day Todoist's words for a date say, read against [today]: an ISO day, `today`, `tomorrow`, `yesterday`, or
/// a month's name and a day (`Oct 20`, `20 Oct 2026`, `October 20, 2026`); a time after it (`at 11:00`) is let go.
/// Null for words that say no day plainly (`next monday`, `in 3 days`) and for a recurrence.
String? todoistDayFromWords(String words, DateTime today) {
  final said = words.trim();
  if (said.isEmpty) return null;
  if (isoDayOf(said) case final day?) return day;
  final low = said.toLowerCase();
  if (low.startsWith('every') || low.startsWith('ev ') || low.startsWith('each ')) return null;
  final first = low.split(RegExp(r'[\s,@]+')).first;
  final base = DateTime(today.year, today.month, today.day);
  switch (first) {
    case 'today' || 'tod':
      return isoDay(base);
    case 'tomorrow' || 'tom':
      return isoDay(base.add(const Duration(days: 1)));
    case 'yesterday':
      return isoDay(base.subtract(const Duration(days: 1)));
  }
  final parts = said.replaceAll(',', ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.length < 2) return null;
  int? number(String w) => RegExp(r'^\d{1,4}(st|nd|rd|th)?$').hasMatch(w) ? int.parse(w.replaceAll(RegExp(r'\D'), '')) : null;
  int? year;
  int? month;
  int? day;
  // `Oct 20 2026`, `October 20`, `20 Oct 2026`, `20 October`.
  final m0 = _month(parts[0]), m1 = _month(parts[1]);
  final n0 = number(parts[0]), n1 = number(parts[1]);
  if (m0 != null && n1 != null && n1 <= 31) {
    month = m0;
    day = n1;
  } else if (m1 != null && n0 != null && n0 <= 31) {
    month = m1;
    day = n0;
  }
  if (parts.length > 2) {
    final n2 = number(parts[2]);
    if (n2 != null && n2 > 1900) year = n2;
  }
  if (month == null || day == null) return null;
  if (year != null) return _validDay(year, month, day);
  // No year: the next such day, today's included, as Todoist reads one.
  final thisYear = _validDay(base.year, month, day);
  if (thisYear != null && !DateTime.parse(thisYear).isBefore(base)) return thisYear;
  return _validDay(base.year + 1, month, day);
}

final RegExp _label = RegExp(r'(^|\s)@([\p{L}\p{N}_\-/]+)', unicode: true);

/// A project read from a CSV export's [text], named [name]. [today] reads `today` and a day with no year.
({TodoistProject project, List<TodoistSection> sections, List<TodoistTask> tasks, int inWords}) todoistCsvProject(String text, String name, DateTime today) {
  var clean = text.startsWith('﻿') ? text.substring(1) : text;
  clean = clean.replaceAll('\r\n', '\n');
  final firstLine = clean.split('\n').first;
  final separator = !firstLine.contains(',') && firstLine.contains(';') ? ';' : ',';
  final rows = csvRows(clean, separator: separator);
  if (rows.isEmpty) throw const FormatException('empty');
  final header = [for (final cell in rows.first) cell.trim().toUpperCase()];
  final type = header.indexOf('TYPE'), content = header.indexOf('CONTENT');
  if (type < 0 || content < 0) throw const FormatException('not a Todoist export');
  String at(List<String> row, String column) {
    final index = header.indexOf(column);
    return index < 0 || index >= row.length ? '' : row[index].trim();
  }

  final project = TodoistProject(id: 'csv', name: name);
  final sections = <TodoistSection>[];
  final tasks = <TodoistTask>[];
  // The last task at each depth, for a sub-task's parent; the section the rows are in.
  final parents = <int, String>{};
  String? section;
  var inWords = 0;
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.trim().isEmpty)) continue;
    final kind = at(row, 'TYPE').toLowerCase();
    final words = at(row, 'CONTENT');
    if (kind == 'section') {
      section = 's${sections.length + 1}';
      sections.add(TodoistSection(id: section, projectId: project.id, name: words, description: at(row, 'DESCRIPTION'), order: sections.length));
      parents.clear();
    } else if (kind == 'note') {
      if (tasks.isEmpty || words.isEmpty) continue;
      final last = tasks.removeLast();
      tasks.add(_withComment(last, words));
    } else if (kind == 'task') {
      final depth = (int.tryParse(at(row, 'INDENT')) ?? 1).clamp(1, 10) - 1;
      final labels = <String>[];
      final rest = words.replaceAllMapped(_label, (match) {
        labels.add(match.group(2)!);
        return match.group(1)!;
      });
      final date = at(row, 'DATE');
      final low = date.toLowerCase();
      final recurring = low.startsWith('every') || low.startsWith('ev ') || low.startsWith('each ');
      final day = recurring ? null : todoistDayFromWords(date, today);
      if (date.isNotEmpty && !recurring && day == null) inWords += 1;
      // Todoist's screens' p1 is the API's 4; an empty cell is none.
      final csvPriority = int.tryParse(at(row, 'PRIORITY'));
      final id = 't${tasks.length + 1}';
      tasks.add(TodoistTask(
        id: id,
        projectId: project.id,
        content: rest,
        description: at(row, 'DESCRIPTION'),
        priority: csvPriority == null || csvPriority < 1 || csvPriority > 4 ? 1 : 5 - csvPriority,
        dueDay: day,
        dueWords: date.isEmpty ? null : date,
        recurring: recurring,
        deadline: isoDayOf(at(row, 'DEADLINE')),
        labels: labels,
        parentId: depth > 0 ? parents[depth - 1] : null,
        sectionId: section,
        order: tasks.length,
      ));
      parents[depth] = id;
      parents.removeWhere((key, _) => key > depth);
    }
  }
  return (project: project, sections: sections, tasks: tasks, inWords: inWords);
}

TodoistTask _withComment(TodoistTask task, String comment) => TodoistTask(
      id: task.id,
      projectId: task.projectId,
      content: task.content,
      description: task.description,
      priority: task.priority,
      dueDay: task.dueDay,
      dueWords: task.dueWords,
      recurring: task.recurring,
      deadline: task.deadline,
      labels: task.labels,
      parentId: task.parentId,
      sectionId: task.sectionId,
      order: task.order,
      completedAt: task.completedAt,
      comments: [...task.comments, comment],
    );

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// Imports the exports [files] through [target]: each a project's note. [progress] hears each file as its note is
/// written; [stopped] is asked between them.
Future<ImportReport> importTodoistCsv(List<ImportFile> files, ImportTarget target, {void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
  final run = target.begin('Todoist');
  final report = run.report;
  final today = DateTime.fromMillisecondsSinceEpoch(run.startedAt);
  var inWords = 0;
  var done = 0;
  try {
    for (final file in files) {
      if (stopped?.call() ?? false) break;
      final name = _stem(file.name).trim().isEmpty ? 'Todoist' : _stem(file.name).trim();
      try {
        final bytes = await File(await file.localPath()).readAsBytes();
        final read = todoistCsvProject(utf8.decode(bytes, allowMalformed: true), name, today);
        inWords += read.inWords;
        final body = todoistProjectBody(read.project, read.sections, read.tasks, counted: () => report.tasks += 1);
        await run.note(body: body, path: run.paths.place(const [], cleanStem(name), original: file.name));
      } catch (_) {
        report.skipped.add('${file.name}, not a Todoist export Ghost.md can read');
      } finally {
        await file.done();
      }
      done += 1;
      progress?.call((done: done, total: files.length, on: name));
    }
  } finally {
    if (inWords > 0) report.skipped.add(inWords == 1 ? 'one date Ghost.md could not read as a day, kept in its words' : '$inWords dates Ghost.md could not read as days, kept in their words');
    run.finish();
  }
  return report;
}
