/// A query run over the library (records.dart): the records it reads from, those its tests pass, in its order, as
/// many as its limit, in its groups, with its totals, as the cells a table, a list, a board, a calendar, a gantt or
/// a count draws (tauri/docs/QUERIES.md, docs/DESIGN.md §159). A port of `src/app/core/query/run.ts`. Everything a
/// drawing needs is answered here as plain data, so the drawing is only drawing, and a result can be compared by
/// what it says.
///
/// The defaults are what make `from: #bug` alone a useful query:
///
/// - **What is read.** Notes, unless `from:` says tickets, tasks or events (the calendars', docs/CALENDAR.md). Notes
///   include tickets, which are notes; an event is in no note.
/// - **Open to-dos.** A tasks query lists the ones not ticked, unless it asks about being done: a `where:` or a
///   `group:` that names `checked`, `status`, `done` or `category`, or a board, whose columns are the statuses.
/// - **The order.** Notes the last changed first; tickets the most urgent first, then the soonest due, then by key;
///   to-dos the soonest due first, then the most urgent; events the soonest first, a day's before the day's hours. A record with nothing in a field sorts after those that
///   have something, whichever way; a priority's none sits between medium and low, as Tasks sorts it.
/// - **The way it is shown.** A table for tickets, a list for notes and to-dos.
/// - **The columns.** Tickets: id, title, status, assignee, priority, due. To-dos: the to-do, due, priority,
///   assignee, and the note it is in. Notes: the title and when it was changed.
/// - **A board's columns** are its `group:`, or the status: for tickets, every status of the workflow, in order,
///   empty ones and all, as a Jira board has them.
///
/// Totals are added as a sum of them would be (sums.dart `totalOf`), over the records shown, and over each group's.
///
/// The port's own (2026-10-30): a rollup is a field like any other, read through rollup.dart's [FieldLook], and a
/// column of its own where `columns:` is unsaid; a calendar's day is its `date:` field where one is written, a
/// timeline's bar runs from its `start:` field to its `end:` (`start` and `due`), and a chart's bars are worked out
/// here (chart.dart). None of it is in a result's JSON unless asked for, so every query the web runs runs the same.
///
/// What differs: `Column`, `Row` and `Group` are [QueryColumn], [QueryRow] and [QueryGroup], since Flutter has a
/// Column and a Row of its own. Each is [QueryData], whose `toJson` is the web's object key for key: what the
/// fixtures hold a run to (tool/query_fixtures.mjs). The orders are sorted so that ties stay as they came, as the
/// page's `Array.sort` leaves them; Dart's own sort promises no such thing.
library;

import '../properties.dart' show StatusCategory, defaultStatuses, statusCategory;
import '../sums.dart' show totalOf;
import '../task_fields.dart' show samePerson;
import '../title_key.dart' show titleKey;
import 'chart.dart';
import 'collate.dart';
import 'gantt.dart';
import 'read.dart';
import 'records.dart';
import 'rollup.dart';
import 'values.dart';

/// A column: the field it shows and what it is called (`Column`).
class QueryColumn extends QueryData {
  const QueryColumn({required this.field, required this.label});
  final String field;
  final String label;
  @override
  Object? toJson() => {'field': field, 'label': label};
}

/// A cell, as the drawing needs it: the value's kind, and what it says (`Cell`).
sealed class Cell extends QueryData {
  const Cell();
}

class EmptyCell extends Cell {
  const EmptyCell();
  @override
  Object? toJson() => {'kind': 'empty'};
}

class TextCell extends Cell {
  const TextCell(this.text);
  final String text;
  @override
  Object? toJson() => {'kind': 'text', 'text': text};
}

class NumberCell extends Cell {
  const NumberCell(this.text);
  final String text;
  @override
  Object? toJson() => {'kind': 'number', 'text': text};
}

/// How a due day not yet done stands to today (`tone`).
enum DayTone { overdue, today }

/// A day; a due day not yet done is `overdue` before today, and `today` on it.
class DayCell extends Cell {
  const DayCell(this.day, {this.tone});
  final String day;
  final DayTone? tone;
  @override
  Object? toJson() => {'kind': 'day', 'day': day, 'tone': tone?.name};
}

