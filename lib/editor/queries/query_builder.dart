/// A query built without the grammar (Matt: make "queries and boards and stuff easier to create"): the pencil still
/// opens the lines for anyone who wants them, but the sliders on a drawn query open this, where what to list, a
/// common filter, how it is grouped and how it is shown are each a tap. Ports `src/app/editor/QueryBuilder.tsx`.
///
/// It writes one clause at a time into the body (lib/core/query/fence.dart `withClause`), live, so the query behind
/// the sheet is redrawn as it is built; it never touches the lines it does not offer (a hand-written `where:`,
/// `columns:`, `sort:`), which stay for the pencil. The deeper reaches of the grammar (and, or, nested conditions)
/// are the pencil's; this is the common query made plain.
///
/// What differs: nothing in what it offers or writes of the web's. The sheet is lib/sheet/sheet.dart, built while it
/// is open. The port's own (Matt, 2026-10-30, "add all 12"): the drawn timeline and the chart among the ways to show
/// it; a calendar's day field, a timeline's two fields and its zoom, each where that view is shown; and a chart's
/// shape, its bars, what they measure and their split, and the rollups (a ready one a tap, each taken off with
/// another), which in simple mode sit behind More, opened in place (docs/DESIGN.md, simple mode).
library;

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/preferences.dart' show preferences;
import '../../core/query/query.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'query_view.dart' show queryViews;

/// The first word of `from:` says the kind; notes where it says nothing (lib/core/query/read.dart).
const Map<String, QueryKind> _kindWord = <String, QueryKind>{
  'notes': QueryKind.notes,
  'note': QueryKind.notes,
  'pages': QueryKind.notes,
  'tickets': QueryKind.tickets,
  'ticket': QueryKind.tickets,
  'issues': QueryKind.tickets,
  'tasks': QueryKind.tasks,
  'task': QueryKind.tasks,
  'todos': QueryKind.tasks,
  'to-dos': QueryKind.tasks,
  'events': QueryKind.events,
  'event': QueryKind.events,
};

final RegExp _space = RegExp(r'\s+');

/// The kind a body's `from:` asks for (`kindOf`).
QueryKind builderKind(String? from) {
  final word = (from ?? '').trim().toLowerCase().split(_space).first;
  return _kindWord[word] ?? QueryKind.notes;
}

/// What to list, and the word written for it (`KINDS`).
const List<({QueryKind kind, String word, String label, LucideIcon icon})> builderKinds = <({QueryKind kind, String word, String label, LucideIcon icon})>[
  (kind: QueryKind.tasks, word: 'tasks', label: 'To-dos', icon: Lucide.listTodo),
  (kind: QueryKind.tickets, word: 'tickets', label: 'Tickets', icon: Lucide.ticket),
  (kind: QueryKind.notes, word: 'notes', label: 'Notes', icon: Lucide.fileText),
  // The calendars' events (docs/CALENDAR.md): the port's own.
  (kind: QueryKind.events, word: 'events', label: 'Events', icon: Lucide.calendarDays),
];

/// A common filter per kind, each a ready `where:` (null is Everything, which takes the line off) (`FILTERS`).
const Map<QueryKind, List<({String id, String label, String? where})>> builderFilters = <QueryKind, List<({String id, String label, String? where})>>{
  QueryKind.tasks: <({String id, String label, String? where})>[
    (id: 'all', label: 'Everything', where: null),
    (id: 'week', label: 'Due this week', where: 'due <= today+7'),
    (id: 'late', label: 'Overdue', where: 'due < today'),
    (id: 'person', label: 'Has a person', where: 'assignee is not empty'),
  ],
  QueryKind.tickets: <({String id, String label, String? where})>[
    (id: 'all', label: 'Everything', where: null),
    (id: 'open', label: 'Not done', where: 'status != Done'),
    (id: 'late', label: 'Overdue', where: 'due < today'),
  ],
  QueryKind.notes: <({String id, String label, String? where})>[
    (id: 'all', label: 'Everything', where: null),
    (id: 'recent', label: 'Changed this week', where: 'updated >= today-7'),
  ],
  QueryKind.events: <({String id, String label, String? where})>[
    (id: 'all', label: 'Everything', where: null),
    (id: 'soon', label: 'Coming up', where: 'start >= today'),
    (id: 'today', label: 'Today', where: 'start = today'),
    (id: 'week', label: 'This week', where: 'start >= today and start <= today+7'),
  ],
};

