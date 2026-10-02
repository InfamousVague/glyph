import type { EditorState } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';
import { CHART_CARD } from '../canvas/edits.ts';
import { NEW_COLUMNS, anchorFor, itemsIn, writeBoard } from '../core/boards.ts';
import { locateHere } from '../core/location.ts';
import { isAndroid, isMacApp } from '../core/platform.ts';
import { preferences } from '../core/preferences.ts';
import { clockTime, stamp } from '../core/stamp.ts';
import { minuteName } from '../core/noteNames.ts';
import { onNamingLine } from './openHeading.ts';
import { isTauri } from '../core/tauri.ts';
import { plugins } from '../plugins/registry.ts';
import type { InlineFormat } from '../plugins/types.ts';
import { TABLE_SEED, insertBlock } from './format.ts';
import { apply, footnotePlan, formPlan, itemPlan, ownLinePlan, wordsPlan, type BlockSelect, type Plan } from './inserts.ts';
import { lineWords, listLead } from '../core/itemSyntax.ts';
import { queryFence } from '../core/query/fence.ts';
import { QUERY_TEMPLATES } from '../core/query/templates.ts';
import { isoDayAfter } from '../core/days.ts';
import { frontMatterValue } from '../core/frontMatter.ts';
import { isTicket, TICKET_TYPE, withProperty } from '../core/properties.ts';
import { FIELD_EMOJI } from '../core/taskFields.ts';

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
  | 'query'
  | `query:${string}`
  | 'dated'
  | 'ticket'
  | 'chart'
  | 'formula'
  | 'canvas'
  | 'footnote'
  | 'tag'
  | 'counter'
  | 'sum'
  | 'blank'
  | 'blankCells'
  | `effect:${string}`;

