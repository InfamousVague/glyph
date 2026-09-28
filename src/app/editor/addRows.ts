import type { EditorView } from '@codemirror/view';
import { CHART_CARD } from '../canvas/edits.ts';
import { NEW_COLUMNS, anchorFor, itemsIn, writeBoard } from '../core/boards.ts';
import { locateHere } from '../core/location.ts';
import { isAndroid, isMacApp } from '../core/platform.ts';
import { preferences } from '../core/preferences.ts';
import { clockTime, stamp } from '../core/stamp.ts';
import { isTauri } from '../core/tauri.ts';
import { plugins } from '../plugins/registry.ts';
import type { InlineFormat } from '../plugins/types.ts';
import { TABLE_SEED, insertBlock } from './format.ts';
import { apply, footnotePlan, formPlan, itemPlan, ownLinePlan, wordsPlan, type BlockSelect, type Plan } from './inserts.ts';

/**
 * What the + beside the line offers (editor/AddList.tsx draws it), whether each row is there, and what each writes.
 *
 * Matt: "Fuller but hide extras behind nested menu". So the list has the seven things people reach for, the phone's
 * own first (a picture, a video, a place, the time) and then the things made of words (a table, a link to a note, a
 * to-do), and an eighth row, More, which turns the list over to the rest: the forms a line takes, the blocks, and the
 * small marks the Guide teaches, each with a seed to write over.
 *
 * **A row is there, dimmed or not there** by one rule. A row this device or this build can never do is not drawn: a
 * page that arrives over the air on an older binary shows nothing it cannot do, so the video row waits for the binary
 * with a video picker (native generation 21) and the picture row on the Mac for the Mac's own run of its picker. A row
 * a choice the person made stands in the way of is drawn dimmed, with the choice named under it: Local only, for a
 * place. A refusal found only by trying (location blocked for the app) keeps the row, and is said when it happens.
 *
 * Where each goes is editor/inserts.ts: a drawn thing on a line of its own, a block with blank lines where words are
 * near, words at the caret. Every write is one Undo, and appears at once (docs/DESIGN.md §140, §141).
 */

/** Every row the list can hold, top level and More. */
export type AddRowId =
  | 'picture'
  | 'video'
  | 'place'
  | 'time'
  | 'table'
  | 'note'
  | 'todo'
  | 'more'
  | 'heading'
  | 'bullets'
  | 'numbers'
  | 'quote'
  | 'callout'
  | 'choice'
  | 'code'
  | 'divider'
  | 'board'
  | 'chart'
  | 'canvas'
  | 'footnote'
  | 'tag'
  | 'counter'
  | 'sum'
  | `effect:${string}`;

/** A row as the list draws it. */
export interface AddRow {
  id: AddRowId;
  words: string;
  /** Its name to a screen reader, where the words alone do not say it (the time row). */
  label?: string;
  /** Why it cannot be pressed: a choice the person made, named. */
  dimmed?: string;
  /** A step inside the list rather than a write: More, or choosing a note or a canvas. */
  step?: 'more' | 'note' | 'canvas';
}

/**
 * The Mac's picture route has been read and not yet run on a Mac (docs/DESIGN.md §141): the Mac shows no picture row
 * until it has, on macOS 13 and the newest, with a JPEG, a PNG, a HEIC, a turned JPEG and a PDF. The commit that
 * records that run sets this true.
 */
export const MAC_PICKER_TRIED = false;

/** What the screen can do, read once when the list opens (the generation is asked once per page load anyway). */
export interface AddGates {
  picture: boolean;
  video: boolean;
  place: 'on' | 'dimmed' | 'absent';
  note: boolean;
  canvas: boolean;
  effects: InlineFormat[];
}

/** Whether this build can pick a picture: the phone's chooser, a browser's file input, and the Mac once its run has passed. */
export function canPickPicture(): boolean {
  if (isMacApp) return MAC_PICKER_TRIED;
  if (!isTauri()) return true;
  if (isAndroid) return typeof window.GlyphHost?.pickImage === 'function';
  // The iPhone's picker path is not built, and a Tauri desktop that is not the Mac has no picker either.
  return false;
}

/** Whether a place can be added here: never where the device cannot say, dimmed under Local only. */
export function placeRow(): AddGates['place'] {
  if (!locateHere().ok) return 'absent';
  return preferences().localOnly ? 'dimmed' : 'on';
}

