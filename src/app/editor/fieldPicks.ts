import { statusCategory, type StatusCategory } from '../core/properties.ts';
import type { Cell, Row } from '../core/query/run.ts';
import type { PriorityName } from '../core/taskFields.ts';

/**
 * What a field picker offers and how its marks are chosen (editor/FieldPicker.tsx draws them; docs/DESIGN.md §169):
 * which sheet a record's field opens in a query (editor/QueryView.tsx), with what it holds now; a status's mark; a
 * person's hue. Pure, so the choices can be tested without drawing a sheet.
 */

export type FieldPick =
  | { kind: 'status'; value: string | null; workflow: readonly string[] }
  /** A to-do's status, which is its box: To do or Done. */
  | { kind: 'box'; done: boolean }
  | { kind: 'priority'; value: PriorityName | null }
  | { kind: 'person'; value: string | null; people: readonly string[] }
  | { kind: 'day'; value: string | null; today: string };

/** How a status is marked: a backlog's dashed ring, a review's eye, else its category's ring, dot or tick. */
export type StatusLook = 'backlog' | 'todo' | 'doing' | 'review' | 'done';

export function statusLook(status: string, workflow?: readonly string[]): StatusLook {
  const category: StatusCategory = statusCategory(status, workflow);
  if (category === 'done') return 'done';
  if (category === 'doing') return /review/i.test(status) ? 'review' : 'doing';
  return /backlog|later|someday|icebox/i.test(status) ? 'backlog' : 'todo';
}

export const HUES = ['blue', 'purple', 'green', 'amber', 'red', 'teal'] as const;

/** One of six hues for a name, the same every time: its letters added up, case and at signs aside. */
export function hueOf(name: string): (typeof HUES)[number] {
  let sum = 0;
  for (const letter of name.replace(/^@+/, '').toLowerCase()) sum = (sum * 31 + letter.charCodeAt(0)) % 9973;
  return HUES[sum % HUES.length]!;
}

/** The days a sheet picks: a due and a start day, and a to-do's scheduled day, which a ticket does not have. */
const PICKED_DAYS: ReadonlySet<string> = new Set(['due', 'start', 'scheduled']);

const picksDay = (row: Row, key: string) => PICKED_DAYS.has(key) && (row.kind === 'task' || key !== 'scheduled');

/** What sheet a record's field opens, from what it holds now; null for a field nothing picks (a title, a tag, a note). */
export function pickOf(row: Row, field: string, cell: Cell, today: string, people: () => readonly string[]): FieldPick | null {
  const key = field.toLowerCase();
  if (key === 'status') {
    if (row.kind === 'task') return row.done === null ? null : { kind: 'box', done: row.done };
    return { kind: 'status', value: cell.kind === 'status' ? cell.text : null, workflow: row.workflow };
  }
  if (key === 'priority') return { kind: 'priority', value: cell.kind === 'priority' ? cell.name : null };
  if (key === 'assignee') return { kind: 'person', value: cell.kind === 'people' ? (cell.names[0] ?? null) : null, people: people() };
  if (picksDay(row, key)) return { kind: 'day', value: cell.kind === 'day' ? cell.day : null, today };
  return null;
}

/** Whether a field is one `pickOf` opens a sheet for, without reading the people. */
export function picksField(row: Row, field: string): boolean {
  const key = field.toLowerCase();
  if (key === 'status') return row.kind !== 'task' || row.done !== null;
  return key === 'priority' || key === 'assignee' || picksDay(row, key);
}