class PriorityCell extends Cell {
  const PriorityCell(this.name);
  final String name;
  @override
  Object? toJson() => {'kind': 'priority', 'name': name};
}

class StatusCell extends Cell {
  const StatusCell(this.text, this.category);
  final String text;
  final StatusCategory category;
  @override
  Object? toJson() => {'kind': 'status', 'text': text, 'category': category.name};
}

class PeopleCell extends Cell {
  const PeopleCell(this.names);
  final List<String> names;
  @override
  Object? toJson() => {'kind': 'people', 'names': names};
}

class ListCell extends Cell {
  const ListCell(this.items, {required this.tags});
  final List<String> items;
  final bool tags;
  @override
  Object? toJson() => {'kind': 'list', 'items': items, 'tags': tags};
}

class BoolCell extends Cell {
  const BoolCell({required this.on});
  final bool on;
  @override
  Object? toJson() => {'kind': 'bool', 'on': on};
}

/// A record, drawn: what it is, how to reach it, and its cells, one for each column (`Row`).
class QueryRow extends QueryData {
  const QueryRow({
    required this.key,
    required this.kind,
    required this.noteId,
    required this.line,
    required this.source,
    required this.anchor,
    required this.name,
    required this.id,
    required this.done,
    required this.category,
    required this.workflow,
    required this.cells,
    required this.day,
    required this.start,
    required this.due,
    required this.overdue,
    this.end,
    this.dayField,
  });

  /// Its note's id, and its line for a to-do: one row's key, whatever else changes.
  final String key;
  final RecordKind kind;
  final String noteId;

  /// A to-do's line in its note, from 0; -1 for a note.
  final int line;

  /// A to-do's line as written, to tick it where its note has moved under it.
  final String source;
  final String? anchor;

  /// What it is called: a to-do's words, a note's or a ticket's title.
  final String name;

  /// A ticket's key, `GHO-12`.
  final String? id;

  /// A to-do's box; null for a note.
  final bool? done;
  final StatusCategory category;

  /// The workflow its status moves through (its notebook's `statuses:`, or the default): what a status picker offers.
  final List<String> workflow;
  final List<Cell> cells;

  /// The day it is on a calendar: its due day, else its scheduled day, its start, or its note's `date:`.
  final String? day;
  final String? start;
  final String? due;

  /// Due before today and not done.
  final bool overdue;

  /// The day a timeline's bar ends on: its query's `end:` field's, else its due day (the port's own).
  final String? end;

  /// The field [day] is from, which a day carried to another on a calendar sets; null where it has no day, and for
  /// an event (the port's own).
  final String? dayField;

  @override
  Object? toJson() => {
        'key': key,
        'kind': kind.name,
        'noteId': noteId,
        'line': line,
        'source': source,
        'anchor': anchor,
        'name': name,
        'id': id,
        'done': done,
        'category': category.name,
        'workflow': workflow,
        'cells': [for (final cell in cells) cell.toJson()],
        'day': day,
        'start': start,
        'due': due,
        'overdue': overdue,
      };
}

/// A field added up (`Total`).
class Total extends QueryData {
  const Total({required this.field, required this.label, required this.text});
  final String field;
  final String label;
  final String text;
  @override
  Object? toJson() => {'field': field, 'label': label, 'text': text};
}

/// Records under one value of `group:`, or all of them under none (`Group`).
class QueryGroup extends QueryData {
  const QueryGroup({required this.key, required this.label, required this.cell, required this.rows, required this.totals});

  /// '' for the group of records with nothing in the field, and for a query not grouped.
  final String key;

  /// What the group is called: the value, or "No status"; '' for a query not grouped.
  final String label;

  /// The value, drawn, for a heading that draws it as a cell does.
  final Cell? cell;
  final List<QueryRow> rows;
  final List<Total> totals;

  @override
  Object? toJson() => {
        'key': key,
        'label': label,
        'cell': cell?.toJson(),
        'rows': [for (final row in rows) row.toJson()],
        'totals': [for (final total in totals) total.toJson()],
      };
}

class QueryResult extends QueryData {
  const QueryResult({
    required this.kind,
    required this.show,
    required this.columns,
    required this.opens,
    required this.group,
    required this.groups,
    required this.matched,
    required this.shown,
    required this.totals,
    required this.gantt,
    required this.warnings,
    required this.today,
    this.chart,
    this.dateField,
    this.startField = 'start',
    this.endField = 'due',
    this.zoom,
  });