/**
 * The gates, for a screen that can do `can` (a picture picker, a video, a place, a note to link, a canvas to frame).
 * A video is the screen's to say outright: it asks the binary once as it opens (core/videos.ts `canAddVideos`, an
 * Android binary of native generation 21 with the picker on its bridge) and gives the list an `onVideo` only there.
 */
export function readGates(can: { picture: boolean; video: boolean; place: boolean; note: boolean; canvas: boolean }): AddGates {
  return {
    picture: can.picture && canPickPicture(),
    video: can.video,
    place: can.place ? placeRow() : 'absent',
    note: can.note,
    canvas: can.canvas,
    effects: plugins.formats().filter((format) => format.look.kind === 'effect'),
  };
}

/** "The date and time, 28 September 2026, 14:05": the time row read aloud, with the month in full. */
export function timeLabel(date: Date): string {
  const parts = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'long' }).formatToParts(date);
  const day = parts
    .filter((part) => part.type === 'day' || part.type === 'month')
    .map((part) => part.value)
    .join(' ');
  return `The date and time, ${day} ${date.getFullYear()}, ${clockTime(date)}`;
}

/** The list's first page: the seven things, as far as this screen can do them, and More. */
export function topRows(gates: AddGates, now: Date): AddRow[] {
  const rows: AddRow[] = [];
  if (gates.picture) rows.push({ id: 'picture', words: 'A picture' });
  if (gates.video) rows.push({ id: 'video', words: 'A video' });
  if (gates.place !== 'absent') rows.push({ id: 'place', words: 'A place', ...(gates.place === 'dimmed' ? { dimmed: 'Local only is on.' } : {}) });
  rows.push({ id: 'time', words: stamp(now), label: timeLabel(now) });
  rows.push({ id: 'table', words: 'A table' });
  if (gates.note) rows.push({ id: 'note', words: 'A note', step: 'note' });
  rows.push({ id: 'todo', words: 'A to-do' });
  rows.push({ id: 'more', words: 'More', step: 'more' });
  return rows;
}

/** More: the forms a line takes, the blocks, and the small marks, each with a seed. */
export function moreRows(gates: AddGates): AddRow[] {
  const rows: AddRow[] = [
    { id: 'heading', words: 'A heading' },
    { id: 'bullets', words: 'A bulleted list' },
    { id: 'numbers', words: 'A numbered list' },
    { id: 'quote', words: 'A quote' },
    { id: 'callout', words: 'A callout' },
    { id: 'choice', words: 'A choice' },
    { id: 'code', words: 'A block of code' },
    { id: 'divider', words: 'A divider' },
    { id: 'board', words: 'A board' },
    { id: 'chart', words: 'A chart' },
  ];
  if (gates.canvas) rows.push({ id: 'canvas', words: 'A canvas', step: 'canvas' });
  rows.push({ id: 'footnote', words: 'A footnote' }, { id: 'tag', words: 'A tag' }, { id: 'counter', words: 'A counter' }, { id: 'sum', words: 'A sum' });
  for (const effect of gates.effects) rows.push({ id: `effect:${effect.name}`, words: effectWords(effect) });
  return rows;
}

/**
 * An effect's row, named as it is said while recording ("heated", "frosted"), so it reads as words that look a way:
 * "Heated words". A plugin's effect with no word of its own is named by its name.
 */
export function effectWords(effect: InlineFormat): string {
  const said = effect.cue?.trim() || effect.name;
  return `${said.charAt(0).toUpperCase()}${said.slice(1).toLowerCase()} words`;
}

// ---- the seeds ---------------------------------------------------------------------------------------------

/** A callout, as the Guide teaches it: a quote whose first line names its kind, the caret on the line under it. */
export const CALLOUT_SEED = '> [!NOTE]\n> ';
/** A block of code with nothing in it yet, the caret inside. */
export const CODE_SEED = '```\n\n```';
/**
 * A chart that reads as one at a glance: three boxes in a row with arrows between, in Mermaid, the canvas's own chart
 * card (canvas/edits.ts `CHART_CARD`), with "Start" selected to be written over.
 */
export const CHART_SEED = CHART_CARD.trimEnd();
/** A counter, with what it counts selected to be written over, as the Guide's `- Water [3/8]` is. */
export const COUNTER_SEED = 'Count [0/8]';
/** The words an effect's seed holds, selected to be written over. */
export const EFFECT_WORDS = 'words';

/**
 * A small board, as Make a board writes one (core/boards.ts `boardFrom`): the three columns, and one to-do named in
 * the first, its words selected to be written over. The anchor is one no item in the note has yet.
 */
