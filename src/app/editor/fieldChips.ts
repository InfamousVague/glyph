import { CalendarDays, ChevronDown, ChevronUp, ChevronsDown, ChevronsUp, Equal, Repeat, type LucideIcon } from '@glacier/icons';
import { EditorView } from '@codemirror/view';
import { dateOfDay, daysBetween, isIsoDay } from '../core/days.ts';
import { priorityOf, type DateKey, type FieldSpan, type PriorityName } from '../core/taskFields.ts';
import { iconElement } from './iconDom.ts';

/**
 * What a field on a to-do looks like as a chip: its words, its icon, its colour and what a screen reader hears. Matt
 * asked what "notion and jira like features" Markdown could give the app, and of the answers took fields on a to-do
 * first, proposed as "due, priority and person as chips: overdue red, @sam as a person" (docs/DESIGN.md §158). The
 * grammar is core/taskFields.ts's (§156); this says only how a field it found is shown, and is shared by the two
 * places that show one: a note's line (editor/taskFields.ts) and a board's card (editor/boards/widget.ts), so a due
 * date reads "Tomorrow" on both and is red on both once it has passed.
 *
 *   📅 2026-10-03   "Sat 3 Oct", "Today", "Tomorrow", "Yesterday"; the year only when it is not this one. Red once it
 *                   has passed and the box is not ticked, amber on the day, quiet once the box is ticked
 *   🛫 ⏳ ✅ ➕ ❌     the other days, quieter, each with its word: "Starts", "Scheduled", "Done", "Added", "Cancelled"
 *   ⏫               a compact mark, the chevrons Jira draws, with the priority's name for a screen reader
 *   @sam             a person: their initial in a ring, and the name as written
 *   🔁 every week    a small repeat mark and its words
 *   [effort:: 3]     the key quiet, the value as written
 *
 * A day is named in the device's own language, as every other date in the app is (core/stamp.ts), so it is "Sat 3
 * Oct" on a British phone and "Sat, Oct 3" on an American one; the tests ask in British (test/locale.ts). Tasks' 🆔, ⛔ and 🏁 are not
 * drawn: they are ids for Obsidian to follow, and nothing here acts on them yet, so they read as written.
 */

/** Which page of the press-and-hold menu a tap on a chip opens (editor/FieldItems.tsx); null, a tap edits it. */
export type FieldMenu = 'date' | 'priority' | 'person';

/** How a chip is coloured: a day by when it is, a priority by its rank, and the rest plain or quiet. */
export type ChipTone = 'overdue' | 'today' | 'plain' | 'quiet' | 'done' | PriorityName;

export interface ChipLook {
  /** What it says, after its icon or its initial: '' for a priority, which is its mark alone. */
  text: string;
  icon: LucideIcon | null;
  tone: ChipTone;
  /** What a screen reader hears, and the chip's title: "Due Friday 3 October, overdue". */
  label: string;
  /** Which menu a tap opens, and for which field. */
  menu: FieldMenu | null;
  /** The field the menu changes: a day's key, `priority`, or the person as written. */
  key: string;
  /** A person's initial, in its ring. */
  initial?: string;
  /** A named field's key, quiet before its value. */
  name?: string;
}

/** The days a menu can set from a chip, by their key; the rest edit as written. */
const DATED: readonly DateKey[] = ['due', 'start', 'scheduled'];
/** The word before a day that is not the due day, so the chips say which day they are. */
const DAY_WORD: Record<Exclude<DateKey, 'due'>, string> = { start: 'Starts', scheduled: 'Scheduled', done: 'Done', created: 'Added', cancelled: 'Cancelled' };
/** Dataview's names for the days, read as the emoji's are (core/taskFields.ts `fieldsOf`). */
const DATAVIEW_DAYS: Readonly<Record<string, DateKey>> = { due: 'due', start: 'start', scheduled: 'scheduled', created: 'created', completion: 'done', cancelled: 'cancelled' };

/** Each priority's mark: Jira's chevrons, two up for the most urgent and two down for the least. */
const PRIORITY_ICON: Record<PriorityName, LucideIcon> = {
  highest: ChevronsUp,
  high: ChevronUp,
  medium: Equal,
  low: ChevronDown,
  lowest: ChevronsDown,
};

/**
 * A day as a chip says it, counted from `today`: "Today", "Tomorrow", "Yesterday", else its weekday, day and month,
 * "Sat 3 Oct", and the year only when it is not this one. Words that are not a day come back as they are.
 */
export function dayLabel(day: string, today: string, locale?: string): string {
  const gap = daysBetween(today, day);
  const at = dateOfDay(day);
  if (gap === null || !at) return day;
  if (gap === 0) return 'Today';
  if (gap === 1) return 'Tomorrow';
  if (gap === -1) return 'Yesterday';
  const year = day.slice(0, 4) === today.slice(0, 4) ? {} : { year: 'numeric' as const };
  return new Intl.DateTimeFormat(locale, { weekday: 'short', day: 'numeric', month: 'short', ...year }).format(at);
}