  final QueryKind kind;
  final ShowAs show;
  final List<QueryColumn> columns;

  /// The column whose cell opens its record: the name's, or the first.
  final int opens;

  /// The field grouped by: `group:`, or a board's status.
  final String? group;
  final List<QueryGroup> groups;

  /// How many records passed, and how many are shown (`limit:`).
  final int matched;
  final int shown;
  final List<Total> totals;

  /// A gantt's Mermaid text, and how many records it places; null where it is not shown as one.
  final Gantt? gantt;

  /// What the query names that is not there: "No note is called “Q4”."
  final List<String> warnings;

  /// The day it was run on.
  final String today;

  /// A chart's bars; null where it is not shown as one (the port's own).
  final ChartData? chart;

  /// A calendar's day field, where `date:` names one; a timeline's start and end fields, and its zoom where written.
  final String? dateField;
  final String startField;
  final String endField;
  final TimelineZoom? zoom;

  @override
  Object? toJson() => {
        'kind': kind.name,
        'show': show.name,
        'columns': [for (final column in columns) column.toJson()],
        'opens': opens,
        'group': group,
        'groups': [for (final each in groups) each.toJson()],
        'matched': matched,
        'shown': shown,
        'totals': [for (final total in totals) total.toJson()],
        'gantt': gantt?.toJson(),
        'warnings': warnings,
        'today': today,
        if (chart != null) 'chart': chart!.toJson(),
      };
}

const Map<QueryKind, ShowAs> _defaultShow = {QueryKind.notes: ShowAs.list, QueryKind.tickets: ShowAs.table, QueryKind.tasks: ShowAs.list, QueryKind.events: ShowAs.list};

/// What each kind of record is called, many of them: a gantt's one section, a count's words (`KIND_WORDS`).
const Map<QueryKind, String> kindWords = {QueryKind.notes: 'Notes', QueryKind.tickets: 'Tickets', QueryKind.tasks: 'To-dos', QueryKind.events: 'Events'};
const Map<QueryKind, List<String>> _defaultColumns = {
  QueryKind.notes: ['title', 'updated'],
  QueryKind.tickets: ['id', 'title', 'status', 'assignee', 'priority', 'due'],
  QueryKind.tasks: ['text', 'due', 'priority', 'assignee', 'note'],
  QueryKind.events: ['title', 'start', 'time', 'location', 'calendar'],
};
const Map<QueryKind, List<SortKey>> _defaultSort = {
  QueryKind.notes: [SortKey('updated', desc: true)],
  QueryKind.tickets: [SortKey('priority'), SortKey('due'), SortKey('id')],
  QueryKind.tasks: [SortKey('due'), SortKey('priority')],
  // The soonest first, a day's events before the day's hours, and the hours in order.
  QueryKind.events: [SortKey('start'), SortKey('allday', desc: true), SortKey('time')],
};

/// The fields that ask whether something is done, which turn off a tasks query's open-only default.
const List<String> _doneFields = ['checked', 'status', 'done', 'category'];

/// The fields a calendar places a record by, the first it has.
const List<String> _dayFields = ['due', 'scheduled', 'start', 'date'];

/// Whether a record is one of the kind asked for.
bool _ofKind(QueryRecord record, QueryKind kind) => switch (kind) {
      QueryKind.tasks => record.kind == RecordKind.task,
      QueryKind.tickets => record.kind == RecordKind.ticket,
      QueryKind.notes => record.kind == RecordKind.note || record.kind == RecordKind.ticket,
      QueryKind.events => record.kind == RecordKind.event,
    };

/// Every `[[title]]` a `from:` names.
List<String> _linksIn(Source? source) => switch (source) {
      null => const [],
      LinkSource(:final title) => [title],
      NotSource(:final of) => _linksIn(of),
      AndSource(:final all) => [for (final each in all) ..._linksIn(each)],
      OrSource(:final any) => [for (final each in any) ..._linksIn(each)],
      _ => const [],
    };

