import { useEffect, useRef } from 'react';
import type { EditorView } from '@codemirror/view';
import { nextWeek } from '../core/dayWords.ts';
import { isIsoDay, isoDay, isoDayAfter } from '../core/days.ts';
import { listLead } from '../core/itemSyntax.ts';
import { fieldsIn, fieldsOf, personKey, withAssignee, withField, type DateKey, type FieldKey } from '../core/taskFields.ts';

/**
 * What the press-and-hold menu does with a to-do's fields (docs/DESIGN.md §158): the page it turns to when a chip is
 * tapped or a field is asked for, the days it offers, and the edits a press makes. Every edit goes through the one
 * writer, core/taskFields.ts `withField` and `withAssignee` (§156), so a date set from the menu is where Obsidian Tasks
 * reads it, and each is one ordinary edit of one line: one undo, saved like typing.
 *
 * The menu is the one the note already has (editor/ContextMenu.tsx), not a new kind: a press and hold on a line
 * offers Due date, Priority and Assign beside Duplicate and Move up, and a tap on a chip opens the same band at the
 * chip, on that field's page (editor/FieldItems.tsx). A chip is drawn by CodeMirror and the menu by React, so a tap is
 * told to the menu as an event on the editor's element (`FIELD_TAP`), the way a press and hold reaches it as the
 * browser's `contextmenu` (editor/pressAndHold.ts).
 */

/** Which page of fields the band shows. */
export type FieldPage =
  /** A day: Today, Tomorrow, Next week, a date picked, or none. */
  | { kind: 'date'; key: Extract<DateKey, 'due' | 'start' | 'scheduled'> }
  /** The five priorities, and none. */
  | { kind: 'priority' }
  /** One person on the line, to take off. */
  | { kind: 'person'; name: string }
  /** The people this note names, to put on the line or take off, and someone new. */
  | { kind: 'assign' };

/** A chip tapped: which page, for which line (counting from 1), and where the chip is on the screen. */
export interface FieldTap {
  page: FieldPage;
  line: number;
  x: number;
  y: number;
}

/** The event a tapped chip sends on the editor's element, which the menu listens for. */
export const FIELD_TAP = 'glyph:fieldtap';

/** Tells the menu a chip was tapped. */
export function tapField(view: EditorView, tap: FieldTap): void {
  view.dom.dispatchEvent(new CustomEvent<FieldTap>(FIELD_TAP, { detail: tap }));
}

/** Calls `onTap` whenever a chip in `view` is tapped. */
export function useFieldTaps(view: EditorView | null, onTap: (tap: FieldTap) => void): void {
  const tap = useRef(onTap);
  tap.current = onTap;
  useEffect(() => {
    if (!view) return undefined;
    const heard = (event: Event) => {
      const detail = (event as CustomEvent<FieldTap>).detail;
      if (detail) tap.current(detail);
    };
    view.dom.addEventListener(FIELD_TAP, heard);
    return () => view.dom.removeEventListener(FIELD_TAP, heard);
  }, [view]);
}

// ---- the days on offer -----------------------------------------------------------------------------

export interface DayChoice {
  id: 'today' | 'tomorrow' | 'next-week';
  label: string;
  day: string;
}

/**
 * The days a date's page offers before Pick a date: today, tomorrow and next week, which is that week's Monday, as a
 * spoken "due next week" is (core/dayWords.ts).
 */
export function dayChoices(today: string): DayChoice[] {
  const choices: DayChoice[] = [
    { id: 'today', label: 'Today', day: today },
    { id: 'tomorrow', label: 'Tomorrow', day: isoDayAfter(today, 1) ?? today },
  ];
  const monday = nextWeek(today);
  if (monday) choices.push({ id: 'next-week', label: 'Next week', day: monday });
  return choices;
}

/** Today, as the menu counts from it: the device's own day (core/days.ts). */
export function todayIs(now: Date = new Date()): string {
  return isoDay(now);
}

// ---- reading a line --------------------------------------------------------------------------------

/** Whether a line can take fields from the menu: a list item, a bullet, a step or a to-do. */
export function takesFields(text: string): boolean {
  return listLead(text) !== null;
}

/** What the fields on line `number` say now, or null where there is no such line. */
export function lineFields(view: EditorView, number: number): ReturnType<typeof fieldsOf> | null {
  if (number < 1 || number > view.state.doc.lines) return null;
  return fieldsOf(view.state.doc.line(number).text);
}

/**
 * The people a note names, each once, in the order it first names them: who the Assign page offers. Read from the
 * whole note the way a line's are, so a person in code or in a redaction is no one's to offer.
 */
