/// A query built without the grammar (Matt: make "queries and boards and stuff easier to create"): the pencil still
/// opens the lines for anyone who wants them, but the sliders on a drawn query open this, where what to list, a
/// common filter, how it is grouped and how it is shown are each a tap. Ports `src/app/editor/QueryBuilder.tsx`.
///
/// It writes one clause at a time into the body (lib/core/query/fence.dart `withClause`), live, so the query behind
/// the sheet is redrawn as it is built; it never touches the lines it does not offer (a hand-written `where:`,
/// `columns:`, `sort:`), which stay for the pencil. The deeper reaches of the grammar (and, or, nested conditions)
/// are the pencil's; this is the common query made plain.
///
/// What differs: nothing in what it offers or writes. The sheet is lib/sheet/sheet.dart, built while it is open.
library;

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
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

/// A row's mark, at the size its slot gives it (`.icon svg { inline-size: 18px }`).
Widget _mark(LucideIcon icon) => AppIcon(icon, size: 18);

bool _same(String? a, String? b) => (a ?? '').trim().toLowerCase() == (b ?? '').trim().toLowerCase();

class QueryBuilder extends StatelessWidget {
  const QueryBuilder({super.key, required this.body, required this.onBody, required this.onLines, required this.onClose});

  /// The current fence body, the lines between the fences.
  final String body;

  /// Writes the whole body back (queries.dart), one clause changed.
  final void Function(String body) onBody;

  /// Shows the lines instead, the caret in them.
  final VoidCallback onLines;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final kind = builderKind(clauseValue(body, 'from'));
    final where = clauseValue(body, 'where');
    final group = clauseValue(body, 'group');
    final show = (clauseValue(body, 'show') ?? '').trim().toLowerCase();
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
            for (final view in const <ShowAs>[ShowAs.table, ShowAs.list, ShowAs.board, ShowAs.calendar, ShowAs.gantt, ShowAs.count])
              SheetRow(
                key: ValueKey<String>('show:${view.name}'),
                icon: _mark(queryViews[view]!.icon),
                label: queryViews[view]!.label,
                chosen: show.isNotEmpty ? show == view.name : view == ShowAs.table,
                onPress: () => onBody(withClause(body, 'show', view.name)),
              ),
          ],
        ),
      ],
    );
  }
}