export function boardSeed(doc: string): { text: string; select: BlockSelect } {
  const words = 'First card';
  const id = anchorFor(words, itemsIn(doc).map((item) => item.id));
  const fence = ['```board', writeBoard(NEW_COLUMNS.map((name, index) => ({ name, cards: index === 0 ? [id] : [] }))), '```'].join('\n');
  const item = `- [ ] ${words} ^${id}`;
  const text = `${fence}\n\n${item}`;
  const from = text.length - item.length + '- [ ] '.length;
  return { text, select: { from, to: from + words.length } };
}

/** What a row that writes at once writes at the caret, as a plan; null for a row that is not one of those. */
export function planFor(view: EditorView, id: AddRowId, now = new Date()): { plan: Plan; drawn?: boolean } | { block: { text: string; select: BlockSelect } } | null {
  const state = view.state;
  const at = state.selection.main.head;
  if (id === 'time') return { plan: wordsPlan(state, at, stamp(now)) };
  if (id === 'todo') return { plan: itemPlan(state, at, 'todo') };
  if (id === 'choice') return { plan: itemPlan(state, at, 'choice') };
  if (id === 'bullets') return { plan: itemPlan(state, at, 'bullet') };
  if (id === 'numbers') return { plan: itemPlan(state, at, 'number') };
  if (id === 'heading') return { plan: formPlan(state, at, 'heading') };
  if (id === 'quote') return { plan: formPlan(state, at, 'quote') };
  if (id === 'sum') return { plan: formPlan(state, at, 'sum') };
  if (id === 'footnote') return { plan: footnotePlan(state, at) };
  if (id === 'tag') return { plan: wordsPlan(state, at, '#tag', { from: 1, to: 4 }) };
  if (id === 'counter') return { plan: wordsPlan(state, at, COUNTER_SEED, { from: 0, to: COUNTER_SEED.indexOf(' [') }) };
  if (id === 'table') return { block: TABLE_SEED };
  if (id === 'callout') return { block: { text: CALLOUT_SEED, select: { from: CALLOUT_SEED.length } } };
  if (id === 'code') return { block: { text: CODE_SEED, select: { from: 4 } } };
  if (id === 'divider') return { block: { text: '---', select: 'after' } };
  if (id === 'chart') return { block: { text: CHART_SEED, select: { from: CHART_SEED.indexOf('Start'), to: CHART_SEED.indexOf('Start') + 'Start'.length } } };
  if (id === 'board') return { block: boardSeed(state.doc.toString()) };
  if (id.startsWith('effect:')) {
    const effect = plugins.formats().find((format) => `effect:${format.name}` === id);
    if (!effect) return null;
    // Its marks round a word to write over, as the tag's and the chart's seeds are: the marks alone draw nothing.
    const mark = effect.delimiter;
    return { plan: wordsPlan(state, at, `${mark}${EFFECT_WORDS}${mark}`, { from: mark.length, to: mark.length + EFFECT_WORDS.length }) };
  }
  return null;
}

/** Writes a row that writes at once, as one Undo; answers whether it wrote. */
export function writeRow(view: EditorView, id: AddRowId, now = new Date()): boolean {
  const found = planFor(view, id, now);
  if (!found) return false;
  if ('block' in found) insertBlock(view, found.block.text, found.block.select, 'input.plus');
  else apply(view, found.plan, 'input.plus');
  return true;
}

/** A link to another note at the caret: `[[Title]]`, spaced from the words around it. */
export function writeNoteLink(view: EditorView, title: string): void {
  apply(view, wordsPlan(view.state, view.state.selection.main.head, `[[${title}]]`), 'input.plus');
}

/** A canvas drawn in a frame, on a line of its own (editor/canvasFrames.ts): `![[Title]]`. */
export function writeCanvasFrame(view: EditorView, title: string): void {
  apply(view, ownLinePlan(view.state, view.state.selection.main.head, `![[${title}]]`, { apart: true }), 'input.plus.drawn');
}

/**
 * The titles a link can be made to: a link cannot hold `|`, `#` or `]` (book/book.ts), and a note does not link to
 * itself. Those that hold part of `looking`, at most twelve.
 */
export function linkableTitles(titles: readonly string[], own: string, looking: string): string[] {
  const words = looking.trim().toLowerCase();
  return titles.filter((title) => title && !/[|#\]]/.test(title) && title !== own && title.toLowerCase().includes(words)).slice(0, 12);
}