/// How a list, a table or a board is grouped into sections; empty is no grouping. For to-dos and tickets (`GROUPS`).
const List<({String value, String label})> builderGroups = <({String value, String label})>[
  (value: '', label: 'No grouping'),
  (value: 'status', label: 'By status'),
  (value: 'assignee', label: 'By person'),
  (value: 'priority', label: 'By priority'),
];

/// The ways to show a query, in the order the builder offers them.
const List<ShowAs> builderViews = <ShowAs>[ShowAs.table, ShowAs.list, ShowAs.board, ShowAs.calendar, ShowAs.timeline, ShowAs.chart, ShowAs.gantt, ShowAs.count];

/// The day field a calendar puts a record on (`date:`); null is the first it has (`DATE_FIELDS`, the port's own).
const List<({String? value, String label})> builderDays = <({String? value, String label})>[
  (value: null, label: 'The first day it has'),
  (value: 'due', label: 'Due'),
  (value: 'scheduled', label: 'Scheduled'),
  (value: 'start', label: 'Start'),
  (value: 'date', label: 'Date'),
  (value: 'created', label: 'Created'),
];

/// A timeline's start fields (`start:`) and end fields (`end:`); null is the default, `start` and `due`.
const List<({String? value, String label})> builderStarts = <({String? value, String label})>[
  (value: null, label: 'Start'),
  (value: 'scheduled', label: 'Scheduled'),
  (value: 'created', label: 'Created'),
  (value: 'date', label: 'Date'),
];
const List<({String? value, String label})> builderEnds = <({String? value, String label})>[
  (value: null, label: 'Due'),
  (value: 'end', label: 'End'),
  (value: 'date', label: 'Date'),
];

/// What a chart's bars are of (`x:`), what they measure (`y:`) and what splits them (`series:`).
const List<({String? value, String label})> builderX = <({String? value, String label})>[
  (value: null, label: 'Status'),
  (value: 'assignee', label: 'Person'),
  (value: 'priority', label: 'Priority'),
  (value: 'tags', label: 'Tags'),
  (value: 'notebook', label: 'Notebook'),
  (value: 'due', label: 'Due'),
];
const List<({String? value, String label})> builderY = <({String? value, String label})>[
  (value: null, label: 'How many'),
  (value: 'sum(estimate)', label: 'Estimate, added up'),
  (value: 'sum(hours)', label: 'Hours, added up'),
  (value: 'percent', label: 'How much is done'),
];
const List<({String? value, String label})> builderSeries = <({String? value, String label})>[
  (value: null, label: 'Not split'),
  (value: 'status', label: 'By status'),
  (value: 'assignee', label: 'By person'),
  (value: 'priority', label: 'By priority'),
];

/// Ready rollups, each a column worked out over the notes a record is linked with (lib/core/query/rollup.dart).
const List<({String name, String line, String label})> builderRollups = <({String name, String line, String label})>[
  (name: 'open', line: 'open = count(links where status != done)', label: 'Open notes it links to'),
  (name: 'done', line: 'done = percent(links)', label: 'How much of what it links to is done'),
  (name: 'linked', line: 'linked = count(backlinks)', label: 'Notes that link to it'),
  (name: 'hours', line: 'hours = sum(hours of backlinks)', label: 'Hours on the notes that link to it'),
  (name: 'todos', line: 'todos = percent(tasks)', label: 'Its to-dos ticked'),
];

