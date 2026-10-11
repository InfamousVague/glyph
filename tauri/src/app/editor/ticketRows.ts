import type { TicketChoice } from '../book/tickets.ts';
import { dateOfDay, daysBetween } from '../core/days.ts';
import { propertiesOf, propertyKind, propertyList, type StatusCategory } from '../core/properties.ts';

/**
 * What a ticket's panel shows and how it says it (editor/TicketPanel.tsx, editor/tickets.ts; docs/DESIGN.md §157):
 * which rows, which keys go under it on the quiet line, a day in words, a due day that has passed, and a link to
 * another ticket as it is written. Pure, apart from the drawing, so each is a test (editor/ticketRows.test.ts).
 */

/** The keys the panel always shows a row for, set or not: what a ticket is mostly asked. */
export const ALWAYS_SHOWN = ['status', 'assignee', 'priority', 'due'] as const;
/** The rows the panel shows past those once set, or when More is pressed. */
export const SHOWN_WHEN_SET = ['start', 'estimate', 'blocked-by', 'parent', 'labels'] as const;

export type PanelKey = (typeof ALWAYS_SHOWN)[number] | (typeof SHOWN_WHEN_SET)[number];

/** Keys the panel never names under itself: the ticket's own type, its id (the panel's heading), and how the note looks. */
const UNSAID = new Set(['type', 'id', 'look']);

/** The panel's rows for a ticket's front matter: the four always, then any of the rest that is set, or all of them with `more`. */
export function panelRows(front: string, more = false): PanelKey[] {
  const set = new Set(
    propertiesOf(front)
      .filter((property) => propertyList(property.value).length > 0)
      .map((property) => property.key.toLowerCase()),
  );
  return [...ALWAYS_SHOWN, ...SHOWN_WHEN_SET.filter((key) => more || set.has(key))];
}

/** The rows waiting behind More: the ticket keys the panel would show if they were set. */
export function hiddenRows(front: string): PanelKey[] {
  const shown = new Set<string>(panelRows(front));
  return SHOWN_WHEN_SET.filter((key) => !shown.has(key));
}

/** The keys a ticket holds that are not a ticket's, in order, as written: the quiet line under the panel. */
export function otherKeys(front: string): string[] {
  return propertiesOf(front)
    .map((property) => property.key)
    .filter((key) => !UNSAID.has(key.toLowerCase()) && propertyKind(key) === 'text');
}

/**
 * A day as the panel says it: Today, Tomorrow, Yesterday, else the weekday and the date in the device's language,
 * "Sat 3 Oct", with the year where it is not this one. The day as written where it is not one.
 */
export function dayLabel(iso: string, today: string): string {
  const between = daysBetween(today, iso);
  const at = dateOfDay(iso);
  if (between === null || !at) return iso;
  if (between === 0) return 'Today';
  if (between === 1) return 'Tomorrow';
  if (between === -1) return 'Yesterday';
  const sameYear = iso.slice(0, 4) === today.slice(0, 4);
  return new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short', ...(sameYear ? {} : { year: 'numeric' }) }).format(at);
}

/** Whether a due day has passed with the ticket not done (red), is today (amber), or neither. */
export function dueState(due: string | null, today: string, category: StatusCategory): 'overdue' | 'today' | null {
  if (!due || category === 'done') return null;
  const between = daysBetween(today, due);
  if (between === null) return null;
  return between < 0 ? 'overdue' : between === 0 ? 'today' : null;
}

/** How a ticket is linked from a property: by its key where it has one, else its title, as a note link. */
export function linkTo(choice: TicketChoice): string {
  return `[[${choice.key ?? choice.title}]]`;
}

/**
 * What a list of links is written as: nothing for none, one link as a quoted value (`blocked-by: "[[GHO-9]]"`, the way
 * the proposal wrote it), several across as a flow list (core/properties.ts `yamlList`).
 */
export function linksValue(links: readonly string[]): string | readonly string[] | null {
  if (!links.length) return null;
  return links.length === 1 ? links[0]! : links;
}