/** A day said in full for a screen reader: "Saturday 3 October", with the year when it is not this one. */
export function daySaid(day: string, today: string, locale?: string): string {
  const at = dateOfDay(day);
  if (!at) return day;
  const year = day.slice(0, 4) === today.slice(0, 4) ? {} : { year: 'numeric' as const };
  return new Intl.DateTimeFormat(locale, { weekday: 'long', day: 'numeric', month: 'long', ...year }).format(at);
}

/**
 * Where a due day stands: past and not done is overdue, on the day is today, and a ticked box quiets it whatever the
 * day, since a finished thing is not late.
 */
export function dueTone(day: string, today: string, done: boolean): 'overdue' | 'today' | 'plain' | 'done' {
  if (done) return 'done';
  const gap = daysBetween(today, day);
  if (gap === null) return 'plain';
  return gap < 0 ? 'overdue' : gap === 0 ? 'today' : 'plain';
}

/** A person's name as a chip shows it: as written, its dashes the spaces they stand for (`@sam-ortiz` is "sam ortiz"). */
export function personShown(name: string): string {
  return name.replace(/[-_]+/g, ' ').trim();
}

/** A day field's look: due, or another day with its word. */
function dayLook(key: DateKey, day: string, today: string, done: boolean, locale?: string): ChipLook {
  const named = dayLabel(day, today, locale);
  const said = daySaid(day, today, locale);
  const menu = DATED.includes(key) ? 'date' : null;
  if (key === 'due') {
    const tone = dueTone(day, today, done);
    return { text: named, icon: CalendarDays, tone, label: `Due ${said}${tone === 'overdue' ? ', overdue' : tone === 'today' ? ', today' : ''}`, menu, key };
  }
  const word = DAY_WORD[key];
  // "Starts tomorrow", "Done yesterday": a relative day after a word reads as part of the sentence.
  const shown = /^(?:Today|Tomorrow|Yesterday)$/.test(named) ? named.toLowerCase() : named;
  return { text: `${word} ${shown}`, icon: null, tone: done ? 'done' : 'quiet', label: `${word} ${said}`, menu, key };
}

/**
 * How `span` is drawn, or null where it is drawn as written: a day the calendar has not got (`2026-02-30`), a
 * priority or a day by name that does not read as one, and Tasks' ids. `done` is whether the item is finished - its
 * box ticked, or a done day on it - which quiets every chip on it.
 */
export function chipLook(span: FieldSpan, { today, done, locale }: { today: string; done: boolean; locale?: string }): ChipLook | null {
  if (span.kind === 'date') return isIsoDay(span.value) ? dayLook(span.key as DateKey, span.value, today, done, locale) : null;
  if (span.kind === 'priority' || (span.kind === 'inline' && span.key === 'priority')) {
    const priority = priorityOf(span.value);
    if (!priority) return null;
    return { text: '', icon: PRIORITY_ICON[priority.name], tone: done ? 'done' : priority.name, label: `${priority.label} priority`, menu: 'priority', key: 'priority' };
  }
  if (span.kind === 'person') {
    const shown = personShown(span.value);
    return { text: shown, icon: null, tone: done ? 'done' : 'plain', label: `Assigned to ${shown}`, menu: 'person', key: span.value, initial: shown.charAt(0).toUpperCase() };
  }
  if (span.kind === 'recurs') return { text: span.value, icon: Repeat, tone: done ? 'done' : 'quiet', label: `Repeats ${span.value}`, menu: null, key: 'recurs' };
  if (span.kind === 'inline') {
    // Dataview's `[due:: 2026-10-03]` is the due day, written its way: drawn as one, and changed in its own form.
    const day = DATAVIEW_DAYS[span.key];
    if (day && isIsoDay(span.value)) return dayLook(day, span.value, today, done, locale);
    return { text: span.value, icon: null, tone: done ? 'done' : 'quiet', label: `${span.key}: ${span.value}`, menu: null, key: span.key, name: span.key };
  }
  return null;
}

/**
 * A chip as an element: its icon or its initial, a named field's key, and its words. The same element on a line and
 * on a card; the editor's stylesheet below draws it in both, since a board is drawn inside the editor.
 */
export function chipElement(look: ChipLook, tag: 'span' | 'button' = 'span'): HTMLElement {
  const chip = document.createElement(tag);
  chip.className = 'cm-field';
  chip.dataset.tone = look.tone;
  if (!look.text) chip.dataset.mark = '';
  chip.title = look.label;
  chip.setAttribute('aria-label', look.label);
  if (look.icon) {
    chip.append(iconElement(look.icon, look.menu === 'priority' ? 2.6 : 2.2));
  }
  if (look.initial) {
    chip.dataset.person = '';
    const ring = document.createElement('span');
    ring.className = 'cm-fieldInitial';
    ring.setAttribute('aria-hidden', 'true');
    ring.textContent = look.initial;
    chip.append(ring);
  }
  if (look.name) {
    const name = document.createElement('span');
    name.className = 'cm-fieldName';
    name.setAttribute('aria-hidden', 'true');
    name.textContent = look.name;
    chip.append(name);
  }
  if (look.text) {
    const words = document.createElement('span');
    words.className = 'cm-fieldWords';
    words.setAttribute('aria-hidden', 'true');
    words.textContent = look.text;
    chip.append(words);
  }
  return chip;
}