/// A row's mark, at the size its slot gives it (`.icon svg { inline-size: 18px }`).
Widget _mark(LucideIcon icon) => AppIcon(icon, size: 18);

bool _same(String? a, String? b) => (a ?? '').trim().toLowerCase() == (b ?? '').trim().toLowerCase();

class QueryBuilder extends StatefulWidget {
  const QueryBuilder({super.key, required this.body, required this.onBody, required this.onLines, required this.onClose, this.simple});

  /// The current fence body, the lines between the fences.
  final String body;

  /// Writes the whole body back (queries.dart), one clause changed.
  final void Function(String body) onBody;

  /// Shows the lines instead, the caret in them.
  final VoidCallback onLines;
  final VoidCallback onClose;

  /// Whether the app is in simple mode, the chart's and the rollups' rows behind More; the preference where unsaid.
  final bool? simple;

  @override
  State<QueryBuilder> createState() => _QueryBuilderState();
}

class _QueryBuilderState extends State<QueryBuilder> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    final onBody = widget.onBody;
    final onLines = widget.onLines;
    final onClose = widget.onClose;
    final kind = builderKind(clauseValue(body, 'from'));
    final where = clauseValue(body, 'where');
    final group = clauseValue(body, 'group');
    // `view:` is read as `show:`, and written where it is the line the body has.
    final showLine = clauseValue(body, 'show') == null && clauseValue(body, 'view') != null ? 'view' : 'show';
    final show = (clauseValue(body, showLine) ?? '').trim().toLowerCase();
    final shown = ShowAs.values.where((each) => each.name == show).firstOrNull ?? (show == 'graph' ? ShowAs.chart : null);
    final simple = widget.simple ?? preferences.value.simple;
    final more = !simple || _more;
    final rollups = rollupNames(body);

    /// A heading and its rows, each a value of [clause] where null takes the line off.
    List<Widget> choices(String heading, String clause, List<({String? value, String label})> each, {String id = ''}) {
      final said = clauseValue(body, clause);
      final has = said != null && said.isNotEmpty;
      return <Widget>[
        SheetHeading(heading),
        SheetGroup(
          children: <Widget>[
            for (final one in each)
              SheetRow(
                key: ValueKey<String>('${id.isEmpty ? clause : id}:${one.value ?? ''}'),
                label: one.label,
                chosen: one.value == null ? !has : _same(said, one.value),
                onPress: () => onBody(withClause(body, clause, one.value)),
              ),
            if (has && !each.any((one) => one.value != null && _same(said, one.value)))
              SheetRow(key: ValueKey<String>('${id.isEmpty ? clause : id}:own'), label: 'Your own: $said', hint: 'Edit with the pencil', chosen: true, onPress: onLines),
          ],
        ),
      ];
    }
    final filters = builderFilters[kind]!;
    // Statuses, people and priorities are a to-do's and a ticket's: a note and an event have none to group by.
    final grouped = kind != QueryKind.notes && kind != QueryKind.events;
    final has = where != null && where.isNotEmpty;
    final none = group == null || group.isEmpty;

    // A new kind drops a filter meant for the old one, so what is listed is never filtered by a field it hasn't got.
    void chooseKind(String word) => onBody(withClause(withClause(body, 'from', word), 'where', null));

    return Sheet(
      label: 'Build the query',
      onClose: onClose,
      children: <Widget>[
        SheetTitle.text('Build the query'),
        const SheetHeading('List'),
        SheetGroup(
          children: <Widget>[
            for (final each in builderKinds) SheetRow(key: ValueKey<String>('kind:${each.word}'), icon: _mark(each.icon), label: each.label, chosen: kind == each.kind, onPress: () => chooseKind(each.word)),
          ],
        ),
        const SheetHeading('Only'),
        SheetGroup(
          children: <Widget>[
            for (final filter in filters)
              SheetRow(
                key: ValueKey<String>('only:${filter.id}'),
                label: filter.label,
                chosen: filter.where == null ? !has : _same(where, filter.where),
                onPress: () => onBody(withClause(body, 'where', filter.where)),
              ),
            if (has && !filters.any((filter) => filter.where != null && _same(where, filter.where)))
              SheetRow(key: const ValueKey<String>('only:own'), label: 'Your own: $where', hint: 'Edit with the pencil', chosen: true, onPress: onLines),
          ],
        ),
        if (grouped) ...<Widget>[
          const SheetHeading('Group'),
          SheetGroup(
            children: <Widget>[
              for (final each in builderGroups)
                SheetRow(
                  key: ValueKey<String>('group:${each.value}'),
                  label: each.label,
                  chosen: each.value.isNotEmpty ? _same(group, each.value) : none,
                  onPress: () => onBody(withClause(body, 'group', each.value.isEmpty ? null : each.value)),
                ),
            ],
          ),
        ],
        const SheetHeading('Show'),
        SheetGroup(
          children: <Widget>[
            for (final view in builderViews)
              SheetRow(
                key: ValueKey<String>('show:${view.name}'),
                icon: _mark(queryViews[view]!.icon),
                label: view == ShowAs.gantt ? 'Gantt (Mermaid)' : queryViews[view]!.label,
                chosen: show.isNotEmpty ? show == view.name || shown == view : view == ShowAs.table,
                onPress: () => onBody(withClause(body, showLine, view.name)),
              ),
          ],
        ),
        if (shown == ShowAs.calendar) ...choices('Put each on', 'date', builderDays),
        if (shown == ShowAs.timeline) ...<Widget>[
          ...choices('Bars start on', 'start', builderStarts),
          ...choices('Bars end on', 'end', builderEnds),
          ...choices('Zoom', 'zoom', const <({String? value, String label})>[
            (value: null, label: 'As wide as the bars'),
            (value: 'week', label: 'Week'),
            (value: 'month', label: 'Month'),
            (value: 'quarter', label: 'Quarter'),
          ]),
        ],
        if (!more)
          SheetGroup(
            children: <Widget>[
              SheetRow(
                key: const ValueKey<String>('more'),
                icon: _mark(Lucide.ellipsis),
                label: 'More',
                hint: shown == ShowAs.chart ? 'The chart and rollups' : 'Rollups over linked notes',
                onPress: () => setState(() => _more = true),
              ),
            ],
          )
        else ...<Widget>[
          if (shown == ShowAs.chart) ...<Widget>[
            ...choices('Chart', 'chart', const <({String? value, String label})>[(value: null, label: 'Bars'), (value: 'line', label: 'A line'), (value: 'pie', label: 'A pie')]),
            ...choices('Bars of', 'x', builderX),
            ...choices('Each measures', 'y', builderY),
            ...choices('Split', 'series', builderSeries),
          ],
          const SheetHeading('Rollups'),
          SheetGroup(
            children: <Widget>[
              for (final name in rollups)
                SheetRow(
                  key: ValueKey<String>('rollup-off:$name'),
                  icon: _mark(Lucide.x),
                  label: 'Take off “$name”',
                  onPress: () => onBody(withRollup(body, name, null)),
                ),
              for (final ready in builderRollups)
                if (!rollups.contains(ready.name))
                  SheetRow(
                    key: ValueKey<String>('rollup:${ready.name}'),
                    icon: _mark(Lucide.plus),
                    label: ready.label,
                    hint: ready.line,
                    onPress: () => onBody(withRollup(body, ready.name, ready.line)),
                  ),
              SheetRow(key: const ValueKey<String>('rollup:own'), label: 'Your own', hint: 'rollup: name = count(links where …), with the pencil', onPress: onLines),
            ],
          ),
        ],
      ],
    );
  }
}
