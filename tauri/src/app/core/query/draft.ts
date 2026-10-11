import type { Condition, Literal, Query, Source } from './read.ts';

/**
 * What a ticket made from a lane of a query's board must say for the query to list it in that lane (Matt: "add the
 * ability to add new tickets to query boards from the board like we can on the standard board"): the lane's value in
 * the field the board groups by, the notebook `from:` names (its pages are what `[[A notebook]]` lists), the labels its
 * `#tag`s ask for, the person its `@name` does, and every `field = value` its `where:` insists on. Only what every
 * record listed must have is taken: a source or a test under `or` or `not` names one of several ways in, so it is left
 * to the person. A ticket made from what is taken may still miss a `<` or a `contains`; the board's lane is the one
 * thing it is sure to match.
 *
 * Tickets only: a query of to-dos has no one note a new line belongs in, and a query of notes no workflow its lanes
 * come from. Pure; the screen makes the note (App.tsx `addFromQuery`).
 */
export interface TicketDraft {
  /** The note `from: [[…]]` names first: the notebook the ticket goes in, or a note it links to; null for neither. */
  link: string | null;
  /** Front-matter properties to set, in order, the lane's last so nothing in `where:` overrides it. */
  fields: [field: string, value: string][];
  /** The `#tag`s `from:` asks for, as the ticket's labels. */
  labels: string[];
}

/** Fields a ticket's maker sets or the library reads from elsewhere, never copied from a test. */
const MADE = new Set(['title', 'id', 'key', 'type', 'note', 'created', 'updated', 'done', 'checked', 'tags', 'labels', 'text']);

/** Whether a board drawn from `query` can make its tickets from a lane. */
export function draftsTickets(query: Query): boolean {
  return query.kind === 'tickets';
}

/**
 * The ticket a lane of `query`'s board makes: `group` is the field the board is grouped by as it ran (a board left
 * ungrouped is a ticket's status, core/query/run.ts), and `lane` the lane's value in it, or null for a board of one lane.
 */
export function ticketDraft(query: Query, group: string | null, lane: string | null): TicketDraft | null {
  if (!draftsTickets(query)) return null;
  const sources = required(query.from);
  const link = sources.find((source) => source.kind === 'link')?.title ?? null;
  const labels = sources.flatMap((source) => (source.kind === 'tag' ? [source.tag.replace(/^#/, '')] : []));
  const person = sources.find((source) => source.kind === 'person')?.name ?? null;
  const fields = new Map<string, string>();
  if (person) fields.set('assignee', person);
  for (const test of insisted(query.where)) {
    const field = test.field.toLowerCase();
    if (MADE.has(field)) continue;
    const value = literalText(test.value);
    if (value !== null) fields.set(field, value);
  }
  const grouped = group?.toLowerCase() ?? null;
  if (grouped) {
    fields.delete(grouped);
    if (lane !== null) fields.set(grouped, lane);
  }
  return { link, fields: [...fields], labels };
}

/** The sources every record must come from: `from:`'s own, or each side of an `and`, never one under `or` or `not`. */
function required(from: Source | null): Source[] {
  if (!from) return [];
  if (from.kind === 'and') return from.all.flatMap(required);
  if (from.kind === 'or' || from.kind === 'not') return [];
  return [from];
}

/** The `field = value` tests every record must pass: `where:`'s own, or each side of an `and`. */
function insisted(where: Condition | null): Extract<Condition, { kind: 'compare' }>[] {
  if (!where) return [];
  if (where.kind === 'and') return where.all.flatMap(insisted);
  if (where.kind === 'compare' && where.op === '=') return [where];
  return [];
}

/** A value as a front-matter property writes it; null for `empty` or a day counted from today, which says no one day. */
function literalText(value: Literal): string | null {
  if (value.kind === 'words' || value.kind === 'number') return value.text;
  if (value.kind === 'date') return value.day;
  return null;
}