export function peopleIn(doc: string): string[] {
  const seen = new Set<string>();
  const people: string[] = [];
  for (const span of fieldsIn(doc)) {
    if (span.kind !== 'person') continue;
    const key = personKey(span.value);
    if (seen.has(key)) continue;
    seen.add(key);
    people.push(span.value);
  }
  return people;
}

// ---- the edits -------------------------------------------------------------------------------------

/** Line `number` rewritten by `change`, as one edit, or false where nothing changed or the line is gone. */
function rewrite(view: EditorView, number: number, change: (text: string) => string): boolean {
  if (view.state.readOnly || number < 1 || number > view.state.doc.lines) return false;
  const line = view.state.doc.line(number);
  const next = change(line.text);
  if (next === line.text) return false;
  // Only what differs is replaced, so the caret and the marks either side of the change stay where they were.
  let head = 0;
  while (head < next.length && head < line.text.length && next[head] === line.text[head]) head += 1;
  let tail = 0;
  while (tail < next.length - head && tail < line.text.length - head && next[next.length - 1 - tail] === line.text[line.text.length - 1 - tail]) tail += 1;
  view.dispatch({
    changes: { from: line.from + head, to: line.to - tail, insert: next.slice(head, next.length - tail) },
    userEvent: 'input.field',
  });
  return true;
}

/** Sets, changes or (with null) takes off one field on line `number`, through the one writer. */
export function setLineField(view: EditorView, number: number, key: FieldKey, value: string | null): boolean {
  return rewrite(view, number, (text) => withField(text, key, value));
}

/** Puts a person on line `number`, or takes them off it. */
export function setLinePerson(view: EditorView, number: number, name: string, on: boolean): boolean {
  return rewrite(view, number, (text) => withAssignee(text, name, on));
}

/**
 * Someone new on line `number`: an at sign where a person goes - before Tasks' run, after any person there - with the
 * caret after it, for the name to be typed. Written as a person would be, then the name taken back off, so the at
 * sign lands exactly where `withAssignee` would put one.
 */
export function startPerson(view: EditorView, number: number): boolean {
  if (view.state.readOnly || number < 1 || number > view.state.doc.lines) return false;
  const line = view.state.doc.line(number);
  const stand = 'Zq';
  const written = withAssignee(line.text, stand);
  const at = written.lastIndexOf(`@${stand}`);
  if (at < 0) return false;
  const next = `${written.slice(0, at + 1)}${written.slice(at + 1 + stand.length)}`;
  view.dispatch({
    changes: { from: line.from, to: line.to, insert: next },
    selection: { anchor: line.from + at + 1 },
    userEvent: 'input.field',
    scrollIntoView: true,
  });
  view.focus();
  return true;
}

// ---- a day picked ----------------------------------------------------------------------------------

/** The page's own date input while it is open, so a second Pick a date replaces the first. */
let picking: HTMLInputElement | null = null;

/**
 * The phone's own date picker, opened from a press on Pick a date: a native `<input type="date">`, so the calendar is
 * the one the phone already draws, in its own language, with nothing to build or keep in step. The input is the
 * page's, not the menu's: the menu closes on the press, as every row's does, and the keyboard going down can scroll
 * the page, which closes it too, so an input inside the menu would be gone before the picker answered. It sits where
 * the press was, so a desktop's picker opens beside it, and goes when a day is picked or the next one opens.
 *
 * `showPicker` opens it from the press itself; a WebView without it is given a focus and a click, which is how a
 * phone opened a date input before it.
 */
export function pickDay(at: { x: number; y: number }, current: string | null, onPick: (day: string) => void): void {
  picking?.remove();
  const input = document.createElement('input');
  input.type = 'date';
  input.className = 'glyph-pickDay';
  input.tabIndex = -1;
  input.setAttribute('aria-hidden', 'true');
  if (current && isIsoDay(current)) input.value = current;
  Object.assign(input.style, {
    position: 'fixed',
    left: `${Math.round(at.x)}px`,
    top: `${Math.round(at.y)}px`,
    width: '1px',
    height: '1px',
    opacity: '0',
    border: '0',
    padding: '0',
    pointerEvents: 'none',
  });
  input.addEventListener('change', () => {
    const day = input.value;
    input.remove();
    if (picking === input) picking = null;
    if (isIsoDay(day)) onPick(day);
  });
  document.body.append(input);
  picking = input;
  try {
    if (typeof input.showPicker === 'function') {
      input.showPicker();
      return;
    }
  } catch {
    // Refused (no press to open it from) or not offered for this input: the older way below.
  }
  input.focus();
  input.click();
}