/// Whether a record is from what `from:` names.
bool _fromHolds(Source source, QueryRecord record, Map<String, LibraryNote?> named) {
  switch (source) {
    case TagSource(:final tag):
      return record.tags.any((each) => each == tag || each.startsWith('$tag/'));
    case LinkSource(:final title):
      final note = named[title];
      if (note == null) return record.linkKeys.contains(titleKey(title));
      // A notebook names its pages; any other note, the notes that link to it, as Dataview reads `FROM [[it]]`.
      return note.book ? record.books.contains(note.key) : record.linksTo.contains(note.id);
    case PersonSource(:final name):
      final said = valueOf(record, 'assignee');
      return said is PeopleValue && said.names.any((each) => samePerson(each, name));
    case WordsSource(:final words):
      return record.haystack.contains(words.toLowerCase());
    case NotSource(:final of):
      return !_fromHolds(of, record, named);
    case AndSource(:final all):
      return all.every((each) => _fromHolds(each, record, named));
    case OrSource(:final any):
      return any.any((each) => _fromHolds(each, record, named));
  }
}


/// Whether a value sorts last, whichever way: nothing in it. A priority's none sorts between medium and low.
bool _sortsLast(Value value) => isEmptyValue(value) && value is! PriorityValue;

/// [items] in [order], two that compare the same left as they came: what the page's `Array.prototype.sort` does.
List<T> _stableSorted<T>(List<T> items, num Function(T a, T b) order) {
  final placed = [for (var i = 0; i < items.length; i += 1) (i, items[i])];
  placed.sort((a, b) {
    final by = order(a.$2, b.$2);
    if (by != 0) return by < 0 ? -1 : 1;
    return a.$1 - b.$1;
  });
  return [for (final each in placed) each.$2];
}

/// Records in the order [keys] asks, then by note and line, so two runs of one query agree.
List<QueryRecord> _sorted(List<QueryRecord> records, List<SortKey> keys, FieldLook look) {
  final decorated = [for (final record in records) (record: record, values: [for (final key in keys) look(record, key.field)])];
  return [
    for (final each in _stableSorted(decorated, (a, b) {
      for (var i = 0; i < keys.length; i += 1) {
        final one = a.values[i];
        final two = b.values[i];
        final last = (_sortsLast(one) ? 1 : 0) - (_sortsLast(two) ? 1 : 0);
        if (last != 0) return last;
        if (_sortsLast(one)) continue;
        final order = compareValues(one, two);
        if (order != 0) return keys[i].desc ? -order : order;
      }
      final title = localeCompare(a.record.title, b.record.title, numeric: true, base: true);
      if (title != 0) return title;
      final id = localeCompare(a.record.noteId, b.record.noteId);
      return id != 0 ? id : a.record.line - b.record.line;
    }))
      each.record,
  ];
}

/// A value as a cell; [open] says whether its record is still to be done, which a due day's tone hangs on.
Cell _cellOf(Value value, String field, String today, bool open) => switch (value) {
      EmptyValue() => const EmptyCell(),
      TextValue(:final text) => TextCell(text),
      NumberValue(:final text) => NumberCell(text),
      DayValue(:final day) => DayCell(
          day,
          tone: field == 'due' && open ? (day.compareTo(today) < 0 ? DayTone.overdue : (day == today ? DayTone.today : null)) : null,
        ),
      PriorityValue(:final name) => name != null && name.isNotEmpty ? PriorityCell(name) : const EmptyCell(),
      StatusValue(:final text, :final category) => StatusCell(text, category),
      PeopleValue(:final names) => PeopleCell(names),
      ListValue(:final items, :final tags) => ListCell(items, tags: tags),
      BoolValue(:final on) => BoolCell(on: on),
    };

/// A day field's day, where it is one.
String? _dayOf(QueryRecord record, String field, [FieldLook look = valueOf]) {
  final value = look(record, field);
  return value is DayValue ? value.day : null;
}

/// A record's row's key: its note's id, and its line for a to-do; an event's own.
String rowKeyOf(QueryRecord record) => record.event != null ? 'event:${record.event!.id}' : (record.kind == RecordKind.task ? '${record.noteId}:${record.line}' : record.noteId);

