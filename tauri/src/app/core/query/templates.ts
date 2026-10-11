import type { ShowAs } from './read.ts';

/**
 * The databases the + offers ready-made (editor/addRows.ts, editor/AddList.tsx; docs/QUERIES.md, docs/DESIGN.md §160).
 * Matt: "make templates for databases on the + menu". Each is a query a person would otherwise have to learn to write,
 * the ones a notes app is asked for most - what is due this week, what is late, who has what, a ticket board, a
 * timeline - written the way docs/QUERIES.md teaches, so the lines that appear are an example of the grammar as much as
 * a database, and changed with the pencil like any other.
 *
 * Written to work in any library: no notebook, tag or person is named, so each finds something the moment it is put
 * in, or says plainly that nothing matches yet. Write your own is last, an open query with its kind selected to be
 * written over. Pure, so every one is read and run by the tests (core/query/templates.test.ts).
 */

export interface QueryTemplate {
  /** Its row's id in the + list, after `query:`. */
  id: string;
  /** What the row says. */
  words: string;
  /** How it is shown, for the row's icon. */
  show: ShowAs;
  /** The fence's lines. */
  lines: string;
  /** Where the caret goes: after the fence, so it is drawn at once; or on these words, to be written over. */
  select?: string;
}

export const QUERY_TEMPLATES: readonly QueryTemplate[] = [
  { id: 'week', words: 'To-dos due this week', show: 'list', lines: 'from: tasks\nwhere: due <= today+7\nsort: due, priority\nshow: list' },
  { id: 'late', words: 'Overdue to-dos', show: 'list', lines: 'from: tasks\nwhere: due < today\nsort: due\nshow: list' },
  { id: 'people', words: 'To-dos by person', show: 'list', lines: 'from: tasks\nwhere: assignee is not empty\ngroup: assignee\nsort: due\nshow: list' },
  { id: 'month', words: 'To-dos on a calendar', show: 'calendar', lines: 'from: tasks\nshow: calendar' },
  { id: 'board', words: 'A ticket board', show: 'board', lines: 'from: tickets\nshow: board' },
  {
    id: 'tickets',
    words: 'Open tickets, with estimates',
    show: 'table',
    lines: 'from: tickets\nwhere: status != Done\nsort: priority, due\ncolumns: id, title, status, assignee, priority, due, estimate\ntotal: estimate\nshow: table',
  },
  { id: 'timeline', words: 'A ticket timeline', show: 'gantt', lines: 'from: tickets\nwhere: status != Done\nshow: gantt' },
  { id: 'recent', words: 'Notes changed this week', show: 'list', lines: 'from: notes\nwhere: updated >= today-7\nshow: list' },
  { id: 'count', words: 'How many to-dos are open', show: 'count', lines: 'from: tasks\nshow: count' },
  { id: 'own', words: 'Write your own', show: 'list', lines: 'from: tasks\nwhere: due <= today+7\nsort: due, priority\nshow: list', select: 'tasks' },
];