/** A row as the list draws it. */
export interface AddRow {
  id: AddRowId;
  words: string;
  /** Its name to a screen reader, where the words alone do not say it (the time row). */
  label?: string;
  /** Why it cannot be pressed: a choice the person made, named. */
  dimmed?: string;
  /** A step inside the list rather than a write: More, the ways to start a board, the ready-made databases, or choosing a note or a canvas. */
  step?: 'more' | 'board' | 'database' | 'note' | 'canvas';
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
  /** The +'s empty line sits straight under a table with an empty body cell: Blanks in the empty cells (docs/DESIGN.md §145). */
  tableAbove?: boolean;
  /** The note can be made a ticket: it is not one, and not a notebook (docs/TICKETS.md). */
  ticket?: boolean;
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
export function readGates(can: { picture: boolean; video: boolean; place: boolean; note: boolean; canvas: boolean; tableAbove?: boolean; ticket?: boolean }): AddGates {
  return {
    picture: can.picture && canPickPicture(),
    video: can.video,
    place: can.place ? placeRow() : 'absent',
    note: can.note,
    canvas: can.canvas,
    effects: plugins.formats().filter((format) => format.look.kind === 'effect'),
    tableAbove: can.tableAbove ?? false,
    ticket: can.ticket ?? false,
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

/**
 * What the time row writes: the stamp, "28 Sept 2026, 14:05", or on the line that names the note, the minute's name,
 * "2026-09-28 14.05" (docs/DESIGN.md §144). There the words are the note's name and its file's, and the stamp's colon
 * and comma make a file called `28 Sept 2026, 1405.md`; the minute's name is the third name on a blank page's chips
 * (core/noteNames.ts), so the two can never differ.
 */
export function timeWords(now: Date, naming: boolean): { words: string; label: string } {
  if (!naming) return { words: stamp(now), label: timeLabel(now) };
  const name = minuteName(now);
  return { words: name, label: `The date and time as a name, ${name}` };
}

/**
 * The list's first page: the things reached for most, as far as this screen can do them, and More. The phone's own
 * come first (a picture, a video, a place, the time), then the data trio made of words - a table, a board, a database -
 * since those are the Notion and Jira features people came for and they were a step down in More before (Matt: make
 * "queries and boards and stuff easier to create"), then a link to a note and a to-do. `naming`: the caret is on the
 * line that names the note.
 */
export function topRows(gates: AddGates, now: Date, naming = false): AddRow[] {
  const rows: AddRow[] = [];
  if (gates.picture) rows.push({ id: 'picture', words: 'A picture' });
  if (gates.video) rows.push({ id: 'video', words: 'A video' });
  if (gates.place !== 'absent') rows.push({ id: 'place', words: 'A place', ...(gates.place === 'dimmed' ? { dimmed: 'Local only is on.' } : {}) });
  rows.push({ id: 'time', ...timeWords(now, naming) });
  rows.push({ id: 'table', words: 'A table' });
  rows.push({ id: 'board', words: 'A board', step: 'board' });
  rows.push({ id: 'query', words: 'A database', step: 'database' });
  if (gates.note) rows.push({ id: 'note', words: 'A note', step: 'note' });
  rows.push({ id: 'todo', words: 'A to-do' });
  rows.push({ id: 'more', words: 'More', step: 'more' });
  return rows;
}

/**
 * More: the forms a line takes, the blocks, and the small marks, each with a seed. A board and a database are on the
 * first page now, not here (editor/addRows.ts `topRows`); what is left is the rest a note is made of. A diagram
 * (Mermaid) and a formula (KaTeX) are the two that had no row of their own before.
 */
export function moreRows(gates: AddGates): AddRow[] {
  const rows: AddRow[] = [
    { id: 'heading', words: 'A heading' },
    { id: 'bullets', words: 'A bulleted list' },
    { id: 'numbers', words: 'A numbered list' },
    { id: 'quote', words: 'A quote' },
    { id: 'callout', words: 'A callout' },
    { id: 'choice', words: 'A choice' },
    { id: 'dated', words: 'A to-do with a due date' },
    { id: 'code', words: 'A block of code' },
    { id: 'divider', words: 'A divider' },
    { id: 'chart', words: 'A diagram' },
    { id: 'formula', words: 'A formula' },
  ];
  // A note that is not a ticket yet, and not a notebook, can be made one: its front matter written for it (§160).
  if (gates.ticket) rows.splice(rows.findIndex((row) => row.id === 'divider') + 1, 0, { id: 'ticket', words: 'Make this a ticket' });
  if (gates.canvas) rows.push({ id: 'canvas', words: 'A canvas', step: 'canvas' });
  rows.push({ id: 'footnote', words: 'A footnote' }, { id: 'tag', words: 'A tag' }, { id: 'counter', words: 'A counter' }, { id: 'sum', words: 'A sum' });
  // A question for the AI where its answer belongs (docs/DESIGN.md §145): writing one needs no model, and one written on
  // the Mac or the web is filled on the phone. Under a table with an empty cell, a blank in every one.
  rows.push({ id: 'blank', words: 'A blank for the AI' });
  if (gates.tableAbove) rows.push({ id: 'blankCells', words: 'Blanks in the empty cells', label: 'Blanks in the empty cells of the table above' });
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
 * A formula on its own, drawn by KaTeX (editor/mathsDrawn.ts): a `$$` block with nothing in it yet, the caret on the
 * empty line between the fences, where the maths is typed. The row the Guide answered "yes" to formatting specially.
 */
export const FORMULA_SEED = '$$\n\n$$';
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

/**
 * A board's page: the two ways to start one, so the two kinds of board are a single choice rather than a name to guess
 * between (Matt: make boards "easier to create"). Fresh columns is a `board` fence of its own (`boardSeed`); From your
 * tickets is the ready-made ticket board, a query grouped into lanes (core/query/templates.ts `board`), which fills
 * itself from the library and turns into any other view with the switcher on it (editor/QueryView.tsx).
 */
export function boardRows(): AddRow[] {
  return [
    { id: 'board', words: 'Fresh columns' },
    { id: 'query:board', words: 'From your tickets' },
  ];
}

/**
 * A database's page: the ready-made queries (core/query/templates.ts), each a row of its own, Write your own last
 * (docs/DESIGN.md §160).
 */
export function databaseRows(): AddRow[] {
  return QUERY_TEMPLATES.map((template) => ({ id: `query:${template.id}` as const, words: template.words }));
}

/**
 * A ready-made query as a block: drawn at once with the caret on the line after it, or, for Write your own, with its
 * kind selected to be written over, the fence's lines showing.
 */
export function querySeed(id: string): { text: string; select: BlockSelect } | null {
  const template = QUERY_TEMPLATES.find((each) => `query:${each.id}` === id);
  if (!template) return null;
  const text = queryFence(template.lines);
  if (!template.select) return { text, select: 'after' };
  const from = text.indexOf(template.select);
  return { text, select: { from, to: from + template.select.length } };
}

/** The words a dated to-do starts with, selected to be written over. */
export const DATED_WORDS = 'To-do';

/**
 * A to-do with a due date (core/taskFields.ts; docs/DESIGN.md §158), due tomorrow, its words selected to be written
 * over and the chip there to tap for another day: a to-do's own lead, where A to-do would put it, then the words and
 * the day, as one change.
 */
export function datedPlan(state: EditorState, at: number, now: Date): Plan {
  const base = itemPlan(state, at, 'todo');
  const first = state.update({ changes: base.changes, selection: base.selection });
  const caret = first.state.selection.main.head;
  const words = `${DATED_WORDS} ${FIELD_EMOJI.due} ${isoDayAfter(now, 1)}`;
  return { changes: first.changes.compose(first.state.changes({ from: caret, insert: words })), selection: { anchor: caret, head: caret + DATED_WORDS.length } };
}

/**
 * The note made a ticket (docs/TICKETS.md): `type: ticket` and, where it has no status yet, `status: To do`, written
 * into its front matter as one change, the rest of the note and the caret where they were. Its panel then offers its
 * notebook's next key where the notebook has one (editor/tickets.ts).
 */
export function ticketPlan(state: EditorState): Plan | null {
  const doc = state.doc.toString();
  if (isTicket(doc)) return null;
  const typed = withProperty(doc, 'type', TICKET_TYPE);
  const next = frontMatterValue(doc, 'status') ? typed : withProperty(typed, 'status', 'To do');
  let start = 0;
  while (start < doc.length && start < next.length && doc[start] === next[start]) start += 1;
  let end = doc.length;
  let nextEnd = next.length;
  while (end > start && nextEnd > start && doc[end - 1] === next[nextEnd - 1]) {
    end -= 1;
    nextEnd -= 1;
  }
  return { changes: { from: start, to: end, insert: next.slice(start, nextEnd) } };
}

/** What a row that writes at once writes at the caret, as a plan; null for a row that is not one of those. */
export function planFor(view: EditorView, id: AddRowId, now = new Date()): { plan: Plan; drawn?: boolean } | { block: { text: string; select: BlockSelect } } | null {
  const state = view.state;
  const at = state.selection.main.head;
  if (id === 'time') return { plan: wordsPlan(state, at, timeWords(now, onNamingLine(state)).words) };
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
  if (id === 'blank') return { plan: blankPlan(state, at) };
  if (id === 'blankCells') {
    const plan = emptyCellsPlan(state, at);
    return plan ? { plan } : null;
  }
  if (id === 'table') return { block: TABLE_SEED };
  if (id === 'callout') return { block: { text: CALLOUT_SEED, select: { from: CALLOUT_SEED.length } } };
  if (id === 'code') return { block: { text: CODE_SEED, select: { from: 4 } } };
  if (id === 'formula') return { block: { text: FORMULA_SEED, select: { from: 3 } } };
  if (id === 'divider') return { block: { text: '---', select: 'after' } };
  if (id === 'chart') return { block: { text: CHART_SEED, select: { from: CHART_SEED.indexOf('Start'), to: CHART_SEED.indexOf('Start') + 'Start'.length } } };
  if (id === 'board') return { block: boardSeed(state.doc.toString()) };
  if (id.startsWith('query:')) {
    const block = querySeed(id);
    return block ? { block } : null;
  }
  if (id === 'dated') return { plan: datedPlan(state, at, now) };
  if (id === 'ticket') {
    const plan = ticketPlan(state);
    return plan ? { plan } : null;
  }
  if (id.startsWith('effect:')) {
    const effect = plugins.formats().find((format) => `effect:${format.name}` === id);
    if (!effect) return null;
    // Its marks round a word to write over, as the tag's and the chart's seeds are: the marks alone draw nothing.
    const mark = effect.delimiter;
    return { plan: wordsPlan(state, at, `${mark}${EFFECT_WORDS}${mark}`, { from: mark.length, to: mark.length + EFFECT_WORDS.length }) };
  }
  return null;
}

/**
 * A blank, `{?}`, with the caret between its `?` and `}` so the question is typed straight in, as the tag row leaves
 * `tag` to write over. On an empty list item or to-do it is the item's words, since a blank there is meant as one;
 * anywhere else it takes a line of its own by the rule every drawn thing keeps (editor/inserts.ts `ownLinePlan`), a
 * blank line first under a table row, a list item or a quote, or the parser reads it as part of that block (a table
 * row of one cell, or the item's words).
 */
export function blankPlan(state: EditorState, at: number): Plan {
  const line = state.doc.lineAt(at);
  const lead = listLead(line.text.replace(/^\s*(?:>\s*)+/, ''));
  if (lead && !lineWords(line.text)) return wordsPlan(state, line.to, '{?}', { from: 2 });
  const plan = ownLinePlan(state, at, '{?}');
  const change = plan.changes as { from: number; insert: string };
  return { ...plan, selection: { anchor: change.from + change.insert.indexOf('{?}') + 2 } };
}

/** The unescaped pipes of a table line, where each cell starts and ends. */
function pipesOf(text: string): number[] {
  return [...text.matchAll(/(?<!\\)\|/g)].map((m) => m.index);
}

/** The table straight above `line`, its body rows' empty cells as ranges, or null where there is none or none is empty. */
export function emptyCellsAbove(state: EditorState, at: number): { from: number; to: number }[] | null {
  const line = state.doc.lineAt(at);
  if (line.number < 2) return null;
  const rows: { from: number; text: string }[] = [];
  for (let n = line.number - 1; n >= 1; n -= 1) {
    const above = state.doc.line(n);
    if (!/^\s*\|/.test(above.text)) break;
    rows.unshift({ from: above.from, text: above.text });
  }
  if (rows.length < 3 || !/^\s*\|?\s*:?-+/.test(rows[1]!.text)) return null;
  const cells: { from: number; to: number }[] = [];
  for (const row of rows.slice(2)) {
    const pipes = pipesOf(row.text);
    for (let i = 0; i + 1 < pipes.length; i += 1) {
      const inside = row.text.slice(pipes[i]! + 1, pipes[i + 1]);
      if (!inside.trim()) cells.push({ from: row.from + pipes[i]! + 1, to: row.from + pipes[i + 1]! });
    }
  }
  return cells.length ? cells : null;
}

/** A blank in every empty body cell of the table above, as one Undo; the caret stays where it was, outside the table. */
export function emptyCellsPlan(state: EditorState, at: number): Plan | null {
  const cells = emptyCellsAbove(state, at);
  if (!cells) return null;
  // Every cell is above the caret, so it moves on by what they grew.
  const grew = cells.reduce((sum, cell) => sum + ' {?} '.length - (cell.to - cell.from), 0);
  return { changes: cells.map((cell) => ({ from: cell.from, to: cell.to, insert: ' {?} ' })), selection: { anchor: at + grew } };
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
