/// The databases the + offers ready-made (lib/editor/plus/add_rows.dart, add_list.dart; tauri/docs/QUERIES.md,
/// docs/DESIGN.md §160). A port of `src/app/core/query/templates.ts`. Matt: "make templates for databases on the +
/// menu". Each is a query a person would otherwise have to learn to write, the ones a notes app is asked for most -
/// what is due this week, what is late, who has what, a ticket board, a timeline - written the way docs/QUERIES.md
/// teaches, so the lines that appear are an example of the grammar as much as a database, and changed with the
/// pencil like any other.
///
/// Written to work in any library: no notebook, tag or person is named, so each finds something the moment it is
/// put in, or says plainly that nothing matches yet. Write your own is last, an open query with its kind selected to
/// be written over. Pure, so every one is read and run by the tests (test/query/templates_test.dart).
///
/// What differs: `QUERY_TEMPLATES` is [queryTemplates]. This was lib/editor/plus/query_templates.dart until the
/// query core was ported, with `show` a word; that file now hands this one on, and [QueryTemplate.show] is a
/// [ShowAs] (its `name` is the word).
library;

import 'read.dart' show ShowAs;

/// One ready-made query.
class QueryTemplate {
  const QueryTemplate({required this.id, required this.words, required this.show, required this.lines, this.select});

  /// Its row's id in the + list, after `query:`.
  final String id;

  /// What the row says.
  final String words;

  /// How it is shown, for the row's icon.
  final ShowAs show;

  /// The fence's lines.
  final String lines;

  /// Where the caret goes: null, after the fence, so it is drawn at once; or on these words, to be written over.
  final String? select;
}

const List<QueryTemplate> queryTemplates = <QueryTemplate>[
  QueryTemplate(id: 'week', words: 'To-dos due this week', show: ShowAs.list, lines: 'from: tasks\nwhere: due <= today+7\nsort: due, priority\nshow: list'),
  QueryTemplate(id: 'late', words: 'Overdue to-dos', show: ShowAs.list, lines: 'from: tasks\nwhere: due < today\nsort: due\nshow: list'),
  QueryTemplate(id: 'people', words: 'To-dos by person', show: ShowAs.list, lines: 'from: tasks\nwhere: assignee is not empty\ngroup: assignee\nsort: due\nshow: list'),
  QueryTemplate(id: 'month', words: 'To-dos on a calendar', show: ShowAs.calendar, lines: 'from: tasks\nshow: calendar'),
  QueryTemplate(id: 'board', words: 'A ticket board', show: ShowAs.board, lines: 'from: tickets\nshow: board'),
  QueryTemplate(
    id: 'tickets',
    words: 'Open tickets, with estimates',
    show: ShowAs.table,
    lines: 'from: tickets\nwhere: status != Done\nsort: priority, due\ncolumns: id, title, status, assignee, priority, due, estimate\ntotal: estimate\nshow: table',
  ),
  QueryTemplate(id: 'timeline', words: 'A ticket timeline', show: ShowAs.gantt, lines: 'from: tickets\nwhere: status != Done\nshow: gantt'),
  QueryTemplate(id: 'recent', words: 'Notes changed this week', show: ShowAs.list, lines: 'from: notes\nwhere: updated >= today-7\nshow: list'),
  QueryTemplate(id: 'count', words: 'How many to-dos are open', show: ShowAs.count, lines: 'from: tasks\nshow: count'),
  QueryTemplate(id: 'own', words: 'Write your own', show: ShowAs.list, lines: 'from: tasks\nwhere: due <= today+7\nsort: due, priority\nshow: list', select: 'tasks'),
];
