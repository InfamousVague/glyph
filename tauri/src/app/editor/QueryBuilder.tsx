import { CalendarDays, ChartGantt, FileText, List as ListIcon, ListTodo, Sigma, SquareKanban, Table as TableIcon, Ticket } from '@glacier/icons';
import type { ComponentType } from 'react';
import { clauseValue, withClause } from '../core/query/fence.ts';
import type { QueryKind, ShowAs } from '../core/query/read.ts';
import { SheetGroup, SheetHeading, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { Sheet } from './Sheet.tsx';

/**
 * A query built without the grammar (Matt: make "queries and boards and stuff easier to create"): the pencil still
 * opens the lines for anyone who wants them, but the sliders on a drawn query open this, where what to list, a common
 * filter, how it is grouped and how it is shown are each a tap. It writes one clause at a time into the body
 * (core/query/fence.ts `withClause`), live, so the query behind the sheet is redrawn as it is built; it never touches
 * the lines it does not offer (a hand-written `where:`, `columns:`, `sort:`), which stay for the pencil. The deeper
 * reaches of the grammar - and, or, nested conditions - are the pencil's; this is the common query made plain.
 */

interface QueryBuilderProps {
  /** The current fence body, the lines between the fences. */
  body: string;
  /** Writes the whole body back (editor/queries.ts), one clause changed. */
  onBody: (body: string) => void;
  /** Shows the lines instead, the caret in them. */
  onLines: () => void;
  onClose: () => void;
}

/** The first word of `from:` says the kind; notes where it says nothing (core/query/read.ts `KINDS`). */
const KIND_WORD: Readonly<Record<string, QueryKind>> = {
  notes: 'notes',
  note: 'notes',
  pages: 'notes',
  tickets: 'tickets',
  ticket: 'tickets',
  issues: 'tickets',
  tasks: 'tasks',
  task: 'tasks',
  todos: 'tasks',
  'to-dos': 'tasks',
};

function kindOf(from: string | null): QueryKind {
  const word = (from ?? '').trim().toLowerCase().split(/\s+/)[0] ?? '';
  return KIND_WORD[word] ?? 'notes';
}

/** What to list, and the word written for it. */
const KINDS: readonly { kind: QueryKind; word: string; label: string; icon: ComponentType }[] = [
  { kind: 'tasks', word: 'tasks', label: 'To-dos', icon: ListTodo },
  { kind: 'tickets', word: 'tickets', label: 'Tickets', icon: Ticket },
  { kind: 'notes', word: 'notes', label: 'Notes', icon: FileText },
];

/** A common filter per kind, each a ready `where:` (null is Everything, which takes the line off). */
const FILTERS: Readonly<Record<QueryKind, readonly { id: string; label: string; where: string | null }[]>> = {
  tasks: [
    { id: 'all', label: 'Everything', where: null },
    { id: 'week', label: 'Due this week', where: 'due <= today+7' },
    { id: 'late', label: 'Overdue', where: 'due < today' },
    { id: 'person', label: 'Has a person', where: 'assignee is not empty' },
  ],
  tickets: [
    { id: 'all', label: 'Everything', where: null },
    { id: 'open', label: 'Not done', where: 'status != Done' },
    { id: 'late', label: 'Overdue', where: 'due < today' },
  ],
  notes: [
    { id: 'all', label: 'Everything', where: null },
    { id: 'recent', label: 'Changed this week', where: 'updated >= today-7' },
  ],
};

/** How a list, a table or a board is grouped into sections; empty is no grouping. For to-dos and tickets. */
const GROUPS: readonly { value: string; label: string }[] = [
  { value: '', label: 'No grouping' },
  { value: 'status', label: 'By status' },
  { value: 'assignee', label: 'By person' },
  { value: 'priority', label: 'By priority' },
];

const VIEWS: readonly { show: ShowAs; label: string; icon: ComponentType }[] = [
  { show: 'table', label: 'Table', icon: TableIcon },
  { show: 'list', label: 'List', icon: ListIcon },
  { show: 'board', label: 'Board', icon: SquareKanban },
  { show: 'calendar', label: 'Calendar', icon: CalendarDays },
  { show: 'gantt', label: 'Timeline', icon: ChartGantt },
  { show: 'count', label: 'Count', icon: Sigma },
];

const same = (a: string | null, b: string | null) => (a ?? '').trim().toLowerCase() === (b ?? '').trim().toLowerCase();

export function QueryBuilder({ body, onBody, onLines, onClose }: QueryBuilderProps) {
  const kind = kindOf(clauseValue(body, 'from'));
  const where = clauseValue(body, 'where');
  const group = clauseValue(body, 'group');
  const show = (clauseValue(body, 'show') ?? '').trim().toLowerCase();
  const filters = FILTERS[kind];
  const grouped = kind !== 'notes';

  const chooseKind = (word: string) => {
    // A new kind drops a filter meant for the old one, so what is listed is never filtered by a field it hasn't got.
    onBody(withClause(withClause(body, 'from', word), 'where', null));
  };

  return (
    <Sheet label="Build the query" onClose={onClose}>
      <SheetTitle>Build the query</SheetTitle>

      <SheetHeading>List</SheetHeading>
      <SheetGroup>
        {KINDS.map((each) => (
          <SheetRow key={each.kind} icon={each.icon} label={each.label} chosen={kind === each.kind} onPress={() => chooseKind(each.word)} />
        ))}
      </SheetGroup>

      <SheetHeading>Only</SheetHeading>
      <SheetGroup>
        {filters.map((filter) => (
          <SheetRow
            key={filter.id}
            label={filter.label}
            chosen={filter.where === null ? !where : same(where, filter.where)}
            onPress={() => onBody(withClause(body, 'where', filter.where))}
          />
        ))}
        {where && !filters.some((filter) => filter.where !== null && same(where, filter.where)) ? <SheetRow label={`Your own: ${where}`} hint="Edit with the pencil" chosen onPress={onLines} /> : null}
      </SheetGroup>

      {grouped ? (
        <>
          <SheetHeading>Group</SheetHeading>
          <SheetGroup>
            {GROUPS.map((each) => (
              <SheetRow key={each.value || 'none'} label={each.label} chosen={each.value ? same(group, each.value) : !group} onPress={() => onBody(withClause(body, 'group', each.value || null))} />
            ))}
          </SheetGroup>
        </>
      ) : null}

      <SheetHeading>Show</SheetHeading>
      <SheetGroup>
        {VIEWS.map((view) => (
          <SheetRow
            key={view.show}
            icon={view.icon}
            label={view.label}
            chosen={show ? show === view.show : view.show === 'table'}
            onPress={() => onBody(withClause(body, 'show', view.show))}
          />
        ))}
      </SheetGroup>
    </Sheet>
  );
}