QueryRow _rowOf(QueryRecord record, List<QueryColumn> columns, String today, [FieldLook look = valueOf, Query? query]) {
  final event = record.event;
  if (event != null) {
    // An event is on its first day, runs to its last (a gantt's bar), and is never late: it is not a thing to do.
    return QueryRow(
      key: 'event:${event.id}',
      kind: record.kind,
      noteId: record.noteId,
      line: record.line,
      source: record.source,
      anchor: null,
      name: record.title,
      id: null,
      done: null,
      category: StatusCategory.todo,
      workflow: record.workflow,
      cells: [for (final column in columns) _cellOf(look(record, column.field), column.field, today, false)],
      day: event.startDay,
      start: event.startDay,
      due: event.endDay,
      overdue: false,
      end: event.endDay,
    );
  }
  final category = categoryOf(record);
  final due = _dayOf(record, 'due');
  final done = category == StatusCategory.done || record.done == true;
  String? day;
  String? dayField;
  final asked = query?.date;
  for (final field in asked != null ? [asked] : _dayFields) {
    day = _dayOf(record, field, look);
    if (day != null) {
      dayField = field;
      break;
    }
  }
  final startField = query?.start ?? 'start';
  final endField = query?.end ?? 'due';
  return QueryRow(
    key: record.kind == RecordKind.task ? '${record.noteId}:${record.line}' : record.noteId,
    kind: record.kind,
    noteId: record.noteId,
    line: record.line,
    source: record.source,
    anchor: record.anchor,
    name: record.kind == RecordKind.task ? record.text : record.title,
    id: record.kind == RecordKind.ticket ? record.ticket?.id : null,
    done: record.done,
    category: category,
    workflow: record.workflow,
    cells: [for (final column in columns) _cellOf(look(record, column.field), column.field, today, !done)],
    day: day,
    start: _dayOf(record, startField, look),
    due: due,
    overdue: due != null && due.compareTo(today) < 0 && !done,
    end: endField == 'due' ? due : _dayOf(record, endField, look),
    dayField: dayField,
  );
}

/// The totals of [fields] over [records], each added as a sum would be.
List<Total> _totalsOf(List<String> fields, List<QueryRecord> records, [FieldLook look = valueOf]) => [
      for (final field in fields)
        Total(
          field: field,
          label: fieldLabel(field),
          text: totalOf([
                for (final record in records)
                  if (look(record, field) case NumberValue(:final text) || TextValue(:final text)) text,
              ]) ??
              '0',
        ),
    ];

/// What a group of records with nothing in the field is called: "No status", "No due".
String _noneLabel(String field) => 'No ${fieldLabel(field).toLowerCase()}';

/// A group's heading, as words: the value, a ticked to-do's "Done", a status's own words.
String _groupLabel(Value value, String field) {
  if (isEmptyValue(value)) return _noneLabel(field);
  if (value is BoolValue) return value.on ? 'Done' : 'Not done';
  if (value is ListValue && value.tags) return '#${value.items[0]}';
  return valueText(value);
}

class _Grouped {
  _Grouped(this.key, this.value);
  final String key;
  final Value value;
  final List<QueryRecord> records = [];
}

/// The records in groups by [field], in the order the field's values sort, the group with nothing last. A list puts
/// its record in a group for each thing it holds. [columns] are the groups to have whether or not anything is in
/// them: a ticket board's workflow.
List<_Grouped> _grouped(List<QueryRecord> records, String field, List<String> columns, List<String> workflow, [FieldLook look = valueOf]) {
  final groups = <String, _Grouped>{};
  for (final status in columns) {
    final value = StatusValue(text: status, rank: workflow.indexOf(status).toDouble(), category: statusCategory(status, workflow), workflow: workflow);
    final key = groupKey(value);
    // Set again where two statuses share a key, in the place the first has, as a Map's `set` leaves it.
    groups[key] = _Grouped(key, value);
  }
  for (final record in records) {
    final value = look(record, field);
    final each = isEmptyValue(value) ? [value] : groupValues(value);
    for (final one in each) {
      final key = groupKey(one);
      (groups[key] ??= _Grouped(key, one)).records.add(record);
    }
  }
  return _stableSorted(groups.values.toList(), (a, b) {
    final none = (a.key.isEmpty ? 1 : 0) - (b.key.isEmpty ? 1 : 0);
    return none != 0 ? none : compareValues(a.value, b.value);
  });
}