/** Whether two looks draw the same chip, so the widget's element is kept. */
export function sameLook(a: ChipLook, b: ChipLook): boolean {
  return a.text === b.text && a.icon === b.icon && a.tone === b.tone && a.label === b.label && a.menu === b.menu && a.key === b.key && a.initial === b.initial && a.name === b.name;
}

/**
 * The chips' look, a tag's size and weight (editor/tags.ts), so a line of them reads as one line of words. A day in
 * the red ramp once it has passed and in amber on the day; a priority's mark in red, amber or blue by its rank, the
 * least in the third ink; a person's initial in a purple ring; and the rest in the third ink, unfilled, quieter than a
 * tag. A finished item's chips all go to the third ink.
 */
export const fieldChipTheme = EditorView.baseTheme({
  '.cm-field': {
    display: 'inline-block',
    // A list item's line hangs off its marker with a negative indent (editor/glyphLines.ts `--hang`), which an
    // inline block inherits and would pull its own words out of its box by.
    textIndent: '0',
    padding: '0 0.35em',
    borderRadius: '0.35em',
    background: 'color-mix(in srgb, currentColor 9%, transparent)',
    color: 'var(--app-ink-2, inherit)',
    fontSize: '0.92em',
    lineHeight: '1.35',
    whiteSpace: 'nowrap',
    fontVariantNumeric: 'tabular-nums',
    userSelect: 'none',
    WebkitUserSelect: 'none',
    WebkitTouchCallout: 'none',
    verticalAlign: 'baseline',
  },
  '.cm-field[role="button"], button.cm-field': {
    cursor: 'pointer',
  },
  'button.cm-field': {
    appearance: 'none',
    border: 'none',
    margin: '0',
    font: 'inherit',
    fontSize: '0.92em',
  },
  // By its place, not its class: an icon handed out before its first draw takes the drawn one's attributes, class and
  // all, when it arrives (editor/iconDom.ts).
  '.cm-field > svg': {
    inlineSize: '0.95em',
    blockSize: '0.95em',
    verticalAlign: '-0.14em',
  },
  '.cm-field > svg + .cm-fieldWords': {
    marginInlineStart: '0.25em',
  },
  // A priority is its mark alone: no fill, no room either side but a breath.
  '.cm-field[data-mark]': {
    padding: '0 0.1em',
    background: 'none',
  },
  '.cm-field[data-mark] > svg': {
    inlineSize: '1.1em',
    blockSize: '1.1em',
    verticalAlign: '-0.2em',
  },
  '.cm-field[data-tone="overdue"]': {
    color: 'var(--glacier-red-11)',
    background: 'color-mix(in oklch, var(--glacier-red-9) 16%, transparent)',
  },
  '.cm-field[data-tone="today"]': {
    color: 'var(--glacier-amber-11)',
    background: 'color-mix(in oklch, var(--glacier-amber-9) 18%, transparent)',
  },
  '.cm-field[data-tone="quiet"], .cm-field[data-tone="done"]': {
    color: 'var(--app-ink-3, inherit)',
    background: 'none',
    boxShadow: 'inset 0 0 0 1px color-mix(in srgb, currentColor 22%, transparent)',
  },
  '.cm-field[data-tone="highest"], .cm-field[data-tone="high"]': { color: 'var(--glacier-red-11)' },
  '.cm-field[data-tone="medium"]': { color: 'var(--glacier-amber-11)' },
  '.cm-field[data-tone="low"]': { color: 'var(--glacier-blue-11)' },
  '.cm-field[data-tone="lowest"]': { color: 'var(--app-ink-3, inherit)' },
  '.cm-field[data-mark][data-tone="done"]': { boxShadow: 'none' },
  // A person: their initial in a ring, then the name, on a pill.
  '.cm-field[data-person]': {
    paddingInlineStart: '0.12em',
    borderRadius: '999px',
  },
  '.cm-fieldInitial': {
    display: 'inline-block',
    inlineSize: '1.25em',
    blockSize: '1.25em',
    marginInlineEnd: '0.28em',
    borderRadius: '50%',
    background: 'color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)',
    color: 'var(--glacier-purple-11)',
    fontSize: '0.78em',
    fontWeight: '700',
    lineHeight: '1.25em',
    textAlign: 'center',
    verticalAlign: '0.08em',
  },
  '.cm-field[data-tone="done"] .cm-fieldInitial': {
    background: 'color-mix(in srgb, currentColor 12%, transparent)',
    color: 'inherit',
  },
  // A named field's key, smaller and a step quieter than its value.
  '.cm-fieldName': {
    marginInlineEnd: '0.3em',
    fontSize: '0.86em',
    letterSpacing: '0.02em',
    opacity: '0.75',
  },
});