/// The workflow a board of these records has: a notebook's named in `from:`, the one they all share, or the default.
List<String> _workflowOf(Query query, QueryLibrary library, List<QueryRecord> records) {
  for (final title in _linksIn(query.from)) {
    final statuses = noteNamed(library, title)?.statuses;
    if (statuses != null) return statuses;
  }
  // By which list it is, not what it says: two notebooks with the same statuses are still two workflows.
  final flows = Set<List<String>>.identity()..addAll(records.map((record) => record.workflow));
  return flows.length == 1 ? flows.first : defaultStatuses;
}

/// [query] run over [library] on [today] (a day, days.dart): every record of its kind that is from what `from:`
/// names and passes `where:`, sorted, limited, grouped and totalled, as the rows the drawing draws.
QueryResult runQuery(Query query, QueryLibrary library, String today) {
  final show = query.show ?? _defaultShow[query.kind]!;
  final named = <String, LibraryNote?>{};
  final warnings = <String>[];
  for (final title in _linksIn(query.from)) {
    if (named.containsKey(title)) continue;
    final note = noteNamed(library, title);
    named[title] = note;
    if (note == null) warnings.add('No note is called “$title”.');
  }
  final groupField = query.group ?? (show == ShowAs.board ? 'status' : null);
  final asksDone = [...fieldsNamed(query.where), ?groupField].any(_doneFields.contains);
  final from = query.from;
  final where = query.where;
  final look = rollupLook(query.rollups, library, today);
  final passed = [
    for (final record in library.records)
      if (_ofKind(record, query.kind) &&
          (from == null || _fromHolds(from, record, named)) &&
          (query.kind != QueryKind.tasks || asksDone || record.done == false) &&
          (where == null || holdsOn(where, record, today, look)))
        record,
  ];
  final ordered = _sorted(passed, query.sort.isNotEmpty ? query.sort : _defaultSort[query.kind]!, look);
  final limit = query.limit;
  final shown = limit != null && limit != 0 ? ordered.sublist(0, limit < ordered.length ? limit : ordered.length) : ordered;

  // A rollup is a column of its own where the columns are the kind's.
  final kinds = _defaultColumns[query.kind]!;
  final fields = query.columns.isNotEmpty ? query.columns : [...kinds, for (final rollup in query.rollups) if (!kinds.contains(rollup.name)) rollup.name];
  final columns = [for (final field in fields) QueryColumn(field: field, label: fieldLabel(field))];
  final nameField = query.kind == QueryKind.tasks ? 'text' : 'title';
  final at = fields.indexOf(nameField);
  final opens = at < 0 ? 0 : at;

  List<QueryGroup> groups;
  if (groupField != null) {
    final workflow = _workflowOf(query, library, shown);
    // A ticket board has every status of its workflow as a column, as a Jira board does, whether or not anything is in it.
    final always = show == ShowAs.board && groupField == 'status' && query.kind == QueryKind.tickets ? workflow : const <String>[];
    groups = [
      for (final group in _grouped(shown, groupField, always, workflow, look))
        QueryGroup(
          key: group.key,
          label: _groupLabel(group.value, groupField),
          cell: isEmptyValue(group.value) ? null : _cellOf(group.value, groupField, today, true),
          rows: [for (final record in group.records) _rowOf(record, columns, today, look, query)],
          totals: _totalsOf(query.total, group.records, look),
        ),
    ];
  } else {
    groups = [QueryGroup(key: '', label: '', cell: null, rows: [for (final record in shown) _rowOf(record, columns, today, look, query)], totals: _totalsOf(query.total, shown, look))];
  }

  return QueryResult(
    kind: query.kind,
    show: show,
    columns: columns,
    opens: opens,
    group: groupField,
    groups: groups,
    matched: passed.length,
    shown: shown.length,
    totals: _totalsOf(query.total, shown, look),
    gantt: show == ShowAs.gantt ? ganttOf(groups, kindWords[query.kind]!) : null,
    warnings: warnings,
    today: today,
    chart: show == ShowAs.chart ? chartOf(query, shown, rowKeyOf, look, group: query.group) : null,
    dateField: query.date,
    startField: query.start ?? 'start',
    endField: query.end ?? 'due',
    zoom: query.zoom,
  );
}
